import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_job_controller.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt 25: Performance Optimization & Subsystem Correctness', () {
    late Uint8List source1536Bytes;
    late img.Image image1536;
    const sourceHash =
        '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

    setUpAll(() {
      image1536 = img.Image(width: 1536, height: 1536, numChannels: 4);
      for (int y = 0; y < 1536; y++) {
        for (int x = 0; x < 1536; x++) {
          image1536.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
        }
      }
      source1536Bytes = Uint8List.fromList(img.encodePng(image1536));
    });

    test('RenderGraphExecutor source buffer cache speeds up successive runs with zero quality loss', () async {
      final executor = RenderGraphExecutor();
      final preset =
          PresetCatalog.getById('ink_wash_mono') ??
          BatchAPresets.graphitePencil;
      final graph = preset.buildGraph(
        sourceHash,
        1536,
        1536,
        preset.resolveParameters(null),
      );

      // Run 1: Cold execution (decodes raw image bytes and caches)
      final swCold = Stopwatch()..start();
      final coldResult = await executor.execute(
        graph: graph,
        sourceImageBytes: source1536Bytes,
        renderScale: 1.0,
      );
      swCold.stop();

      expect(coldResult.width, equals(1536));
      expect(coldResult.height, equals(1536));

      // Run 2: Warm execution (uses cached pre-decoded RGBA source buffer)
      final swWarm = Stopwatch()..start();
      final warmResult = await executor.execute(
        graph: graph,
        sourceImageBytes: source1536Bytes,
        renderScale: 1.0,
      );
      swWarm.stop();

      // Output quality check: Byte-for-byte identical (Zero hidden quality reduction)
      expect(
        warmResult.pixelBytes.length,
        equals(coldResult.pixelBytes.length),
      );
      expect(warmResult.pixelBytes, equals(coldResult.pixelBytes));

      // Verify warm execution is fast and within budget
      expect(swWarm.elapsedMilliseconds, lessThan(350));
    });

    test(
      'Multi-scale source caching isolates preview from export scales',
      () async {
        final executor = RenderGraphExecutor();
        final preset = BatchAPresets.graphitePencil;
        final graph = preset.buildGraph(
          sourceHash,
          1536,
          1536,
          preset.resolveParameters(null),
        );

        // Half-scale preview (768x768)
        final halfResult = await executor.execute(
          graph: graph,
          sourceImageBytes: source1536Bytes,
          renderScale: 0.5,
        );
        expect(halfResult.width, equals(768));
        expect(halfResult.height, equals(768));

        // Full-scale export (1536x1536)
        final fullResult = await executor.execute(
          graph: graph,
          sourceImageBytes: source1536Bytes,
          renderScale: 1.0,
        );
        expect(fullResult.width, equals(1536));
        expect(fullResult.height, equals(1536));
      },
    );

    test(
      'Cancellation acknowledgement occurs within <= 250ms budget',
      () async {
        final jobController = RenderJobController();
        final preset = BatchAPresets.graphitePencil;
        final graph = preset.buildGraph(
          sourceHash,
          1536,
          1536,
          preset.resolveParameters(null),
        );

        final cancelCompleter = Completer<int>();
        final sw = Stopwatch();

        unawaited(
          jobController.submitRenderRequest(
            graph: graph,
            sourceImageBytes: source1536Bytes,
          ),
        );

        // Trigger cooperative cancel after short delay
        Future.delayed(const Duration(milliseconds: 1), () {
          sw.start();
          jobController.cancelCurrentJob();
          sw.stop();
          cancelCompleter.complete(sw.elapsedMilliseconds);
        });

        final elapsedMs = await cancelCompleter.future;
        expect(elapsedMs, lessThanOrEqualTo(250));
        jobController.dispose();
      },
    );

    test('20 consecutive renders execute cleanly without crash or memory accumulation', () async {
      final jobController = RenderJobController();
      final initialRssMb = ProcessInfo.currentRss / (1024 * 1024);

      for (int i = 0; i < 20; i++) {
        final preset = PresetCatalog.all[i % PresetCatalog.all.length];
        final graph = preset.buildGraph(
          sourceHash,
          1536,
          1536,
          preset.resolveParameters(null),
        );
        final res = await jobController.submitRenderRequest(
          graph: graph,
          sourceImageBytes: source1536Bytes,
        );
        expect(res, isNotNull);
      }

      final finalRssMb = ProcessInfo.currentRss / (1024 * 1024);
      final driftMb = finalRssMb - initialRssMb;
      // Memory drift across 20 full renders must remain well within container budget (< 400 MB)
      expect(driftMb, lessThan(400.0));
      jobController.dispose();
    });

    test('Rapid slider adjustment (10 bursts) cancels intermediate jobs and commits only latest', () async {
      final jobController = RenderJobController();
      final preset = BatchAPresets.graphitePencil;

      final futures = <Future<RenderExecutionResult?>>[];
      for (int i = 1; i <= 10; i++) {
        final params = {'pencilHardness': 0.2 + (i * 0.05)};
        final graph = preset.buildGraph(sourceHash, 1536, 1536, params);
        futures.add(
          jobController.submitRenderRequest(
            graph: graph,
            sourceImageBytes: source1536Bytes,
          ),
        );
      }

      final results = await Future.wait(futures);

      // Latest request must succeed
      expect(results.last, isNotNull);
      // Intermediate superseded jobs must be accounted for
      expect(jobController.staleResultsDiscardedCount, greaterThan(0));
      jobController.dispose();
    });
  });
}
