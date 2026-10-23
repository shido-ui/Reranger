import 'dart:math' as math;
import 'dart:typed_data';
import 'image_buffer.dart';

/// Batch A operations: Image orientation handling, grayscale conversion, and Sobel edge detection.
class BatchAOperations {
  /// Applies EXIF orientation transformation non-destructively to produce a new ImageBuffer.
  /// Supported EXIF tags (1 through 8):
  /// - 1: Normal (0 deg)
  /// - 2: Mirrored Horizontal (Flip X)
  /// - 3: Upside Down (180 deg)
  /// - 4: Mirrored Vertical (Flip Y)
  /// - 5: Transposed (Flip X and Rotate 270 deg CW)
  /// - 6: Rotated 90 deg Clockwise
  /// - 7: Transverse (Flip X and Rotate 90 deg CW)
  /// - 8: Rotated 270 deg Clockwise (90 deg Counter-Clockwise)
  static ImageBuffer applyOrientation(ImageBuffer src, int exifOrientation) {
    switch (exifOrientation) {
      case 1:
        return src.clone();

      case 2:
        {
          // Mirrored Horizontal (Flip X)
          final dst = ImageBuffer(width: src.width, height: src.height);
          for (int y = 0; y < src.height; y++) {
            for (int x = 0; x < src.width; x++) {
              final dstX = src.width - 1 - x;
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(dstX, y, r, g, b, a);
            }
          }
          return dst;
        }

      case 3:
        {
          // 180 degrees
          final dst = ImageBuffer(width: src.width, height: src.height);
          for (int y = 0; y < src.height; y++) {
            final dstY = src.height - 1 - y;
            for (int x = 0; x < src.width; x++) {
              final dstX = src.width - 1 - x;
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(dstX, dstY, r, g, b, a);
            }
          }
          return dst;
        }

      case 4:
        {
          // Mirrored Vertical (Flip Y)
          final dst = ImageBuffer(width: src.width, height: src.height);
          for (int y = 0; y < src.height; y++) {
            final dstY = src.height - 1 - y;
            for (int x = 0; x < src.width; x++) {
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(x, dstY, r, g, b, a);
            }
          }
          return dst;
        }

      case 5:
        {
          // Transposed (Flip X and rotate 270 CW, width and height swap)
          final dst = ImageBuffer(width: src.height, height: src.width);
          for (int y = 0; y < src.height; y++) {
            for (int x = 0; x < src.width; x++) {
              final dstX = y;
              final dstY = x;
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(dstX, dstY, r, g, b, a);
            }
          }
          return dst;
        }

      case 6:
        {
          // 90 degrees CW (width and height swap)
          final dst = ImageBuffer(width: src.height, height: src.width);
          for (int y = 0; y < src.height; y++) {
            for (int x = 0; x < src.width; x++) {
              final dstX = src.height - 1 - y;
              final dstY = x;
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(dstX, dstY, r, g, b, a);
            }
          }
          return dst;
        }

      case 7:
        {
          // Transverse (Flip X and rotate 90 CW, width and height swap)
          final dst = ImageBuffer(width: src.height, height: src.width);
          for (int y = 0; y < src.height; y++) {
            for (int x = 0; x < src.width; x++) {
              final dstX = src.height - 1 - y;
              final dstY = src.width - 1 - x;
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(dstX, dstY, r, g, b, a);
            }
          }
          return dst;
        }

      case 8:
        {
          // 270 degrees CW (width and height swap)
          final dst = ImageBuffer(width: src.height, height: src.width);
          for (int y = 0; y < src.height; y++) {
            for (int x = 0; x < src.width; x++) {
              final dstX = y;
              final dstY = src.width - 1 - x;
              final (r, g, b, a) = src.getPixel(x, y);
              dst.setPixel(dstX, dstY, r, g, b, a);
            }
          }
          return dst;
        }

      default:
        throw ArgumentError(
            'Unsupported or invalid EXIF orientation: $exifOrientation');
    }
  }

  /// Converts an image to grayscale using standard ITU-R BT.601 integer luminance weights:
  /// Y = (299 * R + 587 * G + 114 * B) / 1000.
  /// Alpha channel is strictly preserved. Source image remains unchanged.
  static ImageBuffer toGrayscale(ImageBuffer src) {
    final dst = ImageBuffer(width: src.width, height: src.height);
    final srcData = src.data;
    final dstData = dst.data;
    final totalPixels = src.width * src.height;

    for (int i = 0; i < totalPixels; i++) {
      final offset = i * 4;
      final r = srcData[offset];
      final g = srcData[offset + 1];
      final b = srcData[offset + 2];
      final a = srcData[offset + 3];

      final y = ((299 * r + 587 * g + 114 * b) ~/ 1000).clamp(0, 255);

      dstData[offset] = y;
      dstData[offset + 1] = y;
      dstData[offset + 2] = y;
      dstData[offset + 3] = a;
    }
    return dst;
  }

  /// Performs 3x3 Sobel edge detection to extract spatial gradient magnitudes.
  /// Kernel X: [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
  /// Kernel Y: [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]
  /// Boundaries are clamped safely. Non-destructive; preserves source alpha.
  static ImageBuffer sobelEdgeDetection(ImageBuffer src) {
    final w = src.width;
    final h = src.height;
    final dst = ImageBuffer(width: w, height: h);
    final srcData = src.data;
    final dstData = dst.data;

    if (w < 2 || h < 2) {
      // For degenerate 1x1, 1xN, Nx1 images, gradient is 0; preserve source alpha
      for (int i = 0; i < w * h; i++) {
        dstData[i * 4 + 3] = srcData[i * 4 + 3];
      }
      return dst;
    }

    // Pre-calculate luminance array to avoid redundant arithmetic in 3x3 stencil
    final lum = Uint8List(w * h);
    for (int i = 0; i < w * h; i++) {
      final off = i * 4;
      lum[i] = ((299 * srcData[off] +
                  587 * srcData[off + 1] +
                  114 * srcData[off + 2]) ~/
              1000)
          .clamp(0, 255);
    }

    int getLumClamped(int x, int y) {
      final cx = x.clamp(0, w - 1);
      final cy = y.clamp(0, h - 1);
      return lum[cy * w + cx];
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Convolve Sobel X
        final gx = (getLumClamped(x + 1, y - 1) +
                2 * getLumClamped(x + 1, y) +
                getLumClamped(x + 1, y + 1)) -
            (getLumClamped(x - 1, y - 1) +
                2 * getLumClamped(x - 1, y) +
                getLumClamped(x - 1, y + 1));

        // Convolve Sobel Y
        final gy = (getLumClamped(x - 1, y + 1) +
                2 * getLumClamped(x, y + 1) +
                getLumClamped(x + 1, y + 1)) -
            (getLumClamped(x - 1, y - 1) +
                2 * getLumClamped(x, y - 1) +
                getLumClamped(x + 1, y - 1));

        final mag = math.sqrt(gx * gx + gy * gy).round().clamp(0, 255);
        final off = (y * w + x) * 4;
        dstData[off] = mag;
        dstData[off + 1] = mag;
        dstData[off + 2] = mag;
        dstData[off + 3] = srcData[off + 3]; // Preserve original alpha!
      }
    }
    return dst;
  }
}
