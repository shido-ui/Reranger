import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'package:reranger/core/theme/color_tokens.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/render/render_job_controller.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/editor/presentation/editor_screen.dart';
import 'package:reranger/features/humanize/presentation/humanize_controller.dart';
import 'package:reranger/features/humanize/presentation/humanize_screen.dart';
import 'package:reranger/humanize/local_humanize_adapter.dart';

void main() {
  group('Batch C (UX & Accessibility) Red-Team Audit Tests', () {
    late Directory tempDir;
    late ProjectDatabase db;
    late LocalProjectRepository repo;
    late ProjectEntity project;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('batch_c_a11y_');
      db = ProjectDatabase.openInMemory();
      repo = LocalProjectRepository(
        database: db,
        fileStorage: ProjectFileStorage(rootDir: tempDir),
      );

      final dummy = img.Image(width: 32, height: 32);
      final bytes = Uint8List.fromList(img.encodePng(dummy));
      final sourceFile = File('${tempDir.path}/source.png')
        ..writeAsBytesSync(bytes);
      final hash = sha256.convert(bytes).toString();

      project = ProjectEntity(
        id: 'proj_c_001',
        name: 'Batch C Project',
        sourceImagePath: sourceFile.path,
        sourceImageHash: hash,
        sourceWidth: 32,
        sourceHeight: 32,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_c_001',
          sourceImageHash: hash,
          sourceImagePath: sourceFile.path,
        ),
      );
      db.upsertProject(project);
    });

    tearDown(() {
      db.dispose();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    testWidgets(
      'DEF-017 Regression: HumanizeScreen offline badge uses accessible theme success tokens',
      (tester) async {
        final humanizeController = HumanizeController(
          adapter: LocalHumanizeAdapter(totalRamBytes: 8 * 1024 * 1024 * 1024),
        );

        // Test in Light Theme to verify high-contrast token
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: HumanizeScreen(controller: humanizeController),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final badgeTextFinder = find.text('100% OFFLINE');
        expect(badgeTextFinder, findsOneWidget);

        final textWidget = tester.widget<Text>(badgeTextFinder);
        expect(
          textWidget.style?.color,
          equals(AppColorTokens.lightAccentSuccess),
        );
      },
    );

    testWidgets(
      'DEF-018 Regression: Cancel in-flight render button meets >= 48x48dp touch target',
      (tester) async {
        final editor = EditorController(
          projectRepository: repo,
          fileStorage: ProjectFileStorage(rootDir: tempDir),
        );
        await tester.runAsync(() async {
          await editor.loadProject('proj_c_001');
        });

        await tester.pumpWidget(
          MaterialApp(
            home: EditorScreen(projectId: 'proj_c_001', controller: editor),
          ),
        );
        await tester.pump();

        // Simulate in-flight render state
        editor.renderState = const RenderJobExecuting(
          requestId: 1,
          activeNodeId: 'node_1',
          completedNodes: 1,
          totalNodes: 2,
          progress: 0.5,
        );
        editor.notifyListeners();
        await tester.pump();

        final cancelFinder = find.byTooltip('Cancel Render');
        expect(cancelFinder, findsOneWidget);

        final cancelSize = tester.getSize(cancelFinder);
        expect(cancelSize.width, greaterThanOrEqualTo(48.0));
        expect(cancelSize.height, greaterThanOrEqualTo(48.0));

        // Reset state and unmount widget to cancel infinite progress animation ticker
        editor.renderState = const RenderJobIdle();
        editor.notifyListeners();
        await tester.pumpWidget(const SizedBox.shrink());
        editor.dispose();
      },
    );
  });
}
