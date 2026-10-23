import 'package:flutter_test/flutter_test.dart';
import 'package:classical_engine_poc/classical_engine.dart';

void main() {
  group('Batch A: Fixture Verification & Dimensions', () {
    test('1x1 fixture dimensions and pixel retrieval', () {
      final img = SyntheticFixtures.create1x1();
      expect(img.width, equals(1));
      expect(img.height, equals(1));
      expect(img.getPixel(0, 0), equals((255, 0, 0, 255)));
    });

    test('1x2 fixture dimensions and color channel order', () {
      final img = SyntheticFixtures.create1x2();
      expect(img.width, equals(2));
      expect(img.height, equals(1));
      expect(img.getPixel(0, 0), equals((255, 0, 0, 255))); // Red
      expect(img.getPixel(1, 0), equals((0, 255, 0, 255))); // Green
    });

    test('2x2 fixture dimensions and 4 quadrants', () {
      final img = SyntheticFixtures.create2x2();
      expect(img.width, equals(2));
      expect(img.height, equals(2));
      expect(img.getPixel(0, 0), equals((255, 0, 0, 255))); // Red
      expect(img.getPixel(1, 0), equals((0, 255, 0, 255))); // Green
      expect(img.getPixel(0, 1), equals((0, 0, 255, 255))); // Blue
      expect(img.getPixel(1, 1), equals((255, 255, 255, 255))); // White
    });

    test('Portrait and Panorama aspect ratios', () {
      final portrait =
          SyntheticFixtures.createPortrait(width: 120, height: 160);
      expect(portrait.width, equals(120));
      expect(portrait.height, equals(160));
      expect(portrait.height > portrait.width, isTrue);

      final pano = SyntheticFixtures.createPanorama(width: 400, height: 100);
      expect(pano.width, equals(400));
      expect(pano.height, equals(100));
      expect(pano.width > pano.height, isTrue);
    });

    test('Boundary conditions and out-of-range protection', () {
      final img = SyntheticFixtures.create2x2();
      expect(() => img.getPixel(-1, 0), throwsRangeError);
      expect(() => img.getPixel(2, 0), throwsRangeError);
      expect(() => img.getPixel(0, 2), throwsRangeError);
      expect(() => img.setPixel(0, 3, 0, 0, 0, 255), throwsRangeError);
    });

    test('Corrupt byte fixture recognition', () {
      final corrupt = SyntheticFixtures.createCorruptBytes();
      expect(corrupt.length, equals(6));
      expect(corrupt[0], equals(0xFF));
      expect(corrupt[1], equals(0xD8)); // truncated JPEG SOI
    });
  });

  group('Batch A: Alpha Channel & Immutability', () {
    test('Alpha channel fidelity is preserved across grayscale transformation',
        () {
      final img = SyntheticFixtures.createRgbaAlpha(width: 16, height: 16);
      final gray = BatchAOperations.toGrayscale(img);

      expect(gray.width, equals(16));
      expect(gray.height, equals(16));

      // Row 0: Alpha 0 (transparent)
      expect(gray.getPixel(0, 0).$4, equals(0));
      // Row 4: Alpha 64
      expect(gray.getPixel(0, 4).$4, equals(64));
      // Row 8: Alpha 128
      expect(gray.getPixel(0, 8).$4, equals(128));
      // Row 12: Alpha 255
      expect(gray.getPixel(0, 12).$4, equals(255));
    });

    test('Source image immutability assertion (Invariant 4)', () {
      final src = SyntheticFixtures.create2x2();
      final originalHash = src.computeSha256();

      // Perform orientation, grayscale, and edge detection
      BatchAOperations.applyOrientation(src, 6);
      BatchAOperations.toGrayscale(src);
      BatchAOperations.sobelEdgeDetection(src);

      // Verify source hash remains 100% unaltered
      expect(src.computeSha256(), equals(originalHash));
    });
  });

  group('Batch A: EXIF Orientation Handling', () {
    test('Orientation 1 (normal) returns identical copy', () {
      final src = SyntheticFixtures.create1x2();
      final rotated = BatchAOperations.applyOrientation(src, 1);
      expect(rotated.width, equals(2));
      expect(rotated.height, equals(1));
      expect(rotated.computeSha256(), equals(src.computeSha256()));
    });

    test('Orientation 6 (90 deg CW) swaps dimensions and rotates pixels', () {
      final src = SyntheticFixtures.create1x2(); // 2x1 [Red, Green]
      final rotated = BatchAOperations.applyOrientation(src, 6);

      // Dimensions swap to 1x2
      expect(rotated.width, equals(1));
      expect(rotated.height, equals(2));

      // After 90 deg CW: Red moves to (0, 0), Green moves to (0, 1)
      expect(rotated.getPixel(0, 0), equals((255, 0, 0, 255)));
      expect(rotated.getPixel(0, 1), equals((0, 255, 0, 255)));
    });

    test('Orientation 3 (180 deg) inverts coordinate layout', () {
      final src = SyntheticFixtures.create1x2(); // 2x1 [Red, Green]
      final rotated = BatchAOperations.applyOrientation(src, 3);

      expect(rotated.width, equals(2));
      expect(rotated.height, equals(1));

      // Reversed: [Green, Red]
      expect(rotated.getPixel(0, 0), equals((0, 255, 0, 255)));
      expect(rotated.getPixel(1, 0), equals((255, 0, 0, 255)));
    });

    test('Orientation 8 (270 deg CW) swaps dimensions', () {
      final src = SyntheticFixtures.create1x2(); // 2x1 [Red, Green]
      final rotated = BatchAOperations.applyOrientation(src, 8);

      expect(rotated.width, equals(1));
      expect(rotated.height, equals(2));

      // 270 CW: Red moves to (0, 1), Green moves to (0, 0)
      expect(rotated.getPixel(0, 0), equals((0, 255, 0, 255)));
      expect(rotated.getPixel(0, 1), equals((255, 0, 0, 255)));
    });
  });

  group('Batch A: Grayscale & Sobel Edge Extraction', () {
    test('Grayscale conversion verifies BT.601 integer luminance math', () {
      final img = SyntheticFixtures.create2x2();
      final gray = BatchAOperations.toGrayscale(img);

      // Red (255, 0, 0) -> (299 * 255) / 1000 = 76
      expect(gray.getPixel(0, 0).$1, equals(76));
      expect(gray.getPixel(0, 0).$2, equals(76));
      expect(gray.getPixel(0, 0).$3, equals(76));

      // Green (0, 255, 0) -> (587 * 255) / 1000 = 149
      expect(gray.getPixel(1, 0).$1, equals(149));

      // Blue (0, 0, 255) -> (114 * 255) / 1000 = 29
      expect(gray.getPixel(0, 1).$1, equals(29));

      // White (255, 255, 255) -> 254 (integer trunc) or 255
      expect(gray.getPixel(1, 1).$1, closeTo(254, 1));
    });

    test('Sobel edge detection handles degenerate 1x1 without throwing', () {
      final img = SyntheticFixtures.create1x1();
      final edges = BatchAOperations.sobelEdgeDetection(img);
      expect(edges.width, equals(1));
      expect(edges.height, equals(1));
      expect(edges.getPixel(0, 0).$1, equals(0));
    });

    test('Sobel edge detection extracts high-contrast step boundary', () {
      final highContrast =
          SyntheticFixtures.createHighContrast(width: 32, height: 32);
      final edges = BatchAOperations.sobelEdgeDetection(highContrast);

      expect(edges.width, equals(32));
      expect(edges.height, equals(32));

      // Boundary is at x = 16 (between x=15 and x=16)
      // At x=0 (far left, uniform black), edge gradient should be 0
      expect(edges.getPixel(0, 16).$1, equals(0));
      // At x=31 (far right, uniform white), edge gradient should be 0
      expect(edges.getPixel(31, 16).$1, equals(0));

      // Near step boundary (x=15, 16), edge gradient magnitude should be high (> 200)
      expect(edges.getPixel(15, 16).$1, greaterThan(200));
      expect(edges.getPixel(16, 16).$1, greaterThan(200));
    });

    test(
        'Repeatability check: identical operations produce exact SHA-256 match',
        () {
      final portrait = SyntheticFixtures.createPortrait(width: 40, height: 40);
      final run1 = BatchAOperations.sobelEdgeDetection(portrait);
      final run2 = BatchAOperations.sobelEdgeDetection(portrait);

      expect(run1.computeSha256(), equals(run2.computeSha256()));
    });
  });
}
