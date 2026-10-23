import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/render_pipeline_failure.dart';

void main() {
  const validHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  group('RenderGraphNode Schema & Validation (Batch A)', () {
    test('SourceImageNode validates parameters and computes memory', () {
      final node = SourceImageNode(
        id: 'src_0',
        sourceImageHash: validHash,
        sourceWidth: 1920,
        sourceHeight: 1080,
      );

      node.validate();
      expect(node.id, equals('src_0'));
      expect(node.type, equals('SourceImageNode'));
      expect(node.estimateMemoryBytes(1920, 1080), equals(1920 * 1080 * 4));

      // Rejects invalid hash length
      final invalidHashNode = SourceImageNode(
        id: 'src_bad',
        sourceImageHash: 'short_hash',
        sourceWidth: 100,
        sourceHeight: 100,
      );
      expect(
        () => invalidHashNode.validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      // Rejects zero dimension
      final invalidDimNode = SourceImageNode(
        id: 'src_bad_dim',
        sourceImageHash: validHash,
        sourceWidth: 0,
        sourceHeight: 100,
      );
      expect(
        () => invalidDimNode.validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );
    });

    test('GrayscaleNode validates single input dependency', () {
      final node = GrayscaleNode(
        id: 'gray_1',
        inputNodeId: 'src_0',
        preserveAlpha: true,
      );

      node.validate();
      expect(node.inputNodeIds, equals(['src_0']));
      expect(node.parameters['preserveAlpha'], isTrue);
    });

    test('SobelEdgeNode enforces threshold bounds [0, 255]', () {
      final validNode = SobelEdgeNode(
        id: 'sobel_1',
        inputNodeId: 'gray_1',
        edgeThreshold: 60,
      );
      validNode.validate();

      final outOfBoundsNode = SobelEdgeNode(
        id: 'sobel_bad',
        inputNodeId: 'gray_1',
        edgeThreshold: 300,
      );
      expect(
        () => outOfBoundsNode.validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );
    });

    test(
      'Node cache key matrix guarantees determinism and miss on changes',
      () {
        final nodeA = SobelEdgeNode(
          id: 'sobel_1',
          inputNodeId: 'gray_1',
          edgeThreshold: 50,
        );

        final keyBase = nodeA.computeNodeCacheKey(
          ['up_key_123'],
          targetWidth: 512,
          targetHeight: 384,
        );
        expect(keyBase.length, equals(64));

        // Same parameters & upstream -> exact match (Cache Hit)
        final keySame = nodeA.computeNodeCacheKey(
          ['up_key_123'],
          targetWidth: 512,
          targetHeight: 384,
        );
        expect(keySame, equals(keyBase));

        // Upstream key changed -> Cache Miss
        final keyUpstreamChange = nodeA.computeNodeCacheKey(
          ['up_key_DIFFERENT'],
          targetWidth: 512,
          targetHeight: 384,
        );
        expect(keyUpstreamChange, isNot(equals(keyBase)));

        // Dimension changed -> Cache Miss
        final keyDimChange = nodeA.computeNodeCacheKey(
          ['up_key_123'],
          targetWidth: 600,
          targetHeight: 400,
        );
        expect(keyDimChange, isNot(equals(keyBase)));

        // Parameter changed -> Cache Miss
        final nodeParamChange = SobelEdgeNode(
          id: 'sobel_1',
          inputNodeId: 'gray_1',
          edgeThreshold: 75,
        );
        final keyParamChange = nodeParamChange.computeNodeCacheKey(
          ['up_key_123'],
          targetWidth: 512,
          targetHeight: 384,
        );
        expect(keyParamChange, isNot(equals(keyBase)));
      },
    );
  });

  group('RenderGraph Topological Order & DAG Invariants (Batch A)', () {
    test(
      'Topological sort returns linear execution order for valid pipeline',
      () {
        final src = SourceImageNode(
          id: 'src_0',
          sourceImageHash: validHash,
          sourceWidth: 800,
          sourceHeight: 600,
        );
        final gray = GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0');
        final sobel = SobelEdgeNode(id: 'sobel_2', inputNodeId: 'gray_1');

        final graph = RenderGraph(
          id: 'graph_ink_001',
          nodes: {'src_0': src, 'gray_1': gray, 'sobel_2': sobel},
          outputNodeId: 'sobel_2',
        );

        graph.validate();
        final order = graph.getTopologicalExecutionOrder();
        expect(
          order.map((n) => n.id).toList(),
          equals(['src_0', 'gray_1', 'sobel_2']),
        );
      },
    );

    test('Cycle detection: Graph with circular dependency throws RenderGraphCycleFailure', () {
      final nodeA = GrayscaleNode(id: 'node_a', inputNodeId: 'node_b');
      final nodeB = GrayscaleNode(id: 'node_b', inputNodeId: 'node_a');

      final cyclicGraph = RenderGraph(
        id: 'cyclic_graph',
        nodes: {'node_a': nodeA, 'node_b': nodeB},
        outputNodeId: 'node_b',
      );

      expect(
        () => cyclicGraph.validate(),
        throwsA(isA<RenderGraphCycleFailure>()),
      );
    });

    test('Missing dependency throws RenderGraphMissingInputFailure', () {
      final gray = GrayscaleNode(
        id: 'gray_1',
        inputNodeId: 'non_existent_node',
      );

      final brokenGraph = RenderGraph(
        id: 'broken_graph',
        nodes: {'gray_1': gray},
        outputNodeId: 'gray_1',
      );

      expect(
        () => brokenGraph.validate(),
        throwsA(isA<RenderGraphMissingInputFailure>()),
      );
    });

    test('Peak memory estimation calculates concurrent buffer headroom', () {
      final src = SourceImageNode(
        id: 'src_0',
        sourceImageHash: validHash,
        sourceWidth: 500,
        sourceHeight: 400,
      );
      final gray = GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0');

      final graph = RenderGraph(
        id: 'graph_mem',
        nodes: {'src_0': src, 'gray_1': gray},
        outputNodeId: 'gray_1',
      );

      // Width 500 * Height 400 * 4 bytes RGBA = 800,000 bytes per buffer
      // 2 buffers peak = 1,600,000 bytes
      expect(graph.estimatePeakMemoryBytes(500, 400), equals(1600000));
    });

    test('Lossless JSON serialization roundtrip preserves graph and nodes', () {
      final src = SourceImageNode(
        id: 'src_0',
        sourceImageHash: validHash,
        sourceWidth: 1000,
        sourceHeight: 800,
      );
      final gray = GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0');
      final sobel = SobelEdgeNode(
        id: 'sobel_2',
        inputNodeId: 'gray_1',
        edgeThreshold: 65,
      );

      final original = RenderGraph(
        id: 'test_pipeline',
        nodes: {'src_0': src, 'gray_1': gray, 'sobel_2': sobel},
        outputNodeId: 'sobel_2',
      );

      final json = original.toJson();
      final restored = RenderGraph.fromJson(json);
      expect(restored, equals(original));
      expect(restored.outputNodeId, equals('sobel_2'));
      expect(restored.nodes.length, equals(3));
    });
  });
}
