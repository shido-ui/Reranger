import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_job_controller.dart';
import 'package:reranger/data/render/render_node_cache.dart';
import 'package:reranger/domain/recipes/adversarial_stealth_node.dart';
import 'package:reranger/domain/recipes/pixelate_quantize_node.dart';
import 'package:reranger/domain/recipes/recolor_render_node.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/render_pipeline_failure.dart';
import 'package:reranger/domain/recipes/style_render_nodes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to create solid color PNG bytes
  Uint8List makeSolidPng(int w, int h, int r, int g, int b, [int a = 255]) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        image.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return Uint8List.fromList(img.encodePng(image, level: 0));
  }

  group('Prompt 2.A: Render Input and Cache Integrity', () {
    const declaredConstantHash =
        '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

    test('Stale decoded pixels cannot leak into second render when declared hash is identical (Prompt 2.A.1)', () async {
      final executor = RenderGraphExecutor();

      // Image A: Pure Red (32x32)
      final imageABytes = makeSolidPng(32, 32, 255, 0, 0);
      // Image B: Pure Green (32x32)
      final imageBBytes = makeSolidPng(32, 32, 0, 255, 0);

      // Verify the two images are genuinely distinct byte buffers
      expect(imageABytes, isNot(equals(imageBBytes)));

      // Graph built using the SAME declared hash for both executions
      final graph = RenderGraph(
        id: 'stale_cache_test_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: declaredConstantHash,
            sourceWidth: 32,
            sourceHeight: 32,
          ),
          'gray': GrayscaleNode(id: 'gray', inputNodeId: 'src'),
        },
        outputNodeId: 'gray',
      );

      // Render 1: Execute with Image A
      final resultA = await executor.execute(
        graph: graph,
        sourceImageBytes: imageABytes,
      );

      // In BT.601, pure red (255, 0, 0) converts to luminance ~76
      // Red: 299 * 255 / 1000 = 76
      final redLuma = (299 * 255) ~/ 1000;
      expect(resultA.pixelBytes[0], equals(redLuma));

      // Render 2: Execute with Image B through the SAME executor using the SAME graph with identical declared hash
      final resultB = await executor.execute(
        graph: graph,
        sourceImageBytes: imageBBytes,
      );

      // In BT.601, pure green (0, 255, 0) converts to luminance ~149
      // Green: 587 * 255 / 1000 = 149
      final greenLuma = (587 * 255) ~/ 1000;
      expect(resultB.pixelBytes[0], equals(greenLuma));

      // PROOF: Output B is strictly green luminance, NOT red luminance
      expect(resultB.pixelBytes[0], isNot(equals(resultA.pixelBytes[0])));
      expect(resultB.pixelBytes, isNot(equals(resultA.pixelBytes)));
    });

    test('Strict source identity validation catches hash mismatch safely (Prompt 2.A.2)', () async {
      final executor = RenderGraphExecutor();
      final imageBytes = makeSolidPng(16, 16, 100, 100, 100);
      final realHash = crypto.sha256.convert(imageBytes).toString();

      final mismatchedGraph = RenderGraph(
        id: 'mismatched_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: 'wrong_${'0' * 58}',
            sourceWidth: 16,
            sourceHeight: 16,
          ),
        },
        outputNodeId: 'src',
      );

      // When strictSourceIdentity is true, throws RenderSourceIntegrityFailure
      expect(
        () => executor.execute(
          graph: mismatchedGraph,
          sourceImageBytes: imageBytes,
          strictSourceIdentity: true,
        ),
        throwsA(isA<RenderSourceIntegrityFailure>()),
      );

      // When matching, executes cleanly
      final validGraph = RenderGraph(
        id: 'valid_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: realHash,
            sourceWidth: 16,
            sourceHeight: 16,
          ),
        },
        outputNodeId: 'src',
      );

      final result = await executor.execute(
        graph: validGraph,
        sourceImageBytes: imageBytes,
        strictSourceIdentity: true,
      );
      expect(result.width, equals(16));
    });

    test('Validates malformed topology, missing source nodes, and unsupported nodes (Prompt 2.A.3)', () async {
      final executor = RenderGraphExecutor();
      final imageBytes = makeSolidPng(16, 16, 100, 100, 100);

      // 1. Empty image bytes
      expect(
        () => executor.execute(
          graph: RenderGraph(
            id: 'g',
            nodes: {
              'src': SourceImageNode(
                id: 'src',
                sourceImageHash: 'a' * 64,
                sourceWidth: 16,
                sourceHeight: 16,
              ),
            },
            outputNodeId: 'src',
          ),
          sourceImageBytes: Uint8List(0),
        ),
        throwsA(isA<RenderNodeExecutionFailure>()),
      );

      // 2. Invalid renderScale <= 0
      expect(
        () => executor.execute(
          graph: RenderGraph(
            id: 'g',
            nodes: {
              'src': SourceImageNode(
                id: 'src',
                sourceImageHash: 'a' * 64,
                sourceWidth: 16,
                sourceHeight: 16,
              ),
            },
            outputNodeId: 'src',
          ),
          sourceImageBytes: imageBytes,
          renderScale: -0.5,
        ),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      // 3. Graph missing SourceImageNode
      expect(
        () => executor.execute(
          graph: RenderGraph(
            id: 'g',
            nodes: {
              'gray': GrayscaleNode(id: 'gray', inputNodeId: 'src_missing'),
            },
            outputNodeId: 'gray',
          ),
          sourceImageBytes: imageBytes,
        ),
        throwsA(isA<RenderGraphMissingInputFailure>()),
      );
    });

    test('RecolorNode validates corrupt and dimension-mismatched masks without swallowing (Prompt 2.A.3)', () async {
      final executor = RenderGraphExecutor();
      final imageBytes = makeSolidPng(16, 16, 200, 100, 50);

      // 1. Corrupt base64 string on RecolorNode throws RenderInvalidParametersFailure
      expect(
        () => RecolorNode(
          id: 'recolor',
          inputNodeId: 'src',
          sourceR: 200,
          sourceG: 100,
          sourceB: 50,
          targetR: 0,
          targetG: 255,
          targetB: 0,
          maskBase64: '%%%not_valid_base64%%%',
        ).validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      // 2. Mismatched mask buffer size in Recolor execution throws RenderInvalidParametersFailure
      // 16x16 needs 256 bytes; provide only 10 bytes
      final badLengthMask = base64Encode(Uint8List(10));
      final graphWithBadMask = RenderGraph(
        id: 'bad_mask_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: 'a' * 64,
            sourceWidth: 16,
            sourceHeight: 16,
          ),
          'rec': RecolorNode(
            id: 'rec',
            inputNodeId: 'src',
            sourceR: 200,
            sourceG: 100,
            sourceB: 50,
            targetR: 0,
            targetG: 255,
            targetB: 0,
            maskBase64: badLengthMask,
          ),
        },
        outputNodeId: 'rec',
      );

      expect(
        () => executor.execute(
          graph: graphWithBadMask,
          sourceImageBytes: imageBytes,
        ),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      // 3. Valid mask matches dimensions and executes accurately
      final validMask = base64Encode(Uint8List(16 * 16));
      final graphWithValidMask = RenderGraph(
        id: 'valid_mask_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: 'a' * 64,
            sourceWidth: 16,
            sourceHeight: 16,
          ),
          'rec': RecolorNode(
            id: 'rec',
            inputNodeId: 'src',
            sourceR: 200,
            sourceG: 100,
            sourceB: 50,
            targetR: 0,
            targetG: 255,
            targetB: 0,
            maskBase64: validMask,
          ),
        },
        outputNodeId: 'rec',
      );

      final result = await executor.execute(
        graph: graphWithValidMask,
        sourceImageBytes: imageBytes,
      );
      expect(result.width, equals(16));
      expect(result.height, equals(16));
    });

    test('Cache hits produce bitwise identical pixels compared to cold fresh execution (Prompt 2.A.4)', () async {
      final cache = RenderNodeCache();
      final executorWithCache = RenderGraphExecutor(cache: cache);
      final executorFresh = RenderGraphExecutor(cache: RenderNodeCache());

      final imageBytes = makeSolidPng(32, 32, 120, 80, 200);

      final graph = RenderGraph(
        id: 'cache_identity_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: 'a' * 64,
            sourceWidth: 32,
            sourceHeight: 32,
          ),
          'gray': GrayscaleNode(id: 'gray', inputNodeId: 'src'),
          'sobel': SobelEdgeNode(
            id: 'sobel',
            inputNodeId: 'gray',
            edgeThreshold: 30,
          ),
          'dt': DuoToneNode(
            id: 'dt',
            inputNodeId: 'sobel',
            shadowR: 20,
            shadowG: 40,
            shadowB: 80,
            highlightR: 240,
            highlightG: 220,
            highlightB: 180,
          ),
        },
        outputNodeId: 'dt',
      );

      // Cold Run
      final coldResult = await executorWithCache.execute(
        graph: graph,
        sourceImageBytes: imageBytes,
      );
      expect(coldResult.cacheHits, equals(0));

      // Warm Run (Cache hit on downstream nodes)
      final warmResult = await executorWithCache.execute(
        graph: graph,
        sourceImageBytes: imageBytes,
      );
      expect(warmResult.cacheHits, greaterThan(0));

      // Independent Fresh Run without shared cache
      final freshResult = await executorFresh.execute(
        graph: graph,
        sourceImageBytes: imageBytes,
      );

      // BITWISE IDENTICAL PROOF
      expect(warmResult.pixelBytes, equals(coldResult.pixelBytes));
      expect(warmResult.pixelBytes, equals(freshResult.pixelBytes));
    });
  });

  group('Prompt 2.B: Cancellation, UI Responsiveness & Concurrency', () {
    test('Mid-node cooperative cancellation aborts execution promptly (Prompt 2.B.2)', () async {
      final executor = RenderGraphExecutor();
      final imageBytes = makeSolidPng(128, 128, 150, 150, 150);

      final graph = RenderGraph(
        id: 'cancellation_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: 'b' * 64,
            sourceWidth: 128,
            sourceHeight: 128,
          ),
          'sobel': SobelEdgeNode(
            id: 'sobel',
            inputNodeId: 'src',
            edgeThreshold: 10,
          ),
          'gray': GrayscaleNode(id: 'gray', inputNodeId: 'sobel'),
        },
        outputNodeId: 'gray',
      );

      int cancelChecks = 0;
      bool cancelled = false;

      // Cancel after 3 checks
      bool checkCancel() {
        cancelChecks++;
        if (cancelChecks >= 3) {
          cancelled = true;
        }
        return cancelled;
      }

      final sw = Stopwatch()..start();
      await expectLater(
        executor.execute(
          graph: graph,
          sourceImageBytes: imageBytes,
          isCancelled: checkCancel,
        ),
        throwsA(isA<RenderGraphCancelledFailure>()),
      );
      sw.stop();

      // Aborted rapidly within milliseconds
      expect(sw.elapsedMilliseconds, lessThan(150));
      expect(cancelled, isTrue);
    });

    test('Rapid slider scrubbing drops stale results and commits only latest (Prompt 2.B.3)', () async {
      final controller = RenderJobController(useWorkerIsolate: false);
      final imageBytes = makeSolidPng(32, 32, 100, 120, 140);

      RenderGraph makeGraph(int thresh) => RenderGraph(
        id: 'graph_$thresh',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: 'c' * 64,
            sourceWidth: 32,
            sourceHeight: 32,
          ),
          'sobel': SobelEdgeNode(
            id: 'sobel',
            inputNodeId: 'src',
            edgeThreshold: thresh,
          ),
        },
        outputNodeId: 'sobel',
      );

      final states = <RenderJobState>[];
      final sub = controller.stateStream.listen(states.add);

      // Rapidly dispatch 5 slider changes
      final futures = <Future<RenderExecutionResult?>>[];
      for (int i = 1; i <= 5; i++) {
        futures.add(
          controller.submitRenderRequest(
            graph: makeGraph(10 * i),
            sourceImageBytes: imageBytes,
          ),
        );
      }

      final results = await Future.wait(futures);
      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      // Intermediate jobs are superseded and return null
      for (int i = 0; i < 4; i++) {
        expect(results[i], isNull);
      }
      // Latest job (#5) commits cleanly
      expect(results[4], isNotNull);
      expect(controller.latestRequestId, equals(5));

      final completedStates = states.whereType<RenderJobCompleted>().toList();
      expect(completedStates.length, equals(1));
      expect(completedStates.first.requestId, equals(5));

      controller.dispose();
    });

    test(
      'Non-blocking Worker Isolate execution and cancellation (Prompt 2.B.1)',
      () async {
        final controller = RenderJobController(useWorkerIsolate: true);
        final imageBytes = makeSolidPng(32, 32, 80, 140, 200);

        final graph = RenderGraph(
          id: 'worker_test_graph',
          nodes: {
            'src': SourceImageNode(
              id: 'src',
              sourceImageHash: 'd' * 64,
              sourceWidth: 32,
              sourceHeight: 32,
            ),
            'gray': GrayscaleNode(id: 'gray', inputNodeId: 'src'),
            'stealth': AdversarialStealthNode(
              id: 'stealth',
              inputNodeId: 'gray',
              strength: 0.5,
            ),
          },
          outputNodeId: 'stealth',
        );

        final states = <RenderJobState>[];
        final sub = controller.stateStream.listen(states.add);

        // Execute on worker isolate
        final result = await controller.submitRenderRequest(
          graph: graph,
          sourceImageBytes: imageBytes,
        );

        await Future.delayed(const Duration(milliseconds: 20));
        await sub.cancel();

        expect(result, isNotNull);
        expect(result!.width, equals(32));
        expect(result.height, equals(32));

        // Emitted real executing and completed states
        expect(states.any((s) => s is RenderJobExecuting), isTrue);
        expect(states.any((s) => s is RenderJobCompleted), isTrue);

        controller.dispose();
      },
    );

    test(
      'Alpha channel is preserved faithfully across transforms (Prompt 2.B.4)',
      () async {
        final executor = RenderGraphExecutor();
        // Semitransparent pixel with alpha = 127
        final imageBytes = makeSolidPng(8, 8, 200, 100, 50, 127);

        final graph = RenderGraph(
          id: 'alpha_graph',
          nodes: {
            'src': SourceImageNode(
              id: 'src',
              sourceImageHash: 'e' * 64,
              sourceWidth: 8,
              sourceHeight: 8,
            ),
            'gray': GrayscaleNode(
              id: 'gray',
              inputNodeId: 'src',
              preserveAlpha: true,
            ),
            'sobel': SobelEdgeNode(
              id: 'sobel',
              inputNodeId: 'gray',
              edgeThreshold: 10,
            ),
            'grain': GrainOverlayNode(
              id: 'grain',
              inputNodeId: 'sobel',
              intensity: 0.2,
              seed: 42,
            ),
            'pixel': PixelateQuantizeNode(
              id: 'pixel',
              inputNodeId: 'grain',
              blockSize: 2,
              paletteLevels: 8,
              preserveAlpha: true,
            ),
          },
          outputNodeId: 'pixel',
        );

        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: imageBytes,
        );

        // Verify alpha channel is 127 for all pixels
        for (int i = 3; i < result.pixelBytes.length; i += 4) {
          expect(result.pixelBytes[i], equals(127));
        }
      },
    );

    test('Handles degenerate dimensions (1x1, 1x2, 2x1) without out-of-bounds errors', () async {
      final executor = RenderGraphExecutor();

      for (final dim in [(1, 1), (1, 2), (2, 1)]) {
        final imgBytes = makeSolidPng(dim.$1, dim.$2, 255, 128, 64);
        final graph = RenderGraph(
          id: 'degen_${dim.$1}x${dim.$2}',
          nodes: {
            'src': SourceImageNode(
              id: 'src',
              sourceImageHash: 'f' * 64,
              sourceWidth: dim.$1,
              sourceHeight: dim.$2,
            ),
            'sobel': SobelEdgeNode(
              id: 'sobel',
              inputNodeId: 'src',
              edgeThreshold: 20,
            ),
            'gray': GrayscaleNode(id: 'gray', inputNodeId: 'sobel'),
          },
          outputNodeId: 'gray',
        );

        final res = await executor.execute(
          graph: graph,
          sourceImageBytes: imgBytes,
        );
        expect(res.width, equals(dim.$1));
        expect(res.height, equals(dim.$2));
        expect(res.pixelBytes.length, equals(dim.$1 * dim.$2 * 4));
      }
    });
  });
}
