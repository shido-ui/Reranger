import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/project/project_entity.dart';

class MockLowCapacityChecker implements StorageCapacityChecker {
  final int availableBytes;
  const MockLowCapacityChecker(this.availableBytes);

  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async =>
      availableBytes;
}

void main() {
  group('AtomicFileWriter & Source Immutability Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('reranger_writer_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Atomic write creates destination file with correct SHA-256 and no leftover temp files', () async {
      final writer = const AtomicFileWriter();
      final destination = p.join(tempDir.path, 'output.png');
      final bytes = utf8.encode('Reranger Test Image Content');

      final result = await writer.writeBytes(
        destinationPath: destination,
        bytes: bytes,
      );

      expect(File(destination).existsSync(), isTrue);
      expect(result.byteLength, equals(bytes.length));
      expect(result.sha256Checksum, equals(sha256.convert(bytes).toString()));

      // Verify no temporary files remain in directory
      final entities = tempDir.listSync();
      expect(entities.length, equals(1));
      expect(entities.first.path, equals(destination));
    });

    test(
      'Source Image Immutability Guard: Rejects overwriting source media',
      () async {
        final writer = const AtomicFileWriter();
        final sourcePath = p.join(tempDir.path, 'source_original.jpg');
        File(sourcePath).writeAsStringSync('Original Source Media Data');

        expect(
          () => writer.writeBytes(
            destinationPath: sourcePath,
            bytes: utf8.encode('Attempted overwrite'),
            sourceImagePath: sourcePath,
          ),
          throwsA(isA<StorageFailure>()),
        );

        // Verify source file content was NOT mutated
        expect(
          File(sourcePath).readAsStringSync(),
          equals('Original Source Media Data'),
        );
      },
    );

    test('Low-Storage Error Handling: Throws LowStorageFailure when headroom is below margin', () async {
      // Provide only 1 MB available storage (below the 10 MB minimum headroom)
      final writer = AtomicFileWriter(
        capacityChecker: const MockLowCapacityChecker(1024 * 1024),
      );
      final destination = p.join(tempDir.path, 'heavy_render.png');
      final bytes = List<int>.filled(500 * 1024, 0); // 500 KB

      expect(
        () => writer.writeBytes(destinationPath: destination, bytes: bytes),
        throwsA(isA<LowStorageFailure>()),
      );

      expect(File(destination).existsSync(), isFalse);
    });
  });

  group('LocalProjectRepository & Crash Recovery Full Lifecycle Tests', () {
    late Directory sandboxDir;
    late Directory mediaDir;
    late ProjectDatabase db;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    setUp(() {
      sandboxDir = Directory.systemTemp.createTempSync('reranger_sandbox_');
      mediaDir = Directory.systemTemp.createTempSync('reranger_media_');

      db = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: sandboxDir);
      repository = LocalProjectRepository(
        database: db,
        fileStorage: fileStorage,
      );
    });

    tearDown(() {
      db.dispose();
      if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
      if (mediaDir.existsSync()) mediaDir.deleteSync(recursive: true);
    });

    test('Full save/close/reopen round-trip preserves recipe, parameters, and source immutability', () async {
      // 1. Create source image in user media directory
      final sourcePath = p.join(mediaDir.path, 'photo.png');
      final sourceBytes = utf8.encode('Original Immutable Pixel Buffer');
      File(sourcePath).writeAsBytesSync(sourceBytes);
      final sourceHash = sha256.convert(sourceBytes).toString();

      final recipe =
          RenderRecipe.initial(
            recipeId: 'rec_101',
            sourceImageHash: sourceHash,
            sourceImagePath: sourcePath,
            activeStudio: 'style',
            activePresetId: 'cyberpunk_neon',
          ).copyWith(
            masterIntensity: 0.85,
            fineTuneParameters: {'contrast': 1.2, 'saturation': 1.4},
          );

      final project = ProjectEntity(
        id: 'proj_roundtrip',
        name: 'Neon Metropolis',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: 2048,
        sourceHeight: 1536,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipe,
        sceneMapCacheKey: 'scene_map_neon',
      );

      // Save project
      await repository.saveProject(project);

      // 2. Reopen project
      final loaded = await repository.loadProject('proj_roundtrip');
      expect(loaded, isNotNull);
      expect(loaded!.id, equals('proj_roundtrip'));
      expect(loaded.name, equals('Neon Metropolis'));
      expect(loaded.recipe.activeStudio, equals('style'));
      expect(loaded.recipe.activePresetId, equals('cyberpunk_neon'));
      expect(loaded.recipe.masterIntensity, equals(0.85));
      expect(loaded.recipe.fineTuneParameters['contrast'], equals(1.2));
      expect(loaded.sceneMapCacheKey, equals('scene_map_neon'));
      expect(loaded.isCorrupted, isFalse);

      // Verify source file on disk was NOT touched
      expect(File(sourcePath).readAsBytesSync(), equals(sourceBytes));
      expect(
        sha256.convert(File(sourcePath).readAsBytesSync()).toString(),
        equals(sourceHash),
      );
    });

    test('Crash Recovery: Uncommitted dirty journal restores unsaved recipe on launch', () async {
      final sourcePath = p.join(mediaDir.path, 'crash_photo.png');
      final sourceBytes = utf8.encode('Crash Test Source');
      File(sourcePath).writeAsBytesSync(sourceBytes);
      final sourceHash = sha256.convert(sourceBytes).toString();

      final uncommittedRecipe = RenderRecipe.initial(
        recipeId: 'rec_crash_restore',
        sourceImageHash: sourceHash,
        sourceImagePath: sourcePath,
        activeStudio: 'humanize',
        activePresetId: 'anime_delicate',
      ).copyWith(masterIntensity: 0.92);

      // Simulate unexpected termination leaving dirty journal
      await repository.writeDirtyJournal('proj_active', uncommittedRecipe);

      // On app launch: check dirty journal
      final restoredRecipe = await repository.checkDirtyJournal();
      expect(restoredRecipe, isNotNull);
      expect(restoredRecipe!.activeStudio, equals('humanize'));
      expect(restoredRecipe.activePresetId, equals('anime_delicate'));
      expect(restoredRecipe.masterIntensity, equals(0.92));

      // Clear journal after restoring
      await repository.clearDirtyJournal();
      expect(await repository.checkDirtyJournal(), isNull);
    });

    test('Missing Output Recovery: Missing rendered output does not crash and preserves recipe for re-render', () async {
      final sourcePath = p.join(mediaDir.path, 'source_valid.png');
      File(sourcePath).writeAsBytesSync(utf8.encode('Valid Source'));
      final sourceHash = sha256.convert(utf8.encode('Valid Source')).toString();

      final project = ProjectEntity(
        id: 'proj_missing_output',
        name: 'Deleted Output Project',
        sourceImagePath: sourcePath,
        sourceImageHash: sourceHash,
        sourceWidth: 800,
        sourceHeight: 600,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_out',
          sourceImageHash: sourceHash,
          sourceImagePath: sourcePath,
        ),
        outputReferencePath: p.join(sandboxDir.path, 'deleted_file.png'),
        outputChecksum: 'nonexistent_hash',
      );

      db.upsertProject(project);

      // Loading project with deleted output should NOT throw
      final loaded = await repository.loadProject('proj_missing_output');
      expect(loaded, isNotNull);
      expect(loaded!.isCorrupted, isFalse);
      expect(loaded.outputReferencePath, isNull); // Reset so user can re-render
    });

    test('Corrupted Source Detection: Source hash mismatch flags project as corrupted truthfully', () async {
      final sourcePath = p.join(mediaDir.path, 'tampered.png');
      File(sourcePath).writeAsBytesSync(utf8.encode('Original Content'));
      final originalHash = sha256
          .convert(utf8.encode('Original Content'))
          .toString();

      final project = ProjectEntity(
        id: 'proj_corrupt',
        name: 'Tampered Project',
        sourceImagePath: sourcePath,
        sourceImageHash: originalHash,
        sourceWidth: 800,
        sourceHeight: 600,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_tampered',
          sourceImageHash: originalHash,
          sourceImagePath: sourcePath,
        ),
      );

      db.upsertProject(project);

      // Tamper with the source file externally
      File(sourcePath).writeAsBytesSync(utf8.encode('Tampered Modified Bytes'));

      final loaded = await repository.loadProject('proj_corrupt');
      expect(loaded, isNotNull);
      expect(loaded!.isCorrupted, isTrue);
    });

    test(
      'Orphan Cleanup: Purges unreferenced directories and stale .tmp. files',
      () async {
        final p1Dir = fileStorage.getProjectDirectory('proj_active');
        p1Dir.createSync(recursive: true);
        File(p.join(p1Dir.path, 'valid.png')).writeAsStringSync('valid file');
        File(p.join(p1Dir.path, 'stale.tmp.1234.9999'))
            .writeAsStringSync('stale temp');

        final pOrphanDir = fileStorage.getProjectDirectory('proj_orphaned');
        pOrphanDir.createSync(recursive: true);
        File(p.join(pOrphanDir.path, 'abandoned.png'))
            .writeAsStringSync('abandoned');

        // Only proj_active is active in the database
        final cleanedCount = await fileStorage.orphanCleanup({'proj_active'});
        expect(
          cleanedCount,
          greaterThanOrEqualTo(2),
        ); // Orphan dir + stale tmp file

        expect(pOrphanDir.existsSync(), isFalse);
        expect(p1Dir.existsSync(), isTrue);
        expect(File(p.join(p1Dir.path, 'valid.png')).existsSync(), isTrue);
        expect(
          File(p.join(p1Dir.path, 'stale.tmp.1234.9999')).existsSync(),
          isFalse,
        );
      },
    );
  });
}
