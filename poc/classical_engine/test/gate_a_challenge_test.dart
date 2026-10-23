import 'package:flutter_test/flutter_test.dart';
import 'package:classical_engine_poc/classical_engine.dart';

void main() {
  group('Challenge Gate A: Degenerate & Extreme Dimensions Matrix', () {
    test('1x1 single pixel executes all operations without throwing', () {
      final img = SyntheticFixtures.create1x1();
      expect(img.width, equals(1));
      expect(img.height, equals(1));

      // All 8 orientations on 1x1
      for (int ori = 1; ori <= 8; ori++) {
        final rotated = BatchAOperations.applyOrientation(img, ori);
        expect(rotated.width, equals(1));
        expect(rotated.height, equals(1));
        expect(rotated.getPixel(0, 0), equals((255, 0, 0, 255)));
      }

      // Grayscale
      final gray = BatchAOperations.toGrayscale(img);
      expect(gray.getPixel(0, 0).$1, equals(76));
      expect(gray.getPixel(0, 0).$4, equals(255)); // Alpha preserved

      // Sobel edge
      final edges = BatchAOperations.sobelEdgeDetection(img);
      expect(edges.getPixel(0, 0).$1, equals(0)); // Degenerate edge = 0
      // Alpha should be preserved from source (255)
      expect(edges.getPixel(0, 0).$4, equals(255));

      // Contour extraction on 1x1
      final contours =
          BatchBOperations.extractContours(img, luminanceThreshold: 50);
      expect(contours.length, inInclusiveRange(0, 1));

      // Quantization on 1x1
      final quant = BatchBOperations.quantizePalette(img, k: 4);
      expect(quant.palette.length, equals(1));
      expect(quant.quantizedImage.getPixel(0, 0), equals((255, 0, 0, 255)));

      // Recolor on 1x1
      final recolored = BatchBOperations.replaceColorPreservingLuminance(
        img,
        targetColor: (255, 0, 0),
        replacementColor: (0, 255, 0),
      );
      expect(recolored.getPixel(0, 0).$2,
          greaterThan(recolored.getPixel(0, 0).$1));

      // Grain on 1x1
      final grained = BatchCRecipes.applyGrainOverlay(img);
      expect(grained.getPixel(0, 0).$4, equals(255));

      // Recipes on 1x1
      final r1 = BatchCRecipes.recipeDramaticMonochromeInk(img);
      final r2 = BatchCRecipes.recipePastelPosterizeAndGrain(img);
      final r3 = BatchCRecipes.recipeWarmDuoTone(img);
      expect(r1.width, equals(1));
      expect(r2.width, equals(1));
      expect(r3.width, equals(1));
    });

    test('Very wide (1000x1) and very tall (1x1000) dimensions', () {
      final wide = ImageBuffer(width: 1000, height: 1);
      final tall = ImageBuffer(width: 1, height: 1000);

      // Verify Sobel edge preserves dimensions and alpha
      final wideEdges = BatchAOperations.sobelEdgeDetection(wide);
      expect(wideEdges.width, equals(1000));
      expect(wideEdges.height, equals(1));

      final tallEdges = BatchAOperations.sobelEdgeDetection(tall);
      expect(tallEdges.width, equals(1));
      expect(tallEdges.height, equals(1000));

      // Grayscale
      final wideGray = BatchAOperations.toGrayscale(wide);
      expect(wideGray.width, equals(1000));

      // Grain
      final wideGrain = BatchCRecipes.applyGrainOverlay(wide);
      expect(wideGrain.width, equals(1000));
    });
  });

  group('Challenge Gate A: Full EXIF Orientation Matrix (1 to 8)', () {
    // 3x2 Asymmetric fixture:
    // Row 0: [(10, 0, 0), (20, 0, 0), (30, 0, 0)]
    // Row 1: [(40, 0, 0), (50, 0, 0), (60, 0, 0)]
    late ImageBuffer src;

    setUp(() {
      src = ImageBuffer(width: 3, height: 2);
      src.setPixel(0, 0, 10, 0, 0, 255);
      src.setPixel(1, 0, 20, 0, 0, 255);
      src.setPixel(2, 0, 30, 0, 0, 255);
      src.setPixel(0, 1, 40, 0, 0, 255);
      src.setPixel(1, 1, 50, 0, 0, 255);
      src.setPixel(2, 1, 60, 0, 0, 255);
    });

    test('EXIF 1 (normal 0 deg): 3x2 unchanged', () {
      final out = BatchAOperations.applyOrientation(src, 1);
      expect(out.width, equals(3));
      expect(out.height, equals(2));
      expect(out.getPixel(0, 0).$1, equals(10));
      expect(out.getPixel(2, 1).$1, equals(60));
    });

    test('EXIF 2 (horizontal mirror / flip X): 3x2', () {
      final out = BatchAOperations.applyOrientation(src, 2);
      expect(out.width, equals(3));
      expect(out.height, equals(2));
      expect(out.getPixel(0, 0).$1, equals(30)); // was top-right
      expect(out.getPixel(2, 0).$1, equals(10)); // was top-left
      expect(out.getPixel(0, 1).$1, equals(60));
      expect(out.getPixel(2, 1).$1, equals(40));
    });

    test('EXIF 3 (upside down 180 deg): 3x2', () {
      final out = BatchAOperations.applyOrientation(src, 3);
      expect(out.width, equals(3));
      expect(out.height, equals(2));
      expect(out.getPixel(0, 0).$1, equals(60)); // was bottom-right
      expect(out.getPixel(2, 1).$1, equals(10)); // was top-left
    });

    test('EXIF 4 (vertical flip / flip Y): 3x2', () {
      final out = BatchAOperations.applyOrientation(src, 4);
      expect(out.width, equals(3));
      expect(out.height, equals(2));
      expect(out.getPixel(0, 0).$1, equals(40)); // was bottom-left
      expect(out.getPixel(2, 0).$1, equals(60)); // was bottom-right
      expect(out.getPixel(0, 1).$1, equals(10));
      expect(out.getPixel(2, 1).$1, equals(30));
    });

    test('EXIF 5 (transpose: flip X and rotate 270 CW): 2x3', () {
      final out = BatchAOperations.applyOrientation(src, 5);
      expect(out.width, equals(2));
      expect(out.height, equals(3));
      expect(out.getPixel(0, 0).$1, equals(10));
      expect(out.getPixel(1, 0).$1, equals(40));
      expect(out.getPixel(0, 2).$1, equals(30));
      expect(out.getPixel(1, 2).$1, equals(60));
    });

    test('EXIF 6 (rotate 90 deg CW): 2x3', () {
      final out = BatchAOperations.applyOrientation(src, 6);
      expect(out.width, equals(2));
      expect(out.height, equals(3));
      expect(out.getPixel(0, 0).$1, equals(40)); // was bottom-left
      expect(out.getPixel(1, 0).$1, equals(10)); // was top-left
      expect(out.getPixel(0, 2).$1, equals(60)); // was bottom-right
      expect(out.getPixel(1, 2).$1, equals(30)); // was top-right
    });

    test('EXIF 7 (transverse: flip X and rotate 90 CW): 2x3', () {
      final out = BatchAOperations.applyOrientation(src, 7);
      expect(out.width, equals(2));
      expect(out.height, equals(3));
      expect(out.getPixel(0, 0).$1, equals(60));
      expect(out.getPixel(1, 0).$1, equals(30));
      expect(out.getPixel(0, 2).$1, equals(40));
      expect(out.getPixel(1, 2).$1, equals(10));
    });

    test('EXIF 8 (rotate 270 deg CW / 90 CCW): 2x3', () {
      final out = BatchAOperations.applyOrientation(src, 8);
      expect(out.width, equals(2));
      expect(out.height, equals(3));
      expect(out.getPixel(0, 0).$1, equals(30)); // was top-right
      expect(out.getPixel(1, 0).$1, equals(60)); // was bottom-right
      expect(out.getPixel(0, 2).$1, equals(10)); // was top-left
      expect(out.getPixel(1, 2).$1, equals(40)); // was bottom-left
    });
  });

  group('Challenge Gate A: Alpha Fidelity & Transparent Backgrounds', () {
    test('Grain overlay does not pollute transparent pixels (A=0)', () {
      final img = ImageBuffer(width: 4, height: 4);
      // Half transparent (A=0), half opaque (A=255)
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final alpha = (y < 2) ? 0 : 255;
          img.setPixel(x, y, 100, 100, 100, alpha);
        }
      }

      final grained =
          BatchCRecipes.applyGrainOverlay(img, seed: 42, intensity: 0.3);

      // Transparent pixels (y < 2) must remain unpolluted
      for (int y = 0; y < 2; y++) {
        for (int x = 0; x < 4; x++) {
          final (r, g, b, a) = grained.getPixel(x, y);
          expect(a, equals(0));
          // RGB channels of transparent pixels should not be altered
          expect(r, equals(100));
          expect(g, equals(100));
          expect(b, equals(100));
        }
      }

      // Opaque pixels (y >= 2) must receive grain texture
      bool hasOpaqueNoise = false;
      for (int y = 2; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          if (grained.getPixel(x, y).$1 != 100) hasOpaqueNoise = true;
        }
      }
      expect(hasOpaqueNoise, isTrue);
    });

    test('Sobel edge detection preserves alpha on transparent input', () {
      final img = ImageBuffer(width: 4, height: 4);
      // Top row transparent (A=0), others opaque
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final alpha = (y == 0) ? 0 : 255;
          img.setPixel(x, y, 200, 200, 200, alpha);
        }
      }

      final edges = BatchAOperations.sobelEdgeDetection(img);
      for (int x = 0; x < 4; x++) {
        expect(edges.getPixel(x, 0).$4, equals(0)); // Alpha 0 preserved
        expect(edges.getPixel(x, 1).$4, equals(255)); // Alpha 255 preserved
      }
    });
  });

  group('Challenge Gate A: Palette Sorting & Determinism', () {
    test(
        'Quantization palette entries are sorted deterministically by ascending luminance',
        () {
      // 4 distinct colors with different luminances:
      // White (Y ~ 255)
      // Green (Y ~ 149)
      // Red (Y ~ 76)
      // Blue (Y ~ 29)
      final img = ImageBuffer(width: 4, height: 1);
      img.setPixel(0, 0, 255, 255, 255, 255); // White (brightest)
      img.setPixel(1, 0, 0, 255, 0, 255); // Green
      img.setPixel(2, 0, 255, 0, 0, 255); // Red
      img.setPixel(3, 0, 0, 0, 255, 255); // Blue (darkest)

      final result = BatchBOperations.quantizePalette(img, k: 4);
      final palette = result.palette;

      expect(palette.length, equals(4));

      // Compute luminance for each palette entry
      int lum((int, int, int) c) =>
          (299 * c.$1 + 587 * c.$2 + 114 * c.$3) ~/ 1000;

      // Must be sorted in non-descending order: Palette[0] <= Palette[1] <= ...
      for (int i = 0; i < palette.length - 1; i++) {
        expect(lum(palette[i]), lessThanOrEqualTo(lum(palette[i + 1])));
      }

      // Slot 0 should be the darkest (Blue)
      expect(palette[0], equals((0, 0, 255)));
      // Slot 3 should be the brightest (White)
      expect(palette[3], equals((255, 255, 255)));
    });
  });

  group('Challenge Gate A: Cache Key Integrity', () {
    test(
        'Modifying fine-tune slider or preset produces completely distinct cache key',
        () {
      final baseParams = {'exposure': 0.1, 'contrast': 0.2};
      final key1 = computeRenderCacheKey(
        sourceHash: 'sha_test_12345',
        presetId: 'recolor_warm',
        intensity: 0.8,
        fineTune: baseParams,
      );

      final keySame = computeRenderCacheKey(
        sourceHash: 'sha_test_12345',
        presetId: 'recolor_warm',
        intensity: 0.8,
        fineTune: {
          'contrast': 0.2,
          'exposure': 0.1
        }, // Swapped map insertion order
      );

      // Must be order-independent for parameter keys
      expect(key1, equals(keySame));

      // Changing intensity
      final keyDiffIntensity = computeRenderCacheKey(
        sourceHash: 'sha_test_12345',
        presetId: 'recolor_warm',
        intensity: 0.85,
        fineTune: baseParams,
      );
      expect(key1, isNot(equals(keyDiffIntensity)));

      // Changing a fineTune slider
      final keyDiffSlider = computeRenderCacheKey(
        sourceHash: 'sha_test_12345',
        presetId: 'recolor_warm',
        intensity: 0.8,
        fineTune: {'exposure': 0.15, 'contrast': 0.2},
      );
      expect(key1, isNot(equals(keyDiffSlider)));
    });
  });
}
