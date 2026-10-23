import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_node_cache.dart';
import 'package:reranger/domain/color/color_palette.dart';
import 'package:reranger/domain/color/recolor_mask.dart';
import 'package:reranger/domain/recipes/recolor_render_node.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/scene_map/color_region_map_data.dart';
import 'package:reranger/domain/scene_map/coordinate_transform.dart';
import 'package:reranger/features/recolor/presentation/recolor_controller.dart';

void main() {
  group('RegionMask Generation & Touchscreen Repair Tool', () {
    test(
      'fromColorTolerance extracts targeted zone and excludes distinct colors',
      () {
        // 4x4 image: left 2 columns Pure Red (255, 0, 0), right 2 columns Pure Green (0, 255, 0)
        final rgba = Uint8List(4 * 4 * 4);
        for (int y = 0; y < 4; y++) {
          for (int x = 0; x < 4; x++) {
            final off = (y * 4 + x) * 4;
            if (x < 2) {
              rgba[off] = 255;
              rgba[off + 1] = 0;
              rgba[off + 2] = 0;
              rgba[off + 3] = 255;
            } else {
              rgba[off] = 0;
              rgba[off + 1] = 255;
              rgba[off + 2] = 0;
              rgba[off + 3] = 255;
            }
          }
        }

        final mask = RegionMask.fromColorTolerance(
          rgbaBytes: rgba,
          width: 4,
          height: 4,
          sourceColor: const ColorRgb(255, 0, 0),
          tolerance: 0.15,
          feather: 0.05,
        );

        // Left 2 columns must be 255 (selected)
        for (int y = 0; y < 4; y++) {
          expect(mask.getPixel(0, y), equals(255));
          expect(mask.getPixel(1, y), equals(255));
          // Right 2 columns must be 0 (unselected)
          expect(mask.getPixel(2, y), equals(0));
          expect(mask.getPixel(3, y), equals(0));
        }
        expect(mask.selectedPixelCount, equals(8));
        expect(mask.coverage, equals(0.5));
      },
    );

    test(
      'Mobile repair tool applies circular brush paint and eraser with falloff',
      () {
        final mask = RegionMask.empty(10, 10);
        expect(mask.getPixel(5, 5), equals(0));

        // Paint brush at center (5, 5) with radius 3
        mask.applyBrush(
          centerX: 5,
          centerY: 5,
          radius: 3,
          opacity: 1.0,
          isEraser: false,
        );

        // Center should now be strongly selected
        expect(mask.getPixel(5, 5), equals(255));
        // Pixels within radius 2 should be partially selected
        expect(mask.getPixel(5, 6), greaterThan(150));
        // Pixels far outside radius should be 0
        expect(mask.getPixel(0, 0), equals(0));

        // Now apply eraser at (5, 5) with radius 1
        mask.applyBrush(
          centerX: 5,
          centerY: 5,
          radius: 1,
          opacity: 1.0,
          isEraser: true,
        );

        // Center pixel was erased
        expect(mask.getPixel(5, 5), equals(0));
      },
    );

    test('Feathering smooths step mask boundaries without artifacts', () {
      final mask = RegionMask.empty(10, 10);
      // Fill left half with 255
      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 5; x++) {
          mask.setPixel(x, y, 255);
        }
      }

      final feathered = mask.featherMask(1);
      // Boundary at x=4 and x=5 should be smoothed (intermediate values)
      for (int y = 0; y < 10; y++) {
        expect(feathered.getPixel(4, y), lessThan(255));
        expect(feathered.getPixel(4, y), greaterThan(0));
        expect(feathered.getPixel(5, y), greaterThan(0));
        expect(feathered.getPixel(5, y), lessThan(255));
      }
    });

    test('Mask invert flips selection values', () {
      final mask = RegionMask.empty(4, 4);
      mask.setPixel(0, 0, 255);
      mask.setPixel(1, 0, 100);

      final inverted = mask.invert();
      expect(inverted.getPixel(0, 0), equals(0));
      expect(inverted.getPixel(1, 0), equals(155));
      expect(inverted.getPixel(2, 0), equals(255));
    });

    test('Extracts mask from Scene Map ColorRegionMapData', () {
      final labels = Uint8List(4 * 4);
      // 0 on top half, 1 on bottom half
      for (int i = 8; i < 16; i++) {
        labels[i] = 1;
      }

      final colorMap = ColorRegionMapData(
        gridWidth: 4,
        gridHeight: 4,
        regionCount: 2,
        regionLabels: labels,
        regionCentroids: {
          0: const NormalizedPoint(0.5, 0.25),
          1: const NormalizedPoint(0.5, 0.75),
        },
        regionCoverage: {0: 0.5, 1: 0.5},
      );

      final mask = RegionMask.fromColorRegionMap(
        mapData: colorMap,
        targetRegionIndex: 1,
        targetWidth: 4,
        targetHeight: 4,
      );

      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final expected = (y >= 2) ? 255 : 0;
          expect(mask.getPixel(x, y), equals(expected));
        }
      }
    });
  });

  group('Recolor Engine & Acceptance Invariants', () {
    test(
      'Unselected pixel difference is strictly zero (Exact protection)',
      () async {
        // 8x8 image: top 4 rows Pure Red, bottom 4 rows Pure Blue
        final testImg = img.Image(width: 8, height: 8);
        for (int y = 0; y < 8; y++) {
          for (int x = 0; x < 8; x++) {
            if (y < 4) {
              testImg.setPixelRgba(x, y, 255, 0, 0, 255);
            } else {
              testImg.setPixelRgba(x, y, 0, 0, 255, 255);
            }
          }
        }
        final rawPng = Uint8List.fromList(img.encodePng(testImg));
        final rawHash = crypto.sha256.convert(rawPng).toString();

        final root = SourceImageNode(
          id: 'root',
          sourceImageHash: rawHash,
          sourceWidth: 8,
          sourceHeight: 8,
        );
        // Target only Red (255, 0, 0) and recolor to Green (0, 255, 0)
        final recolor = RecolorNode(
          id: 'recolor',
          inputNodeId: root.id,
          sourceR: 255,
          sourceG: 0,
          sourceB: 0,
          targetR: 0,
          targetG: 255,
          targetB: 0,
          tolerance: 0.10,
          feather: 0.05,
        );

        final graph = RenderGraph(
          id: 'graph_unselected_check',
          nodes: {root.id: root, recolor.id: recolor},
          outputNodeId: recolor.id,
        );

        final executor = RenderGraphExecutor(cache: RenderNodeCache());
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: rawPng,
        );

        // Verify: Bottom 4 rows (Pure Blue) must have ZERO difference
        for (int y = 4; y < 8; y++) {
          for (int x = 0; x < 8; x++) {
            final off = (y * 8 + x) * 4;
            expect(
              result.pixelBytes[off],
              equals(0),
              reason: 'R changed on unselected pixel',
            );
            expect(
              result.pixelBytes[off + 1],
              equals(0),
              reason: 'G changed on unselected pixel',
            );
            expect(
              result.pixelBytes[off + 2],
              equals(255),
              reason: 'B changed on unselected pixel',
            );
            expect(
              result.pixelBytes[off + 3],
              equals(255),
              reason: 'A changed on unselected pixel',
            );
          }
        }

        // Verify: Top 4 rows (Pure Red) were recolored towards Green
        for (int y = 0; y < 4; y++) {
          for (int x = 0; x < 8; x++) {
            final off = (y * 8 + x) * 4;
            expect(
              result.pixelBytes[off + 1],
              greaterThan(50),
              reason: 'Selected zone was not recolored',
            );
          }
        }
      },
    );

    test('Alpha channel is strictly preserved across transparent and semitransparent pixels', () async {
      // 4x4 image with varied alpha: 0, 64, 128, 255
      final testImg = img.Image(width: 4, height: 4, numChannels: 4);
      final alphaValues = [0, 64, 128, 255];
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          testImg.setPixelRgba(x, y, 255, 0, 0, alphaValues[y]);
        }
      }
      final rawPng = Uint8List.fromList(img.encodePng(testImg));
      final rawHash = crypto.sha256.convert(rawPng).toString();

      final root = SourceImageNode(
        id: 'root',
        sourceImageHash: rawHash,
        sourceWidth: 4,
        sourceHeight: 4,
      );
      final recolor = RecolorNode(
        id: 'recolor',
        inputNodeId: root.id,
        sourceR: 255,
        sourceG: 0,
        sourceB: 0,
        targetR: 0,
        targetG: 0,
        targetB: 255,
      );
      final graph = RenderGraph(
        id: 'graph_alpha',
        nodes: {root.id: root, recolor.id: recolor},
        outputNodeId: recolor.id,
      );

      final executor = RenderGraphExecutor();
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: rawPng,
      );

      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final off = (y * 4 + x) * 4;
          expect(
            result.pixelBytes[off + 3],
            equals(alphaValues[y]),
            reason: 'Alpha corrupted at ($x, $y)',
          );
        }
      }
    });

    test('Luminance ordering holds monotonically on shaded gradient', () async {
      // 16x1 gradient ramp from dark orange to bright orange
      final testImg = img.Image(width: 16, height: 1);
      for (int x = 0; x < 16; x++) {
        final brightness = (x * 16).clamp(0, 255);
        testImg.setPixelRgba(x, 0, brightness, brightness ~/ 2, 0, 255);
      }
      final rawPng = Uint8List.fromList(img.encodePng(testImg));
      final rawHash = crypto.sha256.convert(rawPng).toString();

      final root = SourceImageNode(
        id: 'root',
        sourceImageHash: rawHash,
        sourceWidth: 16,
        sourceHeight: 1,
      );
      // Recolor to Cyan with luminance preservation enabled
      final recolor = RecolorNode(
        id: 'recolor',
        inputNodeId: root.id,
        sourceR: 128,
        sourceG: 64,
        sourceB: 0,
        targetR: 0,
        targetG: 200,
        targetB: 255,
        tolerance: 0.80, // broad tolerance covering the ramp
        preserveLuminance: true,
      );
      final graph = RenderGraph(
        id: 'graph_luma',
        nodes: {root.id: root, recolor.id: recolor},
        outputNodeId: recolor.id,
      );

      final executor = RenderGraphExecutor();
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: rawPng,
      );

      // Check monotonic luminance ordering: Y(x) <= Y(x+1) + tolerance for rounding
      int prevLuma = -1;
      for (int x = 0; x < 16; x++) {
        final off = x * 4;
        final r = result.pixelBytes[off];
        final g = result.pixelBytes[off + 1];
        final b = result.pixelBytes[off + 2];
        final luma = (299 * r + 587 * g + 114 * b) ~/ 1000;

        if (prevLuma != -1) {
          expect(
            luma,
            greaterThanOrEqualTo(prevLuma - 1),
            reason: 'Luma inverted at x=$x (prev=$prevLuma, cur=$luma)',
          );
        }
        prevLuma = luma;
      }
    });

    test('Low-saturation and neutral gray pixels are protected from chromatic noise', () async {
      // 4x4 image: left half Red (255, 0, 0), right half Neutral Gray (128, 128, 128)
      final testImg = img.Image(width: 4, height: 4);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          if (x < 2) {
            testImg.setPixelRgba(x, y, 255, 0, 0, 255);
          } else {
            testImg.setPixelRgba(x, y, 128, 128, 128, 255);
          }
        }
      }
      final rawPng = Uint8List.fromList(img.encodePng(testImg));
      final rawHash = crypto.sha256.convert(rawPng).toString();

      final root = SourceImageNode(
        id: 'root',
        sourceImageHash: rawHash,
        sourceWidth: 4,
        sourceHeight: 4,
      );
      final recolor = RecolorNode(
        id: 'recolor',
        inputNodeId: root.id,
        sourceR: 255,
        sourceG: 0,
        sourceB: 0,
        targetR: 0,
        targetG: 255,
        targetB: 255, // Cyan
        tolerance: 0.30,
        preserveLuminance: true,
      );
      final graph = RenderGraph(
        id: 'graph_neutral',
        nodes: {root.id: root, recolor.id: recolor},
        outputNodeId: recolor.id,
      );

      final executor = RenderGraphExecutor();
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: rawPng,
      );

      // Verify: Gray pixels (right half) remain neutral gray (R == G == B)
      for (int y = 0; y < 4; y++) {
        for (int x = 2; x < 4; x++) {
          final off = (y * 4 + x) * 4;
          final r = result.pixelBytes[off];
          final g = result.pixelBytes[off + 1];
          final b = result.pixelBytes[off + 2];
          expect(r, equals(128));
          expect(g, equals(128));
          expect(b, equals(128));
        }
      }
    });
  });

  group('RecolorController Lifecycle & Invariant 4 Immutability', () {
    test('Undo, Redo, Reset, and Source Immutability verified', () {
      final sampleRgba = Uint8List(16 * 16 * 4);
      for (int i = 0; i < sampleRgba.length; i += 4) {
        sampleRgba[i] = 200;
        sampleRgba[i + 1] = 50;
        sampleRgba[i + 2] = 50;
        sampleRgba[i + 3] = 255;
      }
      final sourceHashBefore = crypto.sha256.convert(sampleRgba).toString();

      final controller = RecolorController(
        sourceRgba: sampleRgba,
        imageWidth: 16,
        imageHeight: 16,
        sourceImageHash: sourceHashBefore,
      );

      expect(controller.state.canUndo, isFalse);
      expect(controller.state.canRedo, isFalse);
      expect(
        controller.state.semanticSegmentationAvailable,
        isFalse,
      ); // Honest reporting

      // 1. Set target color
      controller.setTargetColor(const ColorRgb(0, 255, 0));
      expect(controller.state.canUndo, isTrue);
      expect(controller.state.targetColor, equals(const ColorRgb(0, 255, 0)));

      // 2. Adjust strength
      controller.setStrength(0.5);
      expect(controller.state.strength, equals(0.5));

      // 3. Undo strength
      controller.undo();
      expect(controller.state.strength, equals(1.0));
      expect(controller.state.canRedo, isTrue);

      // 4. Redo strength
      controller.redo();
      expect(controller.state.strength, equals(0.5));

      // 5. Build render graph
      final graph = controller.buildRenderGraph();
      expect(graph.nodes.length, equals(2));
      expect(graph.outputNodeId, equals('node_recolor_1'));

      // 6. Reset
      controller.reset();
      expect(controller.state.targetColor, isNull);
      final identityGraph = controller.buildRenderGraph();
      expect(identityGraph.outputNodeId, equals('src_root'));

      // 7. Verify Invariant 4: Source image bytes remain strictly byte-identical!
      final sourceHashAfter = crypto.sha256.convert(sampleRgba).toString();
      expect(sourceHashAfter, equals(sourceHashBefore));
    });
  });
}
