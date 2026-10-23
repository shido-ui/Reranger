import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/features/detector_lab/detector_lab_models.dart';

void main() {
  group('Batch B: Detector Robustness Lab & C2PA Provenance Tests', () {
    test(
      'C2PA Parser correctly identifies Valid, Invalid, and Missing states',
      () {
        // 1. Missing C2PA
        final emptyBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
        final missingResult = C2paParser.parseBytes(emptyBytes);
        expect(missingResult.status, equals(C2paStatus.missing));
        expect(
          missingResult.message,
          equals('No supported provenance signal found.'),
        );

        // 2. Valid C2PA Manifest
        final validBytes = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE1, // JPEG SOI + APP1
          ...C2paParser.c2paMagic, // 'c2pa'
          0x00,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
        ]);
        final validResult = C2paParser.parseBytes(validBytes);
        expect(validResult.status, equals(C2paStatus.valid));
        expect(validResult.isValid, isTrue);
        expect(
          validResult.manifestIssuer,
          equals('urn:c2pa:reranger-provenance-authority'),
        );

        // 3. Corrupt C2PA Box
        final corruptBytes = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE1,
          ...C2paParser.corruptMagic, // 'c2xx'
          0x00,
          0x01,
        ]);
        final corruptResult = C2paParser.parseBytes(corruptBytes);
        expect(corruptResult.status, equals(C2paStatus.invalid));
        expect(corruptResult.message, contains('Corrupt'));
      },
    );

    test('BenchmarkMetrics accurately computes FPR, FNR, and AUROC on known 10-image fixture set', () async {
      // Known 10-image fixture set: 5 Real images, 5 AI images
      // Set fixed confidence scores with known distribution:
      // Real images (0 to 4):
      //   img_real_1: 0.10 (True Negative)
      //   img_real_2: 0.20 (True Negative)
      //   img_real_3: 0.30 (True Negative)
      //   img_real_4: 0.40 (True Negative)
      //   img_real_5: 0.70 (False Positive! Flagged AI at threshold 0.5)
      // AI images (5 to 9):
      //   img_ai_1: 0.40 (False Negative! Flagged Real at threshold 0.5)
      //   img_ai_2: 0.80 (True Positive)
      //   img_ai_3: 0.85 (True Positive)
      //   img_ai_4: 0.90 (True Positive)
      //   img_ai_5: 0.95 (True Positive)

      final mockScores = <String, double>{
        'img_real_1': 0.10,
        'img_real_2': 0.20,
        'img_real_3': 0.30,
        'img_real_4': 0.40,
        'img_real_5': 0.70,
        'img_ai_1': 0.40,
        'img_ai_2': 0.80,
        'img_ai_3': 0.85,
        'img_ai_4': 0.90,
        'img_ai_5': 0.95,
      };

      final testImages = <TestImageItem>[
        // 5 Real
        TestImageItem(
          id: 'img_real_1',
          path: '/test/real1.png',
          bytes: Uint8List(16),
          isGroundTruthAi: false,
        ),
        TestImageItem(
          id: 'img_real_2',
          path: '/test/real2.png',
          bytes: Uint8List(16),
          isGroundTruthAi: false,
        ),
        TestImageItem(
          id: 'img_real_3',
          path: '/test/real3.png',
          bytes: Uint8List(16),
          isGroundTruthAi: false,
        ),
        TestImageItem(
          id: 'img_real_4',
          path: '/test/real4.png',
          bytes: Uint8List(16),
          isGroundTruthAi: false,
        ),
        TestImageItem(
          id: 'img_real_5',
          path: '/test/real5.png',
          bytes: Uint8List(16),
          isGroundTruthAi: false,
        ),
        // 5 AI
        TestImageItem(
          id: 'img_ai_1',
          path: '/test/ai1.png',
          bytes: Uint8List(16),
          isGroundTruthAi: true,
        ),
        TestImageItem(
          id: 'img_ai_2',
          path: '/test/ai2.png',
          bytes: Uint8List.fromList([
            ...C2paParser.c2paMagic,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
          ]),
          isGroundTruthAi: true,
        ),
        TestImageItem(
          id: 'img_ai_3',
          path: '/test/ai3.png',
          bytes: Uint8List.fromList([
            ...C2paParser.c2paMagic,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
          ]),
          isGroundTruthAi: true,
        ),
        TestImageItem(
          id: 'img_ai_4',
          path: '/test/ai4.png',
          bytes: Uint8List(16),
          isGroundTruthAi: true,
        ),
        TestImageItem(
          id: 'img_ai_5',
          path: '/test/ai5.png',
          bytes: Uint8List(16),
          isGroundTruthAi: true,
        ),
      ];

      final adapter = MockDetectorAdapter(
        name: 'Mock Classifier v1',
        fixedConfidenceScores: mockScores,
      );

      final runner = EvaluationRunner();
      final progressUpdates = <double>[];

      final metrics = await runner.runEvaluation(
        images: testImages,
        adapter: adapter,
        decisionThreshold: 0.5,
        onProgress: (p, _) => progressUpdates.add(p),
      );

      // Verification of known exact metrics:
      // Total images: 10
      expect(metrics.totalImages, equals(10));
      expect(progressUpdates.length, equals(10));
      expect(progressUpdates.last, equals(1.0));

      // Real: 5 total -> 4 TN (real 1, 2, 3, 4), 1 FP (real 5 with 0.70)
      expect(metrics.trueNegatives, equals(4));
      expect(metrics.falsePositives, equals(1));
      // FPR = FP / (FP + TN) = 1 / (1 + 4) = 0.20 (20%)
      expect(metrics.falsePositiveRate, closeTo(0.20, 1e-4));

      // AI: 5 total -> 4 TP (ai 2, 3, 4, 5), 1 FN (ai 1 with 0.40)
      expect(metrics.truePositives, equals(4));
      expect(metrics.falseNegatives, equals(1));
      // FNR = FN / (FN + TP) = 1 / (1 + 4) = 0.20 (20%)
      expect(metrics.falseNegativeRate, closeTo(0.20, 1e-4));

      // Flagged counts:
      // Flagged AI = TP (4) + FP (1) = 5
      expect(metrics.flaggedAsAi, equals(5));
      // Flagged Real = TN (4) + FN (1) = 5
      expect(metrics.flaggedAsReal, equals(5));
      // Accuracy = (TP + TN) / Total = (4 + 4) / 10 = 0.80 (80%)
      expect(metrics.accuracy, closeTo(0.80, 1e-4));

      // AUROC Calculation:
      // Pairs (ai_score, real_score):
      // ai_1 (0.40): vs (0.10: >), (0.20: >), (0.30: >), (0.40: ==), (0.70: <) -> 3.5 concordant
      // ai_2 (0.80): vs (0.10, 0.20, 0.30, 0.40, 0.70: all >) -> 5.0 concordant
      // ai_3 (0.85): vs (0.10, 0.20, 0.30, 0.40, 0.70: all >) -> 5.0 concordant
      // ai_4 (0.90): vs all > -> 5.0 concordant
      // ai_5 (0.95): vs all > -> 5.0 concordant
      // Total concordant = 3.5 + 5 + 5 + 5 + 5 = 23.5
      // Total pairs = 5 * 5 = 25
      // AUROC = 23.5 / 25 = 0.94
      expect(metrics.auroc, closeTo(0.94, 1e-4));

      // C2PA counts:
      // img_ai_2 and img_ai_3 have valid C2PA headers
      expect(metrics.c2paValidCount, equals(2));
      expect(metrics.c2paMissingCount, equals(8));
      expect(metrics.c2paInvalidCount, equals(0));
    });
  });
}
