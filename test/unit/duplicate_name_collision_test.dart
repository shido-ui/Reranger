import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/domain/project/project_entity.dart';

void main() {
  group('DEF-022: Duplicate Project Name Collision Resolution Tests', () {
    late ProjectDatabase db;

    setUp(() {
      db = ProjectDatabase.openInMemory();
    });

    tearDown(() {
      db.dispose();
    });

    ProjectEntity createTestProject({
      required String id,
      required String name,
    }) {
      return ProjectEntity(
        id: id,
        name: name,
        sourceImagePath: '/dummy/$name.png',
        sourceImageHash: 'dummy_hash_$id',
        sourceWidth: 100,
        sourceHeight: 100,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_$id',
          sourceImageHash: 'dummy_hash_$id',
          sourceImagePath: '/dummy/$name.png',
          activeStudio: 'recolor',
          activePresetId: 'default',
        ),
      );
    }

    test('resolveUniqueProjectName returns original name if not exists', () {
      final name = db.resolveUniqueProjectName('Mountain View');
      expect(name, equals('Mountain View'));
    });

    test('resolveUniqueProjectName resolves collision with (1)', () {
      db.upsertProject(createTestProject(id: 'proj_1', name: 'Mountain View'));

      final resolved = db.resolveUniqueProjectName('Mountain View');
      expect(resolved, equals('Mountain View (1)'));
    });

    test(
      'resolveUniqueProjectName handles successive collisions (1), (2), (3)',
      () {
        db.upsertProject(
          createTestProject(id: 'proj_1', name: 'Mountain View'),
        );
        db.upsertProject(
          createTestProject(id: 'proj_2', name: 'Mountain View (1)'),
        );
        db.upsertProject(
          createTestProject(id: 'proj_3', name: 'Mountain View (2)'),
        );

        final resolved = db.resolveUniqueProjectName('Mountain View');
        expect(resolved, equals('Mountain View (3)'));

        // If resolving from "Mountain View (1)", should increment intelligently to "Mountain View (3)"
        final resolvedFrom1 = db.resolveUniqueProjectName('Mountain View (1)');
        expect(resolvedFrom1, equals('Mountain View (3)'));
      },
    );

    test('resolveUniqueProjectName defaults empty or whitespace names', () {
      final resolved = db.resolveUniqueProjectName('   ');
      expect(resolved, equals('Untitled Project'));

      db.upsertProject(
        createTestProject(id: 'proj_untitled', name: 'Untitled Project'),
      );
      final resolvedNext = db.resolveUniqueProjectName('');
      expect(resolvedNext, equals('Untitled Project (1)'));
    });
  });
}
