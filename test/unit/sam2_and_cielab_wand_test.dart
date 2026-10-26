import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/segmentation/sam2_segmentation_service.dart';
import 'package:reranger/domain/segmentation/cielab_magic_wand_service.dart';
import 'package:reranger/domain/segmentation/sam2_models.dart';
import 'package:reranger/features/autodraw/data/potrace_vectorizer.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';
import 'package:reranger/features/recolor/presentation/recolor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'TASK 1: Split-Brain Architecture (SAM 2.1 Photo AI vs CIELAB Art Color)',
    () {
      test('1. Neural Mode (SAM 2.1 Hiera-Small): Extracts embeddings and decodes point prompt', () async {
        final service = Sam2SegmentationService();
        final width = 64;
        final height = 64;
        final rgba = Uint8List(width * height * 4);

        // Solid circle on contrasting background
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final off = (y * width + x) * 4;
            final dx = x - 32;
            final dy = y - 32;
            if (dx * dx + dy * dy <= 256) {
              rgba[off] = 220;
              rgba[off + 1] = 60;
              rgba[off + 2] = 80;
              rgba[off + 3] = 255;
            } else {
              rgba[off] = 240;
              rgba[off + 1] = 240;
              rgba[off + 2] = 240;
              rgba[off + 3] = 255;
            }
          }
        }

        // Stage 1: Encode once
        final embedding = await service.encodeImage(
          rgbaBytes: rgba,
          width: width,
          height: height,
        );
        expect(embedding.data.length, equals(Sam2Embedding.totalElements));

        // Stage 2: Decode point prompt at center
        final mask = await service.decodePointPrompt(
          embedding: embedding,
          prompt: const Sam2PointPrompt(x: 32, y: 32),
          targetWidth: width,
          targetHeight: height,
        );

        expect(mask.width, equals(width));
        expect(mask.height, equals(height));
        expect(mask.selectedPixelCount, greaterThan(100));
      });

      test('2. Math Mode (CIELAB Magic Wand): Selects connected hair on anime art, bounded by ink outlines', () async {
        const animePath =
            'docs/evidence/prompt-09-a/corpus/ANIME-01-PORTRAIT.bmp';
        final file = File(animePath);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Anime benchmark fixture must exist',
        );

        final rawBytes = await file.readAsBytes();
        final decoded = img.decodeImage(rawBytes)!;
        final rgbaBytes = Uint8List.fromList(
          decoded.getBytes(order: img.ChannelOrder.rgba),
        );

        const wand = CielabMagicWandService();

        // Tap on hair region in ANIME-01-PORTRAIT (x=128, y=95)
        final mask = wand.floodFill(
          rgbaBytes: rgbaBytes,
          width: decoded.width,
          height: decoded.height,
          seedX: 128,
          seedY: 95,
          hueTolerance: 0.22,
          colorTolerance: 0.20,
        );

        expect(mask.selectedPixelCount, greaterThan(200));
        // Verify mask does not bleed across entire image (coverage strictly bounded by lines)
        expect(
          mask.coverage,
          lessThan(0.50),
          reason: 'Hair mask must not bleed to full image',
        );

        // Coordinate mapping test
        final mapped = Sam2CoordinateMapper.mapViewToSource(
          viewPosition: const Offset(100, 100),
          viewSize: const Size(200, 200),
          sourceWidth: 256,
          sourceHeight: 256,
        );
        expect(mapped.dx, closeTo(128.0, 1.0));
        expect(mapped.dy, closeTo(128.0, 1.0));
      });

      test('3. RecolorController Split-Brain Integration: Toggling Photo AI and Art Color works seamlessly', () async {
        final dummyRgba = Uint8List(32 * 32 * 4);
        dummyRgba.fillRange(0, dummyRgba.length, 200);

        final controller = RecolorController(
          sourceRgba: dummyRgba,
          imageWidth: 32,
          imageHeight: 32,
          sourceImageHash: 'dummy_hash',
        );

        expect(
          controller.state.segmentationMode,
          equals(SegmentationMode.artColor),
        );

        controller.setSegmentationMode(SegmentationMode.photoAi);
        expect(
          controller.state.segmentationMode,
          equals(SegmentationMode.photoAi),
        );

        controller.setSegmentationMode(SegmentationMode.artColor);
        expect(
          controller.state.segmentationMode,
          equals(SegmentationMode.artColor),
        );

        // Test tap handling
        await controller.handleCanvasTap(
          viewX: 16,
          viewY: 16,
          viewSize: const Size(32, 32),
        );

        expect(controller.state.activeMask, isNotNull);
        expect(controller.state.isMaskPreviewActive, isTrue);
      });
    },
  );

  group('TASK 2: Autodraw & UI Fixes', () {
    test('1. Non-Zero Strokes: PotraceVectorizer generates strokes even on uniform solid images', () async {
      const vectorizer = PotraceVectorizer();
      final solidRgba = Uint8List(64 * 64 * 4);
      solidRgba.fillRange(0, solidRgba.length, 255); // pure white image

      final result = await vectorizer.vectorizeImage(
        rgbaBytes: solidRgba,
        width: 64,
        height: 64,
      );

      expect(
        result.strokes.isNotEmpty,
        isTrue,
        reason: 'Vectorization must never return 0 strokes',
      );
      expect(result.strokes.length, greaterThanOrEqualTo(1));
    });

    test(
      '2. Original Preset: Pure pass-through DAG with no visual alteration',
      () async {
        final originalPreset = PresetCatalog.getById('original');
        expect(originalPreset, isNotNull);
        expect(originalPreset!.id, equals('original'));
        expect(originalPreset.parameters.isEmpty, isTrue);

        final executor = RenderGraphExecutor();
        final dummyImage = img.Image(width: 16, height: 16, numChannels: 4);
        img.fill(dummyImage, color: img.ColorRgba8(100, 150, 200, 255));
        final pngBytes = Uint8List.fromList(img.encodePng(dummyImage));
        final sourceHash = sha256.convert(pngBytes).toString();

        final graph = originalPreset.buildGraph(sourceHash, 16, 16, {});
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: pngBytes,
        );

        // Verify pixel bytes are byte-for-byte identical (pure pass-through)
        final rawDecoded = dummyImage.getBytes(order: img.ChannelOrder.rgba);
        expect(result.pixelBytes, equals(rawDecoded));
      },
    );
  });

  group('TASK 3: Top-Quality Studio Shaders', () {
    test('1. All 5 Locked Studio Presets are registered and locked to single Studio Strength slider', () {
      final studioPresets = PresetCatalog.studioPresets;
      expect(studioPresets.length, equals(5));

      final expectedIds = [
        'studio_cinematic_teal_orange',
        'studio_ethereal_portrait',
        'studio_vintage_film_pro',
        'studio_cyberpunk_neon',
        'studio_soft_pastel_dream',
      ];

      for (final id in expectedIds) {
        final preset = PresetCatalog.getById(id);
        expect(
          preset,
          isNotNull,
          reason: 'Preset $id must be resolvable via catalog',
        );
        expect(
          preset!.isLockedStudioPreset,
          isTrue,
          reason: '$id must be marked as locked studio preset',
        );
        expect(preset.parameters.length, equals(1));
        expect(preset.parameters.first.id, equals('studioStrength'));
      }
    });

    test('2. Studio Presets execute multi-pass DAG and respond to Studio Strength slider', () async {
      final executor = RenderGraphExecutor();
      final dummyImage = img.Image(width: 32, height: 32, numChannels: 4);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          dummyImage.setPixelRgba(x, y, x * 7, y * 7, (x + y) * 3, 255);
        }
      }
      final pngBytes = Uint8List.fromList(img.encodePng(dummyImage));
      final sourceHash = sha256.convert(pngBytes).toString();

      for (final preset in PresetCatalog.studioPresets) {
        // Execute at strength 1.0
        final graphFull = preset.buildGraph(sourceHash, 32, 32, {
          'studioStrength': 1.0,
        });
        final resultFull = await executor.execute(
          graph: graphFull,
          sourceImageBytes: pngBytes,
        );

        // Execute at strength 0.1
        final graphLow = preset.buildGraph(sourceHash, 32, 32, {
          'studioStrength': 0.1,
        });
        final resultLow = await executor.execute(
          graph: graphLow,
          sourceImageBytes: pngBytes,
        );

        expect(
          resultFull.pixelBytes,
          isNot(equals(resultLow.pixelBytes)),
          reason:
              'Preset ${preset.id} must respond to Studio Strength slider adjustments',
        );
      }
    });
  });
}
