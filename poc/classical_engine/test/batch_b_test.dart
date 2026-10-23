import 'package:flutter_test/flutter_test.dart';
import 'package:classical_engine_poc/classical_engine.dart';

void main() {
  group('Batch B: Contour Extraction', () {
    test('Extracts boundary of a centered white square', () {
      final img = ImageBuffer(width: 8, height: 8);
      // Place a 4x4 white square in the middle: x in [2, 5], y in [2, 5]
      for (int y = 2; y <= 5; y++) {
        for (int x = 2; x <= 5; x++) {
          img.setPixel(x, y, 255, 255, 255, 255);
        }
      }

      final contours =
          BatchBOperations.extractContours(img, luminanceThreshold: 128);
      expect(contours.isNotEmpty, isTrue);

      final totalBoundaryPoints =
          contours.fold<int>(0, (sum, c) => sum + c.length);
      // A 4x4 square has perimeter of 12 boundary pixels (4 corners + 8 edge points)
      expect(totalBoundaryPoints, equals(12));

      // Check that every point in the contour is on the boundary
      for (final c in contours) {
        for (final pt in c) {
          expect(pt.x >= 2 && pt.x <= 5, isTrue);
          expect(pt.y >= 2 && pt.y <= 5, isTrue);
          // At least one coordinate is 2 or 5
          expect(pt.x == 2 || pt.x == 5 || pt.y == 2 || pt.y == 5, isTrue);
        }
      }
    });

    test('Zero contours detected on pure black image', () {
      final img = ImageBuffer(width: 10, height: 10);
      final contours =
          BatchBOperations.extractContours(img, luminanceThreshold: 128);
      expect(contours.isEmpty, isTrue);
    });
  });

  group('Batch B: Palette Quantization (Median Cut)', () {
    test('Quantizing 4-color 2x2 image with k=4 returns exact 4 colors', () {
      final src = SyntheticFixtures.create2x2(); // Red, Green, Blue, White
      final result = BatchBOperations.quantizePalette(src, k: 4);

      expect(result.palette.length, equals(4));
      expect(result.quantizedImage.width, equals(2));
      expect(result.quantizedImage.height, equals(2));

      // Each of the 4 pixels should map to its respective palette color
      expect(result.quantizedImage.getPixel(0, 0),
          equals((255, 0, 0, 255))); // Red
      expect(result.quantizedImage.getPixel(1, 0),
          equals((0, 255, 0, 255))); // Green
      expect(result.quantizedImage.getPixel(0, 1),
          equals((0, 0, 255, 255))); // Blue
      expect(result.quantizedImage.getPixel(1, 1),
          equals((255, 255, 255, 255))); // White
    });

    test('Quantizing with k=2 reduces palette to 2 representative clusters',
        () {
      final src = SyntheticFixtures.create2x2();
      final result = BatchBOperations.quantizePalette(src, k: 2);

      expect(result.palette.length, equals(2));

      // Every pixel in output must match one of the 2 palette entries
      for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 2; x++) {
          final (r, g, b, _) = result.quantizedImage.getPixel(x, y);
          final matchesPalette = result.palette.any(
            (p) => p.$1 == r && p.$2 == g && p.$3 == b,
          );
          expect(matchesPalette, isTrue);
        }
      }
    });

    test('Quantization preserves input immutability', () {
      final src = SyntheticFixtures.createPortrait(width: 20, height: 20);
      final originalHash = src.computeSha256();

      final _ = BatchBOperations.quantizePalette(src, k: 4);

      expect(src.computeSha256(), equals(originalHash));
    });
  });

  group('Batch B: Luminance-Preserving Color Replacement', () {
    test('Replacing Red with Green preserves original luminance (~76)', () {
      final src = SyntheticFixtures
          .create2x2(); // (0,0)=Red, (1,0)=Green, (0,1)=Blue, (1,1)=White
      final originalRedPixel = src.getPixel(0, 0);
      // Original Red luminance = (299 * 255) / 1000 = 76
      final origLum = (299 * originalRedPixel.$1 +
              587 * originalRedPixel.$2 +
              114 * originalRedPixel.$3) ~/
          1000;
      expect(origLum, equals(76));

      // Replace Red with pure Green (which unadjusted would have lum = 149)
      final recolored = BatchBOperations.replaceColorPreservingLuminance(
        src,
        targetColor: (255, 0, 0),
        replacementColor: (0, 255, 0),
        tolerance: 0.2,
      );

      final newPixel = recolored.getPixel(0, 0);
      // Verify hue shifted towards green
      expect(newPixel.$2, greaterThan(newPixel.$1));
      expect(newPixel.$2, greaterThan(newPixel.$3));

      // Crucial test: verify new luminance matches original luminance 76 within ±2 units!
      final newLum =
          (299 * newPixel.$1 + 587 * newPixel.$2 + 114 * newPixel.$3) ~/ 1000;
      expect(newLum, closeTo(origLum, 2));

      // Unrelated pixels (Blue at (0,1), White at (1,1)) must remain completely untouched
      expect(recolored.getPixel(0, 1), equals(src.getPixel(0, 1)));
      expect(recolored.getPixel(1, 1), equals(src.getPixel(1, 1)));
    });

    test('Repeatability: run twice yields identical SHA-256', () {
      final src = SyntheticFixtures.createPortrait(width: 30, height: 30);
      final run1 = BatchBOperations.replaceColorPreservingLuminance(
        src,
        targetColor: (128, 128, 128),
        replacementColor: (200, 50, 50),
      );
      final run2 = BatchBOperations.replaceColorPreservingLuminance(
        src,
        targetColor: (128, 128, 128),
        replacementColor: (200, 50, 50),
      );

      expect(run1.computeSha256(), equals(run2.computeSha256()));
    });
  });
}
