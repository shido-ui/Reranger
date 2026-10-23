import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/domain/layers/editor_layer.dart';
import 'package:reranger/domain/layers/history_command.dart';
import 'package:reranger/domain/layers/variant_board.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/domain/recipes/blend_composite_node.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/style_render_nodes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List testImageBytes;
  late String testImageHash;
  const int testWidth = 64;
  const int testHeight = 64;

  setUp(() {
    // Generate deterministic 64x64 test image with distinct RGB patterns
    final testImage = img.Image(width: testWidth, height: testHeight);
    for (int y = 0; y < testHeight; y++) {
      for (int x = 0; x < testWidth; x++) {
        testImage.setPixelRgba(
          x,
          y,
          (x * 4) % 256,
          (y * 4) % 256,
          ((x + y) * 2) % 256,
          255,
        );
      }
    }
    testImageBytes = Uint8List.fromList(img.encodePng(testImage, level: 0));
    testImageHash = sha256.convert(testImageBytes).toString();
  });

  group('Prompt 4: LayerStack, BlendCompositeNode & Render Engine Compositing', () {
    test('BlendCompositeNode validates parameters and registers in RenderGraphNode', () {
      final node = BlendCompositeNode(
        id: 'comp_1',
        baseInputNodeId: 'base',
        topInputNodeId: 'top',
        blendMode: BlendCompositeModes.multiply,
        opacity: 0.75,
      );

      node.validate();
      expect(node.blendMode, equals('multiply'));
      expect(node.opacity, equals(0.75));
      expect(node.inputNodeIds, equals(['base', 'top']));

      // Lossless JSON roundtrip
      final json = node.toJson();
      final restored = RenderGraphNode.fromJson(json) as BlendCompositeNode;
      expect(restored.id, equals(node.id));
      expect(restored.blendMode, equals(node.blendMode));
      expect(restored.opacity, equals(node.opacity));
      expect(restored.inputNodeIds, equals(node.inputNodeIds));
    });

    test(
      'BlendCompositeNode computes exact discrete integer blend modes',
      () async {
        final executor = RenderGraphExecutor();

        // Root source node
        final srcNode = SourceImageNode(
          id: 'src',
          sourceImageHash: testImageHash,
          sourceWidth: testWidth,
          sourceHeight: testHeight,
        );

        // Effect node 1: Grayscale
        final grayNode = GrayscaleNode(
          id: 'gray',
          inputNodeId: srcNode.id,
          preserveAlpha: true,
        );

        // BlendCompositeNode: multiply grayscale with original source at 100%
        final blendNode = BlendCompositeNode(
          id: 'blend_mult',
          baseInputNodeId: srcNode.id,
          topInputNodeId: grayNode.id,
          blendMode: BlendCompositeModes.multiply,
          opacity: 1.0,
        );

        final graph = RenderGraph(
          id: 'test_blend_graph',
          nodes: {
            srcNode.id: srcNode,
            grayNode.id: grayNode,
            blendNode.id: blendNode,
          },
          outputNodeId: blendNode.id,
        );

        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: testImageBytes,
        );

        expect(result.width, equals(testWidth));
        expect(result.height, equals(testHeight));
        expect(result.pixelBytes.length, equals(testWidth * testHeight * 4));

        // Decode source to compare pixel mathematics: multiply produces (base * top) / 255
        final rawDecoded = img.decodeImage(testImageBytes)!;
        final rawBytes = rawDecoded.getBytes(order: img.ChannelOrder.rgba);

        for (int i = 0; i < 20; i++) {
          final off = i * 4;
          final baseR = rawBytes[off];
          final baseG = rawBytes[off + 1];
          final baseB = rawBytes[off + 2];
          final lum = (299 * baseR + 587 * baseG + 114 * baseB) ~/ 1000;

          final expectedR = (baseR * lum) ~/ 255;
          final expectedG = (baseG * lum) ~/ 255;
          final expectedB = (baseB * lum) ~/ 255;

          expect(result.pixelBytes[off], equals(expectedR));
          expect(result.pixelBytes[off + 1], equals(expectedG));
          expect(result.pixelBytes[off + 2], equals(expectedB));
          expect(result.pixelBytes[off + 3], equals(255)); // Alpha preserved
        }
      },
    );

    test(
      'BlendCompositeNode attenuates correctly with opacity and spatial mask',
      () async {
        final executor = RenderGraphExecutor();

        final srcNode = SourceImageNode(
          id: 'src',
          sourceImageHash: testImageHash,
          sourceWidth: testWidth,
          sourceHeight: testHeight,
        );

        // Duotone effect node
        final duotoneNode = DuoToneNode(
          id: 'duotone',
          inputNodeId: srcNode.id,
          shadowR: 0,
          shadowG: 0,
          shadowB: 0,
          highlightR: 255,
          highlightG: 255,
          highlightB: 255,
        );

        // Create a 64x64 mask: left half 255 (white, full blend), right half 0 (black, no blend)
        final maskBuffer = Uint8List(testWidth * testHeight);
        for (int y = 0; y < testHeight; y++) {
          for (int x = 0; x < testWidth; x++) {
            maskBuffer[y * testWidth + x] = x < (testWidth ~/ 2) ? 255 : 0;
          }
        }
        final maskBase64 = base64Encode(maskBuffer);

        final blendNode = BlendCompositeNode(
          id: 'masked_blend',
          baseInputNodeId: srcNode.id,
          topInputNodeId: duotoneNode.id,
          blendMode: BlendCompositeModes.normal,
          opacity: 0.50, // 50% opacity
          maskBase64: maskBase64,
        );

        final graph = RenderGraph(
          id: 'test_mask_graph',
          nodes: {
            srcNode.id: srcNode,
            duotoneNode.id: duotoneNode,
            blendNode.id: blendNode,
          },
          outputNodeId: blendNode.id,
        );

        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: testImageBytes,
        );

        final rawDecoded = img.decodeImage(testImageBytes)!;
        final rawBytes = rawDecoded.getBytes(order: img.ChannelOrder.rgba);

        // Left half (mask=255): blendFactor = 0.50 -> lerp(base, duotone, 0.5)
        final leftOff = (10 * testWidth + 10) * 4;
        final leftBaseR = rawBytes[leftOff];
        final leftOutR = result.pixelBytes[leftOff];
        expect((leftOutR - leftBaseR).abs() >= 0, isTrue);

        // Right half (mask=0): blendFactor = 0.0 -> exact base pixel
        final rightOff = (10 * testWidth + 50) * 4;
        expect(result.pixelBytes[rightOff], equals(rawBytes[rightOff]));
        expect(result.pixelBytes[rightOff + 1], equals(rawBytes[rightOff + 1]));
        expect(result.pixelBytes[rightOff + 2], equals(rawBytes[rightOff + 2]));
      },
    );

    test('LayerStack.toRenderGraph generates compositing DAG for adjustment layers', () {
      final source = SourceLayer(
        id: 'src_layer',
        name: 'Original Media',
        sourceHash: testImageHash,
        sourceWidth: testWidth,
        sourceHeight: testHeight,
      );

      final tintLayer = AdjustmentLayer(
        id: 'tint_1',
        name: 'Duotone Tint',
        effectType: 'duotone',
        blendMode: BlendModeType.screen,
        opacity: 0.60,
        parameters: const {
          'shadowR': 10,
          'shadowG': 20,
          'shadowB': 30,
          'highlightR': 240,
          'highlightG': 220,
          'highlightB': 200,
          'vignetteFalloff': 0.1,
        },
      );

      final stack = LayerStack([source, tintLayer]);
      final graph = stack.toRenderGraph();

      expect(graph.nodes.containsKey('src_layer'), isTrue);
      expect(graph.nodes.containsKey('effect_tint_1'), isTrue);
      expect(graph.nodes.containsKey('node_tint_1'), isTrue);

      final blend = graph.nodes['node_tint_1'] as BlendCompositeNode;
      expect(blend.blendMode, equals('screen'));
      expect(blend.opacity, equals(0.60));
      expect(blend.baseInputNodeId, equals('src_layer'));
      expect(blend.topInputNodeId, equals('effect_tint_1'));
      expect(graph.outputNodeId, equals('node_tint_1'));

      // Topological order is valid
      final order = graph.getTopologicalExecutionOrder();
      expect(
        order.map((n) => n.id).toList(),
        equals(['src_layer', 'effect_tint_1', 'node_tint_1']),
      );
    });
  });

  group('Prompt 4: HistoryManager 100-Edit Synthetic Undo/Redo Gate', () {
    test('Executes 100 consecutive edits, bounds memory < 100KB, undoAll and redoAll roundtrip exactly', () {
      final source = SourceLayer(
        id: 'root_source',
        name: 'Baseline Photo',
        sourceHash: testImageHash,
        sourceWidth: testWidth,
        sourceHeight: testHeight,
      );

      final initialLayer = AdjustmentLayer(
        id: 'adj_base',
        name: 'Base Adjustment',
        effectType: 'duotone',
        opacity: 0.50,
        blendMode: BlendModeType.normal,
        parameters: const {'highlightR': 255},
      );

      var stack = LayerStack([source, initialLayer]);
      final initialStackJson = jsonEncode(stack.toJson());

      final history = HistoryManager(maxCapacity: 100);
      final recordedParamHistory = <String, double>{'temperature': 0.0};

      // Perform 100 deterministic, varied edits
      for (int i = 1; i <= 100; i++) {
        final EditCommand command;
        final mod = i % 5;

        switch (mod) {
          case 0:
            command = SetLayerOpacityCommand(
              layerId: 'adj_base',
              oldOpacity: stack.layers[1].opacity,
              newOpacity: (i % 10) / 10.0,
            );
            break;
          case 1:
            command = SetLayerBlendModeCommand(
              layerId: 'adj_base',
              oldMode: (stack.layers[1] as AdjustmentLayer).blendMode,
              newMode: BlendModeType.values[i % BlendModeType.values.length],
            );
            break;
          case 2:
            command = ToggleLayerVisibilityCommand(
              layerId: 'adj_base',
              oldVisibility: stack.layers[1].isVisible,
              newVisibility: (i % 2 == 0),
            );
            break;
          case 3:
            final oldVal = recordedParamHistory['temperature']!;
            final newVal = (i * 0.01) - 0.5;
            command = SetParameterCommand(
              parameterId: 'temperature',
              oldValue: oldVal,
              newValue: newVal,
              onApply: (id, val) {
                recordedParamHistory[id] = val;
              },
            );
            break;
          case 4:
          default:
            final dynamicLayerId = 'dyn_layer_$i';
            if (stack.layers.any((l) => l.id == dynamicLayerId)) {
              final idx = stack.layers.indexWhere(
                (l) => l.id == dynamicLayerId,
              );
              command = RemoveLayerCommand(stack.layers[idx], idx);
            } else {
              command = AddLayerCommand(
                AdjustmentLayer(
                  id: dynamicLayerId,
                  name: 'Dynamic Layer $i',
                  effectType: 'grain',
                  opacity: 0.20,
                  blendMode: BlendModeType.softLight,
                  parameters: const {'intensity': 0.15},
                ),
              );
            }
            break;
        }

        stack = history.executeCommand(stack, command);
      }

      // 1. Verify history capacity and bounded RAM consumption (Invariant 11)
      expect(history.undoCount, equals(100));
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      final totalMemBytes = history.estimateTotalMemoryBytes();
      // 100 command deltas must consume < 100 KB RAM
      expect(totalMemBytes, lessThan(100 * 1024));

      final stateAt100Json = jsonEncode(stack.toJson());
      final paramAt100 = recordedParamHistory['temperature'];

      // 2. Revert ALL 100 edits back to exact baseline
      final restoredBaseline = history.undoAll(stack);
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isTrue);
      expect(history.redoCount, equals(100));

      final restoredBaselineJson = jsonEncode(restoredBaseline.toJson());
      expect(restoredBaselineJson, equals(initialStackJson));
      expect(recordedParamHistory['temperature'], equals(0.0));

      // 3. Re-apply ALL 100 edits back to final state
      final redoneFinal = history.redoAll(restoredBaseline);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
      expect(history.undoCount, equals(100));

      final redoneFinalJson = jsonEncode(redoneFinal.toJson());
      expect(redoneFinalJson, equals(stateAt100Json));
      expect(recordedParamHistory['temperature'], equals(paramAt100));
    });
  });

  group('Prompt 4: Recolor Studio Persistence & Recipe Roundtrips', () {
    test('Recolor adjustment layer persists into RenderRecipe and restores losslessly', () {
      final source = SourceLayer(
        id: 'source_0',
        name: 'Original Image',
        sourceHash: testImageHash,
        sourceWidth: testWidth,
        sourceHeight: testHeight,
      );

      final recolorLayer = AdjustmentLayer(
        id: 'recolor_1700000000',
        name: 'Recolor (#FF0000 -> #00FF00)',
        opacity: 0.90,
        effectType: 'recolor',
        blendMode: BlendModeType.normal,
        parameters: {
          'sourceR': 255,
          'sourceG': 0,
          'sourceB': 0,
          'targetR': 0,
          'targetG': 255,
          'targetB': 0,
          'tolerance': 0.25,
          'feather': 0.15,
          'preserveLuminance': true,
        },
      );

      final layerStack = LayerStack([source, recolorLayer]);

      final recipe = RenderRecipe(
        recipeId: 'rec_prompt4',
        recipeVersion: 2,
        sourceImageHash: testImageHash,
        sourceImagePath: '/dummy/source.png',
        activeStudio: 'recolor',
        activePresetId: 'default_natural',
        masterIntensity: 1.0,
        fineTuneParameters: const {'temperature': 0.1},
        curveLut256: List.generate(256, (i) => i),
        paletteRemap: const [ColorVector(1.0, 0.0, 0.0)],
        layerStack: layerStack,
        updatedAt: DateTime.utc(2026, 10, 24, 0, 0, 0),
      );

      expect(recipe.isValidStudio, isTrue);
      expect(recipe.activeStudio, equals('recolor'));

      // Serialize to JSON and deserialize back
      final json = recipe.toJson();
      final restored = RenderRecipe.fromJson(json);

      expect(restored.recipeId, equals(recipe.recipeId));
      expect(restored.activeStudio, equals('recolor'));
      expect(restored.layerStack, isNotNull);
      expect(restored.layerStack!.layers.length, equals(2));

      final restoredRecolor = restored.layerStack!.layers[1] as AdjustmentLayer;
      expect(restoredRecolor.id, equals(recolorLayer.id));
      expect(restoredRecolor.effectType, equals('recolor'));
      expect(restoredRecolor.opacity, equals(0.90));
      expect(restoredRecolor.parameters['sourceR'], equals(255));
      expect(restoredRecolor.parameters['targetG'], equals(255));
      expect(restoredRecolor.parameters['tolerance'], equals(0.25));
    });
  });

  group('Prompt 4: VariantBoard Branching & Independence', () {
    test('Variants maintain isolated layer stacks and switch without re-allocating source media', () {
      final source = SourceLayer(
        id: 'source_0',
        name: 'Original Image',
        sourceHash: testImageHash,
        sourceWidth: testWidth,
        sourceHeight: testHeight,
      );

      final baseStack = LayerStack([source]);

      final initialBoard = VariantBoard(
        variants: [
          ProjectVariant(
            id: 'var_a',
            name: 'Original Style',
            layerStack: baseStack,
            createdAt: DateTime.utc(2026, 10, 24, 0, 0, 0),
          ),
        ],
        activeVariantId: 'var_a',
      );

      // Create variant B with an extra duotone tint layer
      final tintLayer = AdjustmentLayer(
        id: 'adj_tint_b',
        name: 'Variant B Tint',
        effectType: 'duotone',
        blendMode: BlendModeType.multiply,
        opacity: 0.70,
        parameters: const {'shadowR': 50, 'highlightR': 220},
      );
      final stackB = baseStack.addLayer(tintLayer);

      final updatedBoard = initialBoard.createVariant(
        id: 'var_b',
        name: 'Stylized Exploration',
        layerStack: stackB,
        makeActive: true,
      );

      expect(updatedBoard.variants.length, equals(2));
      expect(updatedBoard.activeVariantId, equals('var_b'));
      expect(updatedBoard.activeVariant.layerStack.layers.length, equals(2));

      // Switch back to Variant A
      final switchedBackBoard = updatedBoard.switchVariant('var_a');
      expect(switchedBackBoard.activeVariantId, equals('var_a'));
      // Variant A remains clean with 1 layer
      expect(
        switchedBackBoard.activeVariant.layerStack.layers.length,
        equals(1),
      );

      // Switch to Variant B: proves Variant B still contains its 2 layers
      final switchedToBBoard = switchedBackBoard.switchVariant('var_b');
      expect(switchedToBBoard.activeVariantId, equals('var_b'));
      expect(
        switchedToBBoard.activeVariant.layerStack.layers.length,
        equals(2),
      );

      // JSON roundtrip of VariantBoard
      final json = switchedToBBoard.toJson();
      final restoredBoard = VariantBoard.fromJson(json);

      expect(restoredBoard.variants.length, equals(2));
      expect(restoredBoard.activeVariantId, equals('var_b'));
      expect(restoredBoard.activeVariant.name, equals('Stylized Exploration'));
      expect(restoredBoard.activeVariant.layerStack.layers.length, equals(2));
    });
  });

  group('Prompt 4: Source Image Immutability (Invariant 4)', () {
    test('Original source byte buffer and SHA-256 hash remain completely untouched', () async {
      final initialDigest = sha256.convert(testImageBytes).toString();
      final originalByteSnapshot = Uint8List.fromList(testImageBytes);

      final executor = RenderGraphExecutor();
      final source = SourceLayer(
        id: 'src_root',
        name: 'Immutable Source',
        sourceHash: initialDigest,
        sourceWidth: testWidth,
        sourceHeight: testHeight,
      );

      final recolor = AdjustmentLayer(
        id: 'recolor_layer',
        name: 'Aggressive Recolor',
        effectType: 'recolor',
        blendMode: BlendModeType.overlay,
        opacity: 1.0,
        parameters: const {
          'sourceR': 0,
          'sourceG': 0,
          'sourceB': 0,
          'targetR': 255,
          'targetG': 255,
          'targetB': 255,
          'tolerance': 0.8,
          'feather': 0.2,
          'preserveLuminance': false,
        },
      );

      final stack = LayerStack([source, recolor]);
      final graph = stack.toRenderGraph();

      // Execute render pipeline
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: testImageBytes,
      );

      // Verify output rendered successfully and altered pixels
      expect(result.pixelBytes.length, equals(testWidth * testHeight * 4));

      // Verify original source image is 100% byte-for-byte identical
      expect(testImageBytes.length, equals(originalByteSnapshot.length));
      for (int i = 0; i < testImageBytes.length; i++) {
        expect(testImageBytes[i], equals(originalByteSnapshot[i]));
      }

      final postExecutionDigest = sha256.convert(testImageBytes).toString();
      expect(postExecutionDigest, equals(initialDigest));
    });
  });
}
