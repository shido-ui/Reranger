import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// A tightly packed, uncompressed 32-bit RGBA (RGBA8888) image buffer.
/// Enforces source image immutability by strictly returning new instances
/// on transformations.
class ImageBuffer {
  final int width;
  final int height;
  final Uint8List data; // Length = width * height * 4

  ImageBuffer({
    required this.width,
    required this.height,
    Uint8List? data,
  })  : assert(width > 0, 'Width must be positive'),
        assert(height > 0, 'Height must be positive'),
        data = data ?? Uint8List(width * height * 4) {
    if (this.data.length != width * height * 4) {
      throw ArgumentError(
        'Data length (${this.data.length}) does not match dimensions: $width x $height x 4 = ${width * height * 4}',
      );
    }
  }

  /// Returns deep copy of the image buffer.
  ImageBuffer clone() {
    return ImageBuffer(
      width: width,
      height: height,
      data: Uint8List.fromList(data),
    );
  }

  /// Calculates SHA-256 checksum of raw pixel data for immutability and repeatability checks.
  String computeSha256() {
    return crypto.sha256.convert(data).toString();
  }

  @pragma('vm:prefer-inline')
  int _offset(int x, int y) => (y * width + x) * 4;

  @pragma('vm:prefer-inline')
  (int, int, int, int) getPixel(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError(
          'Pixel coordinates ($x, $y) out of bounds ($width x $height)');
    }
    final offset = _offset(x, y);
    return (
      data[offset],
      data[offset + 1],
      data[offset + 2],
      data[offset + 3],
    );
  }

  @pragma('vm:prefer-inline')
  void setPixel(int x, int y, int r, int g, int b, int a) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError(
          'Pixel coordinates ($x, $y) out of bounds ($width x $height)');
    }
    final offset = _offset(x, y);
    data[offset] = r & 0xFF;
    data[offset + 1] = g & 0xFF;
    data[offset + 2] = b & 0xFF;
    data[offset + 3] = a & 0xFF;
  }
}
