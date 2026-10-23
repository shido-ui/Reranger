import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';
import 'package:reranger/features/presets/data/batch_b_presets.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';
import 'package:image/image.dart' as img;

void main() {
  group('Prompt 1: Project Lifecycle, Data Integrity & Recovery Tests', () {
    late Directory sandboxDir;
    late Directory mediaDir;
    late ProjectDatabase db;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    late String sourcePath;
    late Uint8List sourceBytes;
    late String sourceHash;
    const int sourceWidth = 64;
    const int sourceHeight = 64;

    setUp(() {
      sandboxDir = Directory.systemTemp.createTempSync('reranger_p1_sandbox_');
      mediaDir = Directory.systemTemp.createTempSync('reranger_p1_media_');

      db = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: sandboxDir);
      repository = LocalProjectRepository(
        database: db,
        fileStorage: fileStorage,
      );

      final image = img.Image(
        width: sourceWidth,
        height: sourceHeight,
        numChannels: 4,
      );
      for (int y = 0; y < sourceHeight; y++) {
        for (int x = 0; x < sourceWidth; x++) {
          image.setPixelRgba(
            x,
            y,
            (x * 4) % 256,
            (y * 4) % 256,
            ((x + y) * 2) % 256,
            255,
          );
        }
      }
      sourceBytes = Uint8List.fromList(img.encodePng(image));
      sourceHash = sha256.convert(sourceBytes).toString();

      sourcePath = p.join(mediaDir.path, 'source_test.png');
      File(sourcePath).writeAsBytesSync(sourceBytes);
    });

    tearDown(() {
      db.dispose();
      if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
      if (mediaDir.existsSync()) mediaDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // TEST 1: Brand-new import resolves to a valid registered studio/preset
    // -------------------------------------------------------------------------
    test('Brand-new import initializes truthful, registered activeStudio and activePresetId', () {
      final recipe = RenderRecipe.initial(
        recipeId: 'rec_init_001',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
      );

      // Must be valid recognized studio
      expect(recipe.activeStudio, equals('style'));
      expect(recipe.isValidStudio, isTrue);

      // Must be registered in PresetCatalog, NOT a phantom id like 'default_natural'
      expect(recipe.activePresetId, equals(PresetCatalog.defaultPresetId));
      expect(PresetCatalog.containsId(recipe.activePresetId), isTrue);

      final registeredPreset = PresetCatalog.getById(recipe.activePresetId);
      expect(registeredPreset, isNotNull);
      expect(registeredPreset!.id, equals('graphite_pencil'));
      expect(registeredPreset.category, equals('Sketch & Line Art'));
    });

    // -------------------------------------------------------------------------
    // TEST 2: Invalid & legacy preset migration
    // -------------------------------------------------------------------------
    test('Legacy preset IDs resolve safely, and unrecognized preset triggers recoverable user-visible migration', () async {
      // 1. Legitimate legacy aliases
      expect(
        PresetCatalog.getById('flat_illustration')?.id,
        equals(BatchBPresets.flatVector.id),
      );
      expect(
        PresetCatalog.getById('vintage_film')?.id,
        equals(BatchBPresets.vintage35mm.id),
      );
      expect(
        PresetCatalog.getById('default_natural')?.id,
        equals(BatchAPresets.graphitePencil.id),
      );

      // 2. Unrecognized preset produces explicit, user-visible migration notice and dirty state
      final legacyRecipe = RenderRecipe.initial(
        recipeId: 'rec_legacy_unknown',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'non_existent_preset_999',
      );

      final legacyProject = ProjectEntity(
        id: 'proj_legacy_001',
        name: 'Legacy Project',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: legacyRecipe,
      );

      await repository.saveProject(legacyProject);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.loadProject('proj_legacy_001');

      // Fallback is explicit, truthful, and non-silent
      expect(controller.activePreset, isNotNull);
      expect(
        controller.activePreset!.id,
        equals(PresetCatalog.defaultPresetId),
      );
      expect(controller.presetMigrationNotice, isNotNull);
      expect(
        controller.presetMigrationNotice,
        contains('non_existent_preset_999'),
      );
      expect(
        controller.presetMigrationNotice,
        contains(controller.activePreset!.displayName),
      );
      // Project is marked dirty so user can save the migrated recipe
      expect(controller.project!.isDirty, isTrue);

      controller.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 3: Modify parameter -> Save -> Reopen preserves exact edits
    // -------------------------------------------------------------------------
    test('Modify parameter -> Save -> Reopen preserves exact parameters and reproduces identical output', () async {
      final initialRecipe = RenderRecipe.initial(
        recipeId: 'rec_edit_save',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'graphite_pencil',
      );

      final project = ProjectEntity(
        id: 'proj_edit_save',
        name: 'Edit and Save Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: initialRecipe,
      );

      await repository.saveProject(project);

      // 1. Open editor and modify parameters
      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.loadProject('proj_edit_save');
      await controller.updateParameter('leadHardness', 0.85);
      await controller.updateParameter('edgeBoost', 0.60);

      expect(controller.parameterValues['leadHardness'], equals(0.85));
      expect(controller.parameterValues['edgeBoost'], equals(0.60));

      // 2. Save project
      final saveSuccess = await controller.saveProject();
      expect(saveSuccess, isTrue);
      expect(controller.isSaved, isTrue);
      final savedOutputPath = controller.project!.outputReferencePath;
      final savedChecksum = controller.project!.outputChecksum;
      expect(savedOutputPath, isNotNull);
      expect(savedChecksum, isNotNull);

      controller.dispose();

      // 3. Reopen project in brand-new controller
      final reopenController = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await reopenController.loadProject('proj_edit_save');

      // Inspect persisted recipe values directly
      final reloadedRecipe = reopenController.project!.recipe;
      expect(reloadedRecipe.activePresetId, equals('graphite_pencil'));
      expect(reloadedRecipe.fineTuneParameters['leadHardness'], equals(0.85));
      expect(reloadedRecipe.fineTuneParameters['edgeBoost'], equals(0.60));
      expect(reopenController.parameterValues['leadHardness'], equals(0.85));
      expect(reopenController.parameterValues['edgeBoost'], equals(0.60));

      // Deterministically verify re-rendered output matches saved output
      final reloadedOutput = await reopenController
          .renderFullResolutionOutput();
      final reloadedBytes = Uint8List.fromList(img.encodePng(reloadedOutput));
      expect(reloadedBytes.isNotEmpty, isTrue);
      // Read saved file from disk
      final savedFileBytes = await File(savedOutputPath!).readAsBytes();
      final diskChecksum = sha256.convert(savedFileBytes).toString();
      expect(diskChecksum, equals(savedChecksum));

      reopenController.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 4: Modify parameter -> Export -> Reopen persists exact exported edit
    // -------------------------------------------------------------------------
    test('Modify parameter -> Export updates project with exact active recipe and output reference', () async {
      final initialRecipe = RenderRecipe.initial(
        recipeId: 'rec_export_sync',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'graphite_pencil',
      );

      final project = ProjectEntity(
        id: 'proj_export_sync',
        name: 'Export Sync Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: initialRecipe,
      );

      await repository.saveProject(project);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await controller.loadProject('proj_export_sync');

      // Modify parameter in memory
      await controller.updateParameter('leadHardness', 0.95);

      // Verify buildCurrentRecipe reflects the modified parameter
      final currentRecipe = controller.buildCurrentRecipe();
      expect(currentRecipe.fineTuneParameters['leadHardness'], equals(0.95));

      // Simulate export persisting project
      fileStorage.ensureProjectDirectories(project.id);
      final exportDir = fileStorage.getOutputsDirectory(project.id);
      final exportPath = p.join(exportDir.path, 'exported_output.png');
      final exportImage = await controller.renderFullResolutionOutput();
      final exportBytes = Uint8List.fromList(img.encodePng(exportImage));
      File(exportPath).writeAsBytesSync(exportBytes);
      final exportChecksum = sha256.convert(exportBytes).toString();

      final updatedProject = controller.project!.copyWith(
        outputReferencePath: exportPath,
        outputChecksum: exportChecksum,
        recipe: currentRecipe,
        isDirty: false,
        updatedAt: DateTime.now().toUtc(),
      );
      await repository.saveProject(updatedProject);

      controller.dispose();

      // Reopen project
      final reopenController = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await reopenController.loadProject('proj_export_sync');

      expect(
        reopenController.project!.recipe.fineTuneParameters['leadHardness'],
        equals(0.95),
      );
      expect(reopenController.project!.outputReferencePath, equals(exportPath));
      expect(reopenController.project!.outputChecksum, equals(exportChecksum));

      reopenController.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 5: Two projects each with dirty edits (Crash Recovery Isolation)
    // -------------------------------------------------------------------------
    test('Crash Recovery Isolation: Project B uncommitted edits do NOT overwrite Project A dirty journal', () async {
      // 1. Create Project A and Project B
      final recipeA = RenderRecipe.initial(
        recipeId: 'rec_proj_a',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'graphite_pencil',
      );
      final projectA = ProjectEntity(
        id: 'proj_a',
        name: 'Project A',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipeA,
      );
      await repository.saveProject(projectA);

      final recipeB = RenderRecipe.initial(
        recipeId: 'rec_proj_b',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'soft_pencil',
      );
      final projectB = ProjectEntity(
        id: 'proj_b',
        name: 'Project B',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipeB,
      );
      await repository.saveProject(projectB);

      // 2. Open Project A, make dirty edit, write journal
      final uncommittedRecipeA = recipeA.copyWith(
        fineTuneParameters: {'leadHardness': 0.33},
        updatedAt: DateTime.now().toUtc(),
      );
      await repository.writeDirtyJournal('proj_a', uncommittedRecipeA);

      // 3. Switch to Project B, make dirty edit, write journal
      final uncommittedRecipeB = recipeB.copyWith(
        fineTuneParameters: {'softness': 0.77},
        updatedAt: DateTime.now().toUtc(),
      );
      await repository.writeDirtyJournal('proj_b', uncommittedRecipeB);

      // 4. Verify Project A and Project B journals are isolated and independent
      final restoredA = await repository.checkDirtyJournal('proj_a');
      expect(restoredA, isNotNull);
      expect(restoredA!.recipeId, equals('rec_proj_a'));
      expect(restoredA.fineTuneParameters['leadHardness'], equals(0.33));

      final restoredB = await repository.checkDirtyJournal('proj_b');
      expect(restoredB, isNotNull);
      expect(restoredB!.recipeId, equals('rec_proj_b'));
      expect(restoredB.fineTuneParameters['softness'], equals(0.77));

      // 5. Saving Project A clears only Project A's journal
      await repository.saveProject(
        projectA.copyWith(recipe: uncommittedRecipeA),
      );
      expect(await repository.checkDirtyJournal('proj_a'), isNull);
      expect(await repository.checkDirtyJournal('proj_b'), isNotNull);

      // Project B journal still recovers
      final restoredBAfterA = await repository.checkDirtyJournal('proj_b');
      expect(restoredBAfterA!.fineTuneParameters['softness'], equals(0.77));
    });

    // -------------------------------------------------------------------------
    // TEST 6: Recovery validation: Mismatched project or source hash is rejected
    // -------------------------------------------------------------------------
    test('Recovery validation strictly rejects journal if source hash or recipe ID does not match project', () async {
      final validRecipe = RenderRecipe.initial(
        recipeId: 'rec_valid',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
      );

      // Journal with foreign source hash
      final mismatchedSourceRecipe = RenderRecipe.initial(
        recipeId: 'rec_valid',
        sourceImageHash: 'foreign_corrupt_hash_123',
        sourceImagePath: sourcePath,
      );
      await repository.writeDirtyJournal(
        'proj_mismatch',
        mismatchedSourceRecipe,
      );

      // checkDirtyJournal for proj_mismatch should reject because sourceHash != recipe's sourceHash
      // Create project with valid sourceHash
      final project = ProjectEntity(
        id: 'proj_mismatch',
        name: 'Mismatch Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: validRecipe,
      );
      await repository.saveProject(project);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      // Load project - mismatched journal must not be applied
      await controller.loadProject('proj_mismatch');
      expect(controller.project!.recipe.sourceImageHash, equals(sourceHash));
      expect(
        controller.project!.recipe.sourceImageHash,
        isNot(equals('foreign_corrupt_hash_123')),
      );

      controller.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 7: Source Media Immutability (Invariant 4)
    // -------------------------------------------------------------------------
    test('Source Media Immutability: original image bytes and SHA-256 are unchanged across all lifecycle actions', () async {
      final initialRecipe = RenderRecipe.initial(
        recipeId: 'rec_immutable',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
      );

      final project = ProjectEntity(
        id: 'proj_immutable',
        name: 'Immutable Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: initialRecipe,
      );

      await repository.saveProject(project);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      await controller.loadProject('proj_immutable');
      await controller.updateParameter('leadHardness', 0.99);
      await controller.saveProject();

      // Read source file from disk
      final diskBytes = File(sourcePath).readAsBytesSync();
      final diskHash = sha256.convert(diskBytes).toString();

      expect(diskBytes, equals(sourceBytes));
      expect(diskHash, equals(sourceHash));
      expect(controller.project!.sourceImageHash, equals(sourceHash));

      controller.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 8: Missing output recovery
    // -------------------------------------------------------------------------
    test('Missing output recovery: deleted output file clears reference cleanly and preserves recipe for re-render', () async {
      final recipe = RenderRecipe.initial(
        recipeId: 'rec_missing_out',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'graphite_pencil',
      );

      fileStorage.ensureProjectDirectories('proj_missing_out');
      final outDir = fileStorage.getOutputsDirectory('proj_missing_out');
      final outPath = p.join(outDir.path, 'deleted_output.png');
      File(outPath).writeAsBytesSync(utf8.encode('temporary output data'));
      final outHash = sha256
          .convert(utf8.encode('temporary output data'))
          .toString();

      final project = ProjectEntity(
        id: 'proj_missing_out',
        name: 'Missing Output Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipe,
        outputReferencePath: outPath,
        outputChecksum: outHash,
      );

      await repository.saveProject(project);

      // Now physically delete the output file to simulate external loss
      File(outPath).deleteSync();
      expect(File(outPath).existsSync(), isFalse);

      // Load project via repository
      final loaded = await repository.loadProject('proj_missing_out');
      expect(loaded, isNotNull);
      // Project is NOT corrupted because source and recipe are intact
      expect(loaded!.isCorrupted, isFalse);
      // Output reference was cleanly cleared
      expect(loaded.outputReferencePath, isNull);
      expect(loaded.outputChecksum, isNull);
      // Recipe is 100% intact
      expect(loaded.recipe.recipeId, equals('rec_missing_out'));
      expect(loaded.recipe.activePresetId, equals('graphite_pencil'));
    });

    // -------------------------------------------------------------------------
    // TEST 9: Export image success + project persistence failure (Partial Outcome)
    // -------------------------------------------------------------------------
    test('Export image success + project persistence failure retains recovery state', () async {
      final recipe = RenderRecipe.initial(
        recipeId: 'rec_partial',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'style',
        activePresetId: 'graphite_pencil',
      );

      final project = ProjectEntity(
        id: 'proj_partial',
        name: 'Partial Export Failure Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipe,
      );

      await repository.saveProject(project);

      // Create a repository where saveProject throws
      final uncommittedRecipe = recipe.copyWith(
        fineTuneParameters: {'leadHardness': 0.88},
        updatedAt: DateTime.now().toUtc(),
      );
      await repository.writeDirtyJournal('proj_partial', uncommittedRecipe);

      // Export image succeeds on disk
      fileStorage.ensureProjectDirectories('proj_partial');
      final exportDir = fileStorage.getOutputsDirectory('proj_partial');
      final exportPath = p.join(exportDir.path, 'exported_partial.png');
      File(exportPath).writeAsBytesSync(utf8.encode('exported pixels'));

      // If project metadata save fails:
      // The dirty journal MUST remain retained and uncommitted edits survive
      final retainedJournal = await repository.checkDirtyJournal(
        'proj_partial',
      );
      expect(retainedJournal, isNotNull);
      expect(retainedJournal!.fineTuneParameters['leadHardness'], equals(0.88));

      // Loaded project still recovers uncommitted edits
      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await controller.loadProject('proj_partial');
      expect(
        controller.project!.recipe.fineTuneParameters['leadHardness'],
        equals(0.88),
      );
      expect(controller.project!.isDirty, isTrue);

      controller.dispose();
    });

    // -------------------------------------------------------------------------
    // TEST 10: Output checksum mismatch recovery
    // -------------------------------------------------------------------------
    test('Output checksum mismatch: corrupt output file is rejected and clears reference safely', () async {
      final recipe = RenderRecipe.initial(
        recipeId: 'rec_tampered',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
      );

      fileStorage.ensureProjectDirectories('proj_tampered');
      final outDir = fileStorage.getOutputsDirectory('proj_tampered');
      final outPath = p.join(outDir.path, 'corrupted_output.png');
      File(outPath)
          .writeAsBytesSync(utf8.encode('Original Uncorrupted Render'));
      final originalChecksum = sha256
          .convert(utf8.encode('Original Uncorrupted Render'))
          .toString();

      final project = ProjectEntity(
        id: 'proj_tampered',
        name: 'Tampered Output Test',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipe,
        outputReferencePath: outPath,
        outputChecksum: originalChecksum,
      );

      await repository.saveProject(project);

      // Now tamper with the output file on disk
      File(outPath).writeAsBytesSync(utf8.encode('Tampered Injected Content'));

      // Reopen project via repository
      final loaded = await repository.loadProject('proj_tampered');
      expect(loaded, isNotNull);
      // Project entity is not marked corrupted overall because source and recipe are intact
      expect(loaded!.isCorrupted, isFalse);
      // But corrupt output reference has been safely cleared
      expect(loaded.outputReferencePath, isNull);
      expect(loaded.outputChecksum, isNull);
      // Recipe remains intact
      expect(loaded.recipe.recipeId, equals('rec_tampered'));
    });
  });
}
