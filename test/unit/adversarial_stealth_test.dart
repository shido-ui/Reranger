import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/core/theme/app_theme.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/domain/recipes/adversarial_stealth_node.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/features/detector_lab/detector_lab_models.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/editor/presentation/pro_tools_sheet.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

double computeSsim(Uint8List img1, Uint8List img2, int width, int height) {
  final total = width * height;
  if (total == 0) return 1.0;

  double sum1 = 0.0, sum2 = 0.0;
  for (int i = 0; i < total; i++) {
    final off = i * 4;
    final l1 =
        0.299 * img1[off] + 0.587 * img1[off + 1] + 0.114 * img1[off + 2];
    final l2 =
        0.299 * img2[off] + 0.587 * img2[off + 1] + 0.114 * img2[off + 2];
    sum1 += l1;
    sum2 += l2;
  }
  final mu1 = sum1 / total;
  final mu2 = sum2 / total;

  double var1 = 0.0, var2 = 0.0, covar = 0.0;
  for (int i = 0; i < total; i++) {
    final off = i * 4;
    final l1 =
        0.299 * img1[off] + 0.587 * img1[off + 1] + 0.114 * img1[off + 2];
    final l2 =
        0.299 * img2[off] + 0.587 * img2[off + 1] + 0.114 * img2[off + 2];
    final d1 = l1 - mu1;
    final d2 = l2 - mu2;
    var1 += d1 * d1;
    var2 += d2 * d2;
    covar += d1 * d2;
  }
  var1 /= (total - 1);
  var2 /= (total - 1);
  covar /= (total - 1);

  const c1 = 6.5025; // (0.01 * 255)^2
  const c2 = 58.5225; // (0.03 * 255)^2

  final ssim =
      ((2.0 * mu1 * mu2 + c1) * (2.0 * covar + c2)) /
      ((mu1 * mu1 + mu2 * mu2 + c1) * (var1 + var2 + c2));
  return ssim;
}

void main() {
  group('PROMPT 3: Robust Stealth Engine V2 Suite', () {
    late Uint8List sourceImageBytes;
    late String sourceHash;
    const int width = 64;
    const int height = 64;

    setUp(() {
      final image = img.Image(width: width, height: height, numChannels: 4);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final r = (x * 4) % 256;
          final g = (y * 4) % 256;
          final b = ((x + y) * 2) % 256;
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      sourceImageBytes = Uint8List.fromList(img.encodePng(image));
      sourceHash = sha256.convert(sourceImageBytes).toString();
    });

    test(
      '1. Node parameter validation for ARMORAttackNode and SensorNoiseNode',
      () {
        final validArmor = ARMORAttackNode(
          id: 'armor_1',
          inputNodeId: 'src_0',
          strength: 0.7,
        );
        expect(() => validArmor.validate(), returnsNormally);
        expect(validArmor.strength, equals(0.7));

        final invalidArmor = ARMORAttackNode(
          id: 'armor_bad',
          inputNodeId: 'src_0',
          strength: 1.5,
        );
        expect(() => invalidArmor.validate(), throwsException);

        final validSensor = SensorNoiseNode(
          id: 'sensor_1',
          inputNodeId: 'src_0',
          noiseIntensity: 0.4,
          chromaticAberration: 0.3,
        );
        expect(() => validSensor.validate(), returnsNormally);

        final invalidSensor = SensorNoiseNode(
          id: 'sensor_bad',
          inputNodeId: 'src_0',
          noiseIntensity: 2.0,
        );
        expect(() => invalidSensor.validate(), throwsException);
      },
    );

    test(
      '2. Metadata Annihilation strips 100% of C2PA, EXIF, and XMP chunks',
      () {
        // Create known AI-generated media container with simulated C2PA and EXIF metadata
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        final ihdrChunk = [
          0x00, 0x00, 0x00, 0x0D,
          0x49, 0x48, 0x44, 0x52, // IHDR
          0x00, 0x00, 0x00, 0x10,
          0x00, 0x00, 0x00, 0x10,
          0x08, 0x06, 0x00, 0x00, 0x00,
          0x00, 0x00, 0x00, 0x00, // CRC
        ];
        final c2paChunk = [
          0x00, 0x00, 0x00, 0x10,
          ...C2paParser.c2paMagic, // 'c2pa'
          ...List.filled(16, 0x58),
          0x00, 0x00, 0x00, 0x00, // CRC
        ];
        final exifChunk = [
          0x00, 0x00, 0x00, 0x08,
          0x65, 0x58, 0x49, 0x66, // eXIf
          ...List.filled(8, 0x22),
          0x00, 0x00, 0x00, 0x00, // CRC
        ];
        final iendChunk = [
          0x00, 0x00, 0x00, 0x00,
          0x49, 0x45, 0x4E, 0x44, // IEND
          0xAE, 0x42, 0x60, 0x82,
        ];

        final rawAiImageBytes = Uint8List.fromList([
          ...pngHeader,
          ...ihdrChunk,
          ...c2paChunk,
          ...exifChunk,
          ...iendChunk,
        ]);

        // Verify C2PA is initially detected by C2paParser
        final initialResult = C2paParser.parseBytes(rawAiImageBytes);
        expect(initialResult.isContainerDetected, isTrue);
        expect(initialResult.isMissing, isFalse);

        // Apply Metadata Annihilation
        final annihilatedBytes = MetadataAnnihilator.strip(rawAiImageBytes);

        // Verify C2PA is 100% gone
        final finalResult = C2paParser.parseBytes(annihilatedBytes);
        expect(finalResult.isMissing, isTrue);
        expect(finalResult.isContainerDetected, isFalse);
        expect(
          finalResult.message,
          contains('No supported provenance signal found'),
        );

        // Check raw bytes: zero occurrences of C2PA magic
        final c2paIndex = annihilatedBytes.indexOf(C2paParser.c2paMagic[0]);
        bool foundMagic = false;
        if (c2paIndex != -1) {
          for (int i = 0; i <= annihilatedBytes.length - 4; i++) {
            if (annihilatedBytes[i] == C2paParser.c2paMagic[0] &&
                annihilatedBytes[i + 1] == C2paParser.c2paMagic[1] &&
                annihilatedBytes[i + 2] == C2paParser.c2paMagic[2] &&
                annihilatedBytes[i + 3] == C2paParser.c2paMagic[3]) {
              foundMagic = true;
              break;
            }
          }
        }
        expect(
          foundMagic,
          isFalse,
          reason: 'Zero C2PA bytes must remain in media stream',
        );
      },
    );

    test('3. Universal Adversarial Perturbation (ARMORAttackNode in DCT domain) modifies image while maintaining SSIM > 0.95', () async {
      final executor = RenderGraphExecutor();

      // Render baseline
      final baselineGraph = RenderGraph(
        id: 'graph_base',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: width,
            sourceHeight: height,
          ),
        },
        outputNodeId: 'src_0',
      );
      final baselineResult = await executor.execute(
        graph: baselineGraph,
        sourceImageBytes: sourceImageBytes,
      );
      final baselineHash = sha256.convert(baselineResult.pixelBytes).toString();

      // Render ARMORAttackNode
      final armorGraph = RenderGraph(
        id: 'graph_armor',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: width,
            sourceHeight: height,
          ),
          'armor_0': ARMORAttackNode(
            id: 'armor_0',
            inputNodeId: 'src_0',
            strength: 0.8,
          ),
        },
        outputNodeId: 'armor_0',
      );
      final armorResult = await executor.execute(
        graph: armorGraph,
        sourceImageBytes: sourceImageBytes,
      );
      final armorHash = sha256.convert(armorResult.pixelBytes).toString();

      // Verify hashes are not bitwise identical (proving UAP perturbation was applied)
      expect(armorHash, isNot(equals(baselineHash)));

      // Verify SSIM > 0.95
      final ssim = computeSsim(
        baselineResult.pixelBytes,
        armorResult.pixelBytes,
        width,
        height,
      );
      expect(ssim, greaterThan(0.95));
      expect(ssim, lessThanOrEqualTo(1.0));
    });

    test(
      '4. Realism Fusion (SensorNoiseNode Bayer + CA) maintains SSIM > 0.95',
      () async {
        final executor = RenderGraphExecutor();

        final baselineGraph = RenderGraph(
          id: 'graph_base',
          nodes: {
            'src_0': SourceImageNode(
              id: 'src_0',
              sourceImageHash: sourceHash,
              sourceWidth: width,
              sourceHeight: height,
            ),
          },
          outputNodeId: 'src_0',
        );
        final baselineResult = await executor.execute(
          graph: baselineGraph,
          sourceImageBytes: sourceImageBytes,
        );

        final sensorGraph = RenderGraph(
          id: 'graph_sensor',
          nodes: {
            'src_0': SourceImageNode(
              id: 'src_0',
              sourceImageHash: sourceHash,
              sourceWidth: width,
              sourceHeight: height,
            ),
            'sensor_0': SensorNoiseNode(
              id: 'sensor_0',
              inputNodeId: 'src_0',
              noiseIntensity: 0.6,
              chromaticAberration: 0.5,
            ),
          },
          outputNodeId: 'sensor_0',
        );
        final sensorResult = await executor.execute(
          graph: sensorGraph,
          sourceImageBytes: sourceImageBytes,
        );

        // Verify not bitwise identical
        expect(
          sha256.convert(sensorResult.pixelBytes).toString(),
          isNot(equals(sha256.convert(baselineResult.pixelBytes).toString())),
        );

        // Verify SSIM > 0.95
        final ssim = computeSsim(
          baselineResult.pixelBytes,
          sensorResult.pixelBytes,
          width,
          height,
        );
        expect(ssim, greaterThan(0.95));
      },
    );

    test('5. End-to-End Export Pipeline with Realism slider applies Stealth Engine V2, strips C2PA and achieves SSIM > 0.95', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'reranger_stealth_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final db = ProjectDatabase.openInMemory();
      final fileStorage = ProjectFileStorage(rootDir: tempDir);
      final repository = LocalProjectRepository(
        database: db,
        fileStorage: fileStorage,
      );

      // Embed simulated C2PA into the source image
      final c2paSourceBytes = Uint8List.fromList([
        ...sourceImageBytes,
        ...C2paParser.c2paMagic,
        0x01,
        0x02,
        0x03,
        0x04,
      ]);

      final sourcePath = '${tempDir.path}/ai_source.png';
      File(sourcePath).writeAsBytesSync(c2paSourceBytes);

      final project = ProjectEntity(
        id: 'proj_stealth_test',
        name: 'AI Generated Artwork',
        sourceImagePath: sourcePath,
        sourceImageHash: sha256.convert(c2paSourceBytes).toString(),
        sourceWidth: width,
        sourceHeight: height,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'recipe_proj_stealth_test',
          sourceImageHash: sha256.convert(c2paSourceBytes).toString(),
          sourceImagePath: sourcePath,
        ),
      );
      await repository.saveProject(project);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );
      await controller.loadProject(project.id);

      // 1. Render baseline export without stealth (realism = 0.0)
      controller.setRealism(0.0);
      final baseImage = await controller.renderFullResolutionOutput(scale: 1.0);
      final baseBytes = Uint8List.fromList(img.encodePng(baseImage));

      // 2. Enable Realism slider to 0.75 and export with Stealth Engine V2
      controller.setRealism(0.75);
      final stealthImage = await controller.renderFullResolutionOutput(
        scale: 1.0,
      );
      final stealthBytes = Uint8List.fromList(img.encodePng(stealthImage));

      // 3. Verify C2PA metadata is gone
      final c2paExportResult = C2paParser.parseBytes(stealthBytes);
      expect(c2paExportResult.isMissing, isTrue);
      expect(c2paExportResult.isContainerDetected, isFalse);

      // 4. Verify image is no longer bitwise identical (proving UAP perturbation was applied)
      final baseSha = sha256.convert(baseBytes).toString();
      final stealthSha = sha256.convert(stealthBytes).toString();
      expect(stealthSha, isNot(equals(baseSha)));

      // 5. Verify SSIM > 0.95 (proving it still looks good visually)
      final ssim = computeSsim(
        baseImage.getBytes(),
        stealthImage.getBytes(),
        width,
        height,
      );
      expect(ssim, greaterThan(0.95));

      // 6. Invariant 4: Source image on disk remains strictly immutable
      final diskSourceSha = sha256
          .convert(File(sourcePath).readAsBytesSync())
          .toString();
      expect(diskSourceSha, equals(sha256.convert(c2paSourceBytes).toString()));

      db.dispose();
    });

    testWidgets(
      '6. UI Wiring: Pro Tools Output tab renders Realism slider and updates controller',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final tempDir = Directory.systemTemp.createTempSync(
          'reranger_stealth_ui_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final db = ProjectDatabase.openInMemory();
        final fileStorage = ProjectFileStorage(rootDir: tempDir);
        final repository = LocalProjectRepository(
          database: db,
          fileStorage: fileStorage,
        );

        final controller = EditorController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: ProToolsSheet(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate to Output tab
        await tester.tap(find.text('Output'));
        await tester.pumpAndSettle();

        // Verify Realism section is rendered
        expect(find.text('Realism'), findsOneWidget);
        expect(find.text('0%'), findsOneWidget);
        expect(
          find.byKey(const Key('pro_tools_realism_slider')),
          findsOneWidget,
        );

        // Verify slider state and trigger update
        final sliderFinder = find.byKey(const Key('pro_tools_realism_slider'));
        final sliderWidget = tester.widget<Slider>(sliderFinder);
        expect(sliderWidget.value, equals(0.0));

        sliderWidget.onChanged!(0.85);
        await tester.pump();

        // Verify controller realism updated and UI rendered 85%
        expect(controller.realism, equals(0.85));
        expect(find.text('85%'), findsOneWidget);

        controller.dispose();
        db.dispose();
      },
    );

    test('7. Preset isolation: Presets do not contain ARMORAttackNode by default', () {
      for (final preset in PresetCatalog.all) {
        final graph = preset.buildGraph(
          sourceHash,
          width,
          height,
          preset.resolveParameters(null),
        );
        for (final node in graph.nodes.values) {
          expect(
            node,
            isNot(isA<ARMORAttackNode>()),
            reason:
                'Preset ${preset.id} must not contain ARMORAttackNode by default',
          );
          expect(
            node,
            isNot(isA<SensorNoiseNode>()),
            reason:
                'Preset ${preset.id} must not contain SensorNoiseNode by default',
          );
        }
      }
    });
  });
}
