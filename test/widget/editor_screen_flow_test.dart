import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/core/theme/app_theme.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/editor/presentation/editor_screen.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';

void main() {
  group('SCR-04: Editor Screen & Viewport Flow Widget Tests', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;
    late File sampleImageFile;
    late ProjectEntity project;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('editor_widget_test_');
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );

      final image = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(120, 160, 200, 255));
      final imageBytes = img.encodePng(image);
      sampleImageFile = File('${tempDir.path}/test_source.png')
        ..writeAsBytesSync(imageBytes);
      final realSourceHash = sha256.convert(imageBytes).toString();

      project = ProjectEntity(
        id: 'proj_test_ui',
        name: 'Test Canvas Project',
        sourceImagePath: sampleImageFile.path,
        sourceImageHash: realSourceHash,
        sourceWidth: 32,
        sourceHeight: 32,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'recipe_proj_test_ui',
          sourceImageHash: realSourceHash,
          sourceImagePath: sampleImageFile.path,
        ),
      );
      database.upsertProject(project);
    });

    tearDown(() {
      database.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'EditorScreen mounts, displays viewport, preset carousel, and responds to interactions',
      (tester) async {
        final controller = EditorController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        // Pre-load project using runAsync
        await tester.runAsync(() async {
          await controller.loadProject(project.id);
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: EditorScreen(projectId: project.id, controller: controller),
          ),
        );
        await tester.pump();

        // 1. App bar displays project name
        expect(find.text('Test Canvas Project'), findsOneWidget);

        // 2. Preset Carousel displays registered presets
        expect(
          find.text(BatchAPresets.graphitePencil.displayName),
          findsOneWidget,
        );
        expect(find.text(BatchAPresets.fineInk.displayName), findsOneWidget);

        // 3. Compare button is visible
        expect(find.text('Compare'), findsOneWidget);
        expect(find.byIcon(Icons.compare_outlined), findsOneWidget);

        // 4. Slider for primary parameter is present
        final firstParam = controller.activePreset!.parameters.first;
        expect(find.text(firstParam.label), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);

        // 5. Select another preset via controller in runAsync
        await tester.runAsync(() async {
          await controller.selectPreset(BatchAPresets.fineInk);
        });
        await tester.pump();
        expect(controller.activePreset?.id, equals(BatchAPresets.fineInk.id));

        // 6. Before/After Compare toggle
        controller.setComparing(true);
        await tester.pump();
        expect(controller.isComparing, isTrue);
        expect(find.text('ORIGINAL (BEFORE)'), findsOneWidget);

        controller.setComparing(false);
        await tester.pump();
        expect(controller.isComparing, isFalse);

        // 7. Save Image execution via runAsync
        await tester.runAsync(() async {
          final ok = await controller.saveProject();
          expect(ok, isTrue);
        });
        await tester.pump();
        expect(controller.isSaved, isTrue);

        controller.dispose();
      },
    );

    testWidgets(
      'EditorScreen: No RenderFlex overflow on compact 320dp screen with 1.3 font scale',
      (tester) async {
        tester.view.physicalSize = const Size(320.0 * 2.0, 640.0 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = EditorController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        await tester.runAsync(() async {
          await controller.loadProject(project.id);
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320.0, 640.0),
                textScaler: TextScaler.linear(1.3),
              ),
              child: EditorScreen(
                projectId: project.id,
                controller: controller,
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Test Canvas Project'), findsOneWidget);
        expect(find.byType(Slider), findsOneWidget);

        controller.dispose();
      },
    );
  });
}
