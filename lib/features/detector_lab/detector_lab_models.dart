import 'dart:typed_data';

/// Provenance status indicating C2PA metadata detection.
///
/// Invariant 7: Honest Provenance & Signal Inspection.
/// Raw byte marker matching detects the physical presence of a C2PA JUMBF container,
/// but does NOT validate cryptographic trust chains or X.509 signatures without
/// an on-device PKI trust root. Status is truthfully declared.
enum C2paStatus {
  manifestContainerDetectedUnverified,
  invalid,
  missing;

  @Deprecated(
    'Use manifestContainerDetectedUnverified for truthful provenance reporting',
  )
  static const C2paStatus valid = manifestContainerDetectedUnverified;

  String get label {
    switch (this) {
      case C2paStatus.manifestContainerDetectedUnverified:
        return 'Metadata marker present; cryptographic signature not verified';
      case C2paStatus.invalid:
        return 'Corrupt or Malformed C2PA Box';
      case C2paStatus.missing:
        return 'No supported provenance signal found.';
    }
  }
}

/// Parsed provenance result describing embedded cryptographic provenance.
class C2paProvenanceResult {
  final C2paStatus status;
  final String? manifestIssuer;
  final String message;

  const C2paProvenanceResult({
    required this.status,
    this.manifestIssuer,
    required this.message,
  });

  /// True if raw metadata marker sequence was located in media bytes.
  bool get isContainerDetected =>
      status == C2paStatus.manifestContainerDetectedUnverified;

  /// Cryptographic signature verification is strictly false for raw byte marker inspection.
  bool get isSignatureVerified => false;

  @Deprecated(
    'A raw byte marker does not verify a signature. Use isContainerDetected instead.',
  )
  bool get isValid => false;

  bool get isMissing => status == C2paStatus.missing;
}

/// Read-only parser inspecting binary media for C2PA / JUMBF metadata boxes.
class C2paParser {
  // ISO/IEC 19566-5 JUMBF 'jumb' box type: [0x6a, 0x75, 0x6d, 0x62]
  static const List<int> jumbMagic = [0x6a, 0x75, 0x6d, 0x62];
  // C2PA content type magic: 'c2pa' [0x63, 0x32, 0x70, 0x61]
  static const List<int> c2paMagic = [0x63, 0x32, 0x70, 0x61];
  // Corrupt marker simulation tag: 'c2xx'
  static const List<int> corruptMagic = [0x63, 0x32, 0x78, 0x78];

  /// Parses bytes for standard C2PA / JUMBF boxes.
  static C2paProvenanceResult parseBytes(Uint8List bytes) {
    if (bytes.length < 8) {
      return const C2paProvenanceResult(
        status: C2paStatus.missing,
        message: 'No supported provenance signal found.',
      );
    }

    // Check for corrupt signature simulation
    if (_indexOfSequence(bytes, corruptMagic) != -1) {
      return const C2paProvenanceResult(
        status: C2paStatus.invalid,
        message: 'Corrupt or unreadable C2PA metadata box.',
      );
    }

    // Check for standard C2PA signature
    final c2paIdx = _indexOfSequence(bytes, c2paMagic);
    final jumbIdx = _indexOfSequence(bytes, jumbMagic);

    if (c2paIdx != -1 || jumbIdx != -1) {
      // Validate minimum header structure around match
      final matchIdx = c2paIdx != -1 ? c2paIdx : jumbIdx;
      if (matchIdx + 8 <= bytes.length) {
        return const C2paProvenanceResult(
          status: C2paStatus.manifestContainerDetectedUnverified,
          manifestIssuer: null,
          message: 'Metadata marker present; cryptographic signature not verified (requires on-device PKI trust root).',
        );
      } else {
        return const C2paProvenanceResult(
          status: C2paStatus.invalid,
          message: 'Truncated C2PA metadata segment.',
        );
      }
    }

    return const C2paProvenanceResult(
      status: C2paStatus.missing,
      message: 'No supported provenance signal found.',
    );
  }

  static int _indexOfSequence(Uint8List haystack, List<int> needle) {
    if (needle.isEmpty || haystack.length < needle.length) return -1;
    for (int i = 0; i <= haystack.length - needle.length; i++) {
      bool match = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

/// Single image prediction output from a detector adapter.
class DetectorPrediction {
  final String imageId;
  final bool isGroundTruthAi;
  final double aiConfidence; // Score in [0.0, 1.0]
  final bool isFlaggedAsAi;
  final C2paProvenanceResult provenance;

  const DetectorPrediction({
    required this.imageId,
    required this.isGroundTruthAi,
    required this.aiConfidence,
    required this.isFlaggedAsAi,
    required this.provenance,
  });
}

/// Abstract contract for an AI detector evaluation adapter.
abstract class DetectorAdapter {
  String get name;
  String get version;

  Future<DetectorPrediction> evaluateImage({
    required String imageId,
    required Uint8List bytes,
    required bool isGroundTruthAi,
    double decisionThreshold = 0.5,
  });
}

/// [TEST-ONLY] Mock detector simulating synthetic classifier outputs for harness testing.
///
/// IMPORTANT (Invariant 7 & Product Prompt 5): This adapter is NOT an AI detector and does
/// not evaluate image pixels. Scores are synthetic values derived from test fixture labels
/// for testing the benchmark runner. It must never be presented as an actual detector.
class MockDetectorAdapter implements DetectorAdapter {
  @override
  final String name;
  @override
  final String version;

  final Map<String, double>? fixedConfidenceScores;

  MockDetectorAdapter({
    this.name = '[TEST ONLY] Synthetic Classifier Simulation',
    this.version = '1.0.0',
    this.fixedConfidenceScores,
  });

  @override
  Future<DetectorPrediction> evaluateImage({
    required String imageId,
    required Uint8List bytes,
    required bool isGroundTruthAi,
    double decisionThreshold = 0.5,
  }) async {
    final provenance = C2paParser.parseBytes(bytes);

    double score;
    if (fixedConfidenceScores != null &&
        fixedConfidenceScores!.containsKey(imageId)) {
      score = fixedConfidenceScores![imageId]!;
    } else {
      // Deterministic scoring baseline: AI images typically score high (~0.85), Real low (~0.15)
      score = isGroundTruthAi ? 0.88 : 0.12;
    }

    final isFlagged = score >= decisionThreshold;

    return DetectorPrediction(
      imageId: imageId,
      isGroundTruthAi: isGroundTruthAi,
      aiConfidence: score,
      isFlaggedAsAi: isFlagged,
      provenance: provenance,
    );
  }
}

/// Aggregated statistical evaluation results for a benchmark run.
class BenchmarkMetrics {
  final int totalImages;
  final int flaggedAsAi;
  final int flaggedAsReal;
  final int truePositives; // Actual AI, Flagged AI
  final int falsePositives; // Actual Real, Flagged AI (False Alarm)
  final int trueNegatives; // Actual Real, Flagged Real
  final int falseNegatives; // Actual AI, Flagged Real (Miss)
  final double falsePositiveRate; // FPR = FP / (FP + TN)
  final double falseNegativeRate; // FNR = FN / (FN + TP)
  final double accuracy;
  final double auroc; // Area Under the ROC Curve
  final int c2paValidCount;
  final int c2paInvalidCount;
  final int c2paMissingCount;

  const BenchmarkMetrics({
    required this.totalImages,
    required this.flaggedAsAi,
    required this.flaggedAsReal,
    required this.truePositives,
    required this.falsePositives,
    required this.trueNegatives,
    required this.falseNegatives,
    required this.falsePositiveRate,
    required this.falseNegativeRate,
    required this.accuracy,
    required this.auroc,
    required this.c2paValidCount,
    required this.c2paInvalidCount,
    required this.c2paMissingCount,
  });

  /// Computes exact statistical classification metrics.
  factory BenchmarkMetrics.calculate(
    List<DetectorPrediction> predictions, {
    double decisionThreshold = 0.5,
  }) {
    if (predictions.isEmpty) {
      return const BenchmarkMetrics(
        totalImages: 0,
        flaggedAsAi: 0,
        flaggedAsReal: 0,
        truePositives: 0,
        falsePositives: 0,
        trueNegatives: 0,
        falseNegatives: 0,
        falsePositiveRate: 0.0,
        falseNegativeRate: 0.0,
        accuracy: 0.0,
        auroc: 0.5,
        c2paValidCount: 0,
        c2paInvalidCount: 0,
        c2paMissingCount: 0,
      );
    }

    int tp = 0;
    int fp = 0;
    int tn = 0;
    int fn = 0;
    int validC2pa = 0;
    int invalidC2pa = 0;
    int missingC2pa = 0;

    final List<double> positiveScores = [];
    final List<double> negativeScores = [];

    for (final p in predictions) {
      final flagged = p.aiConfidence >= decisionThreshold;
      if (p.isGroundTruthAi) {
        positiveScores.add(p.aiConfidence);
        if (flagged) {
          tp++;
        } else {
          fn++;
        }
      } else {
        negativeScores.add(p.aiConfidence);
        if (flagged) {
          fp++;
        } else {
          tn++;
        }
      }

      switch (p.provenance.status) {
        case C2paStatus.manifestContainerDetectedUnverified:
          validC2pa++;
          break;
        case C2paStatus.invalid:
          invalidC2pa++;
          break;
        case C2paStatus.missing:
          missingC2pa++;
          break;
      }
    }

    final total = predictions.length;
    final totalReal = fp + tn;
    final totalAi = tp + fn;

    final fpr = totalReal > 0 ? (fp / totalReal) : 0.0;
    final fnr = totalAi > 0 ? (fn / totalAi) : 0.0;
    final accuracy = total > 0 ? ((tp + tn) / total) : 0.0;

    // Exact Wilcoxon-Mann-Whitney rank-sum AUROC calculation
    double auroc = 0.5;
    if (positiveScores.isNotEmpty && negativeScores.isNotEmpty) {
      double concordant = 0.0;
      for (final pScore in positiveScores) {
        for (final nScore in negativeScores) {
          if (pScore > nScore) {
            concordant += 1.0;
          } else if (pScore == nScore) {
            concordant += 0.5;
          }
        }
      }
      auroc = concordant / (positiveScores.length * negativeScores.length);
    }

    return BenchmarkMetrics(
      totalImages: total,
      flaggedAsAi: tp + fp,
      flaggedAsReal: tn + fn,
      truePositives: tp,
      falsePositives: fp,
      trueNegatives: tn,
      falseNegatives: fn,
      falsePositiveRate: fpr,
      falseNegativeRate: fnr,
      accuracy: accuracy,
      auroc: auroc,
      c2paValidCount: validC2pa,
      c2paInvalidCount: invalidC2pa,
      c2paMissingCount: missingC2pa,
    );
  }
}

/// Test image representation for the benchmark evaluation harness.
class TestImageItem {
  final String id;
  final String path;
  final Uint8List bytes;
  final bool isGroundTruthAi;

  const TestImageItem({
    required this.id,
    required this.path,
    required this.bytes,
    required this.isGroundTruthAi,
  });
}

/// Evaluation runner testing local images against detector adapters.
class EvaluationRunner {
  Future<BenchmarkMetrics> runEvaluation({
    required List<TestImageItem> images,
    required DetectorAdapter adapter,
    double decisionThreshold = 0.5,
    void Function(double progress, String currentId)? onProgress,
  }) async {
    final List<DetectorPrediction> predictions = [];
    final total = images.length;

    for (int i = 0; i < total; i++) {
      final img = images[i];
      if (onProgress != null) {
        onProgress((i + 1) / total, img.id);
      }

      final prediction = await adapter.evaluateImage(
        imageId: img.id,
        bytes: img.bytes,
        isGroundTruthAi: img.isGroundTruthAi,
        decisionThreshold: decisionThreshold,
      );
      predictions.add(prediction);
    }

    return BenchmarkMetrics.calculate(
      predictions,
      decisionThreshold: decisionThreshold,
    );
  }
}
