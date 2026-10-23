import 'dart:math' as math;
import 'dart:typed_data';
import 'image_buffer.dart';

/// 2D integer coordinate point.
class Point2D {
  final int x;
  final int y;

  const Point2D(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point2D &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;

  @override
  String toString() => '($x, $y)';
}

/// Result of palette quantization containing the remapped image buffer and extracted palette.
class QuantizationResult {
  final ImageBuffer quantizedImage;
  final List<(int, int, int)> palette;

  const QuantizationResult({
    required this.quantizedImage,
    required this.palette,
  });
}

/// Internal bounding box for Median Cut quantization.
class _ColorBox {
  final List<(int, int, int)> colors;

  _ColorBox(this.colors);

  int get count => colors.length;

  int minR = 255, maxR = 0;
  int minG = 255, maxG = 0;
  int minB = 255, maxB = 0;

  void computeBounds() {
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
  }

  int get rangeR => maxR - minR;
  int get rangeG => maxG - minG;
  int get rangeB => maxB - minB;
  int get maxRange => math.max(rangeR, math.max(rangeG, rangeB));

  (_ColorBox, _ColorBox) split() {
    computeBounds();
    final rRange = rangeR;
    final gRange = rangeG;
    final bRange = rangeB;

    if (rRange >= gRange && rRange >= bRange) {
      colors.sort((a, b) => a.$1.compareTo(b.$1));
    } else if (gRange >= rRange && gRange >= bRange) {
      colors.sort((a, b) => a.$2.compareTo(b.$2));
    } else {
      colors.sort((a, b) => a.$3.compareTo(b.$3));
    }

    final mid = colors.length ~/ 2;
    return (
      _ColorBox(colors.sublist(0, mid)),
      _ColorBox(colors.sublist(mid)),
    );
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
}

/// Batch B operations: Contour extraction, Median-cut palette quantization,
/// and Luminance-preserving color replacement.
class BatchBOperations {
  /// Extracts 4-connected boundary points forming contours from a thresholded binary mask.
  /// Points on the boundary of regions where luminance >= threshold are identified.
  static List<List<Point2D>> extractContours(
    ImageBuffer src, {
    int luminanceThreshold = 128,
  }) {
    final w = src.width;
    final h = src.height;
    final mask = Uint8List(w * h);
    final srcData = src.data;

    for (int i = 0; i < w * h; i++) {
      final off = i * 4;
      final y = ((299 * srcData[off] +
              587 * srcData[off + 1] +
              114 * srcData[off + 2]) ~/
          1000);
      mask[i] = y >= luminanceThreshold ? 1 : 0;
    }

    final visited = Uint8List(w * h);
    final contours = <List<Point2D>>[];

    bool isBoundary(int x, int y) {
      if (mask[y * w + x] == 0) return false;
      // Check 4-connected neighbors
      if (x == 0 || mask[y * w + (x - 1)] == 0) return true;
      if (x == w - 1 || mask[y * w + (x + 1)] == 0) return true;
      if (y == 0 || mask[(y - 1) * w + x] == 0) return true;
      if (y == h - 1 || mask[(y + 1) * w + x] == 0) return true;
      return false;
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        if (mask[idx] == 1 && visited[idx] == 0 && isBoundary(x, y)) {
          // Found unvisited boundary pixel; trace connected boundary component
          final contour = <Point2D>[];
          final queue = <Point2D>[Point2D(x, y)];
          visited[idx] = 1;

          while (queue.isNotEmpty) {
            final curr = queue.removeLast();
            contour.add(curr);

            // Explore 8-connected neighbors for smooth contour continuity
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                final nx = curr.x + dx;
                final ny = curr.y + dy;
                if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
                  final nIdx = ny * w + nx;
                  if (visited[nIdx] == 0 && isBoundary(nx, ny)) {
                    visited[nIdx] = 1;
                    queue.add(Point2D(nx, ny));
                  }
                }
              }
            }
          }
          if (contour.isNotEmpty) {
            contours.add(contour);
          }
        }
      }
    }
    // Sort contours deterministically: top-left (y, x), then descending length
    contours.sort((a, b) {
      final pA = a.first;
      final pB = b.first;
      if (pA.y != pB.y) return pA.y.compareTo(pB.y);
      if (pA.x != pB.x) return pA.x.compareTo(pB.x);
      return b.length.compareTo(a.length);
    });
    return contours;
  }

  /// Quantizes an image to K representative palette colors using the Median Cut algorithm.
  /// Returns both the quantized ImageBuffer and the extracted discrete palette colors.
  static QuantizationResult quantizePalette(ImageBuffer src, {int k = 4}) {
    assert(k >= 1, 'k must be at least 1');
    final w = src.width;
    final h = src.height;
    final total = w * h;

    final pixels = <(int, int, int)>[];
    // Subsample pixels if total image size is very large (> 100k) to maintain sub-second performance
    final step = total > 100000 ? (total ~/ 50000) : 1;
    final srcData = src.data;

    for (int i = 0; i < total; i += step) {
      final off = i * 4;
      pixels.add((srcData[off], srcData[off + 1], srcData[off + 2]));
    }

    final boxes = <_ColorBox>[_ColorBox(pixels)];
    while (boxes.length < k) {
      // Find box with greatest range that has more than 1 pixel
      int bestIdx = -1;
      int maxRange = -1;
      for (int i = 0; i < boxes.length; i++) {
        if (boxes[i].count > 1) {
          boxes[i].computeBounds();
          if (boxes[i].maxRange > maxRange) {
            maxRange = boxes[i].maxRange;
            bestIdx = i;
          }
        }
      }
      if (bestIdx == -1 || maxRange <= 0) break; // Cannot split further

      final target = boxes.removeAt(bestIdx);
      final (box1, box2) = target.split();
      boxes.add(box1);
      boxes.add(box2);
    }

    final palette = boxes.map((b) => b.averageColor()).toList();
    // Canonicalize palette ordering: sort by ascending luminance with RGB tie-breaking
    palette.sort((a, b) {
      final lumA = (299 * a.$1 + 587 * a.$2 + 114 * a.$3);
      final lumB = (299 * b.$1 + 587 * b.$2 + 114 * b.$3);
      if (lumA != lumB) return lumA.compareTo(lumB);
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.compareTo(b.$3);
    });

    // Map each pixel in src to closest palette color
    final dst = ImageBuffer(width: w, height: h);
    final dstData = dst.data;

    (int, int, int) findClosest(int r, int g, int b) {
      int bestDist = 0x7FFFFFFF;
      var bestColor = palette.first;
      for (final p in palette) {
        final dr = r - p.$1;
        final dg = g - p.$2;
        final db = b - p.$3;
        final dist = dr * dr + dg * dg + db * db;
        if (dist < bestDist) {
          bestDist = dist;
          bestColor = p;
        }
      }
      return bestColor;
    }

    for (int i = 0; i < total; i++) {
      final off = i * 4;
      final r = srcData[off];
      final g = srcData[off + 1];
      final b = srcData[off + 2];
      final a = srcData[off + 3];

      final (pr, pg, pb) = findClosest(r, g, b);
      dstData[off] = pr;
      dstData[off + 1] = pg;
      dstData[off + 2] = pb;
      dstData[off + 3] = a;
    }

    return QuantizationResult(quantizedImage: dst, palette: palette);
  }

  /// Replaces target color with replacement color while preserving the pixel's original luminance.
  /// Uses Euclidean RGB distance with softness tolerance and preserves alpha.
  static ImageBuffer replaceColorPreservingLuminance(
    ImageBuffer src, {
    required (int, int, int) targetColor,
    required (int, int, int) replacementColor,
    double tolerance = 0.35, // 0.0 to 1.0
  }) {
    final w = src.width;
    final h = src.height;
    final dst = ImageBuffer(width: w, height: h);
    final srcData = src.data;
    final dstData = dst.data;
    final total = w * h;

    final maxDist = 441.67295593; // sqrt(255^2 * 3)
    final tolDist = tolerance * maxDist;

    final (tr, tg, tb) = targetColor;
    final (rr, rg, rb) = replacementColor;

    // Luminance of pure replacement color
    final repLum = (299 * rr + 587 * rg + 114 * rb) / 1000.0;

    for (int i = 0; i < total; i++) {
      final off = i * 4;
      final r = srcData[off];
      final g = srcData[off + 1];
      final b = srcData[off + 2];
      final a = srcData[off + 3];

      final dr = r - tr;
      final dg = g - tg;
      final db = b - tb;
      final dist = math.sqrt(dr * dr + dg * dg + db * db);

      if (dist < tolDist) {
        // Compute blend factor (1.0 at center, 0.0 at edge of tolerance sphere)
        final weight = 1.0 - (dist / tolDist);

        // Original pixel luminance
        final origLum = (299 * r + 587 * g + 114 * b) / 1000.0;

        // Scale replacement RGB to match original pixel luminance
        double scaledR, scaledG, scaledB;
        if (repLum > 1.0) {
          final scale = origLum / repLum;
          scaledR = (rr * scale).clamp(0.0, 255.0);
          scaledG = (rg * scale).clamp(0.0, 255.0);
          scaledB = (rb * scale).clamp(0.0, 255.0);
        } else {
          // If replacement is pure black, fall back to grayscale luminance
          scaledR = origLum;
          scaledG = origLum;
          scaledB = origLum;
        }

        // Blend between original and luminance-matched replacement
        dstData[off] =
            (r * (1.0 - weight) + scaledR * weight).round().clamp(0, 255);
        dstData[off + 1] =
            (g * (1.0 - weight) + scaledG * weight).round().clamp(0, 255);
        dstData[off + 2] =
            (b * (1.0 - weight) + scaledB * weight).round().clamp(0, 255);
      } else {
        // Outside tolerance; pixel is unchanged
        dstData[off] = r;
        dstData[off + 1] = g;
        dstData[off + 2] = b;
      }
      dstData[off + 3] = a;
    }

    return dst;
  }
}
