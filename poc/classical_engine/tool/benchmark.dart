import 'dart:io';
import 'package:classical_engine_poc/classical_engine.dart';

void main() {
  print('=== RERANGER CLASSICAL IMAGE ENGINE BENCHMARK SUITE ===');
  print('Platform: ${Platform.operatingSystem} ${Platform.version}');

  // 1. Small Fixture: 2x2
  final small = SyntheticFixtures.create2x2();
  print('\n--- [1] Small Fixture (2 x 2 = 4 pixels) ---');
  benchmarkSuite(small, iterations: 1000);

  // 2. Medium Fixture: 400x300 (120,000 pixels)
  final medium = SyntheticFixtures.createPortrait(width: 400, height: 300);
  print('\n--- [2] Medium Fixture (400 x 300 = 120,000 pixels) ---');
  benchmarkSuite(medium, iterations: 20);

  // 3. Large Fixture: 12MP (4000x3000 = 12,000,000 pixels = 48MB uncompressed buffer)
  print('\n--- [3] Large Fixture (4000 x 3000 = 12 Megapixels) ---');
  print('Allocating synthetic 12MP buffer...');
  final swAlloc = Stopwatch()..start();
  final large = SyntheticFixtures.create12Mp();
  swAlloc.stop();
  print(
      'Allocation time: ${swAlloc.elapsedMilliseconds} ms (${large.data.lengthInBytes ~/ (1024 * 1024)} MB)');

  // Run selected operations on 12MP
  benchmarkOp(
      '12MP Grayscale (BT.601)', () => BatchAOperations.toGrayscale(large),
      iterations: 3);
  benchmarkOp('12MP Sobel Edge Detection',
      () => BatchAOperations.sobelEdgeDetection(large),
      iterations: 1);
  benchmarkOp(
      '12MP Grain Overlay', () => BatchCRecipes.applyGrainOverlay(large),
      iterations: 2);
  benchmarkOp('12MP Recipe 3: Warm DuoTone',
      () => BatchCRecipes.recipeWarmDuoTone(large),
      iterations: 2);

  print('\n=== BENCHMARK COMPLETE ===');
}

void benchmarkSuite(ImageBuffer img, {required int iterations}) {
  benchmarkOp('Grayscale (BT.601)', () => BatchAOperations.toGrayscale(img),
      iterations: iterations);
  benchmarkOp(
      'Sobel Edge Detection', () => BatchAOperations.sobelEdgeDetection(img),
      iterations: iterations);
  benchmarkOp('Palette Quantization (k=4)',
      () => BatchBOperations.quantizePalette(img, k: 4),
      iterations: (iterations ~/ 2).clamp(1, 100));
  benchmarkOp(
      'Luminance Color Replace',
      () => BatchBOperations.replaceColorPreservingLuminance(
            img,
            targetColor: (255, 0, 0),
            replacementColor: (0, 255, 0),
          ),
      iterations: iterations);
  benchmarkOp('Grain Overlay', () => BatchCRecipes.applyGrainOverlay(img),
      iterations: iterations);
  benchmarkOp('Recipe 1: Monochrome Ink',
      () => BatchCRecipes.recipeDramaticMonochromeInk(img),
      iterations: iterations);
  benchmarkOp('Recipe 2: Pastel Posterize',
      () => BatchCRecipes.recipePastelPosterizeAndGrain(img),
      iterations: (iterations ~/ 2).clamp(1, 100));
  benchmarkOp(
      'Recipe 3: Warm DuoTone', () => BatchCRecipes.recipeWarmDuoTone(img),
      iterations: iterations);
}

void benchmarkOp(String name, Function() op, {required int iterations}) {
  // Warmup
  op();

  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    op();
  }
  sw.stop();

  final avgMs = sw.elapsedMicroseconds / (iterations * 1000.0);
  print(
      '  • $name: ${avgMs.toStringAsFixed(2)} ms / op (averaged over $iterations runs)');
}
