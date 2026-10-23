import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/core/routing/app_router.dart';
import 'package:reranger/core/theme/app_theme.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/features/editor/presentation/editor_screen.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';
import 'package:reranger/features/import/presentation/import_providers.dart';

void main() {
  group('End-to-End Import Flow Widget Tests (Batch C)', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;
    late File sampleImageFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('import_flow_test_');
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );

      final image = img.Image(width: 320, height: 240);
      img.fill(image, color: img.ColorRgba8(100, 150, 200, 255));
      sampleImageFile = File('${tempDir.path}/sample_photo.png')
        ..writeAsBytesSync(img.encodePng(image));
    });

    tearDown(() {
      database.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'full flow: Home -> Select Image -> Analysis -> Editor Screen',
      (tester) async {
        final controller = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              projectRepositoryProvider.overrideWithValue(repository),
              projectFileStorageProvider.overrideWithValue(fileStorage),
              importControllerProvider.overrideWith((ref) => controller),
            ],
            child: MaterialApp.router(
              theme: AppTheme.darkTheme,
              routerConfig: appRouter,
            ),
          ),
        );
        await tester.pump();

        // 1. Verify Home Screen is visible with Select Image CTA
        expect(find.text('Select Image'), findsOneWidget);

        // 2. Tap Select Image button to open Analysis screen
        await tester.tap(find.text('Select Image'));
        await tester.pump(
          const Duration(milliseconds: 400),
        ); // Finish route push transition

        // 3. Verify Analysis screen is mounted
        expect(find.text('Preparing Canvas'), findsOneWidget);

        // 4. Run import and complete analysis via real async
        await tester.runAsync(() async {
          await controller.importFromPath(sampleImageFile.path);
        });

        // 5. Deliver state update & route to editor
        await tester.pump(
          const Duration(milliseconds: 50),
        ); // Fire post-frame callback
        await tester.pump(
          const Duration(milliseconds: 400),
        ); // Complete route transition

        // 6. Verify Editor Viewport screen is mounted and displays active controls
        expect(find.byType(EditorScreen), findsOneWidget);
        expect(find.byTooltip('Save Image'), findsOneWidget);
      },
    );
  });
}
