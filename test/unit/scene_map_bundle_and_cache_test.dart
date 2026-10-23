import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/scene_map/isolate_scene_map_generator.dart';
import 'package:reranger/data/scene_map/scene_map_cache_key.dart';
import 'package:reranger/data/scene_map/scene_map_repository.dart';
import 'package:reranger/domain/scene_map/scene_map_bundle.dart';
import 'package:reranger/domain/scene_map/scene_map_failure.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  group('SceneMapCacheKey Matrix & Invalidation (Batch C)', () {
    const baseSourceHash =
        '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

    test('Unchanged inputs and parameters produce identical cache keys (Cache Hit)', () {
      final key1 = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        bundleVersion: 1,
        engineVersion: '1.0.0',
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 50, 'paletteK': 5},
      );

      final key2 = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        bundleVersion: 1,
        engineVersion: '1.0.0',
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'paletteK': 5, 'edgeThreshold': 50}, // Swapped order
      );

      expect(key1, equals(key2));
      expect(key1.length, equals(64)); // SHA-256 hex
    });

    test('Changing each cache-key dimension yields distinct cache keys (Cache Miss)', () {
      final baseKey = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        bundleVersion: 1,
        engineVersion: '1.0.0',
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 50, 'paletteK': 5},
      );

      // 1. Source hash change
      final changedSource = computeSceneMapCacheKey(
        sourceHash:
            'ffff3344556677889900aabbccddeeff11223344556677889900aabbccddeeff',
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 50, 'paletteK': 5},
      );
      expect(changedSource, isNot(equals(baseKey)));

      // 2. Bundle version change
      final changedBundleVer = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        bundleVersion: 2,
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 50, 'paletteK': 5},
      );
      expect(changedBundleVer, isNot(equals(baseKey)));

      // 3. Engine version change
      final changedEngineVer = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        engineVersion: '1.1.0',
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 50, 'paletteK': 5},
      );
      expect(changedEngineVer, isNot(equals(baseKey)));

      // 4. Target dimensions change
      final changedDims = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        targetWidth: 600,
        targetHeight: 400,
        parameters: {'edgeThreshold': 50, 'paletteK': 5},
      );
      expect(changedDims, isNot(equals(baseKey)));

      // 5. Parameter edgeThreshold change
      final changedParam1 = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 65, 'paletteK': 5},
      );
      expect(changedParam1, isNot(equals(baseKey)));

      // 6. Parameter paletteK change
      final changedParam2 = computeSceneMapCacheKey(
        sourceHash: baseSourceHash,
        targetWidth: 512,
        targetHeight: 384,
        parameters: {'edgeThreshold': 50, 'paletteK': 8},
      );
      expect(changedParam2, isNot(equals(baseKey)));
    });
  });

  group('IsolateSceneMapGenerator & Full Bundle (Batch C)', () {
    const generator = IsolateSceneMapGenerator();
    const sourceHash =
        '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

    test(
      'Generates complete bundle on checkerboard fixture with valid bounds',
      () async {
        final imgFixture = SyntheticSceneFixtures.createCheckerboard4x4(
          width: 64,
          height: 64,
        );
        final pngBytes = SyntheticSceneFixtures.encodeToPng(imgFixture);

        final bundle = await generator.generate(
          imageBytes: pngBytes,
          sourceHash: sourceHash,
          maxPreviewDimension: 64,
          edgeThreshold: 40,
          paletteK: 4,
        );

        // Verify metadata & Invariant 7 capabilities
        expect(bundle.metadata.sourceHash, equals(sourceHash));
        expect(bundle.metadata.sourceWidth, equals(64));
        expect(bundle.metadata.sourceHeight, equals(64));
        expect(bundle.hasSubjectMap, isFalse);
        expect(bundle.hasDepthMap, isFalse);
        expect(bundle.hasFaceMap, isFalse);

        // Verify 3 pyramid levels
        expect(bundle.pyramidLevels.length, equals(3));
        expect(bundle.pyramidLevels[0].level, equals(0));
        expect(bundle.pyramidLevels[0].width, equals(64));
        expect(bundle.pyramidLevels[1].level, equals(1));
        expect(bundle.pyramidLevels[1].width, equals(32));
        expect(bundle.pyramidLevels[2].level, equals(2));
        expect(bundle.pyramidLevels[2].width, equals(16));

        // Verify coordinate transform
        expect(bundle.transform.sourceWidth, equals(64));
        expect(bundle.transform.previewWidth, equals(64));

        // Verify edge map
        expect(bundle.edgeMap.gridWidth, equals(64));
        expect(bundle.edgeMap.edgeDensity, greaterThan(0.0));

        // Verify contour points are strictly within normalized [0.0, 1.0]
        for (final contour in bundle.contourMap.contours) {
          expect(contour.bounds.left, greaterThanOrEqualTo(0.0));
          expect(contour.bounds.right, lessThanOrEqualTo(1.0001));
          expect(contour.bounds.top, greaterThanOrEqualTo(0.0));
          expect(contour.bounds.bottom, lessThanOrEqualTo(1.0001));
          for (final pt in contour.points) {
            expect(pt.x, greaterThanOrEqualTo(0.0));
            expect(pt.x, lessThanOrEqualTo(1.0));
            expect(pt.y, greaterThanOrEqualTo(0.0));
            expect(pt.y, lessThanOrEqualTo(1.0));
          }
        }

        // Verify palette
        expect(bundle.tonalPaletteMap.palette.length, lessThanOrEqualTo(4));
        expect(
          bundle.tonalPaletteMap.shadowRatio +
              bundle.tonalPaletteMap.midtoneRatio +
              bundle.tonalPaletteMap.highlightRatio,
          closeTo(1.0, 1e-4),
        );

        // Verify color regions
        expect(bundle.colorRegionMap.gridWidth, equals(32)); // Level 1 grid
        expect(
          bundle.colorRegionMap.regionCount,
          equals(bundle.tonalPaletteMap.palette.length),
        );

        // Lossless roundtrip serialization
        final json = bundle.toJson();
        final restored = SceneMapBundle.fromJson(json);
        expect(restored, equals(bundle));
      },
    );

    test(
      'Cancellation check aborts analysis before isolate completion',
      () async {
        final imgFixture = SyntheticSceneFixtures.createCheckerboard4x4(
          width: 32,
          height: 32,
        );
        final pngBytes = SyntheticSceneFixtures.encodeToPng(imgFixture);

        expect(
          () => generator.generate(
            imageBytes: pngBytes,
            sourceHash: sourceHash,
            isCancelled: () => true,
          ),
          throwsA(isA<SceneMapCancellationFailure>()),
        );
      },
    );

    test(
      '1x1 tiny image and transparent images analyze safely without crashes',
      () async {
        final tinyImg = SyntheticSceneFixtures.createTiny1x1(
          r: 200,
          g: 100,
          b: 50,
        );
        final tinyBytes = SyntheticSceneFixtures.encodeToPng(tinyImg);

        final tinyBundle = await generator.generate(
          imageBytes: tinyBytes,
          sourceHash: sourceHash,
          maxPreviewDimension: 64,
        );
        expect(tinyBundle.transform.sourceWidth, equals(1));
        expect(tinyBundle.transform.sourceHeight, equals(1));
        expect(tinyBundle.edgeMap.edgeDensity, equals(0.0));

        final transImg = SyntheticSceneFixtures.createTransparentFixture(
          width: 32,
          height: 32,
        );
        final transBytes = SyntheticSceneFixtures.encodeToPng(transImg);

        final transBundle = await generator.generate(
          imageBytes: transBytes,
          sourceHash: sourceHash,
          maxPreviewDimension: 32,
        );
        expect(transBundle.transform.sourceWidth, equals(32));
        expect(transBundle.pyramidLevels.length, equals(3));
      },
    );
  });

  group('SceneMapRepository & SQLite Integration (Batch C)', () {
    late Directory tempDir;
    late ProjectDatabase db;
    late SceneMapRepository repository;
    const testSourceHash =
        'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('scene_map_repo_test_');
      db = ProjectDatabase.openInMemory();
      repository = SceneMapRepository(db);
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test(
      'Save, retrieve, and cache invalidation lifecycle in repository',
      () async {
        const generator = IsolateSceneMapGenerator();
        final imgFixture = SyntheticSceneFixtures.createCenterSquare(
          width: 32,
          height: 32,
          squareSize: 12,
        );
        final pngBytes = SyntheticSceneFixtures.encodeToPng(imgFixture);

        final bundle = await generator.generate(
          imageBytes: pngBytes,
          sourceHash: testSourceHash,
          maxPreviewDimension: 32,
        );

        final cacheKey = computeSceneMapCacheKey(
          sourceHash: testSourceHash,
          targetWidth: 32,
          targetHeight: 32,
        );

        // Cache miss initially
        final initial = await repository.getCachedBundle(cacheKey);
        expect(initial, isNull);

        // Save bundle
        await repository.saveBundle(bundle, cacheKey);

        // Cache hit
        final cached = await repository.getCachedBundle(cacheKey);
        expect(cached, isNotNull);
        expect(cached!.metadata.sourceHash, equals(testSourceHash));
        expect(cached.pyramidLevels.length, equals(3));

        // Explicit invalidation
        await repository.invalidate(cacheKey);
        final afterInvalidate = await repository.getCachedBundle(cacheKey);
        expect(afterInvalidate, isNull);
      },
    );

    test('Corrupted cache recovery: invalid SQLite JSON is healed gracefully without crash', () async {
      final cacheKey = computeSceneMapCacheKey(
        sourceHash: testSourceHash,
        targetWidth: 64,
        targetHeight: 64,
      );

      // Manually insert corrupted JSON string directly into SQLite scene_map_cache
      db.saveSceneMapCache(
        cacheKey,
        testSourceHash,
        '{broken_corrupt_json: true',
      );

      // Repository must handle gracefully, purge the corrupt entry, and return null
      final retrieved = await repository.getCachedBundle(cacheKey);
      expect(retrieved, isNull);

      // Verify corrupted row was pruned from SQLite
      expect(db.getSceneMapCache(cacheKey), isNull);
    });

    test(
      'invalidateBySourceHash purges all entries tied to a source file',
      () async {
        const generator = IsolateSceneMapGenerator();
        final imgFixture = SyntheticSceneFixtures.createSolidColor(
          width: 32,
          height: 32,
        );
        final pngBytes = SyntheticSceneFixtures.encodeToPng(imgFixture);

        final bundle = await generator.generate(
          imageBytes: pngBytes,
          sourceHash: testSourceHash,
          maxPreviewDimension: 32,
        );

        final key1 = computeSceneMapCacheKey(
          sourceHash: testSourceHash,
          targetWidth: 32,
          targetHeight: 32,
          parameters: {'edgeThreshold': 40},
        );
        final key2 = computeSceneMapCacheKey(
          sourceHash: testSourceHash,
          targetWidth: 32,
          targetHeight: 32,
          parameters: {'edgeThreshold': 60},
        );

        await repository.saveBundle(bundle, key1);
        await repository.saveBundle(bundle, key2);

        expect(await repository.getCachedBundle(key1), isNotNull);
        expect(await repository.getCachedBundle(key2), isNotNull);

        // Invalidate all maps for this source
        await repository.invalidateBySourceHash(testSourceHash);

        expect(await repository.getCachedBundle(key1), isNull);
        expect(await repository.getCachedBundle(key2), isNull);
      },
    );
  });
}
