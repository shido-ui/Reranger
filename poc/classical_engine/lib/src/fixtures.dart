import 'dart:typed_data';
import 'image_buffer.dart';

/// Deterministic, reproducible synthetic image fixtures.
/// Provenance: Pure mathematical generation via algorithms with fixed seeds/patterns.
class SyntheticFixtures {
  /// 1x1 single red pixel (RGBA: 255, 0, 0, 255)
  static ImageBuffer create1x1() {
    final buffer = ImageBuffer(width: 1, height: 1);
    buffer.setPixel(0, 0, 255, 0, 0, 255);
    return buffer;
  }

  /// 1x2 two pixels: Left=Red, Right=Green
  static ImageBuffer create1x2() {
    final buffer = ImageBuffer(width: 2, height: 1);
    buffer.setPixel(0, 0, 255, 0, 0, 255);
    buffer.setPixel(1, 0, 0, 255, 0, 255);
    return buffer;
  }

  /// 2x2 four quadrants: (0,0)=Red, (1,0)=Green, (0,1)=Blue, (1,1)=White
  static ImageBuffer create2x2() {
    final buffer = ImageBuffer(width: 2, height: 2);
    buffer.setPixel(0, 0, 255, 0, 0, 255);
    buffer.setPixel(1, 0, 0, 255, 0, 255);
    buffer.setPixel(0, 1, 0, 0, 255, 255);
    buffer.setPixel(1, 1, 255, 255, 255, 255);
    return buffer;
  }

  /// Portrait aspect ratio (vertical: 120 x 160) with a smooth vertical luminance gradient
  static ImageBuffer createPortrait({int width = 120, int height = 160}) {
    final buffer = ImageBuffer(width: width, height: height);
    for (int y = 0; y < height; y++) {
      final val = ((y / (height - 1)) * 255).round();
      for (int x = 0; x < width; x++) {
        buffer.setPixel(x, y, val, 128, 255 - val, 255);
      }
    }
    return buffer;
  }

  /// Panorama aspect ratio (horizontal: 400 x 100) with horizontal color bars
  static ImageBuffer createPanorama({int width = 400, int height = 100}) {
    final buffer = ImageBuffer(width: width, height: height);
    for (int x = 0; x < width; x++) {
      final bar = (x * 4 ~/ width);
      final (r, g, b) = switch (bar) {
        0 => (255, 50, 50),
        1 => (50, 255, 50),
        2 => (50, 50, 255),
        _ => (240, 240, 50),
      };
      for (int y = 0; y < height; y++) {
        buffer.setPixel(x, y, r, g, b, 255);
      }
    }
    return buffer;
  }

  /// RGBA image with diverse alpha channels (0 = transparent, 64, 128, 255 = opaque)
  static ImageBuffer createRgbaAlpha({int width = 16, int height = 16}) {
    final buffer = ImageBuffer(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final alpha = switch ((y ~/ 4) % 4) {
          0 => 0,
          1 => 64,
          2 => 128,
          _ => 255,
        };
        buffer.setPixel(x, y, 200, 100, 50, alpha);
      }
    }
    return buffer;
  }

  /// Low contrast image (narrow histogram: pixel values strictly within [110, 130])
  static ImageBuffer createLowContrast({int width = 32, int height = 32}) {
    final buffer = ImageBuffer(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final v = 110 + ((x + y) % 21);
        buffer.setPixel(x, y, v, v, v, 255);
      }
    }
    return buffer;
  }

  /// High contrast step edge image (pure black [0, 0, 0] on left, pure white [255, 255, 255] on right)
  static ImageBuffer createHighContrast({int width = 32, int height = 32}) {
    final buffer = ImageBuffer(width: width, height: height);
    final mid = width ~/ 2;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final v = (x < mid) ? 0 : 255;
        buffer.setPixel(x, y, v, v, v, 255);
      }
    }
    return buffer;
  }

  /// Corrupted / truncated byte array for decode robustness testing
  static Uint8List createCorruptBytes() {
    // Starts with JPEG magic FF D8 FF E0 but abruptly truncates after 6 bytes
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
  }

  /// 12 Megapixel synthetic benchmark buffer (4000 x 3000 = 12,000,000 pixels = 48 MB RGBA)
  static ImageBuffer create12Mp() {
    const width = 4000;
    const height = 3000;
    final buffer = ImageBuffer(width: width, height: height);
    // Fill with a synthetic gradient efficiently
    final data = buffer.data;
    for (int i = 0; i < data.length; i += 4) {
      data[i] = (i & 0xFF);
      data[i + 1] = ((i >> 8) & 0xFF);
      data[i + 2] = ((i >> 16) & 0xFF);
      data[i + 3] = 255;
    }
    return buffer;
  }
}
