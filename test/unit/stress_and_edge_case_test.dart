import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/autodraw/data/potrace_vectorizer.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/import/data/isolate_image_decoder.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mandate 2: Extreme Stress & Edge-Case Testing Suite', () {
    const decoder = IsolateImageDecoder();

    test(
      'Corrupt Files: 0-byte file throws ImageDecodingFailure gracefully',
      () async {
        final emptyBytes = Uint8List(0);
        expect(
          () async => await decoder.decodeAndAnalyze(emptyBytes),
          throwsA(isA<ImageDecodingFailure>()),
        );
      },
    );

    test('Corrupt Files: Invalid truncated bytes throws ImageDecodingFailure gracefully', () async {
      final garbageBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
      ]); // incomplete PNG header
      expect(
        () async => await decoder.decodeAndAnalyze(garbageBytes),
        throwsA(isA<ImageDecodingFailure>()),
      );
    });

    test('Edge Case: 1x1 pixel image decodes and extracts palette without division by zero', () async {
      final pixel = img.Image(width: 1, height: 1, numChannels: 4);
      pixel.setPixelRgba(0, 0, 255, 128, 64, 255);
      final bytes = Uint8List.fromList(img.encodePng(pixel));

      final summary = await decoder.decodeAndAnalyze(bytes);
      expect(summary.width, equals(1));
      expect(summary.height, equals(1));
      expect(summary.aspectRatio, equals(1.0));
      expect(summary.thumbnailWidth, equals(1));
      expect(summary.thumbnailHeight, equals(1));
      expect(summary.dominantPalette.isNotEmpty, isTrue);
    });

    test('Edge Case: Extreme aspect ratios (2000x2 and 2x2000) compute thumbnails safely', () async {
      // 2000x2 panoramic sliver
      final wide = img.Image(width: 2000, height: 2, numChannels: 4);
      img.fill(wide, color: img.ColorRgba8(50, 100, 150, 255));
      final wideBytes = Uint8List.fromList(img.encodePng(wide));

      final wideSummary = await decoder.decodeAndAnalyze(
        wideBytes,
        maxThumbnailDimension: 512,
      );
      expect(wideSummary.width, equals(2000));
      expect(wideSummary.height, equals(2));
      expect(wideSummary.thumbnailWidth, equals(512));
      expect(wideSummary.thumbnailHeight, greaterThanOrEqualTo(1));

      // 2x2000 tall strip
      final tall = img.Image(width: 2, height: 2000, numChannels: 4);
      img.fill(tall, color: img.ColorRgba8(150, 100, 50, 255));
      final tallBytes = Uint8List.fromList(img.encodePng(tall));

      final tallSummary = await decoder.decodeAndAnalyze(
        tallBytes,
        maxThumbnailDimension: 512,
      );
      expect(tallSummary.width, equals(2));
      expect(tallSummary.height, equals(2000));
      expect(tallSummary.thumbnailHeight, equals(512));
      expect(tallSummary.thumbnailWidth, greaterThanOrEqualTo(1));
    });

    test('Stress Testing: 12MP (4000x3000) image executes render graph within memory bounds', () async {
      const w = 4000;
      const h = 3000;
      final largeImg = img.Image(width: w, height: h, numChannels: 4);
      largeImg.setPixelRgba(0, 0, 255, 0, 0, 255);
      largeImg.setPixelRgba(w - 1, h - 1, 0, 255, 0, 255);
      final rawLargeBytes = Uint8List.fromList(img.encodePng(largeImg));
      expect(rawLargeBytes.length, greaterThan(1000));
      final realLargeHash = sha256.convert(rawLargeBytes).toString();

      final executor = RenderGraphExecutor();
      final graph = PresetCatalog.studioPresets.first.buildGraph(
        realLargeHash,
        w,
        h,
        {'studioStrength': 0.8},
      );

      // Execute at 0.25 preview scale (typical viewport scale for 12MP preview on mobile)
      final previewResult = await executor.execute(
        graph: graph,
        sourceImageBytes: rawLargeBytes,
        renderScale: 0.25,
      );

      expect(previewResult.width, equals(1000));
      expect(previewResult.height, equals(750));
      expect(previewResult.pixelBytes.isNotEmpty, isTrue);

      // Vectorize on downscaled preview buffer without OOM
      const vectorizer = PotraceVectorizer();
      final sbrResult = await vectorizer.vectorizeImage(
        rgbaBytes: previewResult.pixelBytes,
        width: previewResult.width,
        height: previewResult.height,
        maxPaths: 200,
      );
      expect(sbrResult.strokes.isNotEmpty, isTrue);
    });

    test('Rapid User Input: Spamming save button is safely guarded by isSaving lock', () async {
      final tempDir = Directory.systemTemp.createTempSync('stress_save_test_');
      final database = ProjectDatabase.openInMemory();
      final fileStorage = ProjectFileStorage(rootDir: tempDir);
      final repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );

      final dummyImg = img.Image(width: 16, height: 16, numChannels: 4);
      img.fill(dummyImg, color: img.ColorRgba8(200, 200, 200, 255));
      final bytes = Uint8List.fromList(img.encodePng(dummyImg));
      final file = File('${tempDir.path}/test.png')..writeAsBytesSync(bytes);
      final hash = sha256.convert(bytes).toString();

      final project = ProjectEntity(
        id: 'proj_stress_save',
        name: 'Stress Save Project',
        sourceImagePath: file.path,
        sourceImageHash: hash,
        sourceWidth: 16,
        sourceHeight: 16,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'recipe_stress',
          sourceImageHash: hash,
          sourceImagePath: file.path,
        ),
      );
      database.upsertProject(project);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.loadProject(project.id);
      controller.previewPngBytes = bytes;

      // Simulate rapid user double/triple tap on Save
      final future1 = controller.saveProject();
      // While future1 is in flight, isSaving is true:
      expect(controller.isSaving, isTrue);
      final future2 = controller.saveProject(); // duplicate tap

      final results = await Future.wait([future1, future2]);
      expect(results[0], isTrue);
      expect(
        results[1],
        isFalse,
        reason: 'Duplicate save must be rejected cleanly while first is active',
      );

      database.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('Rapid Preset Switching: Successive preset selections maintain deterministic DAG state', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'stress_switch_test_',
      );
      final database = ProjectDatabase.openInMemory();
      final fileStorage = ProjectFileStorage(rootDir: tempDir);
      final repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );

      final dummyImg = img.Image(width: 16, height: 16, numChannels: 4);
      img.fill(dummyImg, color: img.ColorRgba8(200, 200, 200, 255));
      final bytes = Uint8List.fromList(img.encodePng(dummyImg));
      final file = File('${tempDir.path}/test.png')..writeAsBytesSync(bytes);
      final hash = sha256.convert(bytes).toString();

      final project = ProjectEntity(
        id: 'proj_stress_switch',
        name: 'Stress Switch Project',
        sourceImagePath: file.path,
        sourceImageHash: hash,
        sourceWidth: 16,
        sourceHeight: 16,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'recipe_stress_switch',
          sourceImageHash: hash,
          sourceImagePath: file.path,
        ),
      );
      database.upsertProject(project);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.loadProject(project.id);

      // Rapidly switch through studio presets in succession
      final presets = [PresetCatalog.original, ...PresetCatalog.studioPresets];

      for (final p in presets) {
        controller.selectPreset(p);
      }

      expect(
        controller.activePreset?.id,
        equals(PresetCatalog.studioPresets.last.id),
      );
      expect(controller.isSaved, isFalse);

      database.dispose();
      tempDir.deleteSync(recursive: true);
    });
  });
}
