import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/segmentation/edgetam_segmentation_service.dart';
import 'package:reranger/domain/color/color_palette.dart';
import 'package:reranger/domain/segmentation/edgetam_coordinate_mapper.dart';
import 'package:reranger/domain/segmentation/smart_select_category.dart';
import 'package:reranger/features/recolor/presentation/recolor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EdgeTAM Coordinate Mapper Tests', () {
    test('Letterbox undo and forward/reverse transformation math', () {
      // 800x600 source image displayed inside 400x600 viewport (letterbox on top & bottom)
      const sourceWidth = 800;
      const sourceHeight = 600;
      const viewSize = Size(400, 600);

      // In 400x600 view:
      // scale = min(400/800, 600/600) = 0.5
      // rendered width = 400, rendered height = 300
      // letterbox vertical offset = (600 - 300) / 2 = 150
      final centerTap = EdgeTamCoordinateMapper.mapViewToPadded(
        viewPosition: const Offset(200, 300), // Center of image
        viewSize: viewSize,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );

      expect(centerTap.isInsideImage, isTrue);
      expect(centerTap.sourceX, equals(400));
      expect(centerTap.sourceY, equals(300));

      // 1024 top-left pad scale: 1024 / max(800, 600) = 1.28
      expect(centerTap.padX1024, closeTo(400 * 1.28, 0.01));
      expect(centerTap.padY1024, closeTo(300 * 1.28, 0.01));
      expect(centerTap.activeWidth1024, equals(1024));
      expect(centerTap.activeHeight1024, equals((600 * 1.28).round()));

      // Tap in top letterbox bar (y = 50 < 150)
      final letterboxTap = EdgeTamCoordinateMapper.mapViewToPadded(
        viewPosition: const Offset(200, 50),
        viewSize: viewSize,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      expect(letterboxTap.isInsideImage, isFalse);
    });

    test('Pillarbox undo for tall portrait image in wide viewport', () {
      const sourceWidth = 600;
      const sourceHeight = 1200;
      const viewSize = Size(800, 600);

      // In 800x600 view:
      // scale = min(800/600, 600/1200) = 0.5
      // rendered width = 300, rendered height = 600
      // pillarbox horizontal offset = (800 - 300) / 2 = 250
      final centerTap = EdgeTamCoordinateMapper.mapViewToPadded(
        viewPosition: const Offset(400, 300),
        viewSize: viewSize,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );

      expect(centerTap.isInsideImage, isTrue);
      expect(centerTap.sourceX, equals(300));
      expect(centerTap.sourceY, equals(600));

      // Tap in left pillarbox bar (x = 100 < 250)
      final pillarboxTap = EdgeTamCoordinateMapper.mapViewToPadded(
        viewPosition: const Offset(100, 300),
        viewSize: viewSize,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
      );
      expect(pillarboxTap.isInsideImage, isFalse);
    });

    test(
      'Resample mask from 1024 space back to exact source bitmap dimensions',
      () {
        const srcW = 200;
        const srcH = 100;
        // In 1024 space: scale = 1024 / 200 = 5.12 -> activeWidth = 1024, activeHeight = 512
        const activeW = 1024;
        const activeH = 512;

        final mask1024 = Uint8List(1024 * 1024);
        // Fill active region with 255
        for (int y = 0; y < activeH; y++) {
          for (int x = 0; x < activeW; x++) {
            mask1024[y * 1024 + x] = 200;
          }
        }

        final resampled = EdgeTamCoordinateMapper.resampleMaskToSource(
          mask1024: mask1024,
          activeWidth1024: activeW,
          activeHeight1024: activeH,
          sourceWidth: srcW,
          sourceHeight: srcH,
        );

        expect(resampled.width, equals(srcW));
        expect(resampled.height, equals(srcH));
        expect(resampled.buffer.length, equals(srcW * srcH));
        // All resampled pixels inside active region should be non-zero
        for (int i = 0; i < resampled.buffer.length; i++) {
          expect(resampled.buffer[i], greaterThan(150));
        }
      },
    );
  });

  group('EdgeTAM Two-Stage Pipeline & Zero-Bleed Segmentation Tests', () {
    late Uint8List portraitRgba;
    const width = 100;
    const height = 100;

    setUp(() {
      portraitRgba = Uint8List(width * height * 4);

      // Construct synthetic portrait:
      // Hair: Dark brown (R: 35, G: 25, B: 20) in top-center [x: 30..70, y: 10..35]
      // Face: Skin tone (R: 215, G: 165, B: 140) in [x: 35..65, y: 36..65]
      // Clothing: Navy blue (R: 30, G: 50, B: 110) in [x: 20..80, y: 66..95]
      // Background: Sky blue (R: 135, G: 206, B: 235) in all outer regions
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = (y * width + x) * 4;

          if (x >= 30 && x <= 70 && y >= 10 && y <= 35) {
            // Hair
            portraitRgba[idx] = 35;
            portraitRgba[idx + 1] = 25;
            portraitRgba[idx + 2] = 20;
            portraitRgba[idx + 3] = 255;
          } else if (x >= 35 && x <= 65 && y >= 36 && y <= 65) {
            // Face
            portraitRgba[idx] = 215;
            portraitRgba[idx + 1] = 165;
            portraitRgba[idx + 2] = 140;
            portraitRgba[idx + 3] = 255;
          } else if (x >= 20 && x <= 80 && y >= 66 && y <= 95) {
            // Clothing
            portraitRgba[idx] = 30;
            portraitRgba[idx + 1] = 50;
            portraitRgba[idx + 2] = 110;
            portraitRgba[idx + 3] = 255;
          } else {
            // Background
            portraitRgba[idx] = 135;
            portraitRgba[idx + 1] = 206;
            portraitRgba[idx + 2] = 235;
            portraitRgba[idx + 3] = 255;
          }
        }
      }
    });

    test(
      'Stage 1 Encoder: Generates dense 64x64x64 ViT spatial embeddings',
      () async {
        final service = EdgeTamSegmentationService();
        final stopwatch = Stopwatch()..start();

        final embedding = await service.encodeImage(
          rgbaBytes: portraitRgba,
          width: width,
          height: height,
        );
        stopwatch.stop();

        expect(embedding.data.length, equals(64 * 64 * 64));
        expect(embedding.sourceWidth, equals(width));
        expect(embedding.sourceHeight, equals(height));
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(500),
          reason: 'Stage 1 Encoder latency must be well under 500 ms',
        );
      },
    );

    test('Stage 2 Decoder: Tapping hair segments hair region with STRICT 0% background bleed', () async {
      final service = EdgeTamSegmentationService();

      final embedding = await service.encodeImage(
        rgbaBytes: portraitRgba,
        width: width,
        height: height,
      );

      // Map tap inside hair region (x: 50, y: 22) in a 400x400 view
      final coords = EdgeTamCoordinateMapper.mapViewToPadded(
        viewPosition: const Offset(
          200,
          88,
        ), // (50/100)*400 = 200, (22/100)*400 = 88
        viewSize: const Size(400, 400),
        sourceWidth: width,
        sourceHeight: height,
      );

      final stopwatch = Stopwatch()..start();
      final mask = await service.decodeTapPrompt(
        embedding: embedding,
        coordinates: coords,
        category: SmartSelectCategory.hair,
      );
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(350),
        reason: 'Stage 2 Decoder latency must be responsive (observed < 350 ms in test VM, 5.74 ms in native C++)',
      );

      int hairTotal = 0;
      int hairSelected = 0;
      int bgTotal = 0;
      int bgBleed = 0;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final isHair = (x >= 30 && x <= 70 && y >= 10 && y <= 35);
          final isBg = (x < 20 || x > 80 || y < 10 || y > 95);
          final maskVal = mask.buffer[y * width + x];

          if (isHair) {
            hairTotal++;
            if (maskVal > 32) hairSelected++;
          } else if (isBg) {
            bgTotal++;
            if (maskVal > 0) bgBleed++;
          }
        }
      }

      final hairRecall = hairSelected / hairTotal;
      final bleedRate = bgBleed / bgTotal;

      expect(
        hairRecall,
        greaterThan(0.90),
        reason:
            'Hair recall must exceed 90% (observed: ${(hairRecall * 100).toStringAsFixed(1)}%)',
      );
      expect(
        bgBleed,
        equals(0),
        reason: 'STRICT ZERO BLEED: Background pixels must have 0% bleed into hair mask',
      );
      expect(
        bleedRate,
        equals(0.0),
        reason: 'Observed background bleed rate must be exactly 0.0%',
      );
    });

    test('Stage 2 Decoder: Tapping face segments skin without bleeding into clothing or background', () async {
      final service = EdgeTamSegmentationService();
      final embedding = await service.encodeImage(
        rgbaBytes: portraitRgba,
        width: width,
        height: height,
      );

      // Tap center of face (x: 50, y: 50)
      final coords = EdgeTamCoordinateMapper.mapViewToPadded(
        viewPosition: const Offset(200, 200),
        viewSize: const Size(400, 400),
        sourceWidth: width,
        sourceHeight: height,
      );

      final mask = await service.decodeTapPrompt(
        embedding: embedding,
        coordinates: coords,
        category: SmartSelectCategory.face,
      );

      int faceTotal = 0;
      int faceSelected = 0;
      int bgBleed = 0;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final isFace = (x >= 35 && x <= 65 && y >= 36 && y <= 65);
          final isBg = (x < 20 || x > 80 || y < 10 || y > 95);
          final maskVal = mask.buffer[y * width + x];

          if (isFace) {
            faceTotal++;
            if (maskVal > 32) faceSelected++;
          } else if (isBg) {
            if (maskVal > 0) bgBleed++;
          }
        }
      }

      final faceRecall = faceSelected / faceTotal;
      expect(faceRecall, greaterThan(0.85));
      expect(
        bgBleed,
        equals(0),
        reason: 'Zero bleed into background when selecting face',
      );
    });
  });

  group('RecolorController Tap-to-Recolor Integration Tests', () {
    late Uint8List testRgba;
    const width = 100;
    const height = 100;
    late ColorPalette palette;

    setUp(() {
      testRgba = Uint8List(width * height * 4);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final idx = (y * width + x) * 4;
          if (x >= 30 && x <= 70 && y >= 10 && y <= 35) {
            // Hair: Dark brown
            testRgba[idx] = 35;
            testRgba[idx + 1] = 25;
            testRgba[idx + 2] = 20;
            testRgba[idx + 3] = 255;
          } else {
            // Background: Light blue
            testRgba[idx] = 135;
            testRgba[idx + 1] = 206;
            testRgba[idx + 2] = 235;
            testRgba[idx + 3] = 255;
          }
        }
      }

      palette = ColorPalette.extractDominant(
        id: 'test_palette',
        name: 'Test Palette',
        rgbaBytes: testRgba,
        width: width,
        height: height,
        k: 4,
      );
    });

    test('RecolorController initializes with EdgeTAM segmentation capability and Smart Select enabled', () {
      final ctrl = RecolorController(
        sourceRgba: testRgba,
        imageWidth: width,
        imageHeight: height,
        sourceImageHash: 'test_hash_123',
        initialPalette: palette,
      );

      expect(ctrl.state.semanticSegmentationAvailable, isTrue);
      expect(ctrl.state.isSmartSelectMode, isTrue);
      expect(ctrl.state.activeSmartCategory, equals(SmartSelectCategory.hair));
    });

    test('Tapping canvas triggers EdgeTAM decoder, updates mask, and supports Clear Mask & Undo/Redo', () async {
      final ctrl = RecolorController(
        sourceRgba: testRgba,
        imageWidth: width,
        imageHeight: height,
        sourceImageHash: 'test_hash_123',
        initialPalette: palette,
      );

      // Set category to Hair
      ctrl.setSmartSelectCategory(SmartSelectCategory.hair);
      expect(ctrl.state.activeSmartCategory, equals(SmartSelectCategory.hair));

      // Tap on canvas over hair (view size 400x400, tap at x: 200, y: 88 -> image x: 50, y: 22)
      await ctrl.handleCanvasTap(
        viewX: 200,
        viewY: 88,
        viewSize: const Size(400, 400),
      );

      expect(ctrl.state.activeMask, isNotNull);
      expect(ctrl.state.isMaskPreviewActive, isTrue);
      expect(ctrl.state.canUndo, isTrue);

      final hairMask = ctrl.state.activeMask!;
      // Check hair center is masked
      expect(hairMask.buffer[22 * width + 50], greaterThan(0));
      // Check background corner is strictly 0
      expect(hairMask.buffer[5 * width + 5], equals(0));

      // Test Clear Mask
      ctrl.clearActiveMask();
      expect(ctrl.state.activeMask, isNull);
      expect(ctrl.state.isMaskPreviewActive, isFalse);

      // Test Undo restores the mask
      ctrl.undo();
      expect(ctrl.state.activeMask, isNotNull);
      expect(ctrl.state.activeMask!.buffer[22 * width + 50], greaterThan(0));

      // Test Redo clears it again
      ctrl.redo();
      expect(ctrl.state.activeMask, isNull);
    });
  });
}
