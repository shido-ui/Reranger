import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/layers/editor_layer.dart';

void main() {
  group('SourceLayer & Invariant 4 Immutability', () {
    const source = SourceLayer(
      id: 'src_root',
      sourceHash:
          'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
      sourceWidth: 1920,
      sourceHeight: 1080,
    );

    test('Source layer properties are locked and immutable', () {
      expect(source.isImmutableSource, isTrue);
      expect(source.opacity, equals(1.0));
      expect(source.isVisible, isTrue);

      final copy = source.copyWith(
        name: 'Renamed Source',
        opacity: 0.5,
        isVisible: false,
      );
      // Opacity and visibility must ignore mutation attempts on root SourceLayer
      expect(copy.opacity, equals(1.0));
      expect(copy.isVisible, isTrue);
      expect(copy.name, equals('Renamed Source'));
    });

    test('LayerStack locks SourceLayer at root index 0', () {
      const adj1 = AdjustmentLayer(
        id: 'adj_1',
        name: 'Warm Tint',
        effectType: 'recolor',
        parameters: {'sourceR': 200, 'targetR': 255},
      );
      const adj2 = AdjustmentLayer(
        id: 'adj_2',
        name: 'Film Grain',
        effectType: 'grain',
        parameters: {'intensity': 0.15},
      );

      final stack = LayerStack([source, adj1, adj2]);
      expect(stack.layers.length, equals(3));
      expect(stack.sourceLayer, equals(source));

      // Attempting to remove root SourceLayer throws ArgumentError
      expect(() => stack.removeLayer('src_root'), throwsArgumentError);

      // Attempting to reorder index 0 away from root throws ArgumentError
      expect(() => stack.reorder(0, 1), throwsArgumentError);
      expect(() => stack.reorder(1, 0), throwsArgumentError);
    });
  });

  group('BlendModeType Mathematical Correctness', () {
    test('Normal blend returns top layer directly', () {
      expect(BlendModeType.normal.apply(100, 200), equals(200));
      expect(BlendModeType.normal.apply(0, 255), equals(255));
    });

    test('Multiply blend multiplies normalized values ((A * B) / 255)', () {
      // 0 * B = 0
      expect(BlendModeType.multiply.apply(0, 200), equals(0));
      // 255 * B = B
      expect(BlendModeType.multiply.apply(255, 128), equals(128));
      // 128 * 128 / 255 = 64
      expect(BlendModeType.multiply.apply(128, 128), closeTo(64, 1));
    });

    test('Screen blend lightens image (255 - (255 - A)(255 - B) / 255)', () {
      // Screen with black (0) preserves base
      expect(BlendModeType.screen.apply(100, 0), equals(100));
      // Screen with white (255) yields pure white
      expect(BlendModeType.screen.apply(100, 255), equals(255));
      // 128 Screen 128 = 191
      expect(BlendModeType.screen.apply(128, 128), closeTo(191, 1));
    });

    test('Overlay blend applies contrast curve (Multiply on dark, Screen on light)', () {
      // When base is dark (e.g. 64 < 128): (2 * A * B) / 255
      expect(BlendModeType.overlay.apply(64, 128), closeTo(64, 1));
      // When base is pure black: 0
      expect(BlendModeType.overlay.apply(0, 200), equals(0));
      // When base is pure white: 255
      expect(BlendModeType.overlay.apply(255, 200), equals(255));
    });

    test('Soft Light blend applies Pegtop diffused lighting curve without clipping', () {
      // Midtones blend smoothly
      expect(BlendModeType.softLight.apply(128, 128), closeTo(128, 2));
      expect(BlendModeType.softLight.apply(128, 200), greaterThan(128));
      expect(BlendModeType.softLight.apply(128, 50), lessThan(128));
    });
  });

  group('LayerStack Operations & Composition to RenderGraph', () {
    const source = SourceLayer(
      id: 'src_root',
      sourceHash:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      sourceWidth: 800,
      sourceHeight: 600,
    );

    test('Reordering, updating, and removing adjustment layers', () {
      const adj1 = AdjustmentLayer(
        id: 'adj_1',
        name: 'Layer 1',
        effectType: 'recolor',
        parameters: {'sourceR': 100},
      );
      const adj2 = AdjustmentLayer(
        id: 'adj_2',
        name: 'Layer 2',
        effectType: 'grain',
        parameters: {'intensity': 0.10},
      );

      var stack = LayerStack([source, adj1, adj2]);
      expect(stack.layers[1].id, equals('adj_1'));
      expect(stack.layers[2].id, equals('adj_2'));

      // Reorder layers (index 1 <-> index 2)
      stack = stack.reorder(1, 2);
      expect(stack.layers[1].id, equals('adj_2'));
      expect(stack.layers[2].id, equals('adj_1'));

      // Update opacity on adj_1
      final updatedAdj1 = adj1.copyWith(opacity: 0.65);
      stack = stack.updateLayer(updatedAdj1);
      expect(stack.layers[2].opacity, equals(0.65));

      // Remove adj_2
      stack = stack.removeLayer('adj_2');
      expect(stack.layers.length, equals(2));
      expect(stack.layers.any((l) => l.id == 'adj_2'), isFalse);
    });

    test('Flattens active visible layers into a valid DAG RenderGraph', () {
      const recolor = AdjustmentLayer(
        id: 'adj_recolor',
        name: 'Color Shift',
        effectType: 'recolor',
        parameters: {
          'sourceR': 255,
          'sourceG': 0,
          'sourceB': 0,
          'targetR': 0,
          'targetG': 255,
          'targetB': 0,
          'tolerance': 0.20,
          'feather': 0.10,
        },
        opacity: 0.80,
        isVisible: true,
      );

      const hiddenGrain = AdjustmentLayer(
        id: 'adj_grain',
        name: 'Hidden Grain',
        effectType: 'grain',
        parameters: {'intensity': 0.20},
        opacity: 1.0,
        isVisible: false, // Hidden: must be excluded from render graph
      );

      final stack = LayerStack([source, recolor, hiddenGrain]);
      final graph = stack.toRenderGraph();

      graph.validate(); // Validates acyclicity and inputs
      expect(graph.nodes.length, equals(2)); // root + recolor (grain omitted!)
      expect(graph.nodes.containsKey('src_root'), isTrue);
      expect(graph.nodes.containsKey('node_adj_recolor'), isTrue);
      expect(graph.nodes.containsKey('node_adj_grain'), isFalse);
      expect(graph.outputNodeId, equals('node_adj_recolor'));
    });

    test('JSON serialization round-trip preserves all layers, blend modes, and parameters', () {
      final stack = LayerStack([
        source,
        const AdjustmentLayer(
          id: 'adj_test',
          name: 'DuoTone Layer',
          effectType: 'duotone',
          parameters: {'shadowR': 30, 'highlightR': 240},
          blendMode: BlendModeType.overlay,
          opacity: 0.75,
          seed: 99,
        ),
      ]);

      final json = stack.toJson();
      final restored = LayerStack.fromJson(json);

      expect(restored.layers.length, equals(stack.layers.length));
      final adjRestored = restored.layers[1] as AdjustmentLayer;
      expect(adjRestored.blendMode, equals(BlendModeType.overlay));
      expect(adjRestored.opacity, equals(0.75));
      expect(adjRestored.seed, equals(99));
    });
  });
}
