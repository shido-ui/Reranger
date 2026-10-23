import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/core/theme/app_theme.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/import/data/isolate_image_decoder.dart';
import 'package:reranger/features/import/presentation/analysis_screen.dart';
import 'package:reranger/features/import/presentation/import_controller.dart';

void main() {
  group('AnalysisScreen Widget Tests (Batch C)', () {
    late Directory tempDir;
    late ProjectDatabase database;
    late ProjectFileStorage fileStorage;
    late LocalProjectRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('analysis_widget_test_');
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

    testWidgets(
      'renders honest indeterminate progress and stage names without fake numbers',
      (tester) async {
        final inProgressController = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
          initialState: const ImportInProgress(
            stage: ImportStage.extractingPalette,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: AnalysisScreen(controller: inProgressController),
          ),
        );
        await tester.pump();

        // Verify CircularProgressIndicator is present
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Verify honest stage name is rendered
        expect(find.text(ImportStage.extractingPalette.title), findsOneWidget);
        expect(
          find.text(ImportStage.extractingPalette.description),
          findsOneWidget,
        );

        // Verify no percentage numbers like '0%' or '100%' are rendered on screen (Invariant 7)
        expect(find.textContaining(RegExp(r'\d+%')), findsNothing);

        // Verify Cancel button and offline badge are available
        expect(find.text('Cancel Analysis'), findsOneWidget);
        expect(find.text('Offline • Zero Cloud Telemetry'), findsOneWidget);
      },
    );

    testWidgets('cancel button triggers controller cancellation', (
      tester,
    ) async {
      final controller = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
        initialState: const ImportInProgress(
          stage: ImportStage.stagingSandboxCopy,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AnalysisScreen(controller: controller),
        ),
      );
      await tester.pump();

      final cancelButton = find.text('Cancel Analysis');
      expect(cancelButton, findsOneWidget);
      await tester.tap(cancelButton);
      await tester.pump();

      // Controller state transitioned to cancelled
      expect(controller.state, isA<ImportCancelled>());
    });

    testWidgets(
      'displays error state, failure message, retry CTA, and back navigation',
      (tester) async {
        final errorController = ImportController(
          projectRepository: repository,
          fileStorage: fileStorage,
          initialState: const ImportFailureState(
            errorMessage: 'Corrupt or unsupported image format.',
            canRetry: true,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: AnalysisScreen(controller: errorController),
          ),
        );
        await tester.pump();

        expect(find.text('Import Failed'), findsOneWidget);
        expect(
          find.text('Corrupt or unsupported image format.'),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.text('Back to Gallery'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );

    testWidgets('displays success state when import finishes', (tester) async {
      final dummyProject = ProjectEntity(
        id: 'proj_test_123',
        name: 'test_sunset',
        sourceImagePath: '/dummy/source.png',
        sourceImageHash: 'abcdef123456',
        sourceWidth: 800,
        sourceHeight: 600,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_123',
          sourceImageHash: 'abcdef123456',
          sourceImagePath: '/dummy/source.png',
        ),
      );

      final dummySummary = DecodedImageSummary(
        width: 800,
        height: 600,
        aspectRatio: 1.33,
        hasAlpha: false,
        originalExifOrientation: 1,
        dominantPalette: const [],
        thumbnailBytes: Uint8List(1),
        thumbnailWidth: 100,
        thumbnailHeight: 75,
      );

      final successController = ImportController(
        projectRepository: repository,
        fileStorage: fileStorage,
        initialState: ImportSuccess(
          project: dummyProject,
          imageSummary: dummySummary,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AnalysisScreen(controller: successController),
        ),
      );
      await tester.pump();

      expect(find.text('Image Ready'), findsOneWidget);
      expect(find.text('Opening project test_sunset...'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });
}
