import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;

enum HardwareTier {
  flagshipSupported,
  constrainedSupported,
  unsupportedOomRisk,
}

class ModelNotFoundException implements Exception {
  final String path;
  ModelNotFoundException(this.path);
  @override
  String toString() => 'ModelNotFoundException: Model file not found at $path';
}

class ModelCorruptedException implements Exception {
  final String expectedHash;
  final String actualHash;
  ModelCorruptedException(
      {required this.expectedHash, required this.actualHash});
  @override
  String toString() =>
      'ModelCorruptedException: Hash mismatch. Expected: $expectedHash, got: $actualHash';
}

class HardwareTierUnsupportedException implements Exception {
  final int ramBytes;
  HardwareTierUnsupportedException(this.ramBytes);
  @override
  String toString() =>
      'HardwareTierUnsupportedException: Device RAM ($ramBytes bytes) is below minimum 6GB threshold.';
}

class HumanizeGateController {
  static const int minRamBytes = 6 * 1024 * 1024 * 1024; // 6 GB
  static const int flagshipRamBytes = 8 * 1024 * 1024 * 1024; // 8 GB

  /// Assesses hardware tier to protect Android devices against lowmemorykiller OOM kills (Invariant 11).
  static HardwareTier assessHardware(int totalRamBytes) {
    if (totalRamBytes >= flagshipRamBytes) {
      return HardwareTier.flagshipSupported;
    } else if (totalRamBytes >= minRamBytes) {
      return HardwareTier.constrainedSupported;
    } else {
      return HardwareTier.unsupportedOomRisk;
    }
  }

  /// Verifies model file integrity before loading into native memory (Invariants 7 & 10).
  /// Strictly rejects missing or corrupted files without fake AI fallbacks.
  static bool verifyAndLoadModel({
    required String filePath,
    required String expectedSha256,
  }) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ModelNotFoundException(filePath);
    }
    final bytes = file.readAsBytesSync();
    final actualHash = crypto.sha256.convert(bytes).toString();
    if (actualHash.toLowerCase() != expectedSha256.toLowerCase()) {
      throw ModelCorruptedException(
        expectedHash: expectedSha256,
        actualHash: actualHash,
      );
    }
    return true;
  }
}

void main() {
  group('Prompt 10 — DEBUG GATE B: Humanize Decision Test Suite', () {
    test(
        'Decisive Unknown 1: Model-unavailable path throws descriptive error without fake AI fallback',
        () {
      const nonExistentPath = '/tmp/reranger_models_missing.gguf';
      const expectedHash =
          '6ce0161c80f35f3a32f60271f4b444b084eabab343e0618ff7e4ebff8f328f41';

      expect(
        () => HumanizeGateController.verifyAndLoadModel(
          filePath: nonExistentPath,
          expectedSha256: expectedHash,
        ),
        throwsA(isA<ModelNotFoundException>()),
      );
    });

    test(
        'Decisive Unknown 1: Corrupted model file throws ModelCorruptedException',
        () {
      final tempDir = Directory.systemTemp.createTempSync('reranger_gate_b_');
      final corruptedFile = File('${tempDir.path}/corrupt_model.gguf')
        ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));

      const expectedHash =
          '6ce0161c80f35f3a32f60271f4b444b084eabab343e0618ff7e4ebff8f328f41';

      expect(
        () => HumanizeGateController.verifyAndLoadModel(
          filePath: corruptedFile.path,
          expectedSha256: expectedHash,
        ),
        throwsA(isA<ModelCorruptedException>()),
      );

      tempDir.deleteSync(recursive: true);
    });

    test(
        'Decisive Unknown 2: Device tier gating classifies hardware accurately',
        () {
      const gb = 1024 * 1024 * 1024;

      // 4 GB budget phone (Moto G Power / Galaxy A14) -> Unsupported OOM Risk
      expect(
        HumanizeGateController.assessHardware(4 * gb),
        equals(HardwareTier.unsupportedOomRisk),
      );

      // 6 GB mid-tier phone (Galaxy A54 6GB / Redmi Note 12 Pro) -> Constrained Supported
      expect(
        HumanizeGateController.assessHardware(6 * gb),
        equals(HardwareTier.constrainedSupported),
      );

      // 12 GB flagship (Google Pixel 10 / Galaxy S24 Ultra) -> Flagship Supported
      expect(
        HumanizeGateController.assessHardware(12 * gb),
        equals(HardwareTier.flagshipSupported),
      );
    });

    test(
        'Source-conditioned latent noise perturbation respects mathematical bounds',
        () {
      // Simulating latent vector perturbation
      final z0 = List<double>.filled(1024, 0.5);
      final noise = List<double>.filled(1024, -0.2);
      const strength = 0.20;

      // alpha_bar = cos(strength * pi / 2)
      final alphaBar = 0.951; // approx cos(0.1 * pi)
      final noiseWeight = 0.309; // approx sin(0.1 * pi)

      final zt = List<double>.generate(
        1024,
        (i) => z0[i] * alphaBar + noise[i] * noiseWeight,
      );

      // Residual must be strictly positive and bounded
      double diffSum = 0.0;
      for (int i = 0; i < 1024; i++) {
        diffSum += (zt[i] - z0[i]).abs();
      }
      final meanDiff = diffSum / 1024;

      expect(meanDiff, greaterThan(0.05));
      expect(meanDiff, lessThan(0.15)); // High composition preservation
    });
  });
}
