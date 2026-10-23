import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_job_controller.dart';
import 'package:reranger/data/render/render_node_cache.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/render_pipeline_failure.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const validHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  group('RenderJobController & Concurrency Race Tests (Batch C)', () {
    late Uint8List squareBytes;
    late RenderJobController controller;

    setUp(() {
      final img = SyntheticSceneFixtures.createCenterSquare(
        width: 32,
        height: 32,
        squareSize: 12,
      );
      squareBytes = SyntheticSceneFixtures.encodeToPng(img);
      controller = RenderJobController(
        executor: RenderGraphExecutor(cache: RenderNodeCache()),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    RenderGraph buildGraph(int threshold) {
      return RenderGraph(
        id: 'graph_threshold_$threshold',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: validHash,
            sourceWidth: 32,
            sourceHeight: 32,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: threshold,
          ),
        },
        outputNodeId: 'sobel_2',
      );
    }

    test(
      'Single render job executes cleanly and emits truthful progress events',
      () async {
        final states = <RenderJobState>[];
        final sub = controller.stateStream.listen(states.add);

        final result = await controller.submitRenderRequest(
          graph: buildGraph(50),
          sourceImageBytes: squareBytes,
        );

        await Future.delayed(const Duration(milliseconds: 10));
        await sub.cancel();

        expect(result, isNotNull);
        expect(result!.width, equals(32));
        expect(result.height, equals(32));

        // Verify truthful progress progression
        expect(states.any((s) => s is RenderJobExecuting), isTrue);
        expect(states.any((s) => s is RenderJobCompleted), isTrue);
        final completed = states.firstWhere(
          (s) => s is RenderJobCompleted,
        ) as RenderJobCompleted;
        expect(completed.requestId, equals(1));
      },
    );

    test('Rapid slider adjustment (Latest-Request-Wins) completes only latest request', () async {
      final states = <RenderJobState>[];
      final sub = controller.stateStream.listen(states.add);

      // Rapidly fire 5 requests simulating slider scrubbing
      final futures = <Future<RenderExecutionResult?>>[];
      for (int i = 1; i <= 5; i++) {
        futures.add(
          controller.submitRenderRequest(
            graph: buildGraph(20 + i * 10),
            sourceImageBytes: squareBytes,
          ),
        );
      }

      final results = await Future.wait(futures);
      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      // The latest request (#5) must return a non-null result
      expect(results[4], isNotNull);
      expect(controller.latestRequestId, equals(5));

      // Completed events on the state stream must only be for the latest request (#5)
      final completedStates = states.whereType<RenderJobCompleted>().toList();
      expect(completedStates.length, equals(1));
      expect(completedStates.first.requestId, equals(5));

      // Superseded jobs must be accounted for
      expect(controller.staleResultsDiscardedCount, greaterThanOrEqualTo(1));
    });

    test('Visible cancel action halts execution immediately', () async {
      final states = <RenderJobState>[];
      final sub = controller.stateStream.listen(states.add);

      final renderFuture = controller.submitRenderRequest(
        graph: buildGraph(50),
        sourceImageBytes: squareBytes,
      );

      // Immediate user cancellation
      controller.cancelCurrentJob();

      final result = await renderFuture;
      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(result, isNull);
      expect(states.any((s) => s is RenderJobCancelled), isTrue);
    });

    test('Node parameter failure throws and emits RenderJobFailed', () async {
      final states = <RenderJobState>[];
      final sub = controller.stateStream.listen(states.add);

      // Graph with invalid out-of-bounds parameter
      final brokenGraph = RenderGraph(
        id: 'broken_graph',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: validHash,
            sourceWidth: 32,
            sourceHeight: 32,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 999, // Invalid (> 255)
          ),
        },
        outputNodeId: 'sobel_2',
      );

      expect(
        () => controller.submitRenderRequest(
          graph: brokenGraph,
          sourceImageBytes: squareBytes,
        ),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      await Future.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(states.any((s) => s is RenderJobFailed), isTrue);
    });
  });
}
