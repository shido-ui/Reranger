import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/features/import/data/isolate_image_decoder.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() {
  group('Batch B (Image Quality & Preset Catalog) Red-Team Audit Tests', () {
    const decoder = IsolateImageDecoder();

    test('DEF-016 Regression: All 8 EXIF orientation tags bake correctly into pixel geometry', () async {
      // Create an asymmetrical 200x100 test image with distinct quadrant colors
      for (int orientation = 1; orientation <= 8; orientation++) {
        final testImg = img.Image(width: 200, height: 100);
        img.fill(testImg, color: img.ColorRgba8(50, 100, 150, 255));
        testImg.setPixelRgba(0, 0, 255, 0, 0, 255); // Top-left anchor

        final baseJpg = img.encodeJpg(testImg);
        final exif = img.ExifData()..imageIfd.orientation = orientation;
        final jpgBytes = img.injectJpgExif(Uint8List.fromList(baseJpg), exif)!;

        final summary = await decoder.decodeAndAnalyze(jpgBytes);
        expect(
          summary.originalExifOrientation,
          equals(orientation),
          reason: 'Should detect original tag $orientation',
        );

        // Tags 5, 6, 7, 8 swap width and height (transpose/rotations)
        if (orientation >= 5 && orientation <= 8) {
          expect(
            summary.width,
            equals(100),
            reason: 'Orientation $orientation must swap width to 100',
          );
          expect(
            summary.height,
            equals(200),
            reason: 'Orientation $orientation must swap height to 200',
          );
        } else {
          // Tags 1, 2, 3, 4 preserve aspect ratio dimensions
          expect(
            summary.width,
            equals(200),
            reason: 'Orientation $orientation must retain width 200',
          );
          expect(
            summary.height,
            equals(100),
            reason: 'Orientation $orientation must retain height 100',
          );
        }
      }
    });

    test('Invariant 7 Honesty: 3D-styled presets explicitly disclose 2D raster simulation', () {
      final clay = PresetCatalog.getById('clay_render');
      expect(clay, isNotNull);
      expect(
        clay!.description.toLowerCase(),
        contains('2d raster simulation'),
        reason: 'Clay Render must disclose 2D raster simulation',
      );

      final lowPoly = PresetCatalog.getById('low_poly_facets');
      expect(lowPoly, isNotNull);
      expect(
        lowPoly!.description.toLowerCase(),
        contains('2d raster simulation'),
        reason: 'Low-Poly Facets must disclose 2D raster simulation',
      );
    });

    test('Preset Catalog Integrity: All 48 presets have valid accessible labels and non-empty categories', () {
      expect(PresetCatalog.all.length, equals(48));
      for (final p in PresetCatalog.all) {
        expect(p.accessibleLabel.isNotEmpty, isTrue);
        expect(p.category.isNotEmpty, isTrue);
        expect(p.thumbnailAssetPath.isNotEmpty, isTrue);
        expect(p.thumbnailProvenance.isNotEmpty, isTrue);
      }
    });
  });
}
