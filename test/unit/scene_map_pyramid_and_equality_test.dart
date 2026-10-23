import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/scene_map/isolate_scene_map_generator.dart';
import 'package:reranger/domain/color/color_palette.dart';
import 'package:reranger/domain/scene_map/coordinate_transform.dart';

void main() {
  group('DEF-028 & DEF-029: Scene-Map Pyramid Resizing & Equality Axioms', () {
    test(
      'DEF-029: NormalizedPoint equality and hashCode are strictly consistent',
      () {
        const p1 = NormalizedPoint(0.25, 0.75);
        const p2 = NormalizedPoint(0.25, 0.75);
        const p3 = NormalizedPoint(0.2500001, 0.75);

        expect(p1 == p2, isTrue);
        expect(p1.hashCode, equals(p2.hashCode));

        expect(p1 == p3, isFalse);
      },
    );

    test(
      'DEF-029: NormalizedRect equality and hashCode are strictly consistent',
      () {
        const r1 = NormalizedRect(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
        const r2 = NormalizedRect(left: 0.1, top: 0.2, width: 0.3, height: 0.4);
        const r3 = NormalizedRect(
          left: 0.1,
          top: 0.2,
          width: 0.3,
          height: 0.40001,
        );

        expect(r1 == r2, isTrue);
        expect(r1.hashCode, equals(r2.hashCode));

        expect(r1 == r3, isFalse);
      },
    );

    test('DEF-029: ColorHsl equality and hashCode are strictly consistent', () {
      const c1 = ColorHsl(180.0, 0.5, 0.5, 255);
      const c2 = ColorHsl(180.0, 0.5, 0.5, 255);
      const c3 = ColorHsl(180.1, 0.5, 0.5, 255);

      expect(c1 == c2, isTrue);
      expect(c1.hashCode, equals(c2.hashCode));

      expect(c1 == c3, isFalse);
    });

    test('DEF-028: Scene-Map generator handles extreme aspect ratio (1px height) without buffer mismatch', () async {
      // 100 x 1 image
      final flatImage = img.Image(width: 100, height: 1);
      for (int x = 0; x < 100; x++) {
        flatImage.setPixelRgba(x, 0, (x * 2) % 256, 128, 64, 255);
      }
      final pngBytes = Uint8List.fromList(img.encodePng(flatImage));
      final sourceHash = sha256.convert(pngBytes).toString();

      const generator = IsolateSceneMapGenerator();
      final bundle = await generator.generate(
        imageBytes: pngBytes,
        sourceHash: sourceHash,
        edgeThreshold: 30,
        paletteK: 3,
      );

      expect(bundle, isNotNull);
      expect(bundle.pyramidLevels.length, equals(3));
      // Level 1: half of 100x1 -> 50x1
      final l1 = bundle.pyramidLevels[1];
      expect(l1.width, equals(50));
      expect(l1.height, equals(1));
      expect(l1.luminanceData.length, equals(50 * 1));

      // Level 2: quarter of 100x1 -> 25x1
      final l2 = bundle.pyramidLevels[2];
      expect(l2.width, equals(25));
      expect(l2.height, equals(1));
      expect(l2.luminanceData.length, equals(25 * 1));
    });
  });
}
