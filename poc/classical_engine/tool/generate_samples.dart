import 'dart:io';
import 'dart:typed_data';
import 'package:classical_engine_poc/classical_engine.dart';

Uint8List encodeBmp(ImageBuffer src) {
  final w = src.width;
  final h = src.height;
  final rowStride = (w * 3 + 3) & ~3;
  final imageSize = rowStride * h;
  final fileSize = 54 + imageSize;

  final bytes = ByteData(fileSize);
  bytes.setUint8(0, 0x42); // 'B'
  bytes.setUint8(1, 0x4D); // 'M'
  bytes.setUint32(2, fileSize, Endian.little);
  bytes.setUint32(6, 0, Endian.little);
  bytes.setUint32(10, 54, Endian.little);

  bytes.setUint32(14, 40, Endian.little);
  bytes.setInt32(18, w, Endian.little);
  bytes.setInt32(22, h, Endian.little);
  bytes.setUint16(26, 1, Endian.little);
  bytes.setUint16(28, 24, Endian.little);
  bytes.setUint32(30, 0, Endian.little);
  bytes.setUint32(34, imageSize, Endian.little);
  bytes.setInt32(38, 2835, Endian.little);
  bytes.setInt32(42, 2835, Endian.little);
  bytes.setUint32(46, 0, Endian.little);
  bytes.setUint32(50, 0, Endian.little);

  final uint8 = bytes.buffer.asUint8List();
  int pixelOffset = 54;
  for (int y = h - 1; y >= 0; y--) {
    for (int x = 0; x < w; x++) {
      final (r, g, b, _) = src.getPixel(x, y);
      uint8[pixelOffset++] = b;
      uint8[pixelOffset++] = g;
      uint8[pixelOffset++] = r;
    }
    for (int p = 0; p < (rowStride - w * 3); p++) {
      uint8[pixelOffset++] = 0;
    }
  }
  return uint8;
}

void main() {
  final outDir = Directory('/root/reranger/docs/evidence/prompt-07/samples');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  print('Generating input/output sample images...');

  // Input 1: Portrait fixture (120 x 160)
  final portrait = SyntheticFixtures.createPortrait(width: 120, height: 160);
  File('${outDir.path}/input_portrait.bmp')
      .writeAsBytesSync(encodeBmp(portrait));
  print('Saved: input_portrait.bmp (SHA-256: ${portrait.computeSha256()})');

  // Input 2: Panorama fixture (400 x 100)
  final pano = SyntheticFixtures.createPanorama(width: 400, height: 100);
  File('${outDir.path}/input_panorama.bmp').writeAsBytesSync(encodeBmp(pano));
  print('Saved: input_panorama.bmp (SHA-256: ${pano.computeSha256()})');

  // Input 3: High Contrast fixture (64 x 64)
  final highContrast =
      SyntheticFixtures.createHighContrast(width: 64, height: 64);
  File('${outDir.path}/input_high_contrast.bmp')
      .writeAsBytesSync(encodeBmp(highContrast));
  print(
      'Saved: input_high_contrast.bmp (SHA-256: ${highContrast.computeSha256()})');

  // Output 1: Grayscale
  final gray = BatchAOperations.toGrayscale(portrait);
  File('${outDir.path}/output_grayscale.bmp').writeAsBytesSync(encodeBmp(gray));
  print('Saved: output_grayscale.bmp (SHA-256: ${gray.computeSha256()})');

  // Output 2: Sobel Edge Map
  final edges = BatchAOperations.sobelEdgeDetection(highContrast);
  File('${outDir.path}/output_sobel_edges.bmp')
      .writeAsBytesSync(encodeBmp(edges));
  print('Saved: output_sobel_edges.bmp (SHA-256: ${edges.computeSha256()})');

  // Output 3: Palette Quantization (k=4)
  final quant = BatchBOperations.quantizePalette(portrait, k: 4).quantizedImage;
  File('${outDir.path}/output_palette_quantized.bmp')
      .writeAsBytesSync(encodeBmp(quant));
  print(
      'Saved: output_palette_quantized.bmp (SHA-256: ${quant.computeSha256()})');

  // Output 4: Recipe 1: Dramatic Monochrome Ink
  final rec1 = BatchCRecipes.recipeDramaticMonochromeInk(portrait);
  File('${outDir.path}/output_recipe1_monochrome_ink.bmp')
      .writeAsBytesSync(encodeBmp(rec1));
  print(
      'Saved: output_recipe1_monochrome_ink.bmp (SHA-256: ${rec1.computeSha256()})');

  // Output 5: Recipe 2: Pastel Posterize & Grain
  final rec2 = BatchCRecipes.recipePastelPosterizeAndGrain(portrait);
  File('${outDir.path}/output_recipe2_pastel_grain.bmp')
      .writeAsBytesSync(encodeBmp(rec2));
  print(
      'Saved: output_recipe2_pastel_grain.bmp (SHA-256: ${rec2.computeSha256()})');

  // Output 6: Recipe 3: Warm DuoTone Remap
  final rec3 = BatchCRecipes.recipeWarmDuoTone(portrait);
  File('${outDir.path}/output_recipe3_warm_duotone.bmp')
      .writeAsBytesSync(encodeBmp(rec3));
  print(
      'Saved: output_recipe3_warm_duotone.bmp (SHA-256: ${rec3.computeSha256()})');

  print('All sample files generated successfully.');
}
