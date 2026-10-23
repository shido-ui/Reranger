import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/layers/editor_layer.dart';
import 'package:reranger/domain/layers/variant_board.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/style_render_nodes.dart';
import 'package:reranger/features/editor/presentation/layer_history_controller.dart';

void main() {
  const source = SourceLayer(
    id: 'src_root',
    sourceHash:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    sourceWidth: 800,
    sourceHeight: 600,
  );

  group('LayerHistoryController & Notification Stream (Prompt B)', () {
    test(
      'Adding and updating layers emits notifications and updates history',
      () {
        final controller = LayerHistoryController(sourceLayer: source);
        int notificationCount = 0;
        controller.addListener(() => notificationCount++);

        const adj = AdjustmentLayer(
          id: 'adj_duotone',
          name: 'Duotone Tint',
          effectType: 'duotone',
          parameters: {'shadowR': 10, 'highlightR': 240},
        );

        controller.addAdjustmentLayer(adj);
        expect(notificationCount, equals(1));
        expect(controller.state.layerStack.layers.length, equals(2));
        expect(controller.state.canUndo, isTrue);

        controller.setLayerOpacity('adj_duotone', 0.5);
        expect(notificationCount, equals(2));
        expect(controller.state.layerStack.layers[1].opacity, equals(0.5));

        controller.undo();
        expect(notificationCount, equals(3));
        expect(controller.state.layerStack.layers[1].opacity, equals(1.0));

        controller.redo();
        expect(notificationCount, equals(4));
        expect(controller.state.layerStack.layers[1].opacity, equals(0.5));
      },
    );

    test('Toggling layer visibility bypasses layer in RenderGraph', () {
      final controller = LayerHistoryController(sourceLayer: source);
      const adj = AdjustmentLayer(
        id: 'adj_grain',
        name: 'Film Grain',
        effectType: 'grain',
        parameters: {'intensity': 0.15},
      );
      controller.addAdjustmentLayer(adj);

      final graphVisible = controller.buildRenderGraph();
      expect(graphVisible.nodes.containsKey('node_adj_grain'), isTrue);

      controller.toggleLayerVisibility('adj_grain');
      final graphHidden = controller.buildRenderGraph();
      expect(graphHidden.nodes.containsKey('node_adj_grain'), isFalse);
    });

    test('Chaining layer stack onto preset base graph preserves upstream DAG dependencies', () {
      final basePresetNode1 = GrayscaleNode(
        id: 'node_gray',
        inputNodeId: 'src_root',
      );
      final basePresetNode2 = DuoToneNode(
        id: 'node_preset_duo',
        inputNodeId: 'node_gray',
      );
      final presetGraph = RenderGraph(
        id: 'preset_graph',
        nodes: {
          'src_root': SourceImageNode(
            id: 'src_root',
            sourceImageHash: source.sourceHash,
            sourceWidth: source.sourceWidth,
            sourceHeight: source.sourceHeight,
          ),
          'node_gray': basePresetNode1,
          'node_preset_duo': basePresetNode2,
        },
        outputNodeId: 'node_preset_duo',
      );

      final stack = LayerStack([
        source,
        const AdjustmentLayer(
          id: 'adj_overlay_grain',
          name: 'Extra Grain',
          effectType: 'grain',
          parameters: {'intensity': 0.20},
        ),
      ]);

      final compositeGraph = stack.toRenderGraph(baseGraph: presetGraph);

      // Verify preset nodes are preserved
      expect(compositeGraph.nodes.containsKey('node_gray'), isTrue);
      expect(compositeGraph.nodes.containsKey('node_preset_duo'), isTrue);

      // Verify layer node is chained directly on top of preset output
      expect(
        compositeGraph.nodes.containsKey('node_adj_overlay_grain'),
        isTrue,
      );
      expect(
        compositeGraph.nodes['node_adj_overlay_grain']!.inputNodeIds,
        equals(['node_preset_duo']),
      );
      expect(compositeGraph.outputNodeId, equals('node_adj_overlay_grain'));
    });
  });

  group('Variant Board Exploration & Persistence (Prompt B)', () {
    test('Creating, switching, renaming, and deleting variants', () {
      final controller = LayerHistoryController(sourceLayer: source);
      int notifications = 0;
      controller.addListener(() => notifications++);

      // 1. Create a variant
      controller.createVariant('Vintage High Contrast');
      expect(notifications, equals(1));
      expect(controller.state.variantBoard.variants.length, equals(2));
      expect(
        controller.state.variantBoard.activeVariant.name,
        equals('Vintage High Contrast'),
      );

      final varId = controller.state.variantBoard.activeVariantId;

      // 2. Rename variant
      controller.renameVariant(varId, 'Warm Sepia Film');
      expect(notifications, equals(2));
      expect(
        controller.state.variantBoard.activeVariant.name,
        equals('Warm Sepia Film'),
      );

      // 3. Switch back to original variant
      controller.switchVariant('var_default');
      expect(notifications, equals(3));
      expect(
        controller.state.variantBoard.activeVariantId,
        equals('var_default'),
      );

      // 4. Delete new variant
      controller.deleteVariant(varId);
      expect(notifications, equals(4));
      expect(controller.state.variantBoard.variants.length, equals(1));
    });

    test('RenderRecipe schema v2 round-trip lossless persistence with layerStack and variantBoard', () {
      final stack = LayerStack([
        source,
        const AdjustmentLayer(
          id: 'adj_1',
          name: 'Layer Tint',
          effectType: 'duotone',
          parameters: {'shadowR': 20, 'highlightR': 250},
        ),
      ]);

      final board = VariantBoard(
        variants: [
          ProjectVariant(
            id: 'v_1',
            name: 'Branch 1',
            layerStack: stack,
            createdAt: DateTime.now().toUtc(),
          ),
        ],
        activeVariantId: 'v_1',
      );

      final recipe = RenderRecipe(
        recipeId: 'rec_v2_test',
        recipeVersion: 2,
        sourceImageHash: source.sourceHash,
        sourceImagePath: '/dummy/source.png',
        activeStudio: 'style',
        activePresetId: 'default_natural',
        masterIntensity: 1.0,
        fineTuneParameters: const {'contrast': 0.15},
        curveLut256: List.generate(256, (i) => i),
        paletteRemap: const [],
        layerStack: stack,
        variantBoard: board,
        updatedAt: DateTime.now().toUtc(),
      );

      final json = recipe.toJson();
      final restored = RenderRecipe.fromJson(json);

      expect(restored.recipeVersion, equals(2));
      expect(restored.layerStack, isNotNull);
      expect(restored.layerStack!.layers.length, equals(2));
      expect(restored.variantBoard, isNotNull);
      expect(restored.variantBoard!.variants.first.name, equals('Branch 1'));
    });

    test('Backward compatibility: schema v1 recipe restores gracefully with null layerStack', () {
      final v1Json = {
        'recipeId': 'rec_v1_legacy',
        'recipeVersion': 1,
        'sourceImageHash': 'hash_v1',
        'sourceImagePath': '/path/v1.png',
        'activeStudio': 'style',
        'activePresetId': 'natural',
        'masterIntensity': 1.0,
        'fineTuneParameters': <String, dynamic>{},
        'curveLut256': List.generate(256, (i) => i),
        'paletteRemap': <dynamic>[],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      final restored = RenderRecipe.fromJson(v1Json);
      expect(restored.recipeVersion, equals(1));
      expect(restored.layerStack, isNull);
      expect(restored.variantBoard, isNull);
    });
  });
}
