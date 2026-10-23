import 'package:flutter_test/flutter_test.dart';
import 'package:classical_engine_poc/classical_engine.dart';

void main() {
  group('Batch C: Paper & Grain Overlay', () {
    test('Grain overlay adds procedural texture without altering alpha', () {
      final src = SyntheticFixtures.createPortrait(width: 20, height: 20);
      final grained =
          BatchCRecipes.applyGrainOverlay(src, seed: 100, intensity: 0.15);

      expect(grained.width, equals(20));
      expect(grained.height, equals(20));

      // Output differs from source
      expect(grained.computeSha256(), isNot(equals(src.computeSha256())));

      // Alpha channel must be 100% preserved
      for (int y = 0; y < 20; y++) {
        for (int x = 0; x < 20; x++) {
          expect(grained.getPixel(x, y).$4, equals(src.getPixel(x, y).$4));
        }
      }
    });

    test('Grain overlay is deterministic with identical seed', () {
      final src = SyntheticFixtures.createPortrait(width: 20, height: 20);
      final run1 =
          BatchCRecipes.applyGrainOverlay(src, seed: 999, intensity: 0.2);
      final run2 =
          BatchCRecipes.applyGrainOverlay(src, seed: 999, intensity: 0.2);

      expect(run1.computeSha256(), equals(run2.computeSha256()));
    });

    test('Different seeds produce distinct grain outputs', () {
      final src = SyntheticFixtures.createPortrait(width: 20, height: 20);
      final runA =
          BatchCRecipes.applyGrainOverlay(src, seed: 101, intensity: 0.2);
      final runB =
          BatchCRecipes.applyGrainOverlay(src, seed: 202, intensity: 0.2);

      expect(runA.computeSha256(), isNot(equals(runB.computeSha256())));
    });
  });

  group('Batch C: Three Visibly Different Render Recipes', () {
    late ImageBuffer portrait;

    setUp(() {
      portrait = SyntheticFixtures.createPortrait(width: 40, height: 50);
    });

    test('>= 3 unique recipe fingerprints and distinct outputs', () {
      final originalHash = portrait.computeSha256();

      final out1 = BatchCRecipes.recipeDramaticMonochromeInk(portrait);
      final out2 = BatchCRecipes.recipePastelPosterizeAndGrain(portrait);
      final out3 = BatchCRecipes.recipeWarmDuoTone(portrait);

      final hash1 = out1.computeSha256();
      final hash2 = out2.computeSha256();
      final hash3 = out3.computeSha256();

      // All 3 hashes must be pairwise distinct
      expect(hash1, isNot(equals(originalHash)));
      expect(hash2, isNot(equals(originalHash)));
      expect(hash3, isNot(equals(originalHash)));

      expect(hash1, isNot(equals(hash2)));
      expect(hash2, isNot(equals(hash3)));
      expect(hash1, isNot(equals(hash3)));

      // Input source immutability check
      expect(portrait.computeSha256(), equals(originalHash));
    });

    test('Recipe 1: Dramatic Monochrome Ink produces pure grayscale (R==G==B)',
        () {
      final out = BatchCRecipes.recipeDramaticMonochromeInk(portrait);
      for (int y = 0; y < out.height; y++) {
        for (int x = 0; x < out.width; x++) {
          final (r, g, b, _) = out.getPixel(x, y);
          expect(r, equals(g));
          expect(g, equals(b));
        }
      }
    });

    test(
        'Recipe 3: Warm DuoTone maps shadows to cool indigo and highlights to warm amber',
        () {
      final img = ImageBuffer(width: 2, height: 1);
      img.setPixel(0, 0, 0, 0, 0, 255); // Pure shadow
      img.setPixel(1, 0, 255, 255, 255, 255); // Pure highlight

      final out = BatchCRecipes.recipeWarmDuoTone(img);

      // Shadow pixel at (0, 0)
      final shadowPixel = out.getPixel(0, 0);
      // In cool indigo shadow: Blue (64) > Red (24)
      expect(shadowPixel.$3, greaterThan(shadowPixel.$1));

      // Highlight pixel at (1, 0)
      final highlightPixel = out.getPixel(1, 0);
      // In warm amber highlight: Red (255) > Blue (140)
      expect(highlightPixel.$1, greaterThan(highlightPixel.$3));
    });

    test('Repeatability across all three recipes', () {
      final run1a = BatchCRecipes.recipeDramaticMonochromeInk(portrait);
      final run1b = BatchCRecipes.recipeDramaticMonochromeInk(portrait);
      expect(run1a.computeSha256(), equals(run1b.computeSha256()));

      final run2a = BatchCRecipes.recipePastelPosterizeAndGrain(portrait);
      final run2b = BatchCRecipes.recipePastelPosterizeAndGrain(portrait);
      expect(run2a.computeSha256(), equals(run2b.computeSha256()));

      final run3a = BatchCRecipes.recipeWarmDuoTone(portrait);
      final run3b = BatchCRecipes.recipeWarmDuoTone(portrait);
      expect(run3a.computeSha256(), equals(run3b.computeSha256()));
    });
  });
}
