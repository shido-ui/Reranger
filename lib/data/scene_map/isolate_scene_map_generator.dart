import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/project/project_entity.dart';
import '../../domain/scene_map/analysis_bundle_metadata.dart';
import '../../domain/scene_map/color_region_map_data.dart';
import '../../domain/scene_map/coordinate_transform.dart';
import '../../domain/scene_map/pyramid_level.dart';
import '../../domain/scene_map/scene_map_bundle.dart';
import '../../domain/scene_map/scene_map_failure.dart';
import '../../domain/scene_map/tonal_palette_map_data.dart';
import 'edge_contour_extractor.dart';

/// Worker parameters passed to the background isolate.
class _SceneMapWorkerParams {
  final Uint8List imageBytes;
  final String sourceHash;
  final int maxPreviewDimension;
  final int edgeThreshold;
  final int paletteK;
  final String engineVersion;

  const _SceneMapWorkerParams({
    required this.imageBytes,
    required this.sourceHash,
    required this.maxPreviewDimension,
    required this.edgeThreshold,
    required this.paletteK,
    required this.engineVersion,
  });
}

/// Service generating complete Scene Map / Analysis Bundles in a background worker isolate.
/// Strictly enforces:
/// - Memory-aware downsampling (Invariant 11) to prevent duplicate 12MP memory allocations.
/// - Invariant 4: Source media immutability.
/// - Invariant 7: Honest capability reporting (zero fabricated semantic/depth/face maps).
class IsolateSceneMapGenerator {
  const IsolateSceneMapGenerator();

  /// Generates a full [SceneMapBundle] in a background isolate.
  Future<SceneMapBundle> generate({
    required Uint8List imageBytes,
    required String sourceHash,
    int maxPreviewDimension = 512,
    int edgeThreshold = 50,
    int paletteK = 5,
    String engineVersion = '1.0.0',
    bool Function()? isCancelled,
  }) async {
    if (isCancelled != null && isCancelled()) {
      throw const SceneMapCancellationFailure();
    }

    final params = _SceneMapWorkerParams(
      imageBytes: imageBytes,
      sourceHash: sourceHash,
      maxPreviewDimension: maxPreviewDimension,
      edgeThreshold: edgeThreshold,
      paletteK: paletteK,
      engineVersion: engineVersion,
    );

    final bundle = await Isolate.run(() => _generateWorker(params));

    if (isCancelled != null && isCancelled()) {
      throw const SceneMapCancellationFailure();
    }

    return bundle;
  }

  static SceneMapBundle _generateWorker(_SceneMapWorkerParams params) {
    // 1. Decode raw image stream
    final rawImage = img.decodeImage(params.imageBytes);
    if (rawImage == null) {
      throw const SceneMapUnsupportedFormatFailure(
        'Unrecognized image byte stream',
      );
    }

    // 2. Bake EXIF orientation
    final bakedImage = img.bakeOrientation(rawImage);
    final srcWidth = bakedImage.width;
    final srcHeight = bakedImage.height;

    // 3. Compute preview scale dimensions (max dimension <= maxPreviewDimension)
    final maxDim = math.max(srcWidth, srcHeight);
    final scale = (maxDim > params.maxPreviewDimension)
        ? (params.maxPreviewDimension / maxDim)
        : 1.0;
    final prevWidth = math.max(1, (srcWidth * scale).round());
    final prevHeight = math.max(1, (srcHeight * scale).round());

    // Resize for preview and analysis
    final previewImage = (scale < 1.0)
        ? img.copyResize(
            bakedImage,
            width: prevWidth,
            height: prevHeight,
            interpolation: img.Interpolation.average,
          )
        : bakedImage;

    // 4. Build 3-level Gaussian/Box Pyramid (Level 0: Preview, Level 1: Half, Level 2: Quarter)
    final pyramids = <PyramidLevel>[];

    // Level 0: Primary preview scale
    final lum0 = _extractBt601Luminance(previewImage);
    pyramids.add(
      PyramidLevel(
        level: 0,
        width: prevWidth,
        height: prevHeight,
        scaleFactor: 1.0,
        luminanceData: lum0,
      ),
    );

    // Level 1: Half preview scale
    final halfW = math.max(1, prevWidth ~/ 2);
    final halfH = math.max(1, prevHeight ~/ 2);
    final halfImg = (halfW < prevWidth || halfH < prevHeight)
        ? img.copyResize(previewImage, width: halfW, height: halfH)
        : previewImage;
    pyramids.add(
      PyramidLevel(
        level: 1,
        width: halfW,
        height: halfH,
        scaleFactor: 0.5,
        luminanceData: _extractBt601Luminance(halfImg),
      ),
    );

    // Level 2: Quarter preview scale
    final quartW = math.max(1, prevWidth ~/ 4);
    final quartH = math.max(1, prevHeight ~/ 4);
    final quartImg = (quartW < prevWidth || quartH < prevHeight)
        ? img.copyResize(previewImage, width: quartW, height: quartH)
        : previewImage;
    pyramids.add(
      PyramidLevel(
        level: 2,
        width: quartW,
        height: quartH,
        scaleFactor: 0.25,
        luminanceData: _extractBt601Luminance(quartImg),
      ),
    );

    // 5. Compute Sobel edge gradients & structural contours on Level 0
    const extractor = EdgeContourExtractor();
    final edgeMap = extractor.extractEdges(
      pyramids[0],
      edgeThreshold: params.edgeThreshold,
    );
    final contourMap = extractor.extractContours(edgeMap);

    // 6. Compute dominant harmonic palette & tonal distribution (Median Cut)
    final (palette, tonalMap) = _computePaletteAndTonalDistribution(
      previewImage,
      params.paletteK,
    );

    // 7. Compute spatial color region segmentation (mapped to palette centroids on Level 1 grid)
    final colorRegions = _computeColorRegions(halfImg, palette);

    // 8. Assemble CoordinateTransform
    final transform = CoordinateTransform(
      sourceWidth: srcWidth,
      sourceHeight: srcHeight,
      previewWidth: prevWidth,
      previewHeight: prevHeight,
      mapWidth: halfW,
      mapHeight: halfH,
    );

    // 9. Assemble AnalysisBundleMetadata
    final metadata = AnalysisBundleMetadata(
      sourceHash: params.sourceHash,
      sourceWidth: srcWidth,
      sourceHeight: srcHeight,
      createdAt: DateTime.now().toUtc(),
      engineVersion: params.engineVersion,
      parameters: {
        'maxPreviewDimension': params.maxPreviewDimension,
        'edgeThreshold': params.edgeThreshold,
        'paletteK': params.paletteK,
      },
      hasEdgeMap: true,
      hasContourMap: true,
      hasPaletteMap: true,
      hasColorRegions: true,
      hasSubjectMap: false, // Invariant 7: Honest capability
      hasDepthMap: false,
      hasFaceMap: false,
    );

    return SceneMapBundle(
      metadata: metadata,
      transform: transform,
      pyramidLevels: pyramids,
      edgeMap: edgeMap,
      contourMap: contourMap,
      tonalPaletteMap: tonalMap,
      colorRegionMap: colorRegions,
    );
  }

  static Uint8List _extractBt601Luminance(img.Image image) {
    final w = image.width;
    final h = image.height;
    final bytes = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final lum = (299 * p.r + 587 * p.g + 114 * p.b) ~/ 1000;
        bytes[y * w + x] = lum.clamp(0, 255);
      }
    }
    return bytes;
  }

  static (List<ColorVector>, TonalPaletteMapData)
  _computePaletteAndTonalDistribution(img.Image image, int k) {
    final w = image.width;
    final h = image.height;
    final total = w * h;

    int shadows = 0;
    int midtones = 0;
    int highlights = 0;
    double totalLum = 0.0;

    final pixelSamples = <(int, int, int)>[];
    final step = (total > 50000) ? (total ~/ 25000) : 1;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final lumNorm = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;

        totalLum += lumNorm;
        if (lumNorm < 0.25) {
          shadows++;
        } else if (lumNorm < 0.75) {
          midtones++;
        } else {
          highlights++;
        }

        if ((y * w + x) % step == 0) {
          pixelSamples.add((r, g, b));
        }
      }
    }

    final avgLum = total > 0 ? (totalLum / total).clamp(0.0, 1.0) : 0.0;
    final shadowRatio = total > 0 ? (shadows / total).clamp(0.0, 1.0) : 0.0;
    final midtoneRatio = total > 0 ? (midtones / total).clamp(0.0, 1.0) : 0.0;
    final highlightRatio = total > 0
        ? (highlights / total).clamp(0.0, 1.0)
        : 0.0;

    // Median Cut Quantization
    final rawPalette = _medianCut(pixelSamples, math.max(1, k));

    // Sort palette by ascending luminance with RGB tie-breaking
    rawPalette.sort((a, b) {
      final lumA = 299 * a.$1 + 587 * a.$2 + 114 * a.$3;
      final lumB = 299 * b.$1 + 587 * b.$2 + 114 * b.$3;
      if (lumA != lumB) return lumA.compareTo(lumB);
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.compareTo(b.$3);
    });

    final colorVectors = rawPalette
        .map((p) => ColorVector(p.$1 / 255.0, p.$2 / 255.0, p.$3 / 255.0))
        .toList();

    final tonalMap = TonalPaletteMapData(
      palette: colorVectors,
      shadowRatio: shadowRatio,
      midtoneRatio: midtoneRatio,
      highlightRatio: highlightRatio,
      averageLuminance: avgLum,
      totalPixelSamples: total,
    );

    return (colorVectors, tonalMap);
  }

  static List<(int, int, int)> _medianCut(List<(int, int, int)> colors, int k) {
    if (colors.isEmpty) return const [(128, 128, 128)];
    final boxes = <_Box>[_Box(colors)];

    while (boxes.length < k) {
      int bestIdx = -1;
      int maxRange = -1;
      for (int i = 0; i < boxes.length; i++) {
        if (boxes[i].colors.length > 1) {
          boxes[i].computeRange();
          if (boxes[i].range > maxRange) {
            maxRange = boxes[i].range;
            bestIdx = i;
          }
        }
      }
      if (bestIdx == -1 || maxRange <= 0) break;

      final target = boxes.removeAt(bestIdx);
      final (b1, b2) = target.split();
      boxes.add(b1);
      boxes.add(b2);
    }

    return boxes.map((b) => b.averageColor()).toList();
  }

  static ColorRegionMapData _computeColorRegions(
    img.Image image,
    List<ColorVector> palette,
  ) {
    final w = image.width;
    final h = image.height;
    final total = w * h;
    final labels = Uint8List(total);

    final palInts = palette
        .map(
          (cv) => (
            (cv.r * 255).round().clamp(0, 255),
            (cv.g * 255).round().clamp(0, 255),
            (cv.b * 255).round().clamp(0, 255),
          ),
        )
        .toList();

    final counts = List.filled(palette.length, 0);
    final sumX = List.filled(palette.length, 0.0);
    final sumY = List.filled(palette.length, 0.0);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final pr = p.r.toInt();
        final pg = p.g.toInt();
        final pb = p.b.toInt();

        int bestIdx = 0;
        int bestDist = 0x7FFFFFFF;

        for (int i = 0; i < palInts.length; i++) {
          final target = palInts[i];
          final dr = pr - target.$1;
          final dg = pg - target.$2;
          final db = pb - target.$3;
          final dist = dr * dr + dg * dg + db * db;
          if (dist < bestDist) {
            bestDist = dist;
            bestIdx = i;
          }
        }

        labels[y * w + x] = bestIdx;
        counts[bestIdx]++;
        final nx = (w > 1) ? (x / (w - 1)) : 0.0;
        final ny = (h > 1) ? (y / (h - 1)) : 0.0;
        sumX[bestIdx] += nx;
        sumY[bestIdx] += ny;
      }
    }

    final centroids = <int, NormalizedPoint>{};
    final coverage = <int, double>{};

    for (int i = 0; i < palette.length; i++) {
      final c = counts[i];
      coverage[i] = total > 0 ? (c / total) : 0.0;
      if (c > 0) {
        centroids[i] = NormalizedPoint.clamped(sumX[i] / c, sumY[i] / c);
      } else {
        centroids[i] = const NormalizedPoint(0.5, 0.5);
      }
    }

    return ColorRegionMapData(
      gridWidth: w,
      gridHeight: h,
      regionCount: palette.length,
      regionLabels: labels,
      regionCentroids: centroids,
      regionCoverage: coverage,
    );
  }
}

class _Box {
  final List<(int, int, int)> colors;
  int minR = 255, maxR = 0;
  int minG = 255, maxG = 0;
  int minB = 255, maxB = 0;
  int range = 0;
  int channel = 0; // 0: R, 1: G, 2: B

  _Box(this.colors);

  void computeRange() {
    minR = 255;
    maxR = 0;
    minG = 255;
    maxG = 0;
    minB = 255;
    maxB = 0;

    for (final (r, g, b) in colors) {
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      if (g < minG) minG = g;
      if (g > maxG) maxG = g;
      if (b < minB) minB = b;
      if (b > maxB) maxB = b;
    }

    final rangeR = maxR - minR;
    final rangeG = maxG - minG;
    final rangeB = maxB - minB;

    range = math.max(rangeR, math.max(rangeG, rangeB));
    if (range == rangeR) {
      channel = 0;
    } else if (range == rangeG) {
      channel = 1;
    } else {
      channel = 2;
    }
  }

  (int, int, int) averageColor() {
    if (colors.isEmpty) return (0, 0, 0);
    int sumR = 0, sumG = 0, sumB = 0;
    for (final (r, g, b) in colors) {
      sumR += r;
      sumG += g;
      sumB += b;
    }
    final len = colors.length;
    return (sumR ~/ len, sumG ~/ len, sumB ~/ len);
  }

  (_Box, _Box) split() {
    if (channel == 0) {
      colors.sort((a, b) => a.$1.compareTo(b.$1));
    } else if (channel == 1) {
      colors.sort((a, b) => a.$2.compareTo(b.$2));
    } else {
      colors.sort((a, b) => a.$3.compareTo(b.$3));
    }

    final mid = colors.length ~/ 2;
    return (_Box(colors.sublist(0, mid)), _Box(colors.sublist(mid)));
  }
}
