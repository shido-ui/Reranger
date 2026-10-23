import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/domain/project/project_entity.dart';

void main() {
  group('ProjectDatabase Unit & Migration Tests', () {
    late ProjectDatabase database;

    setUp(() {
      database = ProjectDatabase.openInMemory();
    });

    tearDown(() {
      database.dispose();
    });

    test('Initializes with latest migration version (V3)', () {
      expect(database.currentVersion, equals(3));
    });

    test('Upsert and retrieve project round-trip succeeds with exact values', () {
      final now = DateTime.now().toUtc();
      final recipe = RenderRecipe.initial(
        recipeId: 'rec_001',
        sourceImageHash:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        sourceImagePath: '/sandbox/test.png',
        activeStudio: 'recolor',
        activePresetId: 'warm_glow',
      );

      final project = ProjectEntity(
        id: 'proj_001',
        name: 'Summer Vacation',
        sourceImagePath: '/sandbox/test.png',
        sourceImageHash:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        sourceWidth: 1920,
        sourceHeight: 1080,
        createdAt: now,
        updatedAt: now,
        recipe: recipe,
        sceneMapCacheKey: 'scene_map_001',
      );

      database.upsertProject(project);

      final loaded = database.getProjectById('proj_001');
      expect(loaded, isNotNull);
      expect(loaded!.id, equals('proj_001'));
      expect(loaded.name, equals('Summer Vacation'));
      expect(loaded.sourceWidth, equals(1920));
      expect(loaded.sourceHeight, equals(1080));
      expect(loaded.recipe.activeStudio, equals('recolor'));
      expect(loaded.recipe.activePresetId, equals('warm_glow'));
      expect(loaded.sceneMapCacheKey, equals('scene_map_001'));
    });

    test(
      'Rejects duplicate project names with DuplicateProjectNameFailure',
      () {
        final now = DateTime.now().toUtc();
        final recipe = RenderRecipe.initial(
          recipeId: 'rec_001',
          sourceImageHash: 'hash1',
          sourceImagePath: '/path1.png',
        );

        final project1 = ProjectEntity(
          id: 'proj_001',
          name: 'Unique Project',
          sourceImagePath: '/path1.png',
          sourceImageHash: 'hash1',
          sourceWidth: 100,
          sourceHeight: 100,
          createdAt: now,
          updatedAt: now,
          recipe: recipe,
        );

        final project2 = ProjectEntity(
          id: 'proj_002',
          name: 'Unique Project',
          sourceImagePath: '/path2.png',
          sourceImageHash: 'hash2',
          sourceWidth: 200,
          sourceHeight: 200,
          createdAt: now,
          updatedAt: now,
          recipe: recipe,
        );

        database.upsertProject(project1);
        expect(
          () => database.upsertProject(project2),
          throwsA(isA<DuplicateProjectNameFailure>()),
        );
      },
    );

    test('Recent projects list sorts by update timestamp descending', () {
      final t1 = DateTime.utc(2026, 1, 1, 10, 0);
      final t2 = DateTime.utc(2026, 1, 1, 12, 0);

      final recipe1 = RenderRecipe.initial(
        recipeId: 'rec_1',
        sourceImageHash: 'hash1',
        sourceImagePath: '/path1.png',
      );
      final recipe2 = RenderRecipe.initial(
        recipeId: 'rec_2',
        sourceImageHash: 'hash2',
        sourceImagePath: '/path2.png',
      );

      database.upsertProject(
        ProjectEntity(
          id: 'proj_older',
          name: 'Older Project',
          sourceImagePath: '/path1.png',
          sourceImageHash: 'hash1',
          sourceWidth: 100,
          sourceHeight: 100,
          createdAt: t1,
          updatedAt: t1,
          recipe: recipe1,
        ),
      );

      database.upsertProject(
        ProjectEntity(
          id: 'proj_newer',
          name: 'Newer Project',
          sourceImagePath: '/path2.png',
          sourceImageHash: 'hash2',
          sourceWidth: 200,
          sourceHeight: 200,
          createdAt: t1,
          updatedAt: t2,
          recipe: recipe2,
        ),
      );

      final recents = database.getRecentProjects();
      expect(recents.length, equals(2));
      expect(recents[0].id, equals('proj_newer'));
      expect(recents[1].id, equals('proj_older'));
    });

    test('Crash Recovery Dirty Journal write, read, and clear lifecycle', () {
      expect(database.readDirtyJournal(), isNull);

      final recipe = RenderRecipe.initial(
        recipeId: 'rec_crash_01',
        sourceImageHash: 'hash_crash',
        sourceImagePath: '/path_crash.png',
        activeStudio: 'humanize',
      );

      database.writeDirtyJournal('proj_active', recipe);

      final journal = database.readDirtyJournal();
      expect(journal, isNotNull);
      expect(journal!['projectId'], equals('proj_active'));
      final recoveredRecipe = journal['recipe'] as RenderRecipe;
      expect(recoveredRecipe.activeStudio, equals('humanize'));

      database.clearDirtyJournal();
      expect(database.readDirtyJournal(), isNull);
    });

    test('Crash Recovery Dirty Journal project-scoped isolation', () {
      final recipeA = RenderRecipe.initial(
        recipeId: 'rec_a',
        sourceImageHash: 'hash_a',
        sourceImagePath: '/path_a.png',
        activeStudio: 'style',
      );
      final recipeB = RenderRecipe.initial(
        recipeId: 'rec_b',
        sourceImageHash: 'hash_b',
        sourceImagePath: '/path_b.png',
        activeStudio: 'recolor',
      );

      database.writeDirtyJournal('proj_a', recipeA);
      database.writeDirtyJournal('proj_b', recipeB);

      // Both project entries must coexist independently without overwriting each other
      final journalA = database.readDirtyJournal('proj_a');
      final journalB = database.readDirtyJournal('proj_b');

      expect(journalA, isNotNull);
      expect(journalA!['projectId'], equals('proj_a'));
      expect(
        (journalA['recipe'] as RenderRecipe).activeStudio,
        equals('style'),
      );

      expect(journalB, isNotNull);
      expect(journalB!['projectId'], equals('proj_b'));
      expect(
        (journalB['recipe'] as RenderRecipe).activeStudio,
        equals('recolor'),
      );

      // Clearing proj_a leaves proj_b intact
      database.clearDirtyJournal('proj_a');
      expect(database.readDirtyJournal('proj_a'), isNull);
      expect(database.readDirtyJournal('proj_b'), isNotNull);

      // Clearing proj_b cleans it up
      database.clearDirtyJournal('proj_b');
      expect(database.readDirtyJournal('proj_b'), isNull);
    });

    test('Scene map caching avoids redundant analysis on reopen', () {
      const cacheKey = 'scene_map_sha256_preset';
      const analysisJson =
          '{"dominant_palette":["#FFFFFF","#000000"],"histogram":[1,2,3]}';

      expect(database.getSceneMapCache(cacheKey), isNull);

      database.saveSceneMapCache(cacheKey, 'source_sha256', analysisJson);

      final cached = database.getSceneMapCache(cacheKey);
      expect(cached, equals(analysisJson));
    });

    test('Project deletion cleans up record', () {
      final recipe = RenderRecipe.initial(
        recipeId: 'rec_del',
        sourceImageHash: 'hash_del',
        sourceImagePath: '/path_del.png',
      );
      final project = ProjectEntity(
        id: 'proj_del',
        name: 'To Delete',
        sourceImagePath: '/path_del.png',
        sourceImageHash: 'hash_del',
        sourceWidth: 50,
        sourceHeight: 50,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: recipe,
      );

      database.upsertProject(project);
      expect(database.getProjectById('proj_del'), isNotNull);

      final deleted = database.deleteProject('proj_del');
      expect(deleted, isTrue);
      expect(database.getProjectById('proj_del'), isNull);
    });
  });
}
