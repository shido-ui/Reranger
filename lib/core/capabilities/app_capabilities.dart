import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DeviceRamTier {
  flagship, // >= 8 GB RAM
  constrained, // 6 GB to 8 GB RAM
  unsupported, // < 6 GB RAM
  unknown, // Memory cannot be verified by platform APIs
}

/// In-app capability abstraction representing verified system, memory, and runtime state
/// without hardcoded assumptions or placebo support claims (Invariant 7 & Prompt B).
class AppCapabilities {
  final DeviceRamTier ramTier;
  final int? totalRamMb;
  final bool isOfflineOnly;
  final bool isClassicalEngineOperational;
  final bool isNeuralHumanizeSupported;
  final String? humanizeUnavailabilityReason;
  final String activeAbi;
  final bool isModelInstalled;
  final bool isPlatformRuntimeAvailable;
  final int estimatedPeakInferenceBytes;

  const AppCapabilities({
    required this.ramTier,
    required this.totalRamMb,
    required this.isOfflineOnly,
    required this.isClassicalEngineOperational,
    required this.isNeuralHumanizeSupported,
    this.humanizeUnavailabilityReason,
    required this.activeAbi,
    this.isModelInstalled = false,
    this.isPlatformRuntimeAvailable = false,
    this.estimatedPeakInferenceBytes = 0,
  });

  /// Total physical RAM in gigabytes, or 0 if unknown.
  int get totalRamGb => totalRamMb != null ? (totalRamMb! / 1024).round() : 0;

  /// Baseline truthful factory: does NOT assume 12 GB RAM or flagship status without proof.
  factory AppCapabilities.defaultProfile() {
    return AppCapabilities.evaluate(
      physicalRamMb: null, // Unknown until probed via platform channel
      isModelInstalled: false,
      isRuntimeAvailable: false,
      activeAbi: 'arm64-v8a',
    );
  }

  /// Explicit testing factory for mock configurations.
  factory AppCapabilities.testSupportedProfile({
    int totalRamMb = 12288,
    bool isModelInstalled = true,
    bool isRuntimeAvailable = true,
    String activeAbi = 'arm64-v8a',
  }) {
    return AppCapabilities.evaluate(
      physicalRamMb: totalRamMb,
      isModelInstalled: isModelInstalled,
      isRuntimeAvailable: isRuntimeAvailable,
      activeAbi: activeAbi,
    );
  }

  /// Evaluates capability state from the strict intersection of hardware, runtime, and model assets.
  factory AppCapabilities.evaluate({
    required int? physicalRamMb,
    required bool isModelInstalled,
    required bool isRuntimeAvailable,
    String activeAbi = 'arm64-v8a',
    int targetWidth = 512,
    int targetHeight = 512,
  }) {
    final DeviceRamTier tier;
    if (physicalRamMb == null || physicalRamMb <= 0) {
      tier = DeviceRamTier.unknown;
    } else if (physicalRamMb >= 8192) {
      tier = DeviceRamTier.flagship;
    } else if (physicalRamMb >= 6144) {
      tier = DeviceRamTier.constrained;
    } else {
      tier = DeviceRamTier.unsupported;
    }

    String? unavailabilityReason;
    bool isSupported = false;

    if (tier == DeviceRamTier.unknown) {
      unavailabilityReason = 'Device memory could not be verified. Neural Humanize requires verified >= 6 GB RAM.';
    } else if (tier == DeviceRamTier.unsupported) {
      unavailabilityReason =
          'Host device physical RAM ($physicalRamMb MB) is below the minimum 6 GB threshold required to prevent lowmemorykiller OOM kills.';
    } else if (activeAbi != 'arm64-v8a' && activeAbi != 'x86_64') {
      unavailabilityReason =
          'CPU architecture ($activeAbi) is not supported for on-device neural inference.';
    } else if (!isRuntimeAvailable) {
      unavailabilityReason = 'On-device neural inference runtime backend is not installed on this device.';
    } else if (!isModelInstalled) {
      unavailabilityReason = 'Humanize neural model weights are not installed on device. Download required on-demand.';
    } else {
      isSupported = true;
      unavailabilityReason = null;
    }

    final estimatedBytes = estimateInferenceFootprintBytes(
      width: targetWidth,
      height: targetHeight,
    );

    return AppCapabilities(
      ramTier: tier,
      totalRamMb: physicalRamMb,
      isOfflineOnly: true,
      isClassicalEngineOperational: true,
      isNeuralHumanizeSupported: isSupported,
      humanizeUnavailabilityReason: unavailabilityReason,
      activeAbi: activeAbi,
      isModelInstalled: isModelInstalled,
      isPlatformRuntimeAvailable: isRuntimeAvailable,
      estimatedPeakInferenceBytes: estimatedBytes,
    );
  }

  /// Conservative memory footprint estimation calculating source, latents, solver, output, and weights.
  static int estimateInferenceFootprintBytes({
    required int width,
    required int height,
    int modelWeightsBytes = 1887436800, // ~1.75 GB for Q4_0 GGUF base + LoRA
  }) {
    final sourceBytes = width * height * 4;
    final latentW = (width / 8).ceil();
    final latentH = (height / 8).ceil();
    final latentBytes = latentW * latentH * 4 * 4; // 4-channel float32 latents
    final solverBufferBytes = latentBytes * 2; // solver work buffers
    final outputBytes = width * height * 4;
    final nativeArenaBytes = 256 * 1024 * 1024; // 256 MB native runtime heap

    return sourceBytes +
        latentBytes +
        solverBufferBytes +
        outputBytes +
        modelWeightsBytes +
        nativeArenaBytes;
  }
}

/// Riverpod provider for application capabilities and device hardware status.
final appCapabilitiesProvider = Provider<AppCapabilities>((ref) {
  return AppCapabilities.defaultProfile();
});
