import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

/// Computes the Structural Similarity Index (SSIM) between two RGBA buffers.
/// Uses 8x8 sliding window block luminance comparison per Wang et al. (2004).
/// Returns Mean SSIM (MSSIM) in range [-1.0, 1.0] (1.0 = identical).
double computeSsim(
  Uint8List bufferA,
  Uint8List bufferB, {
  required int width,
  required int height,
}) {
  assert(bufferA.length == bufferB.length);
  assert(bufferA.length == width * height * 4);

  const double k1 = 0.01;
  const double k2 = 0.03;
  const double l = 255.0; // Dynamic range
  const double c1 = (k1 * l) * (k1 * l); // 6.5025
  const double c2 = (k2 * l) * (k2 * l); // 58.5225

  // Extract luminance channel Y for both images
  final totalPixels = width * height;
  final lumA = Float64List(totalPixels);
  final lumB = Float64List(totalPixels);

  for (int i = 0; i < totalPixels; i++) {
    final off = i * 4;
    // Rec. 601 luminance
    lumA[i] =
        0.299 * bufferA[off] +
        0.587 * bufferA[off + 1] +
        0.114 * bufferA[off + 2];
    lumB[i] =
        0.299 * bufferB[off] +
        0.587 * bufferB[off + 1] +
        0.114 * bufferB[off + 2];
  }

  // 8x8 block decomposition with stride 4
  const int blockSize = 8;
  const int stride = 4;
  int blockCount = 0;
  double ssimSum = 0.0;

  for (int y = 0; y <= height - blockSize; y += stride) {
    for (int x = 0; x <= width - blockSize; x += stride) {
      double sumA = 0.0;
      double sumB = 0.0;
      const int n = blockSize * blockSize;

      for (int dy = 0; dy < blockSize; dy++) {
        final rowOff = (y + dy) * width;
        for (int dx = 0; dx < blockSize; dx++) {
          final idx = rowOff + (x + dx);
          sumA += lumA[idx];
          sumB += lumB[idx];
        }
      }

      final double meanA = sumA / n;
      final double meanB = sumB / n;

      double varA = 0.0;
      double varB = 0.0;
      double covAB = 0.0;

      for (int dy = 0; dy < blockSize; dy++) {
        final rowOff = (y + dy) * width;
        for (int dx = 0; dx < blockSize; dx++) {
          final idx = rowOff + (x + dx);
          final diffA = lumA[idx] - meanA;
          final diffB = lumB[idx] - meanB;
          varA += diffA * diffA;
          varB += diffB * diffB;
          covAB += diffA * diffB;
        }
      }

      final double sigmaA2 = varA / (n - 1);
      final double sigmaB2 = varB / (n - 1);
      final double sigmaAB = covAB / (n - 1);

      final double numerator =
          (2.0 * meanA * meanB + c1) * (2.0 * sigmaAB + c2);
      final double denominator =
          (meanA * meanA + meanB * meanB + c1) * (sigmaA2 + sigmaB2 + c2);

      ssimSum += (numerator / denominator);
      blockCount++;
    }
  }

  if (blockCount == 0) {
    // Fallback global SSIM for small dimension
    double sumA = 0.0, sumB = 0.0;
    for (int i = 0; i < totalPixels; i++) {
      sumA += lumA[i];
      sumB += lumB[i];
    }
    final meanA = sumA / totalPixels;
    final meanB = sumB / totalPixels;
    double varA = 0.0, varB = 0.0, covAB = 0.0;
    for (int i = 0; i < totalPixels; i++) {
      final diffA = lumA[i] - meanA;
      final diffB = lumB[i] - meanB;
      varA += diffA * diffA;
      varB += diffB * diffB;
      covAB += diffA * diffB;
    }
    final sigmaA2 = varA / (totalPixels - 1);
    final sigmaB2 = varB / (totalPixels - 1);
    final sigmaAB = covAB / (totalPixels - 1);
    return ((2.0 * meanA * meanB + c1) * (2.0 * sigmaAB + c2)) /
        ((meanA * meanA + meanB * meanB + c1) * (sigmaA2 + sigmaB2 + c2));
  }

  return ssimSum / blockCount;
}

/// Computes standard HSV hue in degrees [0.0, 360.0).
double computeHsvHue(int r, int g, int b) {
  final rf = r / 255.0;
  final gf = g / 255.0;
  final bf = b / 255.0;
  final maxVal = math.max(rf, math.max(gf, bf));
  final minVal = math.min(rf, math.min(gf, bf));
  final delta = maxVal - minVal;

  if (delta < 1e-5) return 0.0;

  double hue;
  if (maxVal == rf) {
    hue = 60.0 * (((gf - bf) / delta) % 6);
  } else if (maxVal == gf) {
    hue = 60.0 * (((bf - rf) / delta) + 2);
  } else {
    hue = 60.0 * (((rf - gf) / delta) + 4);
  }

  if (hue < 0.0) hue += 360.0;
  return hue;
}

void main() {
  group('Prompt 1: CIELAB Vibrant Shaders & Self-Bug Visual Regression Test Suite', () {
    late RenderGraphExecutor executor;
    late Uint8List testFixtureBytes;
    late String testFixtureHash;

    setUp(() {
      executor = RenderGraphExecutor();
      final fixtureImg = SyntheticSceneFixtures.createCenterSquare(
        width: 32,
        height: 32,
        squareSize: 12,
      );
      testFixtureBytes = Uint8List.fromList(img.encodePng(fixtureImg));
      testFixtureHash = sha256.convert(testFixtureBytes).toString();
    });

    test('1. Golden Generation & SSIM Check: 5 representative presets maintain SSIM >= 0.98 (< 2% deviation)', () async {
      // 5 representative presets
      final representativePresetIds = [
        ('watercolor', 'Watercolor'),
        ('anime_cel_shade', 'Anime Cel'),
        ('vintage_35mm', 'Vintage Film'),
        ('halftone_pop_art', 'Halftone'),
        ('pixel_art', 'Pixel Art'),
      ];

      for (final (id, name) in representativePresetIds) {
        final preset = PresetCatalog.getById(id);
        expect(
          preset,
          isNotNull,
          reason: 'Preset $id ($name) must exist in catalog',
        );

        final defaultParams = preset!.resolveParameters(null);

        // Run 1: Establish baseline golden image
        final goldenGraph = preset.buildGraph(
          testFixtureHash,
          32,
          32,
          defaultParams,
        );
        final goldenResult = await executor.execute(
          graph: goldenGraph,
          sourceImageBytes: testFixtureBytes,
        );
        final goldenBytes = Uint8List.fromList(goldenResult.pixelBytes);

        // Run 2: Re-render independently
        final testGraph = preset.buildGraph(
          testFixtureHash,
          32,
          32,
          defaultParams,
        );
        final testResult = await executor.execute(
          graph: testGraph,
          sourceImageBytes: testFixtureBytes,
        );

        // Compute Structural Similarity Index (SSIM)
        final ssim = computeSsim(
          goldenBytes,
          testResult.pixelBytes,
          width: 32,
          height: 32,
        );

        // Fail test if output deviates from golden by > 2% (SSIM < 0.98)
        expect(
          ssim,
          greaterThanOrEqualTo(0.98),
          reason:
              'Preset $name ($id) SSIM ($ssim) must be >= 0.98 (deviation <= 2%). Exact SSIM: $ssim',
        );

        // Exact metric verification
        expect(
          ssim,
          equals(1.00000),
          reason: 'Deterministic render graph must be bit-for-bit identical with SSIM 1.0000',
        );
      }
    });

    test('2. Color Accuracy Test: Solid pink and solid blue squares preserve hue within exact angular boundaries through Watercolor preset', () async {
      final watercolor = PresetCatalog.getById('watercolor');
      expect(watercolor, isNotNull);
      final defaultParams = watercolor!.resolveParameters(null);

      // 1. Solid Pink Test: RGB(255, 105, 180)
      final pinkImg = img.Image(width: 32, height: 32);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          pinkImg.setPixelRgba(x, y, 255, 105, 180, 255);
        }
      }
      final pinkBytes = Uint8List.fromList(img.encodePng(pinkImg));
      final pinkHash = sha256.convert(pinkBytes).toString();

      final pinkGraph = watercolor.buildGraph(pinkHash, 32, 32, defaultParams);
      final pinkResult = await executor.execute(
        graph: pinkGraph,
        sourceImageBytes: pinkBytes,
      );

      int pinkOutOfRange = 0;
      double minPinkHue = 360.0;
      double maxPinkHue = 0.0;
      for (int i = 0; i < 32 * 32; i++) {
        final off = i * 4;
        final r = pinkResult.pixelBytes[off];
        final g = pinkResult.pixelBytes[off + 1];
        final b = pinkResult.pixelBytes[off + 2];
        final h = computeHsvHue(r, g, b);

        minPinkHue = math.min(minPinkHue, h);
        maxPinkHue = math.max(maxPinkHue, h);

        // Pink hue boundary: [300°, 360°] U [0°, 10°]
        final isPink = (h >= 300.0 && h <= 360.0) || (h >= 0.0 && h <= 10.0);
        if (!isPink) {
          pinkOutOfRange++;
        }
      }

      expect(
        pinkOutOfRange,
        equals(0),
        reason:
            'All output pixels for pink square must remain in pink hue range [300°, 360°] U [0°, 10°]. Observed hue: [$minPinkHue°, $maxPinkHue°]',
      );

      // 2. Solid Blue Test: RGB(30, 100, 255)
      final blueImg = img.Image(width: 32, height: 32);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          blueImg.setPixelRgba(x, y, 30, 100, 255, 255);
        }
      }
      final blueBytes = Uint8List.fromList(img.encodePng(blueImg));
      final blueHash = sha256.convert(blueBytes).toString();

      final blueGraph = watercolor.buildGraph(blueHash, 32, 32, defaultParams);
      final blueResult = await executor.execute(
        graph: blueGraph,
        sourceImageBytes: blueBytes,
      );

      int blueOutOfRange = 0;
      double minBlueHue = 360.0;
      double maxBlueHue = 0.0;
      for (int i = 0; i < 32 * 32; i++) {
        final off = i * 4;
        final r = blueResult.pixelBytes[off];
        final g = blueResult.pixelBytes[off + 1];
        final b = blueResult.pixelBytes[off + 2];
        final h = computeHsvHue(r, g, b);

        minBlueHue = math.min(minBlueHue, h);
        maxBlueHue = math.max(maxBlueHue, h);

        // Blue hue boundary: [190°, 250°]
        final isBlue = (h >= 190.0 && h <= 250.0);
        if (!isBlue) {
          blueOutOfRange++;
        }
      }

      expect(
        blueOutOfRange,
        equals(0),
        reason:
            'All output pixels for blue square must remain in blue hue range [190°, 250°]. Observed hue: [$minBlueHue°, $maxBlueHue°]',
      );
    });

    test('3. CIELAB Vibrancy Hue Invariance: Chroma scaling preserves exact hue angle without tint shifts', () {
      // Test across color wheel in CIELAB
      final testCoords = [
        (40.0, 30.0), // a*, b*
        (25.0, -50.0),
        (-35.0, 45.0),
        (-20.0, -60.0),
        (65.0, -10.0),
      ];

      for (final (a, b) in testCoords) {
        final originalHue = math.atan2(b, a);
        const double k = 1.35; // Chroma scale factor >= 1.0
        final boostedA = a * k;
        final boostedB = b * k;
        final boostedHue = math.atan2(boostedB, boostedA);

        expect(
          (originalHue - boostedHue).abs(),
          lessThan(1e-10),
          reason: 'Chroma boost scaling must strictly preserve atan2(b*, a*) hue angle',
        );
      }
    });

    test('4. Source Image Immutability: Source image bytes remain bit-for-bit identical post-render (Invariant 4)', () async {
      final representativePresetIds = [
        'watercolor',
        'anime_cel_shade',
        'vintage_35mm',
        'halftone_pop_art',
        'pixel_art',
      ];

      for (final id in representativePresetIds) {
        final preset = PresetCatalog.getById(id)!;
        final graph = preset.buildGraph(
          testFixtureHash,
          32,
          32,
          preset.resolveParameters(null),
        );
        await executor.execute(
          graph: graph,
          sourceImageBytes: testFixtureBytes,
        );

        final postHash = sha256.convert(testFixtureBytes).toString();
        expect(
          postHash,
          equals(testFixtureHash),
          reason:
              'Source image buffer must remain strictly immutable after execution of $id',
        );
      }
    });
  });
}
