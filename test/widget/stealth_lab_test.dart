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
  group('Batch C: Stealth Studio & Diagnostics Lab Widget Tests', () {
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
      tempDir = Directory.systemTemp.createTempSync('stealth_lab_test_');
      database = ProjectDatabase.openInMemory();
      fileStorage = ProjectFileStorage(rootDir: tempDir);
      repository = LocalProjectRepository(
        database: database,
        fileStorage: fileStorage,
      );

      final image = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(100, 140, 180, 255));
      final imageBytes = img.encodePng(image);
      sampleImageFile = File('${tempDir.path}/test_source.png')
        ..writeAsBytesSync(imageBytes);
      final realSourceHash = sha256.convert(imageBytes).toString();

      project = ProjectEntity(
        id: 'proj_stealth_test',
        name: 'Stealth Lab Project',
        sourceImagePath: sampleImageFile.path,
        sourceImageHash: realSourceHash,
        sourceWidth: 32,
        sourceHeight: 32,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'recipe_stealth_test',
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

    testWidgets('Stealth Studio tab: warning label, controls, and preview', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
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

      // Open Pro Tools
      await tester.tap(find.byTooltip('Open Pro Tools Studio'));
      await settleSheet(tester);

      // Scroll TabBar to reveal Stealth Studio tab
      await tester.drag(find.byType(TabBar), const Offset(-400, 0));
      await settleSheet(tester);

      // Navigate to Stealth Studio tab
      await tester.tap(find.text('Stealth Studio'));
      await settleSheet(tester);

      // Verify mandatory warning label
      expect(
        find.textContaining(
          'This applies adversarial noise optimized to disrupt AI detection algorithms',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('It does not guarantee human authorship.'),
        findsOneWidget,
      );

      // Verify controls
      expect(find.text('Enable Adversarial Stealth'), findsOneWidget);
      expect(find.text('Adversarial Strength'), findsOneWidget);
      expect(find.text('Apply Frequency Perturbation'), findsOneWidget);
      expect(find.text('Preview Noise Impact'), findsOneWidget);

      // Toggle enable stealth
      await tester.tap(find.text('Enable Adversarial Stealth'));
      await settleSheet(tester);
      expect(controller.isStealthEnabled, isTrue);

      // Verify graph builds with AdversarialStealthNode when enabled
      final stealthGraph = controller.buildActiveGraph();
      expect(stealthGraph.nodes.containsKey('stealth_output_node'), isTrue);
      expect(stealthGraph.outputNodeId, equals('stealth_output_node'));

      // Toggle preview
      await tester.tap(find.text('Preview Noise Impact'));
      await settleSheet(tester);
      expect(controller.isPreviewingStealth, isTrue);
      expect(find.text('Stop Preview'), findsOneWidget);
    });

    testWidgets(
      'Diagnostics Lab tab: folder & adapter selectors, benchmark run, and dashboard',
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

        // Open Pro Tools
        await tester.tap(find.byTooltip('Open Pro Tools Studio'));
        await settleSheet(tester);

        // Scroll TabBar to reveal Diagnostics Lab tab
        await tester.drag(find.byType(TabBar), const Offset(-500, 0));
        await settleSheet(tester);

        // Navigate to Diagnostics Lab tab
        await tester.tap(find.text('Diagnostics Lab'));
        await settleSheet(tester);

        // Verify configuration UI
        expect(find.text('Test Image Folder'), findsOneWidget);
        expect(find.text('Detector Adapter'), findsOneWidget);
        expect(find.text('Run Benchmark'), findsOneWidget);

        // Run benchmark
        await tester.tap(find.text('Run Benchmark'));
        await settleSheet(tester);

        // Verify results dashboard metrics
        expect(find.text('Evaluation Results Dashboard'), findsOneWidget);
        expect(find.text('Total Images'), findsOneWidget);
        expect(find.text('10'), findsWidgets);
        expect(find.text('Flagged as AI'), findsOneWidget);
        expect(find.text('Flagged as Real'), findsOneWidget);
        expect(find.text('False Positive Rate (FPR)'), findsOneWidget);
        expect(find.text('20.0%'), findsWidgets); // Both FPR and FNR are 20.0%
        expect(find.text('False Negative Rate (FNR)'), findsOneWidget);
        expect(find.text('AUROC Score'), findsOneWidget);
        expect(find.text('0.940'), findsOneWidget);

        // Verify C2PA provenance section
        expect(find.text('C2PA Provenance Signals'), findsOneWidget);
        expect(find.text('Valid C2PA Signatures'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Missing Provenance'), findsOneWidget);
        expect(find.text('8'), findsOneWidget);
        expect(find.text('Corrupt / Invalid Boxes'), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      },
    );
  });
}
