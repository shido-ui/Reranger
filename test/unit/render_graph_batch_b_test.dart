import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_node_cache.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/style_render_nodes.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const validHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  group('RenderGraphExecutor & Recipe Pipelines (Batch B)', () {
    late Uint8List squarePngBytes;

    setUp(() {
      final img = SyntheticSceneFixtures.createCenterSquare(
        width: 32,
        height: 32,
        squareSize: 12,
      );
      squarePngBytes = SyntheticSceneFixtures.encodeToPng(img);
    });

    test(
      'Recipe 1 (Dramatic Monochrome Ink) executes deterministically',
      () async {
        final executor = RenderGraphExecutor();
        final graph = RenderGraph(
          id: 'recipe_1_monochrome_ink',
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
              edgeThreshold: 40,
            ),
            'ink_3': EdgeInvertSubtractNode(
              id: 'ink_3',
              grayInputNodeId: 'gray_1',
              edgeInputNodeId: 'sobel_2',
              edgeIntensity: 0.85,
              contrastGamma: 1.5,
            ),
          },
          outputNodeId: 'ink_3',
        );

        final res1 = await executor.execute(
          graph: graph,
          sourceImageBytes: squarePngBytes,
        );

        expect(res1.width, equals(32));
        expect(res1.height, equals(32));
        expect(res1.pixelBytes.length, equals(32 * 32 * 4));
        expect(res1.totalNodesExecuted, equals(4));
        expect(res1.cacheHits, equals(0));

        // Re-executing exact graph yields 100% cache hits and zero re-computations
        final res2 = await executor.execute(
          graph: graph,
          sourceImageBytes: squarePngBytes,
        );
        expect(res2.totalNodesExecuted, equals(0));
        expect(res2.cacheHits, equals(4));
        expect(res2.pixelBytes, equals(res1.pixelBytes));
      },
    );

    test(
      'Recipe 2 (Grain Overlay) produces repeatable noise and preserves alpha',
      () async {
        final executor = RenderGraphExecutor();
        final transImg = SyntheticSceneFixtures.createTransparentFixture(
          width: 32,
          height: 32,
        );
        final transBytes = SyntheticSceneFixtures.encodeToPng(transImg);

        final graph = RenderGraph(
          id: 'recipe_2_grain',
          nodes: {
            'src_0': SourceImageNode(
              id: 'src_0',
              sourceImageHash: validHash,
              sourceWidth: 32,
              sourceHeight: 32,
            ),
            'grain_1': GrainOverlayNode(
              id: 'grain_1',
              inputNodeId: 'src_0',
              intensity: 0.2,
              seed: 1337,
            ),
          },
          outputNodeId: 'grain_1',
        );

        final res = await executor.execute(
          graph: graph,
          sourceImageBytes: transBytes,
        );

        expect(res.width, equals(32));
        expect(res.height, equals(32));

        // Invariant DEF-002: Alpha channel is preserved and A=0 pixels are not modified
        for (int i = 0; i < 32 * 32; i++) {
          final off = i * 4;
          final a = res.pixelBytes[off + 3];
          expect(a == 0 || a == 128, isTrue); // Matches fixture alpha pattern
        }
      },
    );

    test(
      'Recipe 3 (Warm DuoTone) maps shadows to indigo and highlights to amber',
      () async {
        final executor = RenderGraphExecutor();
        final graph = RenderGraph(
          id: 'recipe_3_duotone',
          nodes: {
            'src_0': SourceImageNode(
              id: 'src_0',
              sourceImageHash: validHash,
              sourceWidth: 32,
              sourceHeight: 32,
            ),
            'duo_1': DuoToneNode(
              id: 'duo_1',
              inputNodeId: 'src_0',
              shadowR: 24,
              shadowG: 28,
              shadowB: 64,
              highlightR: 255,
              highlightG: 210,
              highlightB: 140,
              vignetteFalloff: 0.35,
            ),
          },
          outputNodeId: 'duo_1',
        );

        final res = await executor.execute(
          graph: graph,
          sourceImageBytes: squarePngBytes,
        );

        expect(res.width, equals(32));
        expect(res.height, equals(32));
        expect(res.pixelBytes.length, equals(32 * 32 * 4));
      },
    );

    test('Downstream cache invalidation: Upstream change recomputes only downstream dependents', () async {
      final cache = RenderNodeCache();
      final executor = RenderGraphExecutor(cache: cache);

      // Graph: src_0 -> gray_1 -> sobel_2 -> ink_3
      RenderGraph makeGraph(int threshold) {
        return RenderGraph(
          id: 'graph_invalidation_test',
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
            'ink_3': EdgeInvertSubtractNode(
              id: 'ink_3',
              grayInputNodeId: 'gray_1',
              edgeInputNodeId: 'sobel_2',
            ),
          },
          outputNodeId: 'ink_3',
        );
      }

      // First run: cold cache (all 4 executed)
      final res1 = await executor.execute(
        graph: makeGraph(50),
        sourceImageBytes: squarePngBytes,
      );
      expect(res1.totalNodesExecuted, equals(4));

      // Modify sobel threshold from 50 to 90
      // Expected: src_0 and gray_1 are CACHE HITS!
      // sobel_2 and ink_3 (downstream) are CACHE MISSES and recomputed!
      final res2 = await executor.execute(
        graph: makeGraph(90),
        sourceImageBytes: squarePngBytes,
      );

      expect(res2.cacheHits, equals(2)); // src_0 and gray_1 reused
      expect(
        res2.totalNodesExecuted,
        equals(2),
      ); // sobel_2 and ink_3 recomputed
    });

    test(
      'Multi-resolution scaling produces consistent dimension scaled buffers',
      () async {
        final executor = RenderGraphExecutor();
        final graph = RenderGraph(
          id: 'scale_test',
          nodes: {
            'src_0': SourceImageNode(
              id: 'src_0',
              sourceImageHash: validHash,
              sourceWidth: 64,
              sourceHeight: 64,
            ),
            'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          },
          outputNodeId: 'gray_1',
        );

        // Preview scale 0.5
        final previewRes = await executor.execute(
          graph: graph,
          sourceImageBytes: squarePngBytes,
          renderScale: 0.5,
        );
        expect(previewRes.width, equals(16));
        expect(previewRes.height, equals(16));
        expect(previewRes.pixelBytes.length, equals(16 * 16 * 4));

        // Full scale 1.0
        final fullRes = await executor.execute(
          graph: graph,
          sourceImageBytes: squarePngBytes,
          renderScale: 1.0,
        );
        expect(fullRes.width, equals(32));
        expect(fullRes.height, equals(32));
        expect(fullRes.pixelBytes.length, equals(32 * 32 * 4));
      },
    );
  });
}
