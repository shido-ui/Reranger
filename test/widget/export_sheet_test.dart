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

void main() {
  group('Prompt 24: Export Sheet Widget Tests (SCR-09)', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;
    late File sampleImageFile;
    late ProjectEntity project;

    Future<void> settleSheet(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'export_sheet_widget_test_',
      );
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );

      final image = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(80, 120, 160, 255));
      final imageBytes = img.encodePng(image);
      sampleImageFile = File('${tempDir.path}/test_source.png')
        ..writeAsBytesSync(imageBytes);
      final realSourceHash = sha256.convert(imageBytes).toString();

      project = ProjectEntity(
        id: 'proj_export_widget_test',
        name: 'Export Sheet Project',
        sourceImagePath: sampleImageFile.path,
        sourceImageHash: realSourceHash,
        sourceWidth: 32,
        sourceHeight: 32,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_export_widget_test',
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
      'Export Sheet: Formats, honest JPEG alpha warning, quality slider, GPS toggle, and save',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final controller = EditorController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        await tester.runAsync(() async {
          await controller.loadProject(project.id);
        });
        controller.previewPngBytes = sampleImageFile.readAsBytesSync();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: EditorScreen(projectId: project.id, controller: controller),
          ),
        );
        await tester.pump();

        // 1. Open Export Sheet from AppBar
        final exportButtonFinder = find.byTooltip('Export Options');
        expect(exportButtonFinder, findsOneWidget);
        await tester.tap(exportButtonFinder);
        await settleSheet(tester);

        // 2. Verify sheet structure & title
        expect(find.text('Export Studio'), findsOneWidget);
        expect(find.text('Output Format'), findsOneWidget);
        expect(find.text('PNG'), findsOneWidget);
        expect(find.text('JPEG'), findsOneWidget);
        expect(find.text('WebP'), findsOneWidget);

        // By default (PNG), no JPEG alpha warning is shown and no quality slider
        expect(
          find.textContaining('JPEG does not support alpha transparency'),
          findsNothing,
        );
        expect(find.text('Compression Quality'), findsNothing);

        // 3. Switch to JPEG
        await tester.tap(find.text('JPEG'));
        await settleSheet(tester);

        // Honest alpha warning appears for JPEG
        expect(
          find.textContaining('JPEG does not support alpha transparency'),
          findsOneWidget,
        );
        // Quality slider appears for JPEG
        expect(find.text('Compression Quality'), findsOneWidget);

        // 4. Switch to WebP
        await tester.tap(find.text('WebP'));
        await settleSheet(tester);

        // Alpha warning disappears for WebP (WebP supports alpha)
        expect(
          find.textContaining('JPEG does not support alpha transparency'),
          findsNothing,
        );
        // Quality slider remains active
        expect(find.text('Compression Quality'), findsOneWidget);

        // 5. GPS privacy toggle
        expect(find.text('Remove GPS & location metadata'), findsOneWidget);

        // 6. Real estimated size is visible
        expect(find.text('Estimated File Size'), findsOneWidget);

        // 7. Save Image to Device action
        final outputsDir = fileStorage.getOutputsDirectory(project.id);
        await tester.runAsync(() async {
          await tester.tap(find.text('Save Image to Device'));
          for (int i = 0; i < 60; i++) {
            await Future.delayed(const Duration(milliseconds: 50));
            if (outputsDir.existsSync() &&
                outputsDir
                    .listSync()
                    .where((f) => f.path.endsWith('.webp'))
                    .isNotEmpty) {
              break;
            }
          }
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();

        expect(
          find.textContaining('Saved successfully to outputs!'),
          findsOneWidget,
        );

        // Verify outputs directory has exported WebP file
        expect(outputsDir.existsSync(), isTrue);
        final webpFiles = outputsDir
            .listSync()
            .where((f) => f.path.endsWith('.webp'))
            .toList();
        expect(webpFiles, isNotEmpty);

        // 8. Export Project Package (.rrproj) action
        await tester.runAsync(() async {
          await tester.tap(find.text('Export Project Package (.rrproj)'));
          for (int i = 0; i < 60; i++) {
            await Future.delayed(const Duration(milliseconds: 50));
            if (outputsDir.existsSync() &&
                outputsDir
                    .listSync()
                    .where((f) => f.path.endsWith('.rrproj'))
                    .isNotEmpty) {
              break;
            }
          }
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();

        expect(
          find.textContaining('Project Package created successfully!'),
          findsOneWidget,
        );

        // Verify .rrproj file was created in outputs directory
        final rrprojFiles = outputsDir
            .listSync()
            .where((f) => f.path.endsWith('.rrproj'))
            .toList();
        expect(rrprojFiles, isNotEmpty);
      },
    );
  });
}
