import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/scene_map/contour_map_data.dart';
import '../../domain/scene_map/coordinate_transform.dart';
import '../../domain/scene_map/edge_map_data.dart';
import '../../domain/scene_map/pyramid_level.dart';

/// Algorithmic extractor for 2D Sobel edge gradients and structural contour boundaries.
/// Implements verified operations OP-03 and OP-04 from the classical engine PoC.
class EdgeContourExtractor {
  const EdgeContourExtractor();

  /// Computes the 3x3 Sobel gradient magnitude landscape over [pyramid].
  /// Edge threshold defaults to 50 (standard high-contrast boundary cutoff).
  EdgeMapData extractEdges(PyramidLevel pyramid, {int edgeThreshold = 50}) {
    final w = pyramid.width;
    final h = pyramid.height;
    final total = w * h;

    if (w < 2 || h < 2) {
      // 1x1 or degenerate input has zero gradient
      return EdgeMapData(
        gridWidth: w,
        gridHeight: h,
        edgeThreshold: edgeThreshold,
        edgeDensity: 0.0,
        highGradientPixelCount: 0,
        edgeMagnitudes: Uint8List(total),
      );
    }

    final magnitudes = Uint8List(total);
    int highCount = 0;

    // 3x3 Sobel kernels
    // Kx: [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
    // Ky: [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]

    for (int y = 0; y < h; y++) {
      final yPrev = (y > 0) ? (y - 1) : 0;
      final yNext = (y < h - 1) ? (y + 1) : (h - 1);

      for (int x = 0; x < w; x++) {
        final xPrev = (x > 0) ? (x - 1) : 0;
        final xNext = (x < w - 1) ? (x + 1) : (w - 1);

        // Sample 8 surrounding neighbors using edge-clamped coordinates
        final tl = pyramid.getLuminance(xPrev, yPrev);
        final tc = pyramid.getLuminance(x, yPrev);
        final tr = pyramid.getLuminance(xNext, yPrev);
        final ml = pyramid.getLuminance(xPrev, y);
        final mr = pyramid.getLuminance(xNext, y);
        final bl = pyramid.getLuminance(xPrev, yNext);
        final bc = pyramid.getLuminance(x, yNext);
        final br = pyramid.getLuminance(xNext, yNext);

        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);

        final mag = math.sqrt(gx * gx + gy * gy).round().clamp(0, 255);
        magnitudes[y * w + x] = mag;

        if (mag >= edgeThreshold) {
          highCount++;
        }
      }
    }

    final density = total > 0 ? (highCount / total) : 0.0;

    return EdgeMapData(
      gridWidth: w,
      gridHeight: h,
      edgeThreshold: edgeThreshold,
      edgeDensity: density,
      highGradientPixelCount: highCount,
      edgeMagnitudes: magnitudes,
    );
  }

  /// Extracts structural boundary contours from [edgeMap].
  /// Traces 8-connected perimeter lines, computes normalized bounds, and normalizes coordinates.
  ContourMapData extractContours(
    EdgeMapData edgeMap, {
    int minContourLength = 4,
    int maxContours = 128,
  }) {
    final w = edgeMap.gridWidth;
    final h = edgeMap.gridHeight;
    final total = w * h;

    if (w < 2 || h < 2 || edgeMap.highGradientPixelCount == 0) {
      return const ContourMapData(
        contours: [],
        totalContourPoints: 0,
        contourDensity: 0.0,
      );
    }

    final visited = Uint8List(total);
    final rawContours = <List<({int x, int y})>>[];

    // 8-connected neighbor offsets
    const dx = [-1, 0, 1, -1, 1, -1, 0, 1];
    const dy = [-1, -1, -1, 0, 0, 1, 1, 1];

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        if (visited[idx] != 0 || !edgeMap.isEdge(x, y)) continue;

        // Start tracing a connected edge component
        visited[idx] = 1;
        final contourPixels = <({int x, int y})>[];
        final queue = <({int x, int y})>[];
        queue.add((x: x, y: y));

        while (queue.isNotEmpty) {
          final curr = queue.removeLast();
          contourPixels.add(curr);

          for (int i = 0; i < 8; i++) {
            final nx = curr.x + dx[i];
            final ny = curr.y + dy[i];

            if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
              final nIdx = ny * w + nx;
              if (visited[nIdx] == 0 && edgeMap.isEdge(nx, ny)) {
                visited[nIdx] = 1;
                queue.add((x: nx, y: ny));
              }
            }
          }
        }

        if (contourPixels.length >= minContourLength) {
          rawContours.add(contourPixels);
        }
      }
    }

    // Sort contours deterministically: descending length, then top-left origin
    rawContours.sort((a, b) {
      if (a.length != b.length) return b.length.compareTo(a.length);
      final pA = a.first;
      final pB = b.first;
      if (pA.y != pB.y) return pA.y.compareTo(pB.y);
      return pA.x.compareTo(pB.x);
    });

    final boundedContours = rawContours.take(maxContours).toList();
    final resultPaths = <ContourPath>[];
    int totalPoints = 0;

    for (final raw in boundedContours) {
      final normPoints = <NormalizedPoint>[];
      double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      double arcLength = 0.0;

      for (int i = 0; i < raw.length; i++) {
        final px = raw[i].x;
        final py = raw[i].y;
        final nx = (w > 1) ? (px / (w - 1)) : 0.0;
        final ny = (h > 1) ? (py / (h - 1)) : 0.0;
        final p = NormalizedPoint.clamped(nx, ny);
        normPoints.add(p);

        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;

        if (i > 0) {
          final prev = normPoints[i - 1];
          final dX = p.x - prev.x;
          final dY = p.y - prev.y;
          arcLength += math.sqrt(dX * dX + dY * dY);
        }
      }

      totalPoints += normPoints.length;

      final bounds = NormalizedRect.clamped(
        left: minX,
        top: minY,
        width: maxX - minX,
        height: maxY - minY,
      );

      resultPaths.add(
        ContourPath(
          points: normPoints,
          bounds: bounds,
          length: arcLength,
          isClosed: false,
        ),
      );
    }

    final contourDensity = total > 0 ? (totalPoints / total) : 0.0;

    return ContourMapData(
      contours: resultPaths,
      totalContourPoints: totalPoints,
      contourDensity: contourDensity.clamp(0.0, 1.0),
    );
  }
}
