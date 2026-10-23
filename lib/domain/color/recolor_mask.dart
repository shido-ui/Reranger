import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../scene_map/color_region_map_data.dart';
import 'color_palette.dart';

/// Single-channel 8-bit discrete selection mask for spatial region recoloring.
/// Values in [0, 255]:
/// - 0: completely unselected (guaranteed exact byte-for-byte source preservation)
/// - 255: completely selected
/// - (0, 255): soft antialiased edge transition
class RegionMask {
  final int width;
  final int height;
  final Uint8List buffer;

  RegionMask({required this.width, required this.height, required this.buffer})
    : assert(width > 0 && height > 0, 'Dimensions must be positive'),
      assert(
        buffer.length == width * height,
        'Buffer size (${buffer.length}) must match width*height (${width * height})',
      );

  factory RegionMask.empty(int width, int height) => RegionMask(
    width: width,
    height: height,
    buffer: Uint8List(width * height),
  );

  factory RegionMask.full(int width, int height) {
    final b = Uint8List(width * height);
    b.fillRange(0, b.length, 255);
    return RegionMask(width: width, height: height, buffer: b);
  }

  /// Clones this mask into a new independent buffer.
  RegionMask copy() => RegionMask(
    width: width,
    height: height,
    buffer: Uint8List.fromList(buffer),
  );

  int getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) return 0;
    return buffer[y * width + x];
  }

  void setPixel(int x, int y, int value) {
    if (x >= 0 && x < width && y >= 0 && y < height) {
      buffer[y * width + x] = value.clamp(0, 255);
    }
  }

  /// Total count of pixels that are at least partially selected (> 0).
  int get selectedPixelCount {
    int count = 0;
    for (int i = 0; i < buffer.length; i++) {
      if (buffer[i] > 0) count++;
    }
    return count;
  }

  /// Fraction of total canvas selected in [0.0, 1.0].
  double get coverage =>
      (width * height > 0) ? (selectedPixelCount / (width * height)) : 0.0;

  /// Builds a selection mask based on color distance from [sourceColor] with smooth falloff.
  static RegionMask fromColorTolerance({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required ColorRgb sourceColor,
    double tolerance = 0.20,
    double feather = 0.10,
  }) {
    final mask = RegionMask.empty(width, height);
    final total = width * height;
    final srcR = sourceColor.r;
    final srcG = sourceColor.g;
    final srcB = sourceColor.b;

    // Normalization factor: 255 * sqrt(3)
    const maxDist = 441.67295593;
    final tolDist = tolerance * maxDist;
    final featherDist = feather * maxDist;

    for (int i = 0; i < total; i++) {
      final offset = i * 4;
      final r = rgbaBytes[offset];
      final g = rgbaBytes[offset + 1];
      final b = rgbaBytes[offset + 2];
      final a = rgbaBytes[offset + 3];

      // Exclude completely transparent pixels
      if (a == 0) {
        mask.buffer[i] = 0;
        continue;
      }

      final dr = (r - srcR).toDouble();
      final dg = (g - srcG).toDouble();
      final db = (b - srcB).toDouble();
      final dist = math.sqrt(dr * dr + dg * dg + db * db);

      if (dist <= tolDist) {
        // Fully within tolerance: modulate by alpha
        mask.buffer[i] = ((a / 255.0) * 255.0).round().clamp(0, 255);
      } else if (featherDist > 1e-4 && dist <= tolDist + featherDist) {
        // Smoothstep cubic Hermite falloff
        final t = (dist - tolDist) / featherDist;
        final weight = 1.0 - (3.0 * t * t - 2.0 * t * t * t);
        final val = (weight * (a / 255.0) * 255.0).round().clamp(0, 255);
        mask.buffer[i] = val;
      } else {
        mask.buffer[i] = 0;
      }
    }

    return mask;
  }

  /// Extracts a mask from Scene Map [ColorRegionMapData] by cluster label.
  static RegionMask fromColorRegionMap({
    required ColorRegionMapData mapData,
    required int targetRegionIndex,
    required int targetWidth,
    required int targetHeight,
  }) {
    final mask = RegionMask.empty(targetWidth, targetHeight);
    final gridW = mapData.gridWidth;
    final gridH = mapData.gridHeight;

    for (int y = 0; y < targetHeight; y++) {
      final gy = ((y / targetHeight) * gridH).floor().clamp(0, gridH - 1);
      final rowOffset = y * targetWidth;
      for (int x = 0; x < targetWidth; x++) {
        final gx = ((x / targetWidth) * gridW).floor().clamp(0, gridW - 1);
        final label = mapData.getRegion(gx, gy);
        mask.buffer[rowOffset + x] = (label == targetRegionIndex) ? 255 : 0;
      }
    }

    return mask;
  }

  /// Interactive mask repair tool for mobile: paints or erases with a circular feathered brush.
  void applyBrush({
    required int centerX,
    required int centerY,
    required int radius,
    double opacity = 1.0,
    required bool isEraser,
  }) {
    if (radius <= 0 || opacity <= 0.0) return;

    final r2 = radius * radius;
    final minX = math.max(0, centerX - radius);
    final maxX = math.min(width - 1, centerX + radius);
    final minY = math.max(0, centerY - radius);
    final maxY = math.min(height - 1, centerY + radius);

    final op = opacity.clamp(0.0, 1.0);

    for (int y = minY; y <= maxY; y++) {
      final dy = y - centerY;
      final dy2 = dy * dy;
      final rowOffset = y * width;

      for (int x = minX; x <= maxX; x++) {
        final dx = x - centerX;
        final d2 = dx * dx + dy2;
        if (d2 <= r2) {
          final normDist = math.sqrt(d2) / radius;
          // Quadratic smooth falloff
          final weight = (1.0 - normDist * normDist) * op;
          final idx = rowOffset + x;
          final current = buffer[idx];

          if (isEraser) {
            final updated = (current * (1.0 - weight)).round().clamp(0, 255);
            buffer[idx] = updated;
          } else {
            final updated = (current + (255 - current) * weight).round().clamp(
              0,
              255,
            );
            buffer[idx] = updated;
          }
        }
      }
    }
  }

  /// Smooths mask edges via separable box-blur to eliminate edge halos.
  RegionMask featherMask(int radius) {
    if (radius <= 0) return copy();

    final temp = Uint8List(width * height);
    final result = Uint8List(width * height);

    // Horizontal pass
    for (int y = 0; y < height; y++) {
      final row = y * width;
      for (int x = 0; x < width; x++) {
        int sum = 0;
        int count = 0;
        final start = math.max(0, x - radius);
        final end = math.min(width - 1, x + radius);
        for (int k = start; k <= end; k++) {
          sum += buffer[row + k];
          count++;
        }
        temp[row + x] = (sum ~/ count).clamp(0, 255);
      }
    }

    // Vertical pass
    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        int sum = 0;
        int count = 0;
        final start = math.max(0, y - radius);
        final end = math.min(height - 1, y + radius);
        for (int k = start; k <= end; k++) {
          sum += temp[k * width + x];
          count++;
        }
        result[y * width + x] = (sum ~/ count).clamp(0, 255);
      }
    }

    return RegionMask(width: width, height: height, buffer: result);
  }

  /// Inverts the mask: 0 -> 255, 255 -> 0.
  RegionMask invert() {
    final inv = Uint8List(width * height);
    for (int i = 0; i < buffer.length; i++) {
      inv[i] = 255 - buffer[i];
    }
    return RegionMask(width: width, height: height, buffer: inv);
  }

  String toBase64() => base64Encode(buffer);

  factory RegionMask.fromBase64({
    required int width,
    required int height,
    required String base64String,
  }) {
    final decoded = base64Decode(base64String);
    if (decoded.length != width * height) {
      throw FormatException(
        'Decoded mask buffer length (${decoded.length}) does not match $width x $height',
      );
    }
    return RegionMask(
      width: width,
      height: height,
      buffer: Uint8List.fromList(decoded),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionMask &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height &&
          _buffersEqual(buffer, other.buffer);

  @override
  int get hashCode => Object.hash(width, height, buffer.length);

  static bool _buffersEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
