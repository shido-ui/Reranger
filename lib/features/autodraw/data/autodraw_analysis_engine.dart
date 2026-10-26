import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Dynamic analysis engine calculating stroke width, perceptual CIELAB colors,
/// and local variance-guided stroke density without hardcoded heuristics.
class AutodrawAnalysisEngine {
  const AutodrawAnalysisEngine();

  // D65 Standard Illuminant reference white
  static const double _xn = 0.95047;
  static const double _yn = 1.00000;
  static const double _zn = 1.08883;

  /// Computes 3x3 Sobel gradient magnitude at pixel (x, y).
  static double computeSobelGradient(
    int x,
    int y,
    Uint8List lum,
    int width,
    int height,
  ) {
    if (x <= 0 || x >= width - 1 || y <= 0 || y >= height - 1) return 0.0;
    final rowPrev = (y - 1) * width;
    final rowCurr = y * width;
    final rowNext = (y + 1) * width;

    final p00 = lum[rowPrev + x - 1];
    final p01 = lum[rowPrev + x];
    final p02 = lum[rowPrev + x + 1];
    final p10 = lum[rowCurr + x - 1];
    final p12 = lum[rowCurr + x + 1];
    final p20 = lum[rowNext + x - 1];
    final p21 = lum[rowNext + x];
    final p22 = lum[rowNext + x + 1];

    final gx = (p02 + 2 * p12 + p22) - (p00 + 2 * p10 + p20);
    final gy = (p20 + 2 * p21 + p22) - (p00 + 2 * p01 + p02);

    return math.sqrt(gx * gx + gy * gy);
  }

  /// Calculates dynamic stroke width based on local Sobel gradient magnitude:
  /// - High gradients (sharp edges): produces thinner lines (width down to 1.0).
  /// - Low gradients (flat colors): produces thicker brush fills (width up to 15.0).
  static double computeDynamicStrokeWidth({
    required double gradient,
    required bool isEdgeLine,
    double minWidth = 1.0,
    double maxWidth = 15.0,
  }) {
    if (isEdgeLine) {
      // Edges: sharp high gradient -> thin 1.0px detail; lower gradient -> 1.5px - 2.2px
      final normGrad = (gradient / 255.0).clamp(0.0, 1.0);
      return (1.0 + (1.0 - normGrad) * 1.2).clamp(1.0, 2.5);
    } else {
      // Fills: flat low gradient -> broad 15.0px brush; higher gradient -> 6.0px
      final normGrad = (gradient / 100.0).clamp(0.0, 1.0);
      return (6.0 + (1.0 - normGrad) * 9.0).clamp(6.0, maxWidth);
    }
  }

  /// Perceptual Color Sampling:
  /// Converts local pixels to CIELAB, averages the L*, a*, and b* channels (chromaticity and lightness),
  /// and converts back to sRGB. Matches human color perception without flat mathematical RGB clipping.
  static Color samplePerceptualColor(
    Uint8List rgba,
    int width,
    int height,
    List<int> pixelIndices,
  ) {
    if (pixelIndices.isEmpty) return const Color(0xFF000000);

    double sumL = 0.0;
    double sumA = 0.0;
    double sumB = 0.0;
    int count = 0;

    for (final idx in pixelIndices) {
      if (idx < 0 || idx >= width * height) continue;
      final off = idx * 4;
      final r = rgba[off];
      final g = rgba[off + 1];
      final b = rgba[off + 2];

      final lab = _rgbToLab(r, g, b);
      sumL += lab[0];
      sumA += lab[1];
      sumB += lab[2];
      count++;
    }

    if (count == 0) return const Color(0xFF000000);

    final avgL = sumL / count;
    final avgA = sumA / count;
    final avgB = sumB / count;

    final rgb = _labToRgb(avgL, avgA, avgB);
    return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  }

  /// Samples perceptual CIELAB average color along a horizontal run segment.
  static Color sampleRunPerceptualColor(
    Uint8List rgba,
    int width,
    int height,
    int startX,
    int endX,
    int y,
  ) {
    final indices = <int>[];
    final rowOff = y * width;
    for (int x = startX; x <= endX; x++) {
      indices.add(rowOff + x);
    }
    return samplePerceptualColor(rgba, width, height, indices);
  }

  /// Analyzes local luminance variance in a (2*radius+1) square window.
  /// High variance areas require denser stroke passes.
  static double computeLocalVariance(
    int x,
    int y,
    int radius,
    Uint8List lum,
    int width,
    int height,
  ) {
    final xMin = math.max(0, x - radius);
    final xMax = math.min(width - 1, x + radius);
    final yMin = math.max(0, y - radius);
    final yMax = math.min(height - 1, y + radius);

    double sum = 0.0;
    int count = 0;
    for (int cy = yMin; cy <= yMax; cy++) {
      final row = cy * width;
      for (int cx = xMin; cx <= xMax; cx++) {
        sum += lum[row + cx];
        count++;
      }
    }

    if (count < 2) return 0.0;
    final mean = sum / count;

    double varSum = 0.0;
    for (int cy = yMin; cy <= yMax; cy++) {
      final row = cy * width;
      for (int cx = xMin; cx <= xMax; cx++) {
        final diff = lum[row + cx] - mean;
        varSum += diff * diff;
      }
    }

    return math.sqrt(varSum / (count - 1));
  }

  // Helper: sRGB [0..255] to CIELAB [L*, a*, b*]
  static List<double> _rgbToLab(int r, int g, int b) {
    // 1. sRGB to linear RGB
    final rLin = _sRgbToLinear(r / 255.0);
    final gLin = _sRgbToLinear(g / 255.0);
    final bLin = _sRgbToLinear(b / 255.0);

    // 2. Linear RGB to CIE XYZ (D65)
    final x = 0.4124564 * rLin + 0.3575761 * gLin + 0.1804375 * bLin;
    final y = 0.2126729 * rLin + 0.7151522 * gLin + 0.0721750 * bLin;
    final z = 0.0193339 * rLin + 0.1191920 * gLin + 0.9503041 * bLin;

    // 3. CIE XYZ to CIELAB
    final xr = x / _xn;
    final yr = y / _yn;
    final zr = z / _zn;

    final fx = _labF(xr);
    final fy = _labF(yr);
    final fz = _labF(zr);

    final lStar = (116.0 * fy) - 16.0;
    final aStar = 500.0 * (fx - fy);
    final bStar = 200.0 * (fy - fz);

    return [lStar, aStar, bStar];
  }

  // Helper: CIELAB [L*, a*, b*] to sRGB [0..255]
  static List<int> _labToRgb(double lStar, double aStar, double bStar) {
    final fy = (lStar + 16.0) / 116.0;
    final fx = (aStar / 500.0) + fy;
    final fz = fy - (bStar / 200.0);

    final xr = _labFInv(fx);
    final yr = _labFInv(fy);
    final zr = _labFInv(fz);

    final x = xr * _xn;
    final y = yr * _yn;
    final z = zr * _zn;

    final rLin = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final gLin = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final bLin = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    final r = (_linearToSRgb(rLin) * 255.0).round().clamp(0, 255);
    final g = (_linearToSRgb(gLin) * 255.0).round().clamp(0, 255);
    final b = (_linearToSRgb(bLin) * 255.0).round().clamp(0, 255);

    return [r, g, b];
  }

  static double _sRgbToLinear(double c) {
    return (c <= 0.04045)
        ? (c / 12.92)
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _linearToSRgb(double c) {
    final clamped = c.clamp(0.0, 1.0);
    return (clamped <= 0.0031308)
        ? (clamped * 12.92)
        : (1.055 * math.pow(clamped, 1.0 / 2.4) - 0.055);
  }

  static double _labF(double t) {
    return (t > 0.008856)
        ? math.pow(t, 1.0 / 3.0).toDouble()
        : (7.787 * t + 16.0 / 116.0);
  }

  static double _labFInv(double t) {
    final t3 = t * t * t;
    return (t3 > 0.008856) ? t3 : (t - 16.0 / 116.0) / 7.787;
  }
}
