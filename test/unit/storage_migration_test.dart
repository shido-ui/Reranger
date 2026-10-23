import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reranger/data/local/app_storage_locator.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/domain/project/project_entity.dart';

void main() {
  group('DEF-021: Durable Storage & Idempotent Migration Tests', () {
    late Directory tempTestDir;
    late Directory durableDir;
    late Directory legacyDir;

    setUp(() {
      tempTestDir = Directory.systemTemp.createTempSync(
        'reranger_storage_test_',
      );
      durableDir = Directory(p.join(tempTestDir.path, 'durable'));
      durableDir.createSync(recursive: true);

      legacyDir = Directory(
        p.join(Directory.systemTemp.path, 'reranger_sandbox'),
      );
      if (legacyDir.existsSync()) {
        legacyDir.deleteSync(recursive: true);
      }
    });

    tearDown(() {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
      if (legacyDir.existsSync()) {
        legacyDir.deleteSync(recursive: true);
      }
    });

    test('Migration returns false when no legacy directory exists', () async {
      final locator = AppStorageLocator(durableDir: durableDir);
      final result = await locator.migrateFromLegacyTempStorage(durableDir);
      expect(result, isFalse);
    });

    test(
      'Migrates SQLite database and projects safely from legacy directory',
      () async {
        // 1. Create legacy database with a test project
        legacyDir.createSync(recursive: true);
        final legacyDbPath = p.join(legacyDir.path, 'reranger.db');
        final legacyDb = ProjectDatabase.openFile(legacyDbPath);
        legacyDb.upsertProject(
          ProjectEntity(
            id: 'legacy_proj_1',
            name: 'Legacy Masterpiece',
            sourceImagePath: '/legacy/image.png',
            sourceImageHash: 'legacy_hash_1',
            sourceWidth: 1920,
            sourceHeight: 1080,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            recipe: RenderRecipe.initial(
              recipeId: 'rec_legacy_1',
              sourceImageHash: 'legacy_hash_1',
              sourceImagePath: '/legacy/image.png',
              activeStudio: 'recolor',
              activePresetId: 'default',
            ),
          ),
        );
        legacyDb.dispose();

        // Create a dummy project file in legacy projects directory
        final legacyProjDir = Directory(
          p.join(legacyDir.path, 'projects', 'legacy_proj_1'),
        );
        legacyProjDir.createSync(recursive: true);
        File(p.join(legacyProjDir.path, 'metadata.json'))
            .writeAsStringSync('{"migrated": true}');

        // 2. Perform migration
        final locator = AppStorageLocator(durableDir: durableDir);
        final migrated = await locator.migrateFromLegacyTempStorage(durableDir);
        expect(migrated, isTrue);

        // 3. Verify target database has the project
        final targetDbPath = p.join(durableDir.path, 'reranger.db');
        expect(File(targetDbPath).existsSync(), isTrue);

        final targetDb = ProjectDatabase.openFile(targetDbPath);
        final loadedProject = targetDb.getProjectById('legacy_proj_1');
        expect(loadedProject, isNotNull);
        expect(loadedProject!.name, equals('Legacy Masterpiece'));
        targetDb.dispose();

        // Verify project file was migrated
        final migratedFile = File(
          p.join(durableDir.path, 'projects', 'legacy_proj_1', 'metadata.json'),
        );
        expect(migratedFile.existsSync(), isTrue);
        expect(migratedFile.readAsStringSync(), contains('"migrated": true'));

        // 4. Repeated migration is idempotent no-op
        final repeated = await locator.migrateFromLegacyTempStorage(durableDir);
        expect(repeated, isFalse);
      },
    );

    test(
      'Migration skips if target database already exists and has data',
      () async {
        legacyDir.createSync(recursive: true);
        final legacyDb = ProjectDatabase.openFile(
          p.join(legacyDir.path, 'reranger.db'),
        );
        legacyDb.upsertProject(
          ProjectEntity(
            id: 'legacy_p',
            name: 'Legacy Project',
            sourceImagePath: '/dummy.png',
            sourceImageHash: 'hash',
            sourceWidth: 10,
            sourceHeight: 10,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            recipe: RenderRecipe.initial(
              recipeId: 'r',
              sourceImageHash: 'h',
              sourceImagePath: '/d.png',
              activeStudio: 'recolor',
              activePresetId: 'p',
            ),
          ),
        );
        legacyDb.dispose();

        // Pre-create target database with different data
        final targetDb = ProjectDatabase.openFile(
          p.join(durableDir.path, 'reranger.db'),
        );
        targetDb.upsertProject(
          ProjectEntity(
            id: 'existing_p',
            name: 'Existing Durable Project',
            sourceImagePath: '/durable.png',
            sourceImageHash: 'dur_hash',
            sourceWidth: 20,
            sourceHeight: 20,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            recipe: RenderRecipe.initial(
              recipeId: 'r2',
              sourceImageHash: 'h2',
              sourceImagePath: '/d2.png',
              activeStudio: 'recolor',
              activePresetId: 'p2',
            ),
          ),
        );
        targetDb.dispose();

        final locator = AppStorageLocator(durableDir: durableDir);
        final migrated = await locator.migrateFromLegacyTempStorage(durableDir);
        expect(migrated, isFalse);

        // Verify existing durable database was preserved
        final verifyDb = ProjectDatabase.openFile(
          p.join(durableDir.path, 'reranger.db'),
        );
        expect(verifyDb.getProjectById('existing_p'), isNotNull);
        expect(verifyDb.getProjectById('legacy_p'), isNull);
        verifyDb.dispose();
      },
    );
  });
}
