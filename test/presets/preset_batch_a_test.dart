import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const sourceHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  group('Batch A Presets (1 to 4) Validation', () {
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

    test('All Batch A presets have valid parameter schemas and defaults', () {
      final presets = BatchAPresets.all;
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

        // Default resolution
        final resolved = p.resolveParameters(null);
        for (final param in p.parameters) {
          expect(resolved[param.id], equals(param.defaultValue));
        }
      }
    });

    test('Batch A presets produce pairwise distinct fingerprints on identical input', () async {
      final fingerprints = <String, String>{};

      for (final p in BatchAPresets.all) {
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

      // Verify all 4 hashes are unique
      final uniqueHashes = fingerprints.values.toSet();
      expect(uniqueHashes.length, equals(4));
    });

    test('All Batch A presets respond to parameter adjustments (responsiveness >= 3/4)', () async {
      for (final p in BatchAPresets.all) {
        final defParams = p.resolveParameters(null);
        final defaultGraph = p.buildGraph(sourceHash, 32, 32, defParams);
        final defaultRes = await executor.execute(
          graph: defaultGraph,
          sourceImageBytes: squareBytes,
        );
        final defaultHash = sha256.convert(defaultRes.pixelBytes).toString();

        // Adjust first parameter to maximum
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

    test('All Batch A presets execute cleanly across 4 fixture classes (Portrait, LineArt, Landscape, Solid)', () async {
      final fixtures = [
        portraitBytes,
        lineArtBytes,
        landscapeBytes,
        solidBytes,
      ];

      for (final p in BatchAPresets.all) {
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
      final p = BatchAPresets.graphitePencil;
      final graph = p.buildGraph(sourceHash, 32, 32, p.resolveParameters(null));

      await executor.execute(graph: graph, sourceImageBytes: squareBytes);

      final postHash = sha256.convert(squareBytes).toString();
      expect(postHash, equals(preHash));
    });
  });
}
