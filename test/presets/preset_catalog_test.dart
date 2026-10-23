import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/presets/data/batch_b_presets.dart';
import 'package:reranger/features/presets/data/batch_c_presets.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const sourceHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  late Uint8List squareBytes;
  late Uint8List portraitBytes;
  late Uint8List lineArtBytes;
  late Uint8List landscapeBytes;
  late Uint8List solidBytes;
  late RenderGraphExecutor executor;

  setUp(() {
    final sqImg = SyntheticSceneFixtures.createCenterSquare(
      width: 32,
      height: 32,
      squareSize: 12,
    );
    squareBytes = SyntheticSceneFixtures.encodeToPng(sqImg);

    portraitBytes = squareBytes;
    lineArtBytes = SyntheticSceneFixtures.encodeToPng(
      SyntheticSceneFixtures.createHorizontalSplit(width: 32, height: 32),
    );
    landscapeBytes = SyntheticSceneFixtures.encodeToPng(
      SyntheticSceneFixtures.createRampGradient(width: 32, height: 32),
    );
    solidBytes = SyntheticSceneFixtures.encodeToPng(
      SyntheticSceneFixtures.createSolidColor(width: 32, height: 32),
    );

    executor = RenderGraphExecutor();
  });

  group('Batch B Presets (5 to 8) Validation', () {
    test('All Batch B presets have valid parameter schemas and defaults', () {
      final presets = BatchBPresets.all;
      expect(presets.length, equals(4));

      for (final p in presets) {
        expect(p.id.isNotEmpty, isTrue);
        expect(p.displayName.isNotEmpty, isTrue);
        expect(p.category.isNotEmpty, isTrue);
        expect(p.description.isNotEmpty, isTrue);
        expect(p.thumbnailAssetPath.isNotEmpty, isTrue);
        expect(p.thumbnailProvenance.isNotEmpty, isTrue);
        expect(p.accessibleLabel.isNotEmpty, isTrue);

        for (final param in p.parameters) {
          expect(param.defaultValue, greaterThanOrEqualTo(param.min));
          expect(param.defaultValue, lessThanOrEqualTo(param.max));
          expect(param.clamp(param.min - 100), equals(param.min));
          expect(param.clamp(param.max + 100), equals(param.max));
        }

        final resolved = p.resolveParameters(null);
        for (final param in p.parameters) {
          expect(resolved[param.id], equals(param.defaultValue));
        }
      }
    });

    test('Batch B presets produce pairwise distinct fingerprints on identical input', () async {
      final fingerprints = <String, String>{};

      for (final p in BatchBPresets.all) {
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: squareBytes,
        );

        expect(result.width, equals(32));
        expect(result.height, equals(32));

        final hash = sha256.convert(result.pixelBytes).toString();
        fingerprints[p.id] = hash;
      }

      final uniqueHashes = fingerprints.values.toSet();
      expect(uniqueHashes.length, equals(4));
    });

    test('All Batch B presets respond to parameter adjustments (responsiveness >= 3/4)', () async {
      for (final p in BatchBPresets.all) {
        final defParams = p.resolveParameters(null);
        final defaultGraph = p.buildGraph(sourceHash, 32, 32, defParams);
        final defaultRes = await executor.execute(
          graph: defaultGraph,
          sourceImageBytes: squareBytes,
        );
        final defaultHash = sha256.convert(defaultRes.pixelBytes).toString();

        final firstParam = p.parameters.first;
        final alteredParams = Map<String, double>.from(defParams);
        alteredParams[firstParam.id] = firstParam.max;

        final alteredGraph = p.buildGraph(sourceHash, 32, 32, alteredParams);
        final alteredRes = await executor.execute(
          graph: alteredGraph,
          sourceImageBytes: squareBytes,
        );
        final alteredHash = sha256.convert(alteredRes.pixelBytes).toString();

        expect(
          alteredHash,
          isNot(equals(defaultHash)),
          reason:
              'Preset ${p.id} must respond to slider adjustments on ${firstParam.id}',
        );
      }
    });
  });

  group('Batch C Presets (9 to 12) Validation', () {
    test('All Batch C presets have valid parameter schemas and defaults', () {
      final presets = BatchCPresets.all;
      expect(presets.length, equals(4));

      for (final p in presets) {
        expect(p.id.isNotEmpty, isTrue);
        expect(p.displayName.isNotEmpty, isTrue);
        expect(p.category.isNotEmpty, isTrue);
        expect(p.description.isNotEmpty, isTrue);
        expect(p.thumbnailAssetPath.isNotEmpty, isTrue);
        expect(p.thumbnailProvenance.isNotEmpty, isTrue);
        expect(p.accessibleLabel.isNotEmpty, isTrue);

        for (final param in p.parameters) {
          expect(param.defaultValue, greaterThanOrEqualTo(param.min));
          expect(param.defaultValue, lessThanOrEqualTo(param.max));
          expect(param.clamp(param.min - 100), equals(param.min));
          expect(param.clamp(param.max + 100), equals(param.max));
        }

        final resolved = p.resolveParameters(null);
        for (final param in p.parameters) {
          expect(resolved[param.id], equals(param.defaultValue));
        }
      }
    });

    test('Batch C presets produce pairwise distinct fingerprints on identical input', () async {
      final fingerprints = <String, String>{};

      for (final p in BatchCPresets.all) {
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: squareBytes,
        );

        expect(result.width, equals(32));
        expect(result.height, equals(32));

        final hash = sha256.convert(result.pixelBytes).toString();
        fingerprints[p.id] = hash;
      }

      final uniqueHashes = fingerprints.values.toSet();
      expect(uniqueHashes.length, equals(4));
    });

    test('All Batch C presets respond to parameter adjustments (responsiveness >= 3/4)', () async {
      for (final p in BatchCPresets.all) {
        final defParams = p.resolveParameters(null);
        final defaultGraph = p.buildGraph(sourceHash, 32, 32, defParams);
        final defaultRes = await executor.execute(
          graph: defaultGraph,
          sourceImageBytes: squareBytes,
        );
        final defaultHash = sha256.convert(defaultRes.pixelBytes).toString();

        final firstParam = p.parameters.first;
        final alteredParams = Map<String, double>.from(defParams);
        alteredParams[firstParam.id] = firstParam.max;

        final alteredGraph = p.buildGraph(sourceHash, 32, 32, alteredParams);
        final alteredRes = await executor.execute(
          graph: alteredGraph,
          sourceImageBytes: squareBytes,
        );
        final alteredHash = sha256.convert(alteredRes.pixelBytes).toString();

        expect(
          alteredHash,
          isNot(equals(defaultHash)),
          reason:
              'Preset ${p.id} must respond to slider adjustments on ${firstParam.id}',
        );
      }
    });

    test('All Batch C presets execute cleanly across 4 fixture classes (Portrait, LineArt, Landscape, Solid)', () async {
      final fixtures = [
        portraitBytes,
        lineArtBytes,
        landscapeBytes,
        solidBytes,
      ];

      for (final p in BatchCPresets.all) {
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        for (final fixture in fixtures) {
          final res = await executor.execute(
            graph: graph,
            sourceImageBytes: fixture,
          );
          expect(res.width, equals(32));
          expect(res.height, equals(32));
          expect(res.pixelBytes.length, equals(32 * 32 * 4));
        }
      }
    });

    test('Source image immutability: Source bytes remain byte-identical pre and post render (Invariant 4)', () async {
      final preHash = sha256.convert(squareBytes).toString();
      final p = BatchCPresets.watercolor;
      final graph = p.buildGraph(sourceHash, 32, 32, p.resolveParameters(null));

      await executor.execute(graph: graph, sourceImageBytes: squareBytes);

      final postHash = sha256.convert(squareBytes).toString();
      expect(postHash, equals(preHash));
    });
  });

  group(
    'PresetCatalog Registry Validation (48 Presets across 6 Categories)',
    () {
      test('Catalog contains exactly 48 validated presets with unique IDs', () {
        expect(PresetCatalog.all.length, equals(48));

        final ids = PresetCatalog.all.map((p) => p.id).toSet();
        expect(ids.length, equals(48));

        for (final p in PresetCatalog.all) {
          expect(PresetCatalog.containsId(p.id), isTrue);
          expect(PresetCatalog.getById(p.id), equals(p));
        }

        // Legacy alias lookups
        expect(PresetCatalog.containsId('flat_illustration'), isTrue);
        expect(
          PresetCatalog.getById('flat_illustration')?.id,
          equals('flat_vector'),
        );
        expect(PresetCatalog.containsId('vintage_film'), isTrue);
        expect(
          PresetCatalog.getById('vintage_film')?.id,
          equals('vintage_35mm'),
        );

        expect(PresetCatalog.containsId('non_existent'), isFalse);
        expect(PresetCatalog.getById('non_existent'), isNull);
      });

      test(
        'All 48 presets produce pairwise distinct outputs on identical input',
        () async {
          final fingerprints = <String, String>{};

          for (final p in PresetCatalog.all) {
            final graph = p.buildGraph(
              sourceHash,
              32,
              32,
              p.resolveParameters(null),
            );
            final result = await executor.execute(
              graph: graph,
              sourceImageBytes: squareBytes,
            );

            final hash = sha256.convert(result.pixelBytes).toString();
            fingerprints[p.id] = hash;
          }

          final uniqueHashes = fingerprints.values.toSet();
          expect(
            uniqueHashes.length,
            equals(48),
            reason: 'All 48 presets must produce unique rendered outputs',
          );
        },
      );

      test('Category filtering covers all registered presets across 6 categories of 8', () {
        final categories = PresetCatalog.categories;
        expect(categories.length, equals(6));

        final expectedCategories = [
          'Sketch & Line Art',
          'Painting Studio',
          'Illustration & Comics',
          'Film & Photography',
          'Graphic & Retro',
          'Experimental & Atmosphere',
        ];
        expect(categories, equals(expectedCategories));

        int totalCount = 0;
        for (final cat in categories) {
          final inCategory = PresetCatalog.getByCategory(cat);
          expect(
            inCategory.length,
            equals(8),
            reason: 'Each category must contain exactly 8 presets',
          );
          for (final p in inCategory) {
            expect(p.category, equals(cat));
          }
          totalCount += inCategory.length;
        }

        expect(totalCount, equals(48));
      });
    },
  );
}
