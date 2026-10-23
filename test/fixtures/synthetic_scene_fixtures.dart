import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Deterministic synthetic test fixtures for Scene Map and Analysis Bundle validation.
class SyntheticSceneFixtures {
  /// Generates a binary 4x4 checkerboard with alternating black (0,0,0) and white (255,255,255) tiles.
  static img.Image createCheckerboard4x4({int width = 64, int height = 64}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    final tileW = width / 4.0;
    final tileH = height / 4.0;

    for (int y = 0; y < height; y++) {
      final tileY = (y / tileH).floor().clamp(0, 3);
      for (int x = 0; x < width; x++) {
        final tileX = (x / tileW).floor().clamp(0, 3);
        final isWhite = (tileX + tileY) % 2 == 0;
        final val = isWhite ? 255 : 0;
        image.setPixelRgba(x, y, val, val, val, 255);
      }
    }
    return image;
  }

  /// Generates a solid uniform color image (guaranteed 0 edges).
  static img.Image createSolidColor({
    int width = 64,
    int height = 64,
    int r = 100,
    int g = 150,
    int b = 200,
    int a = 255,
  }) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return image;
  }

  /// Generates a two-tone image with a sharp horizontal step boundary at the vertical midpoint.
  static img.Image createHorizontalSplit({
    int width = 64,
    int height = 64,
    int topR = 255,
    int topG = 0,
    int topB = 0,
    int bottomR = 0,
    int bottomG = 0,
    int bottomB = 255,
  }) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    final midY = height ~/ 2;
    for (int y = 0; y < height; y++) {
      final isTop = y < midY;
      final r = isTop ? topR : bottomR;
      final g = isTop ? topG : bottomG;
      final b = isTop ? topB : bottomB;
      for (int x = 0; x < width; x++) {
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return image;
  }

  /// Generates a centered square of dimension [squareSize] on a background.
  static img.Image createCenterSquare({
    int width = 64,
    int height = 64,
    int squareSize = 24,
    int bgR = 0,
    int bgG = 0,
    int bgB = 0,
    int sqR = 255,
    int sqG = 255,
    int sqB = 255,
  }) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    final startX = (width - squareSize) ~/ 2;
    final startY = (height - squareSize) ~/ 2;
    final endX = startX + squareSize;
    final endY = startY + squareSize;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final inside = x >= startX && x < endX && y >= startY && y < endY;
        final r = inside ? sqR : bgR;
        final g = inside ? sqG : bgG;
        final b = inside ? sqB : bgB;
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return image;
  }

  /// Generates a 1x1 boundary image.
  static img.Image createTiny1x1({
    int r = 128,
    int g = 128,
    int b = 128,
    int a = 255,
  }) {
    final image = img.Image(width: 1, height: 1, numChannels: 4);
    image.setPixelRgba(0, 0, r, g, b, a);
    return image;
  }

  /// Generates an image with non-opaque and zero alpha pixels.
  static img.Image createTransparentFixture({int width = 32, int height = 32}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final a = ((x + y) % 2 == 0) ? 0 : 128;
        image.setPixelRgba(x, y, 200, 100, 50, a);
      }
    }
    return image;
  }

  /// Generates a smooth horizontal luminance ramp (0 to 255).
  static img.Image createRampGradient({int width = 64, int height = 64}) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final val = ((x / (width - 1)) * 255).round().clamp(0, 255);
        image.setPixelRgba(x, y, val, val, val, 255);
      }
    }
    return image;
  }

  /// Encodes image to PNG byte stream.
  static Uint8List encodeToPng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }
}
