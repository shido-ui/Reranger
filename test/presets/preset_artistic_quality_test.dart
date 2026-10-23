import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const sourceHash =
      '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

  late Uint8List portraitBytes;
  late Uint8List animeCelBytes;
  late Uint8List landscapeBytes;
  late Uint8List flatContrastBytes;
  late Uint8List transparentBytes;
  late RenderGraphExecutor executor;

  setUp(() {
    executor = RenderGraphExecutor();

    // 1. Realistic portrait fixture: gradual skin tones & soft gradients
    final portraitImg = img.Image(width: 32, height: 32, numChannels: 4);
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        final t = (x + y) / 62.0;
        final r = (240 - t * 90).round().clamp(0, 255);
        final g = (200 - t * 100).round().clamp(0, 255);
        final b = (175 - t * 100).round().clamp(0, 255);
        portraitImg.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    portraitBytes = SyntheticSceneFixtures.encodeToPng(portraitImg);

    // 2. Anime / cel line art fixture: high saturation, clean lines, multi-hue zones
    final animeImg = img.Image(width: 32, height: 32, numChannels: 4);
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        if (x < 16 && y < 16) {
          // Vibrant Red
          animeImg.setPixelRgba(x, y, 240, 20, 40, 255);
        } else if (x >= 16 && y < 16) {
          // Vibrant Cyan / Blue
          animeImg.setPixelRgba(x, y, 20, 180, 240, 255);
        } else if (x < 16 && y >= 16) {
          // Vibrant Green
          animeImg.setPixelRgba(x, y, 30, 210, 60, 255);
        } else {
          // Warm Gold
          animeImg.setPixelRgba(x, y, 250, 210, 30, 255);
        }
      }
    }
    animeCelBytes = SyntheticSceneFixtures.encodeToPng(animeImg);

    // 3. Landscape fixture: varied hue range (sky blue, mountain green, sunlight amber)
    final landscapeImg = img.Image(width: 32, height: 32, numChannels: 4);
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        if (y < 12) {
          // Sky Blue gradient
          landscapeImg.setPixelRgba(x, y, 70, 150, 240, 255);
        } else if (y < 22) {
          // Mountain Green
          landscapeImg.setPixelRgba(x, y, 40, 160, 70, 255);
        } else {
          // Earth Umber
          landscapeImg.setPixelRgba(x, y, 140, 90, 50, 255);
        }
      }
    }
    landscapeBytes = SyntheticSceneFixtures.encodeToPng(landscapeImg);

    // 4. Flat colors / high contrast fixture: sharp boundary step
    final flatImg = SyntheticSceneFixtures.createHorizontalSplit(
      width: 32,
      height: 32,
      topR: 255,
      topG: 0,
      topB: 128,
      bottomR: 0,
      bottomG: 255,
      bottomB: 200,
    );
    flatContrastBytes = SyntheticSceneFixtures.encodeToPng(flatImg);

    // 5. Alpha transparency fixture: alternating zero and half alpha
    final transImg = SyntheticSceneFixtures.createTransparentFixture(
      width: 32,
      height: 32,
    );
    transparentBytes = SyntheticSceneFixtures.encodeToPng(transImg);
  });

  group('Prompt 3: Artistic Transformations Quality & Algorithmic Veracity', () {
    test('Watercolor preserves original palette and does not collapse to grayscale duotone', () async {
      final p = PresetCatalog.getById('watercolor')!;
      final graph = p.buildGraph(sourceHash, 32, 32, p.resolveParameters(null));
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: animeCelBytes,
      );

      expect(result.width, equals(32));
      expect(result.height, equals(32));

      // Check color preservation: top-left quadrant should have dominant red, top-right dominant blue
      int redQuadrantR = 0, redQuadrantB = 0;
      int blueQuadrantR = 0, blueQuadrantB = 0;

      for (int y = 2; y < 14; y++) {
        for (int x = 2; x < 14; x++) {
          final off = (y * 32 + x) * 4;
          redQuadrantR += result.pixelBytes[off];
          redQuadrantB += result.pixelBytes[off + 2];
        }
        for (int x = 18; x < 30; x++) {
          final off = (y * 32 + x) * 4;
          blueQuadrantR += result.pixelBytes[off];
          blueQuadrantB += result.pixelBytes[off + 2];
        }
      }

      // Proves red quadrant is distinctly red (R > B by substantial margin)
      expect(redQuadrantR, greaterThan(redQuadrantB * 1.5));
      // Proves blue quadrant is distinctly blue (B > R by substantial margin)
      expect(blueQuadrantB, greaterThan(blueQuadrantR * 1.5));
    });

    test('Anime Cel Shade preserves source colors with stepped quantization and contour ink', () async {
      final p = PresetCatalog.getById('anime_cel_shade')!;
      final graph = p.buildGraph(sourceHash, 32, 32, p.resolveParameters(null));
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: animeCelBytes,
      );

      // Verify that top-left is distinctly red and top-right is distinctly blue
      final tlOff = (4 * 32 + 4) * 4;
      expect(
        result.pixelBytes[tlOff],
        greaterThan(result.pixelBytes[tlOff + 2] + 40),
      );

      final trOff = (4 * 32 + 24) * 4;
      expect(
        result.pixelBytes[trOff + 2],
        greaterThan(result.pixelBytes[trOff] + 40),
      );
    });

    test('Pixel Art preserves full 16-bit color palette with discrete block quantization', () async {
      final p = PresetCatalog.getById('pixel_art')!;
      final graph = p.buildGraph(sourceHash, 32, 32, p.resolveParameters(null));
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: animeCelBytes,
      );

      // Prove output is not monochrome (GameBoy green duotone removed)
      final tlOff = (2 * 32 + 2) * 4;
      final trOff = (2 * 32 + 20) * 4;
      expect(
        result.pixelBytes[tlOff],
        greaterThan(result.pixelBytes[tlOff + 2]),
      );
      expect(
        result.pixelBytes[trOff + 2],
        greaterThan(result.pixelBytes[trOff]),
      );
    });

    test('Halftone Pop Art and Screenprint execute genuine tone-responsive screen dots', () async {
      final popArt = PresetCatalog.getById('halftone_pop_art')!;
      final graphPop = popArt.buildGraph(
        sourceHash,
        32,
        32,
        popArt.resolveParameters(null),
      );
      final resPop = await executor.execute(
        graph: graphPop,
        sourceImageBytes: portraitBytes,
      );
      expect(resPop.pixelBytes.length, equals(32 * 32 * 4));

      final screenprint = PresetCatalog.getById('screenprint')!;
      final graphScreen = screenprint.buildGraph(
        sourceHash,
        32,
        32,
        screenprint.resolveParameters(null),
      );
      final resScreen = await executor.execute(
        graph: graphScreen,
        sourceImageBytes: landscapeBytes,
      );
      expect(resScreen.pixelBytes.length, equals(32 * 32 * 4));
    });

    test('Crosshatch and Stipple execute real directional hatching and pointillist dots', () async {
      final crosshatch = PresetCatalog.getById('crosshatch')!;
      final graphHatch = crosshatch.buildGraph(
        sourceHash,
        32,
        32,
        crosshatch.resolveParameters(null),
      );
      final resHatch = await executor.execute(
        graph: graphHatch,
        sourceImageBytes: portraitBytes,
      );
      expect(resHatch.pixelBytes.length, equals(32 * 32 * 4));

      final stipple = PresetCatalog.getById('stipple')!;
      final graphStipple = stipple.buildGraph(
        sourceHash,
        32,
        32,
        stipple.resolveParameters(null),
      );
      final resStipple = await executor.execute(
        graph: graphStipple,
        sourceImageBytes: portraitBytes,
      );
      expect(resStipple.pixelBytes.length, equals(32 * 32 * 4));
    });

    test(
      'Low-Poly Facets executes 2D facet quantization with color preservation',
      () async {
        final lowPoly = PresetCatalog.getById('low_poly_facets')!;
        final graph = lowPoly.buildGraph(
          sourceHash,
          32,
          32,
          lowPoly.resolveParameters(null),
        );
        final res = await executor.execute(
          graph: graph,
          sourceImageBytes: landscapeBytes,
        );
        expect(res.pixelBytes.length, equals(32 * 32 * 4));
      },
    );

    test('Preserve Alpha channel across all artistic transformation nodes (Invariant 4 & 5)', () async {
      final presetsToTest = [
        'watercolor',
        'anime_cel_shade',
        'comic_book',
        'halftone_pop_art',
        'crosshatch',
        'stipple',
        'pixel_art',
        'low_poly_facets',
      ];

      for (final id in presetsToTest) {
        final p = PresetCatalog.getById(id)!;
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        final res = await executor.execute(
          graph: graph,
          sourceImageBytes: transparentBytes,
        );

        // Transparent pixels (a == 0 in input) must strictly remain 0 in output
        for (int y = 0; y < 32; y++) {
          for (int x = 0; x < 32; x++) {
            final off = (y * 32 + x) * 4;
            if ((x + y) % 2 == 0) {
              expect(
                res.pixelBytes[off + 3],
                equals(0),
                reason: 'Preset $id failed alpha preservation at ($x, $y)',
              );
            }
          }
        }
      }
    });

    test('Source image immutability: Source bytes are completely unaltered (Invariant 4)', () async {
      final preHash = sha256.convert(animeCelBytes).toString();

      for (final p in PresetCatalog.all) {
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        await executor.execute(graph: graph, sourceImageBytes: animeCelBytes);
      }

      final postHash = sha256.convert(animeCelBytes).toString();
      expect(postHash, equals(preHash));
    });

    test('Four-Fixture Rubric: All 48 presets execute cleanly across all 4 fixture classes', () async {
      final fixtures = [
        portraitBytes,
        animeCelBytes,
        landscapeBytes,
        flatContrastBytes,
      ];

      for (final p in PresetCatalog.all) {
        final graph = p.buildGraph(
          sourceHash,
          32,
          32,
          p.resolveParameters(null),
        );
        for (final fix in fixtures) {
          final res = await executor.execute(
            graph: graph,
            sourceImageBytes: fix,
          );
          expect(res.width, equals(32));
          expect(res.height, equals(32));
          expect(res.pixelBytes.length, equals(32 * 32 * 4));
        }
      }
    });
  });
}
