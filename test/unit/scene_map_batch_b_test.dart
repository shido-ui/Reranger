import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/scene_map/edge_contour_extractor.dart';
import 'package:reranger/domain/scene_map/contour_map_data.dart';
import 'package:reranger/domain/scene_map/edge_map_data.dart';
import 'package:reranger/domain/scene_map/pyramid_level.dart';

import '../fixtures/synthetic_scene_fixtures.dart';

void main() {
  const extractor = EdgeContourExtractor();

  PyramidLevel imageToPyramid(img.Image image) {
    final w = image.width;
    final h = image.height;
    final lum = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        // ITU-R BT.601 integer luminance: (299*R + 587*G + 114*B) / 1000
        final yVal = (299 * p.r + 587 * p.g + 114 * p.b) ~/ 1000;
        lum[y * w + x] = yVal.clamp(0, 255);
      }
    }
    return PyramidLevel(
      level: 0,
      width: w,
      height: h,
      scaleFactor: 1.0,
      luminanceData: lum,
    );
  }

  group('EdgeMapData & Sobel Extraction (Batch B)', () {
    test(
      'Solid color image produces exactly zero edge gradients and zero density',
      () {
        final solidImg = SyntheticSceneFixtures.createSolidColor(
          width: 32,
          height: 32,
          r: 120,
          g: 120,
          b: 120,
        );
        final pyramid = imageToPyramid(solidImg);
        final edgeMap = extractor.extractEdges(pyramid, edgeThreshold: 30);

        expect(edgeMap.gridWidth, equals(32));
        expect(edgeMap.gridHeight, equals(32));
        expect(edgeMap.edgeDensity, equals(0.0));
        expect(edgeMap.highGradientPixelCount, equals(0));
        for (int i = 0; i < edgeMap.edgeMagnitudes.length; i++) {
          expect(edgeMap.edgeMagnitudes[i], equals(0));
        }
      },
    );

    test('Horizontal split image produces strong gradients along center horizontal line', () {
      final splitImg = SyntheticSceneFixtures.createHorizontalSplit(
        width: 32,
        height: 32,
        topR: 255,
        topG: 255,
        topB: 255,
        bottomR: 0,
        bottomG: 0,
        bottomB: 0,
      );
      final pyramid = imageToPyramid(splitImg);
      final edgeMap = extractor.extractEdges(pyramid, edgeThreshold: 50);

      expect(edgeMap.edgeDensity, greaterThan(0.0));
      expect(edgeMap.highGradientPixelCount, greaterThan(0));

      // Midpoint row (y = 15, 16) must have high gradient magnitudes > 100
      expect(edgeMap.getMagnitude(16, 15), greaterThan(100));
      expect(edgeMap.getMagnitude(16, 16), greaterThan(100));
      // Far corners (uniform) must have zero gradient
      expect(edgeMap.getMagnitude(0, 0), equals(0));
      expect(edgeMap.getMagnitude(31, 31), equals(0));
    });

    test('EdgeMapData serialization roundtrip preserves all values', () {
      final checkerImg = SyntheticSceneFixtures.createCheckerboard4x4(
        width: 32,
        height: 32,
      );
      final pyramid = imageToPyramid(checkerImg);
      final edgeMap = extractor.extractEdges(pyramid, edgeThreshold: 50);

      final json = edgeMap.toJson();
      final restored = EdgeMapData.fromJson(json);
      expect(restored, equals(edgeMap));
    });

    test('1x1 degenerate image does not crash and returns zero edge map', () {
      final tinyImg = SyntheticSceneFixtures.createTiny1x1(r: 255, g: 0, b: 0);
      final pyramid = imageToPyramid(tinyImg);
      final edgeMap = extractor.extractEdges(pyramid);

      expect(edgeMap.gridWidth, equals(1));
      expect(edgeMap.gridHeight, equals(1));
      expect(edgeMap.edgeDensity, equals(0.0));
      expect(edgeMap.highGradientPixelCount, equals(0));
    });
  });

  group('ContourMapData & Boundary Tracing (Batch B)', () {
    test('Solid color image extracts zero contours', () {
      final solidImg = SyntheticSceneFixtures.createSolidColor(
        width: 32,
        height: 32,
      );
      final pyramid = imageToPyramid(solidImg);
      final edgeMap = extractor.extractEdges(pyramid);
      final contours = extractor.extractContours(edgeMap);

      expect(contours.contours, isEmpty);
      expect(contours.totalContourPoints, equals(0));
      expect(contours.contourDensity, equals(0.0));
    });

    test('Center square fixture extracts perimeter contour bounding square precisely', () {
      // 64x64 canvas, 24x24 square centered at (20, 20) to (44, 44)
      final sqImg = SyntheticSceneFixtures.createCenterSquare(
        width: 64,
        height: 64,
        squareSize: 24,
      );
      final pyramid = imageToPyramid(sqImg);
      final edgeMap = extractor.extractEdges(pyramid, edgeThreshold: 50);
      final contourMap = extractor.extractContours(
        edgeMap,
        minContourLength: 8,
      );

      expect(contourMap.contours, isNotEmpty);
      final mainContour = contourMap.contours.first;

      // Verify all contour points are strictly within normalized [0.0, 1.0]
      for (final p in mainContour.points) {
        expect(p.x, greaterThanOrEqualTo(0.0));
        expect(p.x, lessThanOrEqualTo(1.0));
        expect(p.y, greaterThanOrEqualTo(0.0));
        expect(p.y, lessThanOrEqualTo(1.0));
      }

      // Expected normalized bounds: 20/63 ~ 0.317, 44/63 ~ 0.698
      expect(mainContour.bounds.left, closeTo(20 / 63, 0.05));
      expect(mainContour.bounds.top, closeTo(20 / 63, 0.05));
      expect(mainContour.bounds.right, closeTo(44 / 63, 0.05));
      expect(mainContour.bounds.bottom, closeTo(44 / 63, 0.05));
    });

    test(
      'ContourMapData serialization roundtrip preserves paths and bounds',
      () {
        final sqImg = SyntheticSceneFixtures.createCenterSquare(
          width: 32,
          height: 32,
          squareSize: 12,
        );
        final pyramid = imageToPyramid(sqImg);
        final edgeMap = extractor.extractEdges(pyramid, edgeThreshold: 50);
        final contourMap = extractor.extractContours(
          edgeMap,
          minContourLength: 4,
        );

        final json = contourMap.toJson();
        final restored = ContourMapData.fromJson(json);
        expect(restored, equals(contourMap));
      },
    );
  });
}
