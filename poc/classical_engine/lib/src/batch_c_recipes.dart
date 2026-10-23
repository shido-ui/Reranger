import 'dart:math' as math;
import 'image_buffer.dart';
import 'batch_a_ops.dart';
import 'batch_b_ops.dart';

/// Batch C: Paper/grain overlay and three visibly distinct render recipes.
class BatchCRecipes {
  /// Applies a deterministic procedural film/paper grain overlay using a 32-bit PRNG.
  /// Blends grain noise onto RGB channels while preserving original alpha.
  static ImageBuffer applyGrainOverlay(
    ImageBuffer src, {
    int seed = 42,
    double intensity = 0.15,
  }) {
    final w = src.width;
    final h = src.height;
    final dst = ImageBuffer(width: w, height: h);
    final srcData = src.data;
    final dstData = dst.data;
    final total = w * h;

    int prngState = seed & 0xFFFFFFFF;
    int nextPrng() {
      // 32-bit Linear Congruential Generator (Numerical Recipes)
      prngState = (prngState * 1664525 + 1013904223) & 0xFFFFFFFF;
      return prngState;
    }

    final scale = intensity * 128.0;

    for (int i = 0; i < total; i++) {
      final off = i * 4;
      final r = srcData[off];
      final g = srcData[off + 1];
      final b = srcData[off + 2];
      final a = srcData[off + 3];

      // Normalized noise value centered around 0 in [-1.0, 1.0]
      final noise = ((nextPrng() & 0xFFFF) / 32768.0 - 1.0) * scale;

      // Modulate noise by pixel alpha to protect transparent pixels and blend smoothly
      final alphaFactor = a / 255.0;
      final effectiveNoise = noise * alphaFactor;

      dstData[off] = (r + effectiveNoise).round().clamp(0, 255);
      dstData[off + 1] = (g + effectiveNoise).round().clamp(0, 255);
      dstData[off + 2] = (b + effectiveNoise).round().clamp(0, 255);
      dstData[off + 3] = a;
    }
    return dst;
  }

  /// Recipe 1: "Dramatic Monochrome Ink"
  /// - Full BT.601 Grayscale conversion
  /// - Sobel edge extraction to identify structural boundaries
  /// - Inverted edge blend (subtracting edge magnitude to create dark ink contours)
  /// - Steep contrast gamma curve to emphasize ink marks
  static ImageBuffer recipeDramaticMonochromeInk(ImageBuffer src) {
    final gray = BatchAOperations.toGrayscale(src);
    final edges = BatchAOperations.sobelEdgeDetection(src);

    final w = src.width;
    final h = src.height;
    final dst = ImageBuffer(width: w, height: h);
    final grayData = gray.data;
    final edgeData = edges.data;
    final dstData = dst.data;
    final total = w * h;

    for (int i = 0; i < total; i++) {
      final off = i * 4;
      final gVal = grayData[off];
      final eVal = edgeData[off];

      // Inverted ink subtract: strong edges darken the base tone
      final inkVal = (gVal - (eVal * 0.85).round()).clamp(0, 255);

      // Contrast gamma curve (gamma ~ 1.5)
      final norm = inkVal / 255.0;
      final finalVal = (math.pow(norm, 1.5) * 255.0).round().clamp(0, 255);

      dstData[off] = finalVal;
      dstData[off + 1] = finalVal;
      dstData[off + 2] = finalVal;
      dstData[off + 3] = grayData[off + 3];
    }
    return dst;
  }

  /// Recipe 2: "Pastel Posterize & Grain"
  /// - Median Cut palette reduction (K=4 color clusters)
  /// - Film/paper texture grain overlay for vintage tactile print aesthetic
  static ImageBuffer recipePastelPosterizeAndGrain(
    ImageBuffer src, {
    int k = 4,
    int seed = 1337,
  }) {
    final quantized =
        BatchBOperations.quantizePalette(src, k: k).quantizedImage;
    return applyGrainOverlay(quantized, seed: seed, intensity: 0.12);
  }

  /// Recipe 3: "Warm DuoTone Remap"
  /// - Luminance-based two-tone gradient mapping:
  ///   Shadows: Deep Indigo (24, 28, 64)
  ///   Highlights: Warm Amber Gold (255, 210, 140)
  /// - Radial vignette darkening outer edges
  static ImageBuffer recipeWarmDuoTone(ImageBuffer src) {
    final w = src.width;
    final h = src.height;
    final dst = ImageBuffer(width: w, height: h);
    final srcData = src.data;
    final dstData = dst.data;

    const shadowR = 24.0, shadowG = 28.0, shadowB = 64.0;
    const highR = 255.0, highG = 210.0, highB = 140.0;

    final cx = w / 2.0;
    final cy = h / 2.0;
    final maxDist = math.sqrt(cx * cx + cy * cy);

    for (int y = 0; y < h; y++) {
      final dy = y - cy;
      for (int x = 0; x < w; x++) {
        final off = (y * w + x) * 4;
        final r = srcData[off];
        final g = srcData[off + 1];
        final b = srcData[off + 2];
        final a = srcData[off + 3];

        // Tonal luminance factor [0.0, 1.0]
        final lumT = ((299 * r + 587 * g + 114 * b) / 1000.0) / 255.0;

        // Gradient interpolation between shadow and highlight
        var mappedR = shadowR + (highR - shadowR) * lumT;
        var mappedG = shadowG + (highG - shadowG) * lumT;
        var mappedB = shadowB + (highB - shadowB) * lumT;

        // Radial vignette falloff
        final dx = x - cx;
        final dist = math.sqrt(dx * dx + dy * dy);
        final vig =
            (1.0 - 0.35 * (dist / maxDist) * (dist / maxDist)).clamp(0.0, 1.0);

        dstData[off] = (mappedR * vig).round().clamp(0, 255);
        dstData[off + 1] = (mappedG * vig).round().clamp(0, 255);
        dstData[off + 2] = (mappedB * vig).round().clamp(0, 255);
        dstData[off + 3] = a;
      }
    }
    return dst;
  }
}
