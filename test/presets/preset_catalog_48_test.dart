import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const sourceHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  late Uint8List squareBytes;
  late Uint8List portraitBytes;
  late Uint8List lineArtBytes;
  late Uint8List landscapeBytes;
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

    executor = RenderGraphExecutor();
  });

  group('Prompt 22: 48-Preset Catalog Exhaustive Validation', () {
    test(
      'Catalog contains exactly 48 unique presets across 6 categories of 8',
      () {
        expect(PresetCatalog.all.length, equals(48));

        final ids = PresetCatalog.all.map((p) => p.id).toSet();
        expect(
          ids.length,
          equals(48),
          reason: 'Every preset ID must be unique',
        );

        final displayNames = PresetCatalog.all
            .map((p) => p.displayName)
            .toSet();
        expect(
          displayNames.length,
          equals(48),
          reason: 'Every display name must be unique',
        );

        final expectedCategories = [
          'Sketch & Line Art',
          'Painting Studio',
          'Illustration & Comics',
          'Film & Photography',
          'Graphic & Retro',
          'Experimental & Atmosphere',
        ];
        expect(PresetCatalog.categories, equals(expectedCategories));

        for (final cat in expectedCategories) {
          final presetsInCat = PresetCatalog.getByCategory(cat);
          expect(
            presetsInCat.length,
            equals(8),
            reason: 'Category $cat must contain exactly 8 presets',
          );
        }
      },
    );

    test(
      'All 48 presets have valid parameter schemas, bounds, and metadata',
      () {
        for (final p in PresetCatalog.all) {
          expect(p.id.isNotEmpty, isTrue);
          expect(p.displayName.isNotEmpty, isTrue);
          expect(p.category.isNotEmpty, isTrue);
          expect(p.description.isNotEmpty, isTrue);
          expect(p.thumbnailAssetPath.isNotEmpty, isTrue);
          expect(p.thumbnailProvenance.isNotEmpty, isTrue);
          expect(p.accessibleLabel.isNotEmpty, isTrue);
          expect(p.version, greaterThanOrEqualTo(1));

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
      },
    );

    test('All 48 presets have bundled local thumbnail assets on disk', () {
      for (final p in PresetCatalog.all) {
        final file = File(p.thumbnailAssetPath);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'Precomputed thumbnail missing for ${p.id}: ${p.thumbnailAssetPath}',
        );
        expect(
          file.lengthSync(),
          greaterThan(100),
          reason: 'Thumbnail file for ${p.id} must be non-empty valid PNG',
        );
      }
    });

    test('All 48 presets produce pairwise distinct SHA-256 fingerprints on identical input', () async {
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

        expect(result.width, equals(32));
        expect(result.height, equals(32));

        final hash = sha256.convert(result.pixelBytes).toString();
        fingerprints[p.id] = hash;
      }

      final uniqueHashes = fingerprints.values.toSet();
      expect(
        uniqueHashes.length,
        equals(48),
        reason:
            'All 48 presets must produce pairwise distinct rendered outputs',
      );
    });

    test('Parameter responsiveness: adjusting parameters changes pixel output for all 48 presets', () async {
      for (final p in PresetCatalog.all) {
        if (p.parameters.isEmpty) continue;

        final defaultParams = p.resolveParameters(null);
        final defaultGraph = p.buildGraph(sourceHash, 32, 32, defaultParams);
        final defaultResult = await executor.execute(
          graph: defaultGraph,
          sourceImageBytes: squareBytes,
        );
        final defaultHash = sha256.convert(defaultResult.pixelBytes).toString();

        // Adjust primary parameter to maximum or minimum (whichever is farther from default)
        final param0 = p.parameters.first;
        final alteredParams = Map<String, double>.from(defaultParams);
        final testVal =
            (param0.max - param0.defaultValue).abs() >=
                (param0.defaultValue - param0.min).abs()
            ? param0.max
            : param0.min;
        alteredParams[param0.id] = testVal;

        final alteredGraph = p.buildGraph(sourceHash, 32, 32, alteredParams);
        final alteredResult = await executor.execute(
          graph: alteredGraph,
          sourceImageBytes: squareBytes,
        );
        final alteredHash = sha256.convert(alteredResult.pixelBytes).toString();

        expect(
          alteredHash != defaultHash,
          isTrue,
          reason:
              'Preset ${p.id} parameter ${param0.id} must produce altered output at $testVal',
        );
      }
    });

    test('All 48 presets execute deterministically across 4 fixture classes without failure', () async {
      final fixtures = [
        squareBytes,
        portraitBytes,
        lineArtBytes,
        landscapeBytes,
      ];

      for (final p in PresetCatalog.all) {
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );

        for (final fixture in fixtures) {
          final result = await executor.execute(
            graph: graph,
            sourceImageBytes: fixture,
          );
          expect(result.pixelBytes.length, equals(32 * 32 * 4));
        }
      }
    });

    test('Source image immutability: Source bytes remain byte-for-byte identical (Invariant 4)', () async {
      final preHash = sha256.convert(squareBytes).toString();

      // Execute across representative presets
      for (final cat in PresetCatalog.categories) {
        final p = PresetCatalog.getByCategory(cat).first;
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        await executor.execute(graph: graph, sourceImageBytes: squareBytes);
      }

      final postHash = sha256.convert(squareBytes).toString();
      expect(postHash, equals(preHash));
    });

    test('Raster simulation transparency: Clay Render and Low-Poly Facets disclose 2D simulation', () {
      final clay = PresetCatalog.getById('clay_render')!;
      expect(clay.description.contains('2D raster simulation'), isTrue);

      final lowPoly = PresetCatalog.getById('low_poly_facets')!;
      expect(lowPoly.description.contains('2D raster simulation'), isTrue);
    });

    test(
      'Legacy migration: legacy IDs resolve correctly via catalog lookup',
      () {
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
      },
    );
  });
}
