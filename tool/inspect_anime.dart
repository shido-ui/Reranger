import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:reranger/domain/segmentation/cielab_magic_wand_service.dart';

void main() async {
  final file = File('docs/evidence/prompt-09-a/corpus/ANIME-01-PORTRAIT.bmp');
  final bytes = await file.readAsBytes();
  final decoded = img.decodeImage(bytes)!;
  final rgbaBytes = Uint8List.fromList(
    decoded.getBytes(order: img.ChannelOrder.rgba),
  );

  const wand = CielabMagicWandService();

  // Test hair tap at (128, 95)
  final mask = wand.floodFill(
    rgbaBytes: rgbaBytes,
    width: decoded.width,
    height: decoded.height,
    seedX: 128,
    seedY: 95,
    hueTolerance: 0.22,
    colorTolerance: 0.20,
  );

  print(
    'Hair Tap at (128, 95): Selected=${mask.selectedPixelCount}, Coverage=${(mask.coverage * 100).toStringAsFixed(2)}%',
  );
}
