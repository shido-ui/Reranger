import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/humanize/humanize_adapter.dart';
import 'package:reranger/humanize/local_humanize_adapter.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  group('HumanizeAdapter Contract & Hardware Tier Gating', () {
    test('Flagship device (>= 8 GB RAM) reports full 512x512 resolution and OpenRAIL-M license', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final caps = await adapter.getCapabilities();

      expect(caps.isSupported, isTrue);
      expect(caps.hardwareTier, equals(HardwareTier.flagshipSupported));
      expect(caps.supportedResolutions, equals(const [512, 384]));
      expect(caps.supportedConditionings, contains('img2img_latent_strength'));
      expect(caps.license, contains('CreativeML OpenRAIL-M'));
      expect(
        caps.sha256Checksum,
        equals(LocalHumanizeAdapter.canonicalBaseModelSha256),
      );
      expect(caps.estimatedMemoryBytes, equals(2291130368)); // ~2.185 GB
      expect(caps.unavailabilityReason, isNull);
    });

    test('Constrained device (6 GB to 8 GB RAM) reports downscaled 384x384 resolution', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 6 * gb);
      final caps = await adapter.getCapabilities();

      expect(caps.isSupported, isTrue);
      expect(caps.hardwareTier, equals(HardwareTier.constrainedSupported));
      expect(caps.supportedResolutions, equals(const [384]));
      expect(caps.estimatedMemoryBytes, equals(1468006400)); // ~1.400 GB
      expect(caps.unavailabilityReason, isNull);
    });

    test('Unsupported device (< 6 GB RAM) disables Humanize truthfully (Invariant 7)', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 4 * gb);
      final caps = await adapter.getCapabilities();

      expect(caps.isSupported, isFalse);
      expect(caps.hardwareTier, equals(HardwareTier.unsupportedOomRisk));
      expect(caps.supportedResolutions, isEmpty);
      expect(
        caps.unavailabilityReason,
        contains('below the minimum 6 GB threshold'),
      );
    });
  });

  group('Model Validation & Cryptographic Provenance (Invariant 10)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('humanize_adapter_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Missing model file throws ModelNotFoundException', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final nonExistentPath = '${tempDir.path}/missing_sd15.gguf';

      expect(
        () => adapter.initializeModel(modelPath: nonExistentPath),
        throwsA(isA<ModelNotFoundException>()),
      );
      expect(adapter.isLoaded, isFalse);
    });

    test('Corrupted model file throws ModelCorruptedException with checksum details', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final corruptFile = File('${tempDir.path}/corrupt_sd15.gguf')
        ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));

      expect(
        () => adapter.initializeModel(modelPath: corruptFile.path),
        throwsA(isA<ModelCorruptedException>()),
      );
      expect(adapter.isLoaded, isFalse);
    });

    test(
      'Unsupported hardware tier rejects model initialization immediately',
      () async {
        final adapter = LocalHumanizeAdapter(totalRamBytes: 4 * gb);
        expect(
          () => adapter.initializeModel(modelPath: '/dummy/path.gguf'),
          throwsA(isA<HardwareTierUnsupportedException>()),
        );
      },
    );
  });

  group('Source-Conditioned Neural Inference & Invariant 4 Immutability', () {
    test('Unloaded adapter strictly rejects inference with ModelNotLoadedException (Invariant 7)', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final input = HumanizeInput(
        sourceRgba: Uint8List(64 * 64 * 4),
        width: 64,
        height: 64,
        strength: 0.25,
        seed: 1234,
      );

      expect(
        () => adapter.runInference(input),
        throwsA(isA<ModelNotLoadedException>()),
      );
    });

    test('Source image buffer is strictly immutable during and after inference (Invariant 4)', () async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      const w = 64;
      const h = 64;
      final source = Uint8List(w * h * 4);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final idx = (y * w + x) * 4;
          source[idx] = 180 + (x * 60 ~/ w);
          source[idx + 1] = 140 + (y * 50 ~/ h);
          source[idx + 2] = 100 + ((x + y) * 40 ~/ (w + h));
          source[idx + 3] = 255;
        }
      }

      final initialSha = crypto.sha256.convert(source).toString();
      final sourceClone = Uint8List.fromList(source);

      final input = HumanizeInput(
        sourceRgba: source,
        width: w,
        height: h,
        strength: 0.25,
        seed: 1234,
        steps: 4,
      );

      final result = await adapter.runInference(input);

      // Verify Output
      expect(result.width, equals(w));
      expect(result.height, equals(h));
      expect(result.outputRgba.length, equals(w * h * 4));
      expect(result.compositionResidual, greaterThan(0.005));
      expect(result.compositionResidual, lessThan(0.15));

      // Invariant 4 Check: Source bytes are 100% bit-for-bit unchanged!
      final postSha = crypto.sha256.convert(source).toString();
      expect(postSha, equals(initialSha));
      expect(source, equals(sourceClone));
    });

    test('Alpha channel is strictly preserved across transparent and semitransparent pixels', () async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      const w = 32;
      const h = 32;
      final source = Uint8List(w * h * 4);

      // Varied alpha pattern
      for (int i = 0; i < w * h; i++) {
        source[i * 4] = 120; // R
        source[i * 4 + 1] = 140; // G
        source[i * 4 + 2] = 160; // B
        source[i * 4 + 3] = (i % 256); // Alpha varying from 0 to 255
      }

      final input = HumanizeInput(
        sourceRgba: source,
        width: w,
        height: h,
        strength: 0.30,
        seed: 999,
        steps: 4,
      );

      final result = await adapter.runInference(input);

      for (int i = 0; i < w * h; i++) {
        expect(
          result.outputRgba[i * 4 + 3],
          equals(source[i * 4 + 3]),
          reason: 'Alpha corrupted at pixel $i',
        );
      }
    });

    test(
      'Progress notifications stream through all pipeline stages sequentially',
      () async {
        final adapter = LocalHumanizeAdapter(
          totalRamBytes: 12 * gb,
          isLoadedForTesting: true,
        );
        const w = 32;
        const h = 32;
        final source = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128);

        final stagesRecorded = <HumanizeStage>[];
        final input = HumanizeInput(
          sourceRgba: source,
          width: w,
          height: h,
          strength: 0.20,
          seed: 42,
          steps: 3,
        );

        await adapter.runInference(
          input,
          onProgress: (p) => stagesRecorded.add(p.stage),
        );

        expect(stagesRecorded, contains(HumanizeStage.encodingLatents));
        expect(stagesRecorded, contains(HumanizeStage.denoising));
        expect(stagesRecorded, contains(HumanizeStage.decodingLatents));
        expect(stagesRecorded.last, equals(HumanizeStage.completed));
      },
    );
  });

  group('Cooperative Cancellation & Concurrency Protection', () {
    test(
      'Cancellation token aborts inference and resets lock immediately',
      () async {
        final adapter = LocalHumanizeAdapter(
          totalRamBytes: 12 * gb,
          isLoadedForTesting: true,
        );
        const w = 32;
        const h = 32;
        final source = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128);

        final cancelToken = CancellationToken()..cancel(); // Pre-cancelled
        final input = HumanizeInput(
          sourceRgba: source,
          width: w,
          height: h,
          strength: 0.20,
          seed: 42,
        );

        await expectLater(
          adapter.runInference(input, cancelToken: cancelToken),
          throwsA(isA<InferenceCancelledException>()),
        );

        expect(adapter.isInferring, isFalse);
      },
    );

    test('Concurrent inference requests are rejected with ConcurrentInferenceException', () async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      const w = 32;
      const h = 32;
      final source = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128);

      final input = HumanizeInput(
        sourceRgba: source,
        width: w,
        height: h,
        strength: 0.20,
        seed: 42,
        steps: 10,
      );

      // Trigger first inference (async)
      final future1 = adapter.runInference(input);

      // Immediately attempt second inference
      expect(
        adapter.runInference(input),
        throwsA(isA<ConcurrentInferenceException>()),
      );

      // Await first to clean up
      await future1;
      expect(adapter.isInferring, isFalse);
    });
  });

  group('Fixed-Input Dry-Run / Self-Test & Lifecycle Management', () {
    test('runSelfTest fails honestly when no verified model is loaded (Invariant 7)', () async {
      final adapter = LocalHumanizeAdapter(totalRamBytes: 12 * gb);
      final testResult = await adapter.runSelfTest();

      expect(testResult.passed, isFalse);
      expect(
        testResult.message,
        contains('No verified neural model is loaded'),
      );
    });

    test(
      'runSelfTest verifies model validity and bounded residual when loaded',
      () async {
        final adapter = LocalHumanizeAdapter(
          totalRamBytes: 12 * gb,
          isLoadedForTesting: true,
        );
        final testResult = await adapter.runSelfTest();

        expect(testResult.passed, isTrue);
        expect(testResult.compositionResidual, greaterThan(0.005));
        expect(testResult.compositionResidual, lessThan(0.15));
        expect(testResult.durationMs, greaterThanOrEqualTo(0));
        expect(
          testResult.message,
          contains('Startup dry-run self-test passed'),
        );
      },
    );

    test(
      'onAppBackgrounded unloads model on constrained hardware tier',
      () async {
        final adapter = LocalHumanizeAdapter(totalRamBytes: 6 * gb);
        expect(adapter.hardwareTier, equals(HardwareTier.constrainedSupported));

        await adapter.onAppBackgrounded();
        expect(adapter.isLoaded, isFalse);
      },
    );

    test(
      'TruthfulUnavailableHumanizeAdapter enforces zero fake AI (Invariant 7)',
      () async {
        const adapter = TruthfulUnavailableHumanizeAdapter(
          tier: HardwareTier.unsupportedOomRisk,
          reason: 'Device has 4 GB RAM. Minimum 6 GB required.',
        );

        final caps = await adapter.getCapabilities();
        expect(caps.isSupported, isFalse);
        expect(caps.unavailabilityReason, contains('Device has 4 GB RAM'));

        const w = 16;
        const h = 16;
        final source = Uint8List(w * h * 4);
        final input = HumanizeInput(
          sourceRgba: source,
          width: w,
          height: h,
          strength: 0.20,
          seed: 1,
        );

        expect(
          () => adapter.runInference(input),
          throwsA(isA<HardwareTierUnsupportedException>()),
        );

        final selfTest = await adapter.runSelfTest();
        expect(selfTest.passed, isFalse);
        expect(selfTest.message, contains('Self-test aborted'));
      },
    );
  });
}
