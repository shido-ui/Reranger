import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/scene_map/analysis_bundle_metadata.dart';
import 'package:reranger/domain/scene_map/coordinate_transform.dart';
import 'package:reranger/domain/scene_map/pyramid_level.dart';
import 'package:reranger/domain/scene_map/scene_map_failure.dart';

void main() {
  group('NormalizedPoint & NormalizedRect (Batch A)', () {
    test('NormalizedPoint enforces bounds and serializes correctly', () {
      const p1 = NormalizedPoint(0.25, 0.75);
      expect(p1.x, equals(0.25));
      expect(p1.y, equals(0.75));
      expect(p1.isFinite, isTrue);

      final json = p1.toJson();
      final deserialized = NormalizedPoint.fromJson(json);
      expect(deserialized, equals(p1));

      // Clamped factory prevents out of bounds crashes
      final clamped = NormalizedPoint.clamped(-0.5, 1.5);
      expect(clamped.x, equals(0.0));
      expect(clamped.y, equals(1.0));

      // Lerp
      const p2 = NormalizedPoint(0.75, 0.25);
      final mid = p1.lerp(p2, 0.5);
      expect(mid.x, closeTo(0.5, 1e-5));
      expect(mid.y, closeTo(0.5, 1e-5));
    });

    test('NormalizedRect computes bounds and point containment correctly', () {
      const rect = NormalizedRect(left: 0.1, top: 0.2, width: 0.4, height: 0.5);

      expect(rect.right, closeTo(0.5, 1e-5));
      expect(rect.bottom, closeTo(0.7, 1e-5));
      expect(rect.center.x, closeTo(0.3, 1e-5));
      expect(rect.center.y, closeTo(0.45, 1e-5));

      expect(rect.containsPoint(const NormalizedPoint(0.2, 0.3)), isTrue);
      expect(rect.containsPoint(const NormalizedPoint(0.05, 0.3)), isFalse);
      expect(rect.containsPoint(const NormalizedPoint(0.6, 0.3)), isFalse);

      final json = rect.toJson();
      final restored = NormalizedRect.fromJson(json);
      expect(restored, equals(rect));
    });

    test('NormalizedRect.fromPoints handles inverted corners gracefully', () {
      const pA = NormalizedPoint(0.8, 0.9);
      const pB = NormalizedPoint(0.2, 0.3);

      final rect = NormalizedRect.fromPoints(pA, pB);
      expect(rect.left, closeTo(0.2, 1e-5));
      expect(rect.top, closeTo(0.3, 1e-5));
      expect(rect.width, closeTo(0.6, 1e-5));
      expect(rect.height, closeTo(0.6, 1e-5));
    });
  });

  group('CoordinateTransform (Batch A)', () {
    const transform = CoordinateTransform(
      sourceWidth: 4000,
      sourceHeight: 3000,
      previewWidth: 512,
      previewHeight: 384,
      mapWidth: 256,
      mapHeight: 192,
    );

    test('Aspect ratios match across scaled spaces', () {
      expect(transform.sourceAspectRatio, closeTo(4 / 3, 1e-4));
      expect(transform.previewAspectRatio, closeTo(4 / 3, 1e-4));
      expect(transform.mapAspectRatio, closeTo(4 / 3, 1e-4));
    });

    test(
      'Normalized coordinates map deterministically to and from source pixels',
      () {
        // Top-left
        final normTL = transform.sourceToNormalized(0, 0);
        expect(normTL.x, equals(0.0));
        expect(normTL.y, equals(0.0));
        final (srcX0, srcY0) = transform.normalizedToSource(normTL);
        expect(srcX0, closeTo(0.0, 1e-4));
        expect(srcY0, closeTo(0.0, 1e-4));

        // Bottom-right
        final normBR = transform.sourceToNormalized(3999, 2999);
        expect(normBR.x, equals(1.0));
        expect(normBR.y, equals(1.0));
        final (srcX1, srcY1) = transform.normalizedToSource(normBR);
        expect(srcX1, closeTo(3999.0, 1e-4));
        expect(srcY1, closeTo(2999.0, 1e-4));

        // Center point
        final normCenter = transform.sourceToNormalized(1999.5, 1499.5);
        expect(normCenter.x, closeTo(0.5, 1e-4));
        expect(normCenter.y, closeTo(0.5, 1e-4));
      },
    );

    test(
      'Direct space mappings (sourceToPreview, sourceToMap) preserve alignment',
      () {
        final (prevX, prevY) = transform.sourceToPreview(3999, 2999);
        expect(prevX, closeTo(511.0, 1e-4));
        expect(prevY, closeTo(383.0, 1e-4));

        final (mapX, mapY) = transform.sourceToMap(3999, 2999);
        expect(mapX, closeTo(255.0, 1e-4));
        expect(mapY, closeTo(191.0, 1e-4));

        final (backSrcX, backSrcY) = transform.mapToSource(mapX, mapY);
        expect(backSrcX, closeTo(3999.0, 1e-2));
        expect(backSrcY, closeTo(2999.0, 1e-2));
      },
    );

    test(
      'calculateFitLayout accurately computes pillarbox and letterbox offsets',
      () {
        // Landscape image (4:3) on portrait screen (360x740) -> letterboxed top/bottom
        final letterbox = transform.calculateFitLayout(360, 740);
        expect(letterbox.width, equals(360.0));
        expect(letterbox.height, closeTo(270.0, 1e-4));
        expect(letterbox.left, equals(0.0));
        expect(letterbox.top, closeTo((740 - 270) / 2.0, 1e-4));

        // Landscape image (4:3) on ultrawide viewport (1200x600) -> pillarboxed left/right
        final pillarbox = transform.calculateFitLayout(1200, 600);
        expect(pillarbox.height, equals(600.0));
        expect(pillarbox.width, closeTo(800.0, 1e-4));
        expect(pillarbox.top, equals(0.0));
        expect(pillarbox.left, closeTo((1200 - 800) / 2.0, 1e-4));
      },
    );

    test('Serialization roundtrip preserves all transform fields', () {
      final json = transform.toJson();
      final restored = CoordinateTransform.fromJson(json);
      expect(restored, equals(transform));
    });
  });

  group('PyramidLevel (Batch A)', () {
    test('PyramidLevel stores and retrieves luminance data with clamping', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      final level = PyramidLevel(
        level: 0,
        width: 2,
        height: 2,
        scaleFactor: 1.0,
        luminanceData: bytes,
      );

      expect(level.getLuminance(0, 0), equals(10));
      expect(level.getLuminance(1, 0), equals(20));
      expect(level.getLuminance(0, 1), equals(30));
      expect(level.getLuminance(1, 1), equals(40));

      // Edge clamping
      expect(level.getLuminance(-1, 0), equals(10));
      expect(level.getLuminance(5, 5), equals(40));

      // Serialization
      final json = level.toJson();
      final restored = PyramidLevel.fromJson(json);
      expect(restored, equals(level));
    });

    test('PyramidLevel asserts invalid dimensions or mismatched buffer', () {
      expect(
        () => PyramidLevel(
          level: 0,
          width: 2,
          height: 2,
          scaleFactor: 1.0,
          luminanceData: Uint8List(3), // Mismatch (needs 4)
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AnalysisBundleMetadata (Batch A)', () {
    test('Metadata serializes faithfully and preserves Invariant 7 capability flags', () {
      final meta = AnalysisBundleMetadata(
        sourceHash: 'a' * 64,
        sourceWidth: 1920,
        sourceHeight: 1080,
        createdAt: DateTime.utc(2026, 10, 22, 12, 0, 0),
        parameters: {'edge_threshold': 50, 'palette_k': 5},
      );

      expect(meta.bundleVersion, equals(1));
      expect(meta.engineVersion, equals('1.0.0'));
      expect(meta.colorSpace, equals('sRGB'));
      // Invariant 7: No fake AI - subject/depth/face maps must be false
      expect(meta.hasSubjectMap, isFalse);
      expect(meta.hasDepthMap, isFalse);
      expect(meta.hasFaceMap, isFalse);
      expect(meta.hasEdgeMap, isTrue);
      expect(meta.hasContourMap, isTrue);

      final json = meta.toJson();
      final restored = AnalysisBundleMetadata.fromJson(json);
      expect(restored, equals(meta));
      expect(restored.hasSubjectMap, isFalse);
    });

    test('Metadata asserts invalid source hash or dimensions', () {
      expect(
        () => AnalysisBundleMetadata(
          sourceHash: 'short_hash',
          sourceWidth: 100,
          sourceHeight: 100,
          createdAt: DateTime.now(),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('SceneMapFailure Taxonomy (Batch A)', () {
    test(
      'Structured domain failure classes instantiate with expected messages',
      () {
        const cancelFail = SceneMapCancellationFailure();
        expect(cancelFail.toString(), contains('cancelled by user'));

        const corruptFail = SceneMapCorruptCacheFailure(
          'key_123',
          'Missing key',
        );
        expect(corruptFail.cacheKey, equals('key_123'));
        expect(corruptFail.toString(), contains('key_123'));

        const coordFail = SceneMapInvalidCoordinatesFailure(1.5, -0.2);
        expect(coordFail.x, equals(1.5));
        expect(coordFail.y, equals(-0.2));

        const memFail = SceneMapMemoryBudgetFailure(200000000, 100000000);
        expect(memFail.requestedBytes, equals(200000000));
        expect(memFail.maxAllowedBytes, equals(100000000));
      },
    );
  });
}
