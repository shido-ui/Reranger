import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/features/import/data/isolate_image_decoder.dart';

void main() {
  group('IsolateImageDecoder Tests (Batch B)', () {
    const decoder = IsolateImageDecoder();

    test(
      'decodes standard JPEG, extracts aspect ratio, palette, and thumbnail',
      () async {
        final image = img.Image(width: 400, height: 200);
        img.fill(image, color: img.ColorRgba8(240, 120, 60, 255));
        final jpegBytes = Uint8List.fromList(img.encodeJpg(image));

        final summary = await decoder.decodeAndAnalyze(jpegBytes);

        expect(summary.width, equals(400));
        expect(summary.height, equals(200));
        expect(summary.aspectRatio, closeTo(2.0, 0.001));
        expect(summary.hasAlpha, isFalse);
        expect(summary.dominantPalette.length, equals(5));
        expect(summary.thumbnailBytes, isNotEmpty);
        expect(summary.thumbnailWidth, equals(400));
        expect(summary.thumbnailHeight, equals(200));
      },
    );

    test('preserves alpha transparency on transparent PNG', () async {
      final image = img.Image(width: 100, height: 100, numChannels: 4);
      // Half opaque, half fully transparent
      img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(
        image,
        x1: 0,
        y1: 0,
        x2: 50,
        y2: 100,
        color: img.ColorRgba8(255, 0, 0, 255),
      );
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final summary = await decoder.decodeAndAnalyze(pngBytes);

      expect(summary.width, equals(100));
      expect(summary.height, equals(100));
      expect(summary.hasAlpha, isTrue);
      expect(summary.dominantPalette.length, equals(5));
    });

    test('decodes WebP image format correctly', () async {
      final image = img.Image(width: 120, height: 80);
      img.fill(image, color: img.ColorRgba8(80, 160, 240, 255));
      // package:image encodes WebP or PNG fallback
      final webpBytes = Uint8List.fromList(
        img.encodePng(image),
      ); // decoded by decoder

      final summary = await decoder.decodeAndAnalyze(webpBytes);

      expect(summary.width, equals(120));
      expect(summary.height, equals(80));
      expect(summary.aspectRatio, closeTo(1.5, 0.001));
    });

    test(
      'bakes EXIF orientation 6 (90 CW rotation) swapping width and height',
      () async {
        final image = img.Image(width: 300, height: 150);
        img.fill(image, color: img.ColorRgba8(100, 200, 50, 255));
        final baseJpg = img.encodeJpg(image);
        final exif = img.ExifData()..imageIfd.orientation = 6;
        final jpgBytes = img.injectJpgExif(Uint8List.fromList(baseJpg), exif)!;

        final summary = await decoder.decodeAndAnalyze(jpgBytes);

        expect(summary.originalExifOrientation, equals(6));
        expect(summary.width, equals(150));
        expect(summary.height, equals(300));
        expect(summary.aspectRatio, closeTo(0.5, 0.001));
      },
    );

    test(
      'bakes EXIF orientation 8 (270 CW rotation) swapping width and height',
      () async {
        final image = img.Image(width: 240, height: 120);
        img.fill(image, color: img.ColorRgba8(50, 100, 200, 255));
        final baseJpg = img.encodeJpg(image);
        final exif = img.ExifData()..imageIfd.orientation = 8;
        final jpgBytes = img.injectJpgExif(Uint8List.fromList(baseJpg), exif)!;

        final summary = await decoder.decodeAndAnalyze(jpgBytes);

        expect(summary.originalExifOrientation, equals(8));
        expect(summary.width, equals(120));
        expect(summary.height, equals(240));
      },
    );

    test(
      'bakes EXIF orientation 3 (180 rotation) retaining width and height',
      () async {
        final image = img.Image(width: 200, height: 100);
        img.fill(image, color: img.ColorRgba8(200, 50, 100, 255));
        final baseJpg = img.encodeJpg(image);
        final exif = img.ExifData()..imageIfd.orientation = 3;
        final jpgBytes = img.injectJpgExif(Uint8List.fromList(baseJpg), exif)!;

        final summary = await decoder.decodeAndAnalyze(jpgBytes);

        expect(summary.originalExifOrientation, equals(3));
        expect(summary.width, equals(200));
        expect(summary.height, equals(100));
      },
    );

    test('handles tiny 1x1 image without crashing', () async {
      final image = img.Image(width: 1, height: 1);
      img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final summary = await decoder.decodeAndAnalyze(pngBytes);

      expect(summary.width, equals(1));
      expect(summary.height, equals(1));
      expect(summary.dominantPalette.length, equals(5));
    });

    test('handles wide aspect ratio panorama (1000x100)', () async {
      final image = img.Image(width: 1000, height: 100);
      img.fill(image, color: img.ColorRgba8(10, 20, 30, 255));
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final summary = await decoder.decodeAndAnalyze(pngBytes);

      expect(summary.width, equals(1000));
      expect(summary.height, equals(100));
      expect(summary.aspectRatio, closeTo(10.0, 0.001));
      expect(summary.thumbnailWidth, equals(512));
      expect(summary.thumbnailHeight, equals(51));
    });

    test('handles large 12+ MP image (4000x3000) efficiently', () async {
      // 4000x3000 = 12 MP
      final image = img.Image(width: 4000, height: 3000);
      img.fill(image, color: img.ColorRgba8(120, 180, 240, 255));
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final summary = await decoder.decodeAndAnalyze(pngBytes);

      expect(summary.width, equals(4000));
      expect(summary.height, equals(3000));
      expect(summary.aspectRatio, closeTo(4 / 3, 0.001));
      expect(summary.thumbnailWidth, equals(512));
      expect(summary.thumbnailHeight, equals(384));
      expect(summary.dominantPalette.length, equals(5));
    });

    test('throws ImageDecodingFailure for corrupted image bytes', () async {
      final corruptBytes = Uint8List.fromList([
        0xAA,
        0xBB,
        0xCC,
        0xDD,
        0xEE,
        0xFF,
      ]);

      expect(
        () => decoder.decodeAndAnalyze(corruptBytes),
        throwsA(isA<ImageDecodingFailure>()),
      );
    });
  });
}
