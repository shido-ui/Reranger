import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/color/color_palette.dart';
import 'package:reranger/domain/color/recolor_mask.dart';

void main() {
  group('DEF-030: Recolor Mask Single-Alpha Contract Tests', () {
    test('RegionMask.fromColorTolerance preserves full 255 selection for matching semi-transparent pixels', () {
      // 1 pixel with color (200, 100, 50) and semi-transparent alpha 128
      final rgba = Uint8List.fromList([200, 100, 50, 128]);
      const sourceColor = ColorRgb(200, 100, 50);

      final mask = RegionMask.fromColorTolerance(
        rgbaBytes: rgba,
        width: 1,
        height: 1,
        sourceColor: sourceColor,
        tolerance: 0.1,
      );

      // Single-alpha contract: RegionMask represents pure spatial/color match weight (255)
      // Alpha modulation is performed downstream in render pipeline exactly once.
      expect(mask.buffer[0], equals(255));
    });

    test('RegionMask.fromColorTolerance zeros out completely transparent pixels (alpha 0)', () {
      final rgba = Uint8List.fromList([200, 100, 50, 0]);
      const sourceColor = ColorRgb(200, 100, 50);

      final mask = RegionMask.fromColorTolerance(
        rgbaBytes: rgba,
        width: 1,
        height: 1,
        sourceColor: sourceColor,
        tolerance: 0.1,
      );

      expect(mask.buffer[0], equals(0));
    });
  });
}
