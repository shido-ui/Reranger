import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/domain/recipes/adversarial_stealth_node.dart';
import 'package:reranger/features/detector_lab/detector_lab_models.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/humanize/presentation/humanize_controller.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';
import 'package:reranger/humanize/humanize_adapter.dart';
import 'package:reranger/humanize/local_humanize_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const gb = 1024 * 1024 * 1024;

  Uint8List createDummyRgba(int w, int h) {
    return Uint8List(w * h * 4);
  }

  Uint8List createDummyPng(int w, int h) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(100, 150, 200, 255));
    return Uint8List.fromList(img.encodePng(image));
  }

  group('PROMPT 5: Section A - Truthful Humanize Release Gate', () {
    test('LocalHumanizeAdapter truthfully reports unsupported and notInstalled when weights absent', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      expect(
        adapter.lifecycleState,
        equals(HumanizeLifecycleState.notInstalled),
      );
      expect(await adapter.isModelAvailable(), isFalse);

      final caps = await adapter.getCapabilities();
      expect(caps.isSupported, isFalse);
      expect(caps.modelName, contains('None Installed'));
      expect(
        caps.unavailabilityReason,
        contains('model weights are not installed'),
      );
      expect(caps.supportedResolutions, isEmpty);
      expect(caps.supportedConditionings, isEmpty);
    });

    test('LocalHumanizeAdapter throws ModelNotLoadedException on runInference when not loaded', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final dummyBytes = createDummyRgba(64, 64);
      final input = HumanizeInput(
        sourceRgba: dummyBytes,
        width: 64,
        height: 64,
        strength: 0.35,
        seed: 42,
      );

      expect(
        () => adapter.runInference(input),
        throwsA(isA<ModelNotLoadedException>()),
      );
    });

    test('LocalHumanizeAdapter initializeModel throws ModelNotFoundException when weights file is absent', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      expect(
        () => adapter.initializeModel(
          modelPath: '/nonexistent/path/weights.gguf',
        ),
        throwsA(isA<ModelNotFoundException>()),
      );
    });

    test('HumanizeController truthfully transitions to modelNotInstalled with honest gating notice', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final controller = HumanizeController(adapter: adapter);
      final dummyPng = createDummyPng(32, 32);

      await controller.initialize(
        sourceImageBytes: dummyPng,
        width: 32,
        height: 32,
      );

      expect(controller.isGated, isTrue);
      expect(controller.status, equals(HumanizeUiStatus.modelNotInstalled));
      expect(
        controller.unavailabilityReason,
        contains('model weights are not installed'),
      );
      expect(controller.isRunning, isFalse);
    });

    test('Conventional presets remain fully operational and independent of Humanize gating', () {
      expect(PresetCatalog.all.length, equals(48));
      for (final preset in PresetCatalog.all) {
        expect(preset.id, isNotEmpty);
        final graph = preset.buildGraph(
          'dummy_hash',
          512,
          512,
          preset.resolveParameters(null),
        );
        expect(graph.nodes, isNotEmpty);
      }
    });
  });

  group('PROMPT 5: Section B - Removal of Detector-Evasion Claims and Code', () {
    test('Preset catalog contains zero AdversarialStealthNode occurrences', () {
      for (final preset in PresetCatalog.all) {
        final graph = preset.buildGraph(
          'dummy_hash',
          512,
          512,
          preset.resolveParameters(null),
        );
        final hasStealth = graph.nodes.values.any(
          (node) => node is AdversarialStealthNode,
        );
        expect(
          hasStealth,
          isFalse,
          reason:
              'Preset ${preset.id} must not contain adversarial stealth nodes',
        );
      }
    });

    test('EditorController buildActiveGraph contains zero stealth nodes or evasion injections', () async {
      final tempDir = Directory.systemTemp.createTempSync('reranger_p5_test_');
      final db = ProjectDatabase.openInMemory();
      final storage = ProjectFileStorage(rootDir: tempDir);
      final repo = LocalProjectRepository(database: db, fileStorage: storage);

      final sourceBytes = createDummyPng(64, 64);
      final sourceFile = File('${tempDir.path}/test_source.png');
      sourceFile.writeAsBytesSync(sourceBytes);
      final sourceHash = sha256.convert(sourceBytes).toString();

      final project = ProjectEntity(
        id: 'proj_stealth_test',
        name: 'Stealth Test',
        sourceImagePath: sourceFile.path,
        sourceImageHash: sourceHash,
        sourceWidth: 64,
        sourceHeight: 64,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: RenderRecipe.initial(
          recipeId: 'rec_p5',
          sourceImageHash: sourceHash,
          sourceImagePath: sourceFile.path,
          activePresetId: PresetCatalog.defaultPresetId,
        ),
      );
      await repo.saveProject(project);

      final controller = EditorController(
        projectRepository: repo,
        fileStorage: storage,
      );
      await controller.loadProject(project.id);

      final initialGraph = controller.buildActiveGraph();
      final hasStealth = initialGraph.nodes.values.any(
        (node) => node is AdversarialStealthNode,
      );
      expect(
        hasStealth,
        isFalse,
        reason: 'buildActiveGraph must not inject adversarial stealth nodes',
      );

      controller.dispose();
      db.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('PROMPT 5: Section C - Truthful Provenance & Test-Only Detector Lab', () {
    test(
      'C2paParser never certifies signature validity from raw metadata markers',
      () {
        final validMarkerBytes = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE1,
          ...C2paParser.c2paMagic,
          0x00,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
        ]);

        final result = C2paParser.parseBytes(validMarkerBytes);
        expect(
          result.status,
          equals(C2paStatus.manifestContainerDetectedUnverified),
        );
        expect(result.isValid, isFalse);
        expect(result.isSignatureVerified, isFalse);
        expect(result.isContainerDetected, isTrue);
        expect(result.manifestIssuer, isNull);
        expect(result.message, contains('not verified'));
      },
    );

    test('MockDetectorAdapter is clearly labeled as [TEST ONLY]', () {
      final mock = MockDetectorAdapter();
      expect(mock.name, contains('[TEST ONLY]'));
    });
  });
}
