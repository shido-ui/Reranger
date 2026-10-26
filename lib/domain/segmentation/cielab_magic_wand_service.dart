import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import '../color/recolor_mask.dart';

/// Math Mode: CIELAB Color Tolerance Magic Wand.
/// Designed specifically for Anime, Manga, and 2D Digital Art.
/// Executes connected flood fill in CIELAB color space, strictly bounded by line art ink outlines.
class CielabMagicWandService {
  const CielabMagicWandService();

  /// Executes connected region flood fill starting at ([seedX], [seedY]).
  /// Only includes connected pixels within the specified [hueTolerance] and [colorTolerance],
  /// and strictly halts at line art boundaries.
  RegionMask floodFill({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required int seedX,
    required int seedY,
    double hueTolerance = 0.22,
    double colorTolerance = 0.20,
  }) {
    final mask = RegionMask.empty(width, height);
    if (width <= 0 ||
        height <= 0 ||
        seedX < 0 ||
        seedX >= width ||
        seedY < 0 ||
        seedY >= height) {
      return mask;
    }

    developer.log(
      '[Magic Wand] Starting CIELAB flood fill at ($seedX, $seedY), hueTol=$hueTolerance, colorTol=$colorTolerance',
      name: 'MagicWand',
    );

    final total = width * height;

    // 1. Build Luminance and Line Art Edge Map
    final lum = Float32List(total);
    for (int i = 0; i < total; i++) {
      final off = i * 4;
      final r = rgbaBytes[off] / 255.0;
      final g = rgbaBytes[off + 1] / 255.0;
      final b = rgbaBytes[off + 2] / 255.0;
      lum[i] = (0.299 * r + 0.587 * g + 0.114 * b);
    }

    final rawEdge = Uint8List(total);
    for (int y = 0; y < height; y++) {
      final ym1 = math.max(0, y - 1);
      final yp1 = math.min(height - 1, y + 1);
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        final xm1 = math.max(0, x - 1);
        final xp1 = math.min(width - 1, x + 1);
        final idx = rowOff + x;

        // Full 3x3 Sobel Operator
        final p00 = lum[ym1 * width + xm1];
        final p01 = lum[ym1 * width + x];
        final p02 = lum[ym1 * width + xp1];

        final p10 = lum[rowOff + xm1];
        final p12 = lum[rowOff + xp1];

        final p20 = lum[yp1 * width + xm1];
        final p21 = lum[yp1 * width + x];
        final p22 = lum[yp1 * width + xp1];

        final gx =
            (-1.0 * p00 + 1.0 * p02) +
            (-2.0 * p10 + 2.0 * p12) +
            (-1.0 * p20 + 1.0 * p22);
        final gy =
            (-1.0 * p00 - 2.0 * p01 - 1.0 * p02) +
            (1.0 * p20 + 2.0 * p21 + 1.0 * p22);

        final sobelMag = math.sqrt(gx * gx + gy * gy) / 8.0;
        if (lum[idx] < 0.22 || sobelMag > 0.08) {
          rawEdge[idx] = 1;
        }
      }
    }

    // 1-pixel Morphological Dilation of edge map to seal anti-aliased diagonal gaps
    final isEdge = Uint8List.fromList(rawEdge);
    for (int y = 1; y < height - 1; y++) {
      final rowOff = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = rowOff + x;
        if (rawEdge[idx] == 1) {
          isEdge[idx - 1] = 1;
          isEdge[idx + 1] = 1;
          isEdge[idx - width] = 1;
          isEdge[idx + width] = 1;
          isEdge[idx - width - 1] = 1;
          isEdge[idx - width + 1] = 1;
          isEdge[idx + width - 1] = 1;
          isEdge[idx + width + 1] = 1;
        }
      }
    }
    // Never allow seed pixel to be marked as an edge
    isEdge[seedY * width + seedX] = 0;

    // 2. Convert Seed Pixel to CIELAB with float32 precision
    final seedOff = (seedY * width + seedX) * 4;
    final seedLab = rgbToLab(
      rgbaBytes[seedOff] / 255.0,
      rgbaBytes[seedOff + 1] / 255.0,
      rgbaBytes[seedOff + 2] / 255.0,
    );
    final sL = seedLab[0];
    final sA = seedLab[1];
    final sB = seedLab[2];
    double sHue = math.atan2(sB, sA) * 180.0 / math.pi;
    if (sHue < 0) sHue += 360.0;
    final sChroma = math.sqrt(sA * sA + sB * sB);

    // 3. Breadth-First Connected Flood Fill
    final visited = Uint8List(total);
    final queue = Queue<int>();

    final seedIdx = seedY * width + seedX;
    visited[seedIdx] = 1;
    mask.buffer[seedIdx] = 255;
    queue.add(seedIdx);

    final effColTol = colorTolerance * 65.0;
    final effHueTol = hueTolerance * 120.0;

    const dx = [1, -1, 0, 0];
    const dy = [0, 0, 1, -1];

    while (queue.isNotEmpty) {
      final currIdx = queue.removeFirst();
      final cx = currIdx % width;
      final cy = currIdx ~/ width;

      for (int d = 0; d < 4; d++) {
        final nx = cx + dx[d];
        final ny = cy + dy[d];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;

        final nidx = ny * width + nx;
        if (visited[nidx] == 1) continue;
        visited[nidx] = 1;

        // Strictly halt at ink outline edges!
        if (isEdge[nidx] == 1) continue;

        final noff = nidx * 4;
        final nLab = rgbToLab(
          rgbaBytes[noff] / 255.0,
          rgbaBytes[noff + 1] / 255.0,
          rgbaBytes[noff + 2] / 255.0,
        );
        final nL = nLab[0];
        final nA = nLab[1];
        final nB = nLab[2];

        final dl = nL - sL;
        final da = nA - sA;
        final db = nB - sB;
        final deltaE = math.sqrt(dl * dl + da * da + db * db);

        double nHue = math.atan2(nB, nA) * 180.0 / math.pi;
        if (nHue < 0) nHue += 360.0;
        double dh = (nHue - sHue).abs();
        if (dh > 180.0) dh = 360.0 - dh;
        final nChroma = math.sqrt(nA * nA + nB * nB);

        bool matches = false;
        if (sChroma < 10.0 && nChroma < 15.0) {
          // Low chroma / neutral tones
          matches = deltaE <= effColTol;
        } else {
          matches = (dh <= effHueTol && deltaE <= effColTol * 1.5);
        }

        if (matches) {
          mask.buffer[nidx] = 255;
          queue.add(nidx);
        }
      }
    }

    return mask;
  }

  /// Converts normalized sRGB in [0.0, 1.0] to CIELAB [L*, a*, b*].
  static List<double> rgbToLab(double r, double g, double b) {
    final rLin = srgbToLinear(r);
    final gLin = srgbToLinear(g);
    final bLin = srgbToLinear(b);

    // Clamp intermediate XYZ values to [0.0, 1.0] to prevent color banding
    final x =
        ((0.4124564 * rLin + 0.3575761 * gLin + 0.1804375 * bLin) / 0.95047)
            .clamp(0.0, 1.0);
    final y =
        ((0.2126729 * rLin + 0.7151522 * gLin + 0.0721750 * bLin) / 1.00000)
            .clamp(0.0, 1.0);
    final z =
        ((0.0193339 * rLin + 0.1191920 * gLin + 0.9503041 * bLin) / 1.08883)
            .clamp(0.0, 1.0);

    final fx = labF(x);
    final fy = labF(y);
    final fz = labF(z);

    final labL = 116.0 * fy - 16.0;
    final labA = 500.0 * (fx - fy);
    final labB = 200.0 * (fy - fz);

    return [labL, labA, labB];
  }

  /// Converts CIELAB [L*, a*, b*] back to sRGB bytes [0, 255].
  static List<int> labToRgb(double l, double a, double b) {
    final fy = (l + 16.0) / 116.0;
    final fx = a / 500.0 + fy;
    final fz = fy - b / 200.0;

    double fInv(double t) {
      final t3 = t * t * t;
      return (t3 > 0.008856451679) ? t3 : (t - 16.0 / 116.0) / 7.787037037;
    }

    final x = (fInv(fx) * 0.95047).clamp(0.0, 1.0);
    final y = (fInv(fy) * 1.00000).clamp(0.0, 1.0);
    final z = (fInv(fz) * 1.08883).clamp(0.0, 1.0);

    final rLin = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final gLin = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final bLin = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    final rByte = (linearToSrgb(rLin) * 255.0).round().clamp(0, 255);
    final gByte = (linearToSrgb(gLin) * 255.0).round().clamp(0, 255);
    final bByte = (linearToSrgb(bLin) * 255.0).round().clamp(0, 255);

    return [rByte, gByte, bByte];
  }

  /// High-fidelity Luminance-Preserving Recolor in CIELAB space.
  /// Replaces a* and b* with target chromaticity while keeping original L* (100% shadow/highlight preservation).
  static List<int> recolorLuminancePreserving({
    required int rIn,
    required int gIn,
    required int bIn,
    required int targetR,
    required int targetG,
    required int targetB,
  }) {
    final inLab = rgbToLab(rIn / 255.0, gIn / 255.0, bIn / 255.0);
    final targetLab = rgbToLab(
      targetR / 255.0,
      targetG / 255.0,
      targetB / 255.0,
    );

    // Retain original L* luminance, substitute target chromaticity (a*, b*)
    return labToRgb(inLab[0], targetLab[1], targetLab[2]);
  }

  static double srgbToLinear(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double linearToSrgb(double c) {
    final clamped = c.clamp(0.0, 1.0);
    return clamped <= 0.0031308
        ? 12.92 * clamped
        : 1.055 * math.pow(clamped, 1.0 / 2.4) - 0.055;
  }

  static double labF(double t) {
    if (t > 0.008856451679) {
      return math.pow(t, 1.0 / 3.0).toDouble();
    } else {
      return 7.787037 * t + 0.137931034;
    }
  }
}
