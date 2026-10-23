import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/core/capabilities/app_capabilities.dart';

void main() {
  group(
    'AppCapabilities Truthful Capability Detection & Gating (Prompt B)',
    () {
      test('Probing device with unknown RAM does not assume flagship (Conservative safety)', () {
        final caps = AppCapabilities.evaluate(
          physicalRamMb: null,
          isModelInstalled: true,
          isRuntimeAvailable: true,
        );

        expect(caps.ramTier, equals(DeviceRamTier.unknown));
        expect(caps.isNeuralHumanizeSupported, isFalse);
        expect(
          caps.humanizeUnavailabilityReason,
          contains('could not be verified'),
        );
      });

      test('Unsupported RAM (< 6144 MB) rejects Humanize to eliminate OOM risk (Invariant 11)', () {
        final caps = AppCapabilities.evaluate(
          physicalRamMb: 4096,
          isModelInstalled: true,
          isRuntimeAvailable: true,
        );

        expect(caps.ramTier, equals(DeviceRamTier.unsupported));
        expect(caps.isNeuralHumanizeSupported, isFalse);
        expect(
          caps.humanizeUnavailabilityReason,
          contains('below the minimum 6 GB threshold'),
        );
      });

      test('Constrained RAM (6144 MB to 8191 MB) reports constrained tier', () {
        final caps = AppCapabilities.evaluate(
          physicalRamMb: 6144,
          isModelInstalled: true,
          isRuntimeAvailable: true,
        );

        expect(caps.ramTier, equals(DeviceRamTier.constrained));
        expect(caps.isNeuralHumanizeSupported, isTrue);
        expect(caps.humanizeUnavailabilityReason, isNull);
      });

      test('Flagship RAM (>= 8192 MB) reports flagship tier', () {
        final caps = AppCapabilities.evaluate(
          physicalRamMb: 12288,
          isModelInstalled: true,
          isRuntimeAvailable: true,
        );

        expect(caps.ramTier, equals(DeviceRamTier.flagship));
        expect(caps.isNeuralHumanizeSupported, isTrue);
        expect(caps.humanizeUnavailabilityReason, isNull);
      });

      test(
        'Missing model weights gate Humanize studio with actionable reason',
        () {
          final caps = AppCapabilities.evaluate(
            physicalRamMb: 12288,
            isModelInstalled: false, // Model not installed
            isRuntimeAvailable: true,
          );

          expect(caps.isNeuralHumanizeSupported, isFalse);
          expect(
            caps.humanizeUnavailabilityReason,
            contains('model weights are not installed'),
          );
        },
      );

      test(
        'Missing runtime backend gates Humanize studio with actionable reason',
        () {
          final caps = AppCapabilities.evaluate(
            physicalRamMb: 12288,
            isModelInstalled: true,
            isRuntimeAvailable: false, // Runtime missing
          );

          expect(caps.isNeuralHumanizeSupported, isFalse);
          expect(
            caps.humanizeUnavailabilityReason,
            contains('runtime backend is not installed'),
          );
        },
      );

      test('Unsupported ABI (e.g. armeabi-v7a) gates inference', () {
        final caps = AppCapabilities.evaluate(
          physicalRamMb: 12288,
          isModelInstalled: true,
          isRuntimeAvailable: true,
          activeAbi: 'armeabi-v7a',
        );

        expect(caps.isNeuralHumanizeSupported, isFalse);
        expect(
          caps.humanizeUnavailabilityReason,
          contains('CPU architecture (armeabi-v7a) is not supported'),
        );
      });

      test('Conservative memory footprint calculator accounts for model weights, latents, and native heap', () {
        final footprint512 = AppCapabilities.estimateInferenceFootprintBytes(
          width: 512,
          height: 512,
        );

        // Must be at least 2 GB (~2.18 GB) to account for 1.75GB weights + buffers
        expect(footprint512, greaterThan(2 * 1024 * 1024 * 1024));
      });
    },
  );
}
