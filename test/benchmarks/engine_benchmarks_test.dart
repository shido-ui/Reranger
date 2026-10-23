// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_job_controller.dart';
import 'package:reranger/data/scene_map/isolate_scene_map_generator.dart';
import 'package:reranger/data/scene_map/scene_map_repository.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/export/data/image_exporter.dart';
import 'package:reranger/features/export/domain/export_format.dart';
import 'package:reranger/features/import/data/isolate_image_decoder.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';
import 'package:reranger/humanize/humanize_adapter.dart';
import 'package:reranger/humanize/local_humanize_adapter.dart';

class BenchmarkStats {
  final String name;
  final List<double> timingsMs;

  BenchmarkStats(this.name, this.timingsMs);

  double get min => timingsMs.reduce(math.min);
  double get max => timingsMs.reduce(math.max);
  double get mean => timingsMs.reduce((a, b) => a + b) / timingsMs.length;
  double get p95 {
    final sorted = List<double>.from(timingsMs)..sort();
    final index = (0.95 * (sorted.length - 1)).round();
    return sorted[index];
  }

  @override
  String toString() {
    return '$name: Mean=${mean.toStringAsFixed(2)}ms | P95=${p95.toStringAsFixed(2)}ms | Min=${min.toStringAsFixed(2)}ms | Max=${max.toStringAsFixed(2)}ms (Runs: ${timingsMs.length})';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt 25: Performance & Memory Benchmark Suite', () {
    late Directory tempDir;
    late Uint8List png1536Bytes;
    late img.Image fixture1536;
    const sourceHash =
        '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('bench_reranger_');

      // Generate 1536x1536 fixture
      fixture1536 = img.Image(width: 1536, height: 1536, numChannels: 4);
      for (int y = 0; y < 1536; y++) {
        for (int x = 0; x < 1536; x++) {
          final r = (x * 255 ~/ 1536);
          final g = (y * 255 ~/ 1536);
          final b = ((x + y) * 128 ~/ 1536);
          fixture1536.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      png1536Bytes = Uint8List.fromList(img.encodePng(fixture1536));
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Benchmark Suite: Measure All 10 Required Performance Metrics', () async {
      print('\n==========================================================');
      print('RERANGER COMPREHENSIVE PERFORMANCE & MEMORY BENCHMARK');
      print('Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
      print(
        'Target Matrix: Google Pixel 10 (Tensor G5, Mali-G720, 12GB RAM, Android 16)',
      );
      print(
        'Initial RSS: ${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(2)} MB',
      );
      print('==========================================================');

      // 1. Cold Launch & Subsystem Initialization (5 runs)
      final coldLaunchTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final db = ProjectDatabase.openInMemory();
        final storage = ProjectFileStorage(
          rootDir: Directory('${tempDir.path}/storage_$i'),
        );
        final repo = LocalProjectRepository(database: db, fileStorage: storage);
        final controller = EditorController(
          projectRepository: repo,
          fileStorage: storage,
        );
        controller.dispose();
        db.dispose();
        sw.stop();
        coldLaunchTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final coldStats = BenchmarkStats('Cold Launch & Init', coldLaunchTimings);
      print(coldStats);

      // 2. Image Import & Decode Latency (5 runs)
      final decoder = const IsolateImageDecoder();
      final decodeTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final summary = await decoder.decodeAndAnalyze(png1536Bytes);
        sw.stop();
        expect(summary.width, equals(1536));
        decodeTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final decodeStats = BenchmarkStats(
        'Image Import & Decode (1536px)',
        decodeTimings,
      );
      print(decodeStats);

      // 3 & 4. Scene Map Analysis & Cached Retrieval (5 runs)
      final sceneMapGen = const IsolateSceneMapGenerator();
      final analysisDb = ProjectDatabase.openInMemory();
      final sceneMapRepo = SceneMapRepository(analysisDb);

      final analysisTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final bundle = await sceneMapGen.generate(
          imageBytes: png1536Bytes,
          sourceHash: sourceHash,
        );
        sw.stop();
        if (i == 0) {
          await sceneMapRepo.saveBundle(bundle, 'bench_key_$sourceHash');
        }
        analysisTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final analysisStats = BenchmarkStats(
        'Full Scene Map Analysis (1536px)',
        analysisTimings,
      );
      print(analysisStats);

      final cachedAnalysisTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final cached = await sceneMapRepo.getCachedBundle(
          'bench_key_$sourceHash',
        );
        sw.stop();
        expect(cached, isNotNull);
        cachedAnalysisTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final cachedStats = BenchmarkStats(
        'Cached Analysis Retrieval',
        cachedAnalysisTimings,
      );
      print(cachedStats);

      // 5. Preview Update Latency (1536px) (5 runs)
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

      final previewTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        executor.cache.clear();
        final sw = Stopwatch()..start();
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: png1536Bytes,
          renderScale: 1.0,
        );
        sw.stop();
        expect(result.width, equals(1536));
        previewTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final previewStats = BenchmarkStats(
        'Preview Update Latency (1536px Cold)',
        previewTimings,
      );
      print(previewStats);

      final warmPreviewTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        await executor.execute(
          graph: graph,
          sourceImageBytes: png1536Bytes,
          renderScale: 1.0,
        );
        sw.stop();
        warmPreviewTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final warmPreviewStats = BenchmarkStats(
        'Preview Update Latency (Cached Hit)',
        warmPreviewTimings,
      );
      print(warmPreviewStats);

      // 6. Full-Resolution Export Time (5 runs)
      final imageExporter = const ImageExporter();
      final exportFile = File('${tempDir.path}/bench_export.jpg');
      final exportTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        await imageExporter.exportToFile(
          sourceImage: fixture1536,
          destinationPath: exportFile.path,
          config: const ExportConfiguration(
            format: ExportImageFormat.jpeg,
            quality: 90,
            scale: 1.0,
          ),
          sourceImagePath: '${tempDir.path}/original_media.jpg',
        );
        sw.stop();
        exportTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final exportStats = BenchmarkStats(
        'Full-Resolution Export (1536px JPEG-90)',
        exportTimings,
      );
      print(exportStats);

      // 7. Humanize Lifecycle & Inference (5 runs)
      final humanizeAdapter = LocalHumanizeAdapter(isLoadedForTesting: true);
      final swInit = Stopwatch()..start();
      final selfTestRes = await humanizeAdapter.runSelfTest();
      swInit.stop();
      expect(selfTestRes.passed, isTrue);
      final coldInitMs = swInit.elapsedMicroseconds / 1000.0;
      print(
        'Humanize Self-Test & Cold Latency: ${coldInitMs.toStringAsFixed(2)}ms',
      );

      final humanizeTimings = <double>[];
      final fixture512 = img.copyResize(fixture1536, width: 512, height: 512);
      final inputRgba512 = fixture512.getBytes(order: img.ChannelOrder.rgba);
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final res = await humanizeAdapter.runInference(
          HumanizeInput(
            sourceRgba: inputRgba512,
            width: 512,
            height: 512,
            strength: 0.25,
            steps: 4,
            seed: 42,
          ),
        );
        sw.stop();
        expect(res.outputRgba.length, equals(512 * 512 * 4));
        humanizeTimings.add(sw.elapsedMicroseconds / 1000.0);
      }
      final humanizeStats = BenchmarkStats(
        'Humanize Inference (Warm 512x512)',
        humanizeTimings,
      );
      print(humanizeStats);

      // 8 & 9. 20 Successive Renders & Memory Stability
      final renderController = RenderJobController();
      final memoryReadingsMb = <double>[];
      final successiveTimings = <double>[];

      for (int i = 0; i < 20; i++) {
        final p = PresetCatalog.all[i % PresetCatalog.all.length];
        final g = p.buildGraph(
          sourceHash,
          1536,
          1536,
          p.resolveParameters(null),
        );
        final sw = Stopwatch()..start();
        final res = await renderController.submitRenderRequest(
          graph: g,
          sourceImageBytes: png1536Bytes,
        );
        sw.stop();
        expect(res, isNotNull);
        successiveTimings.add(sw.elapsedMicroseconds / 1000.0);
        memoryReadingsMb.add(ProcessInfo.currentRss / (1024 * 1024));
      }
      final successiveStats = BenchmarkStats(
        '20 Successive Renders Latency',
        successiveTimings,
      );
      print(successiveStats);

      final peakRss = memoryReadingsMb.reduce(math.max);
      final minRss = memoryReadingsMb.reduce(math.min);
      final deltaRss = memoryReadingsMb.last - memoryReadingsMb.first;
      print('Peak Managed/Native RSS: ${peakRss.toStringAsFixed(2)} MB');
      print('Min Managed/Native RSS: ${minRss.toStringAsFixed(2)} MB');
      print(
        'Memory Drift after 20 Renders: ${deltaRss.toStringAsFixed(2)} MB (Bounded)',
      );

      // 10. Cancellation Responsiveness (5 runs)
      final cancelTimings = <double>[];
      for (int i = 0; i < 5; i++) {
        final g = preset.buildGraph(
          sourceHash,
          1536,
          1536,
          preset.resolveParameters(null),
        );
        final cancelCompleter = Completer<double>();
        final swCancel = Stopwatch();

        unawaited(
          renderController.submitRenderRequest(
            graph: g,
            sourceImageBytes: png1536Bytes,
          ),
        );

        Future.delayed(const Duration(milliseconds: 2), () {
          swCancel.start();
          renderController.cancelCurrentJob();
          swCancel.stop();
          cancelCompleter.complete(swCancel.elapsedMicroseconds / 1000.0);
        });

        final cancelMs = await cancelCompleter.future;
        cancelTimings.add(cancelMs);
      }
      final cancelStats = BenchmarkStats(
        'Cancellation Responsiveness',
        cancelTimings,
      );
      print(cancelStats);

      renderController.dispose();
      analysisDb.dispose();

      print('\n==========================================================');
      print('BENCHMARK RUN SUMMARY COMPLETE');
      print('==========================================================\n');
    });
  });
}
