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
  group('Prompt 23: Progressive Disclosure & Pro Controls Widget Tests', () {
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
      tempDir = Directory.systemTemp.createTempSync('prog_disclosure_test_');
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
        id: 'proj_prog_test',
        name: 'Progressive Disclosure Project',
        sourceImagePath: sampleImageFile.path,
        sourceImageHash: realSourceHash,
        sourceWidth: 32,
        sourceHeight: 32,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'recipe_prog_test',
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
      'Level 1 Simple Mode: Single dominant CTA, style carousel, strength slider, compare, no jargon',
      (tester) async {
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

        // 1. Title and Save CTA
        expect(find.text('Progressive Disclosure Project'), findsOneWidget);
        expect(find.byTooltip('Save Image'), findsOneWidget);

        // 2. Simple mode shows only 1 primary slider
        expect(find.byType(Slider), findsOneWidget);
        expect(find.text('Pencil Hardness'), findsOneWidget);

        // 3. Compare button is available
        expect(find.text('Compare'), findsOneWidget);

        // 4. Fine-Tune opt-in button is present
        expect(find.text('Fine-Tune'), findsOneWidget);

        // 5. Zero technical engine jargon displayed
        expect(find.textContaining('Sobel'), findsNothing);
        expect(find.textContaining('EdgeInvertSubtract'), findsNothing);
        expect(find.textContaining('contrastGamma'), findsNothing);
        expect(find.textContaining('tensor'), findsNothing);
      },
    );

    testWidgets(
      'Level 2 Fine-Tune Sheet: Recipe parameters, reset-per-control, reset-all, plain explanations',
      (tester) async {
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

        // Open Fine-Tune sheet
        await tester.tap(find.text('Fine-Tune'));
        await settleSheet(tester);

        // Verify sheet content
        expect(find.text('Fine-Tune Adjustments'), findsOneWidget);
        expect(find.text('Customizing Graphite Pencil'), findsOneWidget);
        expect(find.text('Reset All'), findsOneWidget);

        // Verify parameters for Graphite Pencil
        expect(find.text('Pencil Hardness'), findsWidgets);
        expect(find.text('Paper Tooth'), findsOneWidget);
        expect(
          find.text('Controls stroke intensity and edge line sharpness.'),
          findsOneWidget,
        );

        // Adjust parameter and test reset-per-control
        await tester.runAsync(() async {
          await controller.updateParameter('grainIntensity', 0.30);
        });
        await settleSheet(tester);

        expect(controller.parameterValues['grainIntensity'], equals(0.30));

        // Tap reset for Paper Tooth
        final resetToothFinder = find.byTooltip('Reset Paper Tooth');
        expect(resetToothFinder, findsOneWidget);
        await tester.tap(resetToothFinder);
        await settleSheet(tester);

        // Verify parameter returned to default (0.15)
        expect(controller.parameterValues['grainIntensity'], equals(0.15));

        // Test Reset All
        await tester.runAsync(() async {
          await controller.updateParameter('pencilHardness', 0.90);
          await controller.updateParameter('grainIntensity', 0.25);
        });
        await settleSheet(tester);

        await tester.tap(find.text('Reset All'));
        await settleSheet(tester);

        expect(controller.parameterValues['pencilHardness'], equals(0.65));
        expect(controller.parameterValues['grainIntensity'], equals(0.15));

        // Close sheet
        await tester.tap(find.byTooltip('Close fine-tune'));
        await settleSheet(tester);

        expect(find.text('Fine-Tune Adjustments'), findsNothing);
      },
    );

    testWidgets(
      'Level 3 Pro Tools Sheet: Layers, History, Curtain, Variants, and Output settings',
      (tester) async {
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

        // Open Pro Tools Studio
        await tester.tap(find.byTooltip('Open Pro Tools Studio'));
        await settleSheet(tester);

        expect(find.text('Pro Tools Studio'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        // 1. Tab 1: Layers
        expect(find.text('Layers'), findsOneWidget);
        expect(find.text('Original Photo'), findsOneWidget);
        expect(find.text('LOCKED BASE'), findsOneWidget);

        // Add an adjustment layer
        await tester.tap(find.text('Add Tint Layer'));
        await settleSheet(tester);
        expect(find.text('Color Tint 1'), findsOneWidget);

        // 2. Tab 2: History
        await tester.tap(find.text('History'));
        await settleSheet(tester);
        expect(find.text('History & Timeline'), findsOneWidget);
        expect(find.textContaining('Undo (1)'), findsOneWidget);

        // 3. Tab 3: Curtain & Variants
        await tester.tap(find.text('Curtain & Variants'));
        await settleSheet(tester);
        expect(find.text('Split-Screen Comparison (SCR-06)'), findsOneWidget);
        expect(find.text('Variant Board (1)'), findsOneWidget);

        // Branch a variant
        await tester.tap(find.text('Branch Variant'));
        await settleSheet(tester);
        expect(find.text('Variant Board (2)'), findsOneWidget);
        expect(find.text('Variant 2'), findsOneWidget);

        // 4. Tab 4: Output
        await tester.tap(find.text('Output'));
        await settleSheet(tester);
        expect(find.text('Render Resolution'), findsOneWidget);
        expect(find.text('50% (Fast Preview)'), findsOneWidget);
        expect(find.text('100% (Full Master)'), findsOneWidget);

        // Tap Done to return to simple viewport
        await tester.tap(find.text('Done'));
        await settleSheet(tester);
        expect(find.text('Pro Tools Studio'), findsNothing);
      },
    );

    testWidgets(
      'Persona 1 Walkthrough: First-time casual user selects preset, adjusts strength, saves in 3 taps',
      (tester) async {
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

        // Tap Fine Ink preset in carousel
        await tester.tap(find.text(BatchAPresets.fineInk.displayName));
        await tester.pump();

        expect(controller.activePreset?.id, equals(BatchAPresets.fineInk.id));

        // Adjust primary slider
        final slider = find.byType(Slider);
        expect(slider, findsOneWidget);

        // Tap Save Image
        await tester.tap(find.byTooltip('Save Image'));
        await tester.pump();

        // Clean journey completed without opening advanced sheets
        expect(find.text('Fine-Tune Adjustments'), findsNothing);
        expect(find.text('Pro Tools Studio'), findsNothing);
      },
    );

    testWidgets(
      'Persona 2 Walkthrough: Digital illustrator fine-tunes recipe parameters and resets per-control',
      (tester) async {
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

        // Open Fine-Tune sheet
        await tester.tap(find.text('Fine-Tune'));
        await settleSheet(tester);

        // Illustrator tweaks Pencil Hardness
        await tester.runAsync(() async {
          await controller.updateParameter('pencilHardness', 0.85);
        });
        await settleSheet(tester);
        expect(controller.parameterValues['pencilHardness'], equals(0.85));

        // Resets Pencil Hardness
        await tester.tap(find.byTooltip('Reset Pencil Hardness'));
        await settleSheet(tester);
        expect(controller.parameterValues['pencilHardness'], equals(0.65));

        // Navigates directly to Pro Tools via footer link
        await tester.tap(
          find.text('Need layers, masks & history? Open Pro Tools'),
        );
        await settleSheet(tester);

        expect(find.text('Pro Tools Studio'), findsOneWidget);
      },
    );

    testWidgets(
      'Persona 3 Walkthrough: AI-art creator enables split comparison curtain and branches variant',
      (tester) async {
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

        // Switch to Curtain & Variants tab
        await tester.tap(find.text('Curtain & Variants'));
        await settleSheet(tester);

        // Enable split curtain
        await tester.tap(find.text('Show Split Curtain'));
        await settleSheet(tester);
        expect(controller.isSplitComparisonActive, isTrue);

        // Branch a new variant
        await tester.tap(find.text('Branch Variant'));
        await settleSheet(tester);

        final variants =
            controller.layerHistoryController?.state.variantBoard.variants;
        expect(variants?.length, equals(2));

        // Close Pro Tools
        await tester.tap(find.text('Done'));
        await settleSheet(tester);

        // Viewport now displays split curtain view
        expect(
          find.byKey(const ValueKey('split_curtain_preview')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('split_curtain_source')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Responsive Viewport Overflow Protection: 320dp, 360dp, 412dp, 768dp at 1.0 and 1.3 fontScale',
      (tester) async {
        final controller = EditorController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        await tester.runAsync(() async {
          await controller.loadProject(project.id);
        });
        controller.previewPngBytes = sampleImageFile.readAsBytesSync();

        final viewports = [
          const Size(320, 640),
          const Size(360, 800),
          const Size(412, 915),
          const Size(768, 1024),
        ];

        for (final vp in viewports) {
          for (final scale in [1.0, 1.3]) {
            tester.view.physicalSize = Size(vp.width * 2.0, vp.height * 2.0);
            tester.view.devicePixelRatio = 2.0;

            await tester.pumpWidget(
              MediaQuery(
                data: MediaQueryData(
                  size: vp,
                  textScaler: TextScaler.linear(scale),
                ),
                child: MaterialApp(
                  theme: AppTheme.darkTheme,
                  home: EditorScreen(
                    projectId: project.id,
                    controller: controller,
                  ),
                ),
              ),
            );
            await tester.pump();

            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow at ${vp.width}dp with fontScale $scale',
            );
          }
        }
      },
    );
  });
}
