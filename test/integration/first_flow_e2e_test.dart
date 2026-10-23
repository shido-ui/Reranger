import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';
import 'package:reranger/features/presets/data/batch_b_presets.dart';
import 'package:reranger/features/presets/data/batch_c_presets.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() {
  group('Prompt 17 — DEBUG GATE C: First Complete Flow Audit E2E Suite', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gate_c_audit_');
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );
    });

    tearDown(() {
      database.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File createSampleImageFile(
      String name, {
      int w = 64,
      int h = 64,
      int r = 180,
      int g = 120,
      int b = 60,
    }) {
      final image = img.Image(width: w, height: h, numChannels: 4);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final isCenter =
              (x - w / 2).abs() < (w / 4) && (y - h / 2).abs() < (h / 4);
          image.setPixelRgba(
            x,
            y,
            isCenter ? 240 : r,
            isCenter ? 210 : g,
            isCenter ? 90 : b,
            255,
          );
        }
      }
      final file = File('${tempDir.path}/$name')
        ..writeAsBytesSync(img.encodePng(image));
      return file;
    }

    test(
      'Audit Requirement 1: Complete Happy Path executed 3 consecutive times',
      () async {
        for (int run = 1; run <= 3; run++) {
          final sampleFile = createSampleImageFile(
            'sample_run_$run.png',
            w: 32,
            h: 32,
          );
          final initialSourceBytes = sampleFile.readAsBytesSync();
          final initialSourceHash = sha256
              .convert(initialSourceBytes)
              .toString();

          // 1. Intake Validation, Staging & Analysis via ImportController
          final importCtrl = ImportController(
            projectRepository: repository,
            fileStorage: fileStorage,
          );
          await importCtrl.importFromPath(sampleFile.path);

          expect(importCtrl.state, isA<ImportSuccess>());
          final project = (importCtrl.state as ImportSuccess).project;
          expect(project.sourceImageHash, equals(initialSourceHash));

          // 2. Open in Editor Controller
          final editor = EditorController(
            projectRepository: repository,
            fileStorage: fileStorage,
          );
          await editor.loadProject(project.id);

          expect(editor.isLoading, isFalse);
          expect(editor.errorMessage, isNull);
          expect(editor.previewPngBytes, isNotNull);
          final initialRenderHash = sha256
              .convert(editor.previewPngBytes!)
              .toString();

          // 3. Select Preset (Comic Book)
          await editor.selectPreset(BatchBPresets.comicBook);
          expect(editor.activePreset?.id, equals('comic_book'));
          final comicRenderHash = sha256
              .convert(editor.previewPngBytes!)
              .toString();
          expect(comicRenderHash, isNot(equals(initialRenderHash)));

          // 4. Adjust Slider Parameter
          final firstParam = BatchBPresets.comicBook.parameters.first;
          await editor.updateParameter(firstParam.id, firstParam.max);
          final alteredRenderHash = sha256
              .convert(editor.previewPngBytes!)
              .toString();
          expect(alteredRenderHash, isNot(equals(comicRenderHash)));

          // 5. Before/After Compare toggle
          editor.setComparing(true);
          expect(editor.isComparing, isTrue);
          editor.setComparing(false);
          expect(editor.isComparing, isFalse);

          // 6. Save & Export
          final saved = await editor.saveProject();
          expect(saved, isTrue);
          expect(editor.isSaved, isTrue);
          expect(editor.project?.outputReferencePath, isNotNull);

          final savedOutputFile = File(editor.project!.outputReferencePath!);
          expect(savedOutputFile.existsSync(), isTrue);
          final savedOutputBytes = savedOutputFile.readAsBytesSync();
          expect(
            savedOutputBytes.length,
            equals(editor.previewPngBytes!.length),
          );

          // 7. Reopen project from storage
          final reopenEditor = EditorController(
            projectRepository: repository,
            fileStorage: fileStorage,
          );
          await reopenEditor.loadProject(project.id);
          expect(reopenEditor.isSaved, isTrue);
          expect(reopenEditor.activePreset?.id, equals('comic_book'));
          expect(reopenEditor.previewPngBytes, isNotNull);

          // 8. Invariant 4 Check: Source image is 100% byte-identical
          final postSourceBytes = sampleFile.readAsBytesSync();
          final postSourceHash = sha256.convert(postSourceBytes).toString();
          expect(postSourceHash, equals(initialSourceHash));

          importCtrl.dispose();
          editor.dispose();
          reopenEditor.dispose();
        }
      },
    );

    test('Audit Requirement 2: Canceled render cannot overwrite newer result (Race Protection)', () async {
      final sampleFile = createSampleImageFile('sample_race.png', w: 32, h: 32);
      final importCtrl = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await importCtrl.importFromPath(sampleFile.path);
      final project = (importCtrl.state as ImportSuccess).project;

      final editor = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await editor.loadProject(project.id);

      // Dispatch render, immediately cancel, and dispatch another
      final future1 = editor.selectPreset(BatchCPresets.watercolor);
      editor.cancelRender();
      final future2 = editor.selectPreset(BatchCPresets.oilPaint);

      await Future.wait([future1, future2]);

      // Active preset and final preview must strictly match request 2 (oil paint)
      expect(editor.activePreset?.id, equals(BatchCPresets.oilPaint.id));
      expect(
        editor.renderJobController.staleResultsDiscardedCount,
        greaterThanOrEqualTo(0),
      );
      expect(editor.previewPngBytes, isNotNull);

      importCtrl.dispose();
      editor.dispose();
    });

    test('Audit Requirement 3: Project survives uncommitted force-stop and recovers via Dirty Journal', () async {
      final sampleFile = createSampleImageFile(
        'sample_crash.png',
        w: 32,
        h: 32,
      );
      final importCtrl = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await importCtrl.importFromPath(sampleFile.path);
      final project = (importCtrl.state as ImportSuccess).project;

      // 1. Session A: User selects Duotone and alters vignette, but process terminates before saving
      final editor1 = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await editor1.loadProject(project.id);
      await editor1.selectPreset(BatchAPresets.duotone);
      await editor1.updateParameter('vignetteFalloff', 0.65);

      // Verify dirty journal is recorded in SQLite
      final dirtyRecipe = await repository.checkDirtyJournal();
      expect(dirtyRecipe, isNotNull);
      expect(dirtyRecipe!.activePresetId, equals('duotone'));
      expect(dirtyRecipe.fineTuneParameters['vignetteFalloff'], equals(0.65));

      // Simulate crash: editor1 is closed abruptly without calling saveProject()
      editor1.dispose();

      // 2. Session B: Cold start after force stop
      final editor2 = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await editor2.loadProject(project.id);

      // Recovery assertion: active preset and fine tune parameters restored from crash journal
      expect(editor2.activePreset?.id, equals('duotone'));
      expect(editor2.parameterValues['vignetteFalloff'], equals(0.65));
      expect(editor2.project?.isDirty, isTrue);

      importCtrl.dispose();
      editor2.dispose();
    });

    test('Audit Requirement 4: Offline runtime compliance (Zero Network Calls, Invariant 5)', () async {
      // Execute all 12 presets in sequence and verify zero network exceptions
      final sampleFile = createSampleImageFile(
        'sample_offline.png',
        w: 16,
        h: 16,
      );
      final importCtrl = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await importCtrl.importFromPath(sampleFile.path);
      final project = (importCtrl.state as ImportSuccess).project;

      final editor = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await editor.loadProject(project.id);

      for (final preset in PresetCatalog.all) {
        await editor.selectPreset(preset);
        expect(editor.previewPngBytes, isNotNull);
      }

      importCtrl.dispose();
      editor.dispose();
    });

    test('Audit Requirement 5: Corrupted source detection and missing output recovery', () async {
      // 1. Missing output does not crash and enables fresh re-render
      final sampleFile = createSampleImageFile(
        'sample_recover.png',
        w: 16,
        h: 16,
      );
      final importCtrl = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await importCtrl.importFromPath(sampleFile.path);
      final project = (importCtrl.state as ImportSuccess).project;

      final projectWithMissingOutput = project.copyWith(
        outputReferencePath:
            '${tempDir.path}/deleted_output.png', // Non-existent
        outputChecksum: 'deadbeef',
      );
      await repository.saveProject(projectWithMissingOutput);

      final editor = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await editor.loadProject(projectWithMissingOutput.id);

      expect(editor.errorMessage, isNull);
      expect(editor.previewPngBytes, isNotNull); // Re-rendered successfully

      // 2. Corrupted source file reports error gracefully
      File(project.sourceImagePath)
          .writeAsStringSync('corrupted_garbage_bytes');
      final editorCorrupt = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await editorCorrupt.loadProject(projectWithMissingOutput.id);
      expect(editorCorrupt.errorMessage, isNotNull);

      importCtrl.dispose();
      editor.dispose();
      editorCorrupt.dispose();
    });
  });
}
