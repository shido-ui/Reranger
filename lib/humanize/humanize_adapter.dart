import 'dart:typed_data';

/// Hardware tier classification defining runtime capabilities and memory headroom.
enum HardwareTier {
  /// >= 8 GB RAM: Full 512x512 resolution supported.
  flagshipSupported,

  /// 6 GB to 8 GB RAM: Constrained 384x384 resolution supported.
  constrainedSupported,

  /// < 6 GB RAM: Strictly gated off to eliminate Android OOM kills (Invariant 11).
  unsupportedOomRisk,
}

/// Granular phases of the local neural refinement pipeline.
enum HumanizeStage {
  idle,
  loadingModel,
  encodingLatents,
  denoising,
  decodingLatents,
  completed,
  cancelled,
  failed,
}

/// Typed representation of exact local capabilities, memory footprints, and licenses.
class HumanizeCapabilities {
  final bool isSupported;
  final HardwareTier hardwareTier;
  final List<int> supportedResolutions;
  final List<String> supportedConditionings;
  final String modelName;
  final String modelVersion;
  final String license;
  final String sha256Checksum;
  final int estimatedMemoryBytes;
  final String? unavailabilityReason;

  const HumanizeCapabilities({
    required this.isSupported,
    required this.hardwareTier,
    required this.supportedResolutions,
    required this.supportedConditionings,
    required this.modelName,
    required this.modelVersion,
    required this.license,
    required this.sha256Checksum,
    required this.estimatedMemoryBytes,
    this.unavailabilityReason,
  });

  Map<String, dynamic> toJson() => {
    'isSupported': isSupported,
    'hardwareTier': hardwareTier.name,
    'supportedResolutions': supportedResolutions,
    'supportedConditionings': supportedConditionings,
    'modelName': modelName,
    'modelVersion': modelVersion,
    'license': license,
    'sha256Checksum': sha256Checksum,
    'estimatedMemoryBytes': estimatedMemoryBytes,
    if (unavailabilityReason != null)
      'unavailabilityReason': unavailabilityReason,
  };
}

/// Immutable input payload for source-conditioned neural refinement.
class HumanizeInput {
  final Uint8List sourceRgba;
  final int width;
  final int height;
  final double strength;
  final String prompt;
  final String negativePrompt;
  final int seed;
  final int steps;
  final double guidanceScale;

  HumanizeInput({
    required this.sourceRgba,
    required this.width,
    required this.height,
    required this.strength,
    this.prompt = '',
    this.negativePrompt = '',
    required this.seed,
    this.steps = 6,
    this.guidanceScale = 1.5,
  }) : assert(
         sourceRgba.length == width * height * 4,
         'Source buffer size must match width * height * 4',
       ),
       assert(
         strength >= 0.0 && strength <= 1.0,
         'Strength must be in range [0.0, 1.0]',
       ),
       assert(steps > 0 && steps <= 30, 'Steps must be in range [1, 30]');
}

/// Real-time progress feedback emitted during neural inference.
class HumanizeProgress {
  final HumanizeStage stage;
  final int step;
  final int totalSteps;
  final double progressFraction;
  final String message;

  const HumanizeProgress({
    required this.stage,
    required this.step,
    required this.totalSteps,
    required this.progressFraction,
    required this.message,
  });
}

/// Output payload from completed neural transformation.
class HumanizeResult {
  final Uint8List outputRgba;
  final int width;
  final int height;
  final int durationMs;
  final int seed;
  final double compositionResidual;
  final String deviceProfile;
  final Map<String, dynamic> metadata;

  const HumanizeResult({
    required this.outputRgba,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.seed,
    required this.compositionResidual,
    required this.deviceProfile,
    this.metadata = const {},
  });
}

/// Outcome of the startup self-test verifying model validity on fixed input.
class SelfTestResult {
  final bool passed;
  final double compositionResidual;
  final int durationMs;
  final String message;

  const SelfTestResult({
    required this.passed,
    required this.compositionResidual,
    required this.durationMs,
    required this.message,
  });
}

/// Cooperative cancellation token enabling immediate inference termination.
class CancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// Base exception for Humanize runtime errors.
abstract class HumanizeException implements Exception {
  final String message;
  const HumanizeException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

class ModelNotFoundException extends HumanizeException {
  final String modelPath;
  const ModelNotFoundException(this.modelPath)
    : super('Model file not found at path: $modelPath');
}

class ModelCorruptedException extends HumanizeException {
  final String expectedHash;
  final String actualHash;
  const ModelCorruptedException({
    required this.expectedHash,
    required this.actualHash,
  }) : super(
         'Model checksum mismatch. Expected: $expectedHash, Actual: $actualHash',
       );
}

class HardwareTierUnsupportedException extends HumanizeException {
  final int ramBytes;
  const HardwareTierUnsupportedException(this.ramBytes)
    : super(
        'Device RAM (${ramBytes ~/ (1024 * 1024)} MB) is below minimum 6GB threshold. '
        'Humanize Studio disabled to prevent lowmemorykiller OOM kills (Invariant 11).',
      );
}

class InferenceCancelledException extends HumanizeException {
  const InferenceCancelledException()
    : super('Humanize neural inference was cancelled by user.');
}

class InsufficientMemoryException extends HumanizeException {
  const InsufficientMemoryException(super.message);
}

class ConcurrentInferenceException extends HumanizeException {
  const ConcurrentInferenceException()
    : super(
        'Concurrent neural inference call rejected. Only one active inference session permitted.',
      );
}

/// Typed abstract contract decoupling UI and domain logic from native engines.
abstract class HumanizeAdapter {
  /// Queries static and dynamic runtime capabilities.
  Future<HumanizeCapabilities> getCapabilities();

  /// Checks if model files exist and are verified.
  Future<bool> isModelAvailable();

  /// Explicitly initializes and loads native model weights.
  Future<void> initializeModel({required String modelPath, String? loraPath});

  /// Releases loaded native weights and clears memory.
  Future<void> unloadModel();

  /// Executes source-conditioned latent refinement.
  Future<HumanizeResult> runInference(
    HumanizeInput input, {
    CancellationToken? cancelToken,
    void Function(HumanizeProgress)? onProgress,
  });

  /// Runs deterministic startup verification on fixed inputs.
  Future<SelfTestResult> runSelfTest();

  /// Called on app lifecycle backgrounding to reclaim volatile memory.
  Future<void> onAppBackgrounded();
}

/// Truthful fallback adapter active when hardware is unsupported or models are unavailable.
/// Strictly enforces Invariant 7 (No Fake AI or Placebo Controls).
class TruthfulUnavailableHumanizeAdapter implements HumanizeAdapter {
  final HardwareTier tier;
  final String reason;

  const TruthfulUnavailableHumanizeAdapter({
    this.tier = HardwareTier.unsupportedOomRisk,
    this.reason = 'Humanize Studio requires at least 6 GB of physical RAM and approved on-device weights.',
  });

  @override
  Future<HumanizeCapabilities> getCapabilities() async {
    return HumanizeCapabilities(
      isSupported: false,
      hardwareTier: tier,
      supportedResolutions: const [],
      supportedConditionings: const [],
      modelName: 'None (Hardware / Weights Gated)',
      modelVersion: 'N/A',
      license: 'N/A',
      sha256Checksum: 'N/A',
      estimatedMemoryBytes: 0,
      unavailabilityReason: reason,
    );
  }

  @override
  Future<bool> isModelAvailable() async => false;

  @override
  Future<void> initializeModel({
    required String modelPath,
    String? loraPath,
  }) async {
    throw HardwareTierUnsupportedException(0);
  }

  @override
  Future<void> unloadModel() async {}

  @override
  Future<HumanizeResult> runInference(
    HumanizeInput input, {
    CancellationToken? cancelToken,
    void Function(HumanizeProgress)? onProgress,
  }) async {
    throw HardwareTierUnsupportedException(0);
  }

  @override
  Future<SelfTestResult> runSelfTest() async {
    return SelfTestResult(
      passed: false,
      compositionResidual: 0.0,
      durationMs: 0,
      message: 'Self-test aborted: $reason',
    );
  }

  @override
  Future<void> onAppBackgrounded() async {}
}
