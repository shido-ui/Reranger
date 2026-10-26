import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../domain/autodraw_models.dart';
import 'autodraw_analysis_engine.dart';

// ============================================================================
// Dart FFI Struct & Function Signatures for Native C++ Skeleton Engine
// ============================================================================

final class NativeStrokeBuffer extends ffi.Struct {
  external ffi.Pointer<ffi.Int16> pointsXY;
  external ffi.Pointer<ffi.Uint8> widths;
  external ffi.Pointer<ffi.Uint32> offsets;

  @ffi.Int32()
  external int strokeCount;

  @ffi.Int32()
  external int totalPoints;
}

typedef _NativeSkeletonTraceC = ffi.Pointer<NativeStrokeBuffer> Function(
  ffi.Pointer<ffi.Uint8> rgba,
  ffi.Int32 width,
  ffi.Int32 height,
  ffi.Int32 maxStrokes,
);
typedef _NativeSkeletonTraceDart = ffi.Pointer<NativeStrokeBuffer> Function(
  ffi.Pointer<ffi.Uint8> rgba,
  int width,
  int height,
  int maxStrokes,
);

typedef _NativeStrokeBufferFreeC = ffi.Void Function(
  ffi.Pointer<NativeStrokeBuffer> buffer,
);
typedef _NativeStrokeBufferFreeDart = void Function(
  ffi.Pointer<NativeStrokeBuffer> buffer,
);

class _VectorizeTaskParams {
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final int maxPaths;

  const _VectorizeTaskParams({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.maxPaths,
  });
}

/// Autodraw Engine V3 (Centerline Skeletonization, Guo-Hall Thinning, Pre-Computed Pipeline):
/// - Step A (Loading): Displays "Preparing artist sequence..." spinner while Isolate executes.
/// - Step B (Pre-computation): Runs Guo-Hall thinning & Medial Axis distance transform in background Isolate.
/// - Step C (Playback): Returns zero-copy FlatStrokeBuffer with strictly ordered passes:
///   Pass 1: The Sketch (Centerline Lines) - 1-pixel skeleton (strokeWidth = 1.0 - 2.5, dark ink).
///   Pass 2: The Color (Fills) - Broad painterly color strokes (strokeWidth = 6.0 - 15.0).
///   Pass 3: The Highlights - Bright spots (Luminance > 0.85).
class PotraceVectorizer {
  const PotraceVectorizer();

  /// Executes the Pre-Computed Artist Pipeline on a background isolate via [Isolate.run].
  Future<AutodrawVectorizationResult> vectorizeImage({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    int maxPaths = 2500,
  }) async {
    final params = _VectorizeTaskParams(
      rgbaBytes: rgbaBytes,
      width: width,
      height: height,
      maxPaths: maxPaths,
    );

    // Guaranteed execution on a background isolate
    return await Isolate.run(() => _vectorizeWorker(params));
  }

  /// Worker function executing on the background isolate.
  static AutodrawVectorizationResult _vectorizeWorker(
    _VectorizeTaskParams params,
  ) {
    final width = params.width;
    final height = params.height;
    final total = width * height;
    final rgba = params.rgbaBytes;

    if (total == 0 || rgba.length < total * 4) {
      return AutodrawVectorizationResult(
        width: width,
        height: height,
        commands: [],
      );
    }

    // Attempt native C++ FFI first if dynamic library is available
    final nativeResult = _tryNativeSkeletonTrace(params);
    if (nativeResult != null) {
      return nativeResult;
    }

    // 0. Luminance computation for edge and highlight extraction
    final lum = Uint8List(total);
    for (int i = 0; i < total; i++) {
      final off = i * 4;
      lum[i] =
          (0.299 * rgba[off] + 0.587 * rgba[off + 1] + 0.114 * rgba[off + 2])
              .round()
              .clamp(0, 255);
    }

    int nextCommandId = 1;

    // -------------------------------------------------------------------------
    // PASS 1: The Sketch (Centerline Lines via Guo-Hall Thinning & Medial Axis)
    // -------------------------------------------------------------------------
    final lineCommands = <AutodrawCommand>[];
    final maxLinePaths = (params.maxPaths * 0.45).round().clamp(10, 1500);

    // 1. Integral Image Adaptive Thresholding + Sobel Edge detection
    final binaryMap = Uint8List(total);
    final edgeMap = Uint8List(total);

    // Compute integral image
    final integral = Int32List(total);
    for (int y = 0; y < height; y++) {
      int rowSum = 0;
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        rowSum += lum[idx];
        integral[idx] = rowSum + (y > 0 ? integral[idx - width] : 0);
      }
    }

    final winR = math.max(7, width ~/ 32);

    for (int y = 1; y < height - 1; y++) {
      final rowOff = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = rowOff + x;

        // Sobel kernels
        final p00 = lum[idx - width - 1];
        final p01 = lum[idx - width];
        final p02 = lum[idx - width + 1];
        final p10 = lum[idx - 1];
        final p12 = lum[idx + 1];
        final p20 = lum[idx + width - 1];
        final p21 = lum[idx + width];
        final p22 = lum[idx + width + 1];

        final gx = (p02 + 2 * p12 + p22) - (p00 + 2 * p10 + p20);
        final gy = (p20 + 2 * p21 + p22) - (p00 + 2 * p01 + p02);
        final mag = (gx.abs() + gy.abs()) >> 1;

        // Color difference
        final leftOff = (idx - 1) * 4;
        final rightOff = (idx + 1) * 4;
        final cDiff =
            (rgba[rightOff] - rgba[leftOff]).abs() +
            (rgba[rightOff + 1] - rgba[leftOff + 1]).abs() +
            (rgba[rightOff + 2] - rgba[leftOff + 2]).abs();

        if (mag >= 36 || cDiff >= 70) {
          edgeMap[idx] = 1;
        }

        // Adaptive threshold
        final x0 = math.max(0, x - winR);
        final y0 = math.max(0, y - winR);
        final x1 = math.min(width - 1, x + winR);
        final y1 = math.min(height - 1, y + winR);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);

        int sum = integral[y1 * width + x1];
        if (x0 > 0) sum -= integral[y1 * width + x0 - 1];
        if (y0 > 0) sum -= integral[(y0 - 1) * width + x1];
        if (x0 > 0 && y0 > 0) sum += integral[(y0 - 1) * width + x0 - 1];

        final localMean = sum / area;
        if (lum[idx] < localMean * 0.88 || edgeMap[idx] == 1) {
          binaryMap[idx] = 1;
        }
      }
    }

    // 1b. Mandate 1: 3x3 Median Filter to remove salt-and-pepper noise
    final medianFiltered = Uint8List(total);
    for (int y = 0; y < height; y++) {
      final yTop = math.max(0, y - 1);
      final yBot = math.min(height - 1, y + 1);
      for (int x = 0; x < width; x++) {
        final xLeft = math.max(0, x - 1);
        final xRight = math.min(width - 1, x + 1);

        int count = 0;
        int winTotal = 0;
        for (int ny = yTop; ny <= yBot; ny++) {
          final rIdx = ny * width;
          for (int nx = xLeft; nx <= xRight; nx++) {
            count += binaryMap[rIdx + nx];
            winTotal++;
          }
        }
        medianFiltered[y * width + x] = (count >= (winTotal + 1) ~/ 2) ? 1 : 0;
      }
    }
    binaryMap.setAll(0, medianFiltered);

    // 1c. Mandate 1: Connected Component Analysis (CCA) - Delete components < 15 px
    final visitedCca = Uint8List(total);
    final component = <int>[];
    final queue = <int>[];
    const ccaDx = [-1, 0, 1, -1, 1, -1, 0, 1];
    const ccaDy = [-1, -1, -1, 0, 0, 1, 1, 1];

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        if (binaryMap[idx] == 0 || visitedCca[idx] == 1) continue;

        component.clear();
        queue.clear();

        visitedCca[idx] = 1;
        queue.add(idx);
        component.add(idx);

        int head = 0;
        while (head < queue.length) {
          final curr = queue[head++];
          final cx = curr % width;
          final cy = curr ~/ width;

          for (int d = 0; d < 8; d++) {
            final nx = cx + ccaDx[d];
            final ny = cy + ccaDy[d];
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final nidx = ny * width + nx;
              if (binaryMap[nidx] == 1 && visitedCca[nidx] == 0) {
                visitedCca[nidx] = 1;
                queue.add(nidx);
                component.add(nidx);
              }
            }
          }
        }

        // Isolated component smaller than 15 pixels must be deleted
        if (component.length < 15) {
          for (final cIdx in component) {
            binaryMap[cIdx] = 0;
          }
        }
      }
    }

    // 2. Medial Axis via 2-Pass Chamfer Distance Transform
    final distMap = Uint16List(total);
    for (int i = 0; i < total; i++) {
      distMap[i] = binaryMap[i] == 1 ? 9999 : 0;
    }

    // Forward pass
    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = row + x;
        if (distMap[idx] > 0) {
          int d = distMap[idx];
          d = math.min(d, distMap[idx - width] + 5);
          d = math.min(d, distMap[idx - 1] + 5);
          d = math.min(d, distMap[idx - width - 1] + 7);
          d = math.min(d, distMap[idx - width + 1] + 7);
          distMap[idx] = d;
        }
      }
    }

    // Backward pass
    for (int y = height - 2; y >= 1; y--) {
      final row = y * width;
      for (int x = width - 2; x >= 1; x--) {
        final idx = row + x;
        if (distMap[idx] > 0) {
          int d = distMap[idx];
          d = math.min(d, distMap[idx + width] + 5);
          d = math.min(d, distMap[idx + 1] + 5);
          d = math.min(d, distMap[idx + width + 1] + 7);
          d = math.min(d, distMap[idx + width - 1] + 7);
          distMap[idx] = d;
        }
      }
    }

    // 3. Guo-Hall Thinning (Parallel 2-Subiteration Centerline Thinning)
    final skeleton = Uint8List.fromList(binaryMap);
    final toDelete = <int>[];

    for (int iter = 0; iter < 48; iter++) {
      // Sub-iteration 1
      toDelete.clear();
      for (int y = 1; y < height - 1; y++) {
        final row = y * width;
        for (int x = 1; x < width - 1; x++) {
          final idx = row + x;
          if (skeleton[idx] == 0) continue;

          final p2 = skeleton[idx - width];
          final p3 = skeleton[idx - width + 1];
          final p4 = skeleton[idx + 1];
          final p5 = skeleton[idx + width + 1];
          final p6 = skeleton[idx + width];
          final p7 = skeleton[idx + width - 1];
          final p8 = skeleton[idx - 1];
          final p9 = skeleton[idx - width - 1];

          final c =
              ((1 - p2) & (p3 | p4)) +
              ((1 - p4) & (p5 | p6)) +
              ((1 - p6) & (p7 | p8)) +
              ((1 - p8) & (p9 | p2));
          if (c != 1) continue;

          final n1 = math.min(p9 | p2, p3 | p4);
          final n2 = math.min(p5 | p6, p7 | p8);
          final n = n1 + n2;
          if (n < 2 || n > 3) continue;

          if (((p2 | p3 | (1 - p5)) & p4) == 0) {
            toDelete.add(idx);
          }
        }
      }
      for (final idx in toDelete) {
        skeleton[idx] = 0;
      }
      final sub1Deleted = toDelete.length;

      // Sub-iteration 2
      toDelete.clear();
      for (int y = 1; y < height - 1; y++) {
        final row = y * width;
        for (int x = 1; x < width - 1; x++) {
          final idx = row + x;
          if (skeleton[idx] == 0) continue;

          final p2 = skeleton[idx - width];
          final p3 = skeleton[idx - width + 1];
          final p4 = skeleton[idx + 1];
          final p5 = skeleton[idx + width + 1];
          final p6 = skeleton[idx + width];
          final p7 = skeleton[idx + width - 1];
          final p8 = skeleton[idx - 1];
          final p9 = skeleton[idx - width - 1];

          final c =
              ((1 - p2) & (p3 | p4)) +
              ((1 - p4) & (p5 | p6)) +
              ((1 - p6) & (p7 | p8)) +
              ((1 - p8) & (p9 | p2));
          if (c != 1) continue;

          final n1 = math.min(p9 | p2, p3 | p4);
          final n2 = math.min(p5 | p6, p7 | p8);
          final n = n1 + n2;
          if (n < 2 || n > 3) continue;

          if (((p6 | p7 | (1 - p9)) & p8) == 0) {
            toDelete.add(idx);
          }
        }
      }
      for (final idx in toDelete) {
        skeleton[idx] = 0;
      }

      if (sub1Deleted == 0 && toDelete.isEmpty) break;
    }

    // 4. Trace 8-Connected Skeleton Pixels into Polylines + Spur Pruning (< 6px)
    final visitedSkel = Uint8List(total);
    final candidateStrokes = <List<Offset>>[];
    final strokeWidths = <double>[];

    const dx = [1, 1, 0, -1, -1, -1, 0, 1];
    const dy = [0, 1, 1, 1, 0, -1, -1, -1];

    for (int y = 1; y < height - 1; y++) {
      final row = y * width;
      for (int x = 1; x < width - 1; x++) {
        final idx = row + x;
        if (skeleton[idx] == 0 || visitedSkel[idx] == 1) continue;

        final polyline = <Offset>[];
        double sumWidth = 0.0;
        int cx = x, cy = y;

        for (int step = 0; step < 96; step++) {
          final cidx = cy * width + cx;
          visitedSkel[cidx] = 1;
          polyline.add(Offset(cx.toDouble(), cy.toDouble()));

          final w = ((distMap[cidx] / 5.0) * 2.0).clamp(1.0, 25.0);
          sumWidth += w;

          int nx = -1, ny = -1;
          for (int d = 0; d < 8; d++) {
            final tx = cx + dx[d];
            final ty = cy + dy[d];
            if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
              final tidx = ty * width + tx;
              if (skeleton[tidx] == 1 && visitedSkel[tidx] == 0) {
                nx = tx;
                ny = ty;
                break;
              }
            }
          }
          if (nx == -1) break;
          cx = nx;
          cy = ny;
        }

        // Spur pruning: Ignore short spurs (< 6px) to eliminate double-loops & visual noise
        double strokeLen = 0.0;
        for (int k = 1; k < polyline.length; k++) {
          strokeLen += (polyline[k] - polyline[k - 1]).distance;
        }
        if (strokeLen < 6.0 && polyline.length < 5) continue;

        // Simplify using Ramer-Douglas-Peucker (RDP) epsilon = 0.3px to preserve smooth curvature
        final simplified = _rdpSimplify(polyline, 0.3);
        if (simplified.length < 2) continue;

        candidateStrokes.add(simplified);
        strokeWidths.add((sumWidth / polyline.length).clamp(1.0, 2.5));
      }
    }

    // 5. 256x256 Tone Coverage Buffer to Skip Redundant Hatching (> 92%)
    const covDim = 256;
    final covBuffer = Uint8List(covDim * covDim);
    final acceptedStrokes = <List<Offset>>[];
    final acceptedWidths = <double>[];

    for (int i = 0; i < candidateStrokes.length; i++) {
      final st = candidateStrokes[i];
      int overdrawnPts = 0;
      for (final pt in st) {
        final cx = ((pt.dx / width) * covDim).round().clamp(0, covDim - 1);
        final cy = ((pt.dy / height) * covDim).round().clamp(0, covDim - 1);
        if (covBuffer[cy * covDim + cx] > 18) {
          overdrawnPts++;
        }
      }
      if (st.length > 3 && overdrawnPts > (st.length * 0.92)) {
        continue; // Skip redundant overlapping lines
      }

      // Mark coverage buffer
      for (final pt in st) {
        final cx = ((pt.dx / width) * covDim).round().clamp(0, covDim - 1);
        final cy = ((pt.dy / height) * covDim).round().clamp(0, covDim - 1);
        covBuffer[cy * covDim + cx] = (covBuffer[cy * covDim + cx] + 4).clamp(
          0,
          255,
        );
      }

      acceptedStrokes.add(st);
      acceptedWidths.add(strokeWidths[i]);
    }

    // 6. Greedy Nearest-Endpoint TSP Stroke Ordering (Major Structures First)
    final orderedStrokes = <List<Offset>>[];
    final orderedWidths = <double>[];
    if (acceptedStrokes.isNotEmpty) {
      // Sort primary structures (longest) first
      final indexed = List.generate(acceptedStrokes.length, (i) => i);
      indexed.sort((a, b) {
        return acceptedStrokes[b].length.compareTo(acceptedStrokes[a].length);
      });

      final used = List<bool>.filled(acceptedStrokes.length, false);
      int cur = indexed.first;
      used[cur] = true;
      orderedStrokes.add(acceptedStrokes[cur]);
      orderedWidths.add(acceptedWidths[cur]);
      Offset pen = acceptedStrokes[cur].last;

      for (int step = 1; step < acceptedStrokes.length; step++) {
        double minD = 1e9;
        int best = -1;
        bool reverse = false;

        for (int i = 0; i < acceptedStrokes.length; i++) {
          if (used[i]) continue;
          final d1 = (acceptedStrokes[i].first - pen).distanceSquared;
          final d2 = (acceptedStrokes[i].last - pen).distanceSquared;
          if (d1 < minD) {
            minD = d1;
            best = i;
            reverse = false;
          }
          if (d2 < minD) {
            minD = d2;
            best = i;
            reverse = true;
          }
        }

        if (best == -1) break;
        used[best] = true;
        final chosen = reverse
            ? acceptedStrokes[best].reversed.toList()
            : acceptedStrokes[best];
        orderedStrokes.add(chosen);
        orderedWidths.add(acceptedWidths[best]);
        pen = chosen.last;
      }
    }

    // 7. Fit smooth Bézier curves to centerline skeleton strokes for Pass 1
    for (
      int i = 0;
      i < orderedStrokes.length && lineCommands.length < maxLinePaths;
      i++
    ) {
      final poly = orderedStrokes[i];
      final segments = <BezierSegment>[];
      for (int s = 0; s < poly.length - 1; s++) {
        final p0 = poly[s];
        final p3 = poly[s + 1];
        final prev = s > 0 ? poly[s - 1] : p0;
        final next = s + 2 < poly.length ? poly[s + 2] : p3;

        final t0 = (p3 - prev) * 0.35;
        final t3 = (next - p0) * 0.35;
        final cp1 = Offset(
          (p0.dx + t0.dx / 3.0).clamp(0.0, width.toDouble()),
          (p0.dy + t0.dy / 3.0).clamp(0.0, height.toDouble()),
        );
        final cp2 = Offset(
          (p3.dx - t3.dx / 3.0).clamp(0.0, width.toDouble()),
          (p3.dy - t3.dy / 3.0).clamp(0.0, height.toDouble()),
        );
        segments.add(BezierSegment(cp1: cp1, cp2: cp2, end: p3));
      }

      lineCommands.add(
        AutodrawCommand.drawLine(
          id: nextCommandId++,
          startPoint: poly.first,
          segments: segments,
          strokeWidth: orderedWidths[i],
          color: const Color(0xFF1E1E24),
          layer: AutodrawTonalLayer.background,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // PASS 2: The Color (Fills) - Sampled average color with broad brush
    // -------------------------------------------------------------------------
    final fillCommands = <AutodrawCommand>[];
    final maxFillPaths = (params.maxPaths * 0.40).round().clamp(10, 1500);

    final tonalBands = const [
      (0, 50),
      (50, 100),
      (100, 150),
      (150, 200),
      (200, 256),
    ];

    for (final (low, high) in tonalBands) {
      if (fillCommands.length >= maxFillPaths) break;

      final bandMask = Uint8List(total);
      int bandPixels = 0;

      for (int i = 0; i < total; i++) {
        final l = lum[i];
        if (l >= low && l < high) {
          bandMask[i] = 1;
          bandPixels++;
        }
      }

      if (bandPixels == 0) continue;

      final bandMidLum = (low + high) / 2.0;
      final regionLayer = bandMidLum < 85
          ? AutodrawTonalLayer.background
          : bandMidLum > 170
          ? AutodrawTonalLayer.highlights
          : AutodrawTonalLayer.midtones;

      for (int y = 2; y < height - 2;) {
        if (fillCommands.length >= maxFillPaths) break;
        final rowVar = AutodrawAnalysisEngine.computeLocalVariance(
          width ~/ 2,
          y,
          4,
          lum,
          width,
          height,
        );
        final fillStride = (rowVar > 16.0) ? 3 : 6;
        int runStart = -1;

        for (int x = 2; x < width - 2; x++) {
          if (fillCommands.length >= maxFillPaths) break;
          final idx = y * width + x;

          if (bandMask[idx] == 1) {
            if (runStart == -1) runStart = x;

            final isEnd =
                (x - runStart >= 24) ||
                (x == width - 3) ||
                (bandMask[idx + 1] == 0);

            if (isEnd) {
              final runLen = x - runStart + 1;
              if (runLen >= 3) {
                final p0 = Offset(runStart.toDouble(), y.toDouble());
                final p3 = Offset(x.toDouble(), y.toDouble());

                final arcY = (y + (y % 4 == 0 ? 1.5 : -1.5)).toDouble().clamp(
                  0.0,
                  height.toDouble(),
                );
                final cp1 = Offset(
                  (runStart + (x - runStart) * 0.33).clamp(
                    0.0,
                    width.toDouble(),
                  ),
                  arcY,
                );
                final cp2 = Offset(
                  (runStart + (x - runStart) * 0.66).clamp(
                    0.0,
                    width.toDouble(),
                  ),
                  arcY,
                );

                final perceptualColor =
                    AutodrawAnalysisEngine.sampleRunPerceptualColor(
                      rgba,
                      width,
                      height,
                      runStart,
                      x,
                      y,
                    );

                final midRunX = (runStart + x) ~/ 2;
                final runGrad = AutodrawAnalysisEngine.computeSobelGradient(
                  midRunX,
                  y,
                  lum,
                  width,
                  height,
                );
                final dynFillWidth =
                    AutodrawAnalysisEngine.computeDynamicStrokeWidth(
                      gradient: runGrad,
                      isEdgeLine: false,
                    );

                final localLum =
                    (0.299 * (perceptualColor.r * 255) +
                            0.587 * (perceptualColor.g * 255) +
                            0.114 * (perceptualColor.b * 255))
                        .round();
                final strokeLayer = localLum < 85
                    ? AutodrawTonalLayer.background
                    : localLum > 170
                    ? AutodrawTonalLayer.highlights
                    : regionLayer;

                fillCommands.add(
                  AutodrawCommand.fillRegion(
                    id: nextCommandId++,
                    startPoint: p0,
                    segments: [BezierSegment(cp1: cp1, cp2: cp2, end: p3)],
                    color: perceptualColor,
                    strokeWidth: dynFillWidth,
                    isClosed: false,
                    layer: strokeLayer,
                  ),
                );
              }
              runStart = -1;
            }
          } else {
            runStart = -1;
          }
        }
        y += fillStride;
      }

      // Add closed perimeter fills for the region to guarantee solid contour fill
      final visitedPerimeter = Uint8List(total);
      for (int y = 2; y < height - 2; y += 4) {
        if (fillCommands.length >= maxFillPaths) break;
        for (int x = 2; x < width - 2; x += 4) {
          if (fillCommands.length >= maxFillPaths) break;
          final idx = y * width + x;
          if (bandMask[idx] == 0 || visitedPerimeter[idx] == 1) continue;

          final isBoundary =
              bandMask[idx - 1] == 0 ||
              bandMask[idx + 1] == 0 ||
              bandMask[idx - width] == 0 ||
              bandMask[idx + width] == 0;
          if (!isBoundary) continue;

          final contour = <Offset>[];
          int cx = x, cy = y;
          for (int s = 0; s < 48; s++) {
            visitedPerimeter[cy * width + cx] = 1;
            contour.add(Offset(cx.toDouble(), cy.toDouble()));

            int nx = -1, ny = -1;
            for (int d = 0; d < 8; d++) {
              final tx = cx + dx[d];
              final ty = cy + dy[d];
              if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
                final tidx = ty * width + tx;
                if (bandMask[tidx] == 1 && visitedPerimeter[tidx] == 0) {
                  nx = tx;
                  ny = ty;
                  break;
                }
              }
            }
            if (nx == -1) break;
            cx = nx;
            cy = ny;
          }

          if (contour.length >= 4) {
            final segs = <BezierSegment>[];
            for (int k = 0; k < contour.length - 1; k++) {
              final p0 = contour[k];
              final p1 = contour[k + 1];
              final cp = (p0 + p1) * 0.5;
              segs.add(BezierSegment(cp1: cp, cp2: cp, end: p1));
            }
            final contourIndices = <int>[];
            for (final pt in contour) {
              contourIndices.add(
                pt.dy.round().clamp(0, height - 1) * width +
                    pt.dx.round().clamp(0, width - 1),
              );
            }
            final contourColor = AutodrawAnalysisEngine.samplePerceptualColor(
              rgba,
              width,
              height,
              contourIndices,
            );
            fillCommands.add(
              AutodrawCommand.fillRegion(
                id: nextCommandId++,
                startPoint: contour.first,
                segments: segs,
                color: contourColor,
                strokeWidth: 6.0,
                isClosed: true,
                layer: regionLayer,
              ),
            );
          }
        }
      }
    }

    // -------------------------------------------------------------------------
    // PASS 3: The Highlights - Bright spots (Luminance > 0.85)
    // -------------------------------------------------------------------------
    final highlightCommands = <AutodrawCommand>[];
    final maxHighlightPaths = (params.maxPaths * 0.20).round().clamp(10, 600);

    const hiThreshold = 217;
    final hiMask = Uint8List(total);
    int hiPixels = 0;

    for (int i = 0; i < total; i++) {
      if (lum[i] >= hiThreshold) {
        hiMask[i] = 1;
        hiPixels++;
      }
    }

    if (hiPixels < 16) {
      int maxLum = 0;
      for (int i = 0; i < total; i++) {
        if (lum[i] > maxLum) maxLum = lum[i];
      }
      final adaptiveThreshold = math.max(160, maxLum - 35);
      for (int i = 0; i < total; i++) {
        if (lum[i] >= adaptiveThreshold) {
          hiMask[i] = 1;
          hiPixels++;
        }
      }
    }

    final visitedHi = Uint8List(total);
    for (int y = 1; y < height - 1; y++) {
      if (highlightCommands.length >= maxHighlightPaths) break;
      for (int x = 1; x < width - 1; x++) {
        if (highlightCommands.length >= maxHighlightPaths) break;
        final idx = y * width + x;
        if (hiMask[idx] == 0 || visitedHi[idx] == 1) continue;

        final contour = <Offset>[];
        int cx = x, cy = y;

        for (int s = 0; s < 36; s++) {
          visitedHi[cy * width + cx] = 1;
          contour.add(Offset(cx.toDouble(), cy.toDouble()));

          int nx = -1, ny = -1;
          for (int d = 0; d < 8; d++) {
            final tx = cx + dx[d];
            final ty = cy + dy[d];
            if (tx >= 0 && tx < width && ty >= 0 && ty < height) {
              final tidx = ty * width + tx;
              if (hiMask[tidx] == 1 && visitedHi[tidx] == 0) {
                nx = tx;
                ny = ty;
                break;
              }
            }
          }
          if (nx == -1) break;
          cx = nx;
          cy = ny;
        }

        if (contour.length >= 2) {
          final segs = <BezierSegment>[];
          for (int k = 0; k < contour.length - 1; k++) {
            final p0 = contour[k];
            final p1 = contour[k + 1];
            final cp = (p0 + p1) * 0.5;
            segs.add(BezierSegment(cp1: cp, cp2: cp, end: p1));
          }

          final hiGrad = AutodrawAnalysisEngine.computeSobelGradient(
            cx,
            cy,
            lum,
            width,
            height,
          );
          final hiWidth = (1.5 + (1.0 - (hiGrad / 255.0).clamp(0.0, 1.0)) * 0.7)
              .clamp(1.5, 2.2);

          final hiIndices = <int>[];
          for (final pt in contour) {
            hiIndices.add(
              pt.dy.round().clamp(0, height - 1) * width +
                  pt.dx.round().clamp(0, width - 1),
            );
          }
          final percHiColor = AutodrawAnalysisEngine.samplePerceptualColor(
            rgba,
            width,
            height,
            hiIndices,
          );
          final outR = math.max((percHiColor.r * 255).round(), 215);
          final outG = math.max((percHiColor.g * 255).round(), 215);
          final outB = math.max((percHiColor.b * 255).round(), 215);
          final hiColor = Color.fromARGB(255, outR, outG, outB);

          highlightCommands.add(
            AutodrawCommand.drawHighlight(
              id: nextCommandId++,
              startPoint: contour.first,
              segments: segs,
              strokeWidth: hiWidth,
              color: hiColor,
              layer: AutodrawTonalLayer.highlights,
            ),
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // Fallback on flat/tiny images
    // -------------------------------------------------------------------------
    if (lineCommands.isEmpty && width > 0 && height > 0) {
      final fw = width.toDouble();
      final fh = height.toDouble();
      lineCommands.add(
        AutodrawCommand.drawLine(
          id: nextCommandId++,
          startPoint: Offset.zero,
          segments: [
            BezierSegment(
              cp1: Offset(fw * 0.33, 0),
              cp2: Offset(fw * 0.66, 0),
              end: Offset(fw, 0),
            ),
            BezierSegment(
              cp1: Offset(fw, fh * 0.33),
              cp2: Offset(fw, fh * 0.66),
              end: Offset(fw, fh),
            ),
            BezierSegment(
              cp1: Offset(fw * 0.66, fh),
              cp2: Offset(fw * 0.33, fh),
              end: Offset(0, fh),
            ),
            BezierSegment(
              cp1: Offset(0, fh * 0.66),
              cp2: Offset(0, fh * 0.33),
              end: Offset.zero,
            ),
          ],
          strokeWidth: 1.5,
          color: const Color(0xFF1E1E24),
          layer: AutodrawTonalLayer.background,
        ),
      );
    }

    if (fillCommands.isEmpty && width > 0 && height > 0) {
      final midX = width ~/ 2;
      final midY = height ~/ 2;
      final off = (midY * width + midX) * 4;
      final c = Color.fromARGB(255, rgba[off], rgba[off + 1], rgba[off + 2]);
      fillCommands.add(
        AutodrawCommand.fillRegion(
          id: nextCommandId++,
          startPoint: Offset(width * 0.2, height * 0.5),
          segments: [
            BezierSegment(
              cp1: Offset(width * 0.4, height * 0.48),
              cp2: Offset(width * 0.6, height * 0.52),
              end: Offset(width * 0.8, height * 0.5),
            ),
          ],
          color: c,
          strokeWidth: 10.0,
          isClosed: false,
          layer: AutodrawTonalLayer.midtones,
        ),
      );
    }

    if (highlightCommands.isEmpty && width > 0 && height > 0) {
      highlightCommands.add(
        AutodrawCommand.drawHighlight(
          id: nextCommandId++,
          startPoint: Offset(width * 0.45, height * 0.45),
          segments: [
            BezierSegment(
              cp1: Offset(width * 0.48, height * 0.45),
              cp2: Offset(width * 0.52, height * 0.45),
              end: Offset(width * 0.55, height * 0.45),
            ),
          ],
          strokeWidth: 2.0,
          color: const Color(0xFFFFFFFF),
          layer: AutodrawTonalLayer.highlights,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // FINAL SORTING (Mandates 1 & 2): Strictly ordered
    // All Lines -> All Fills -> All Highlights
    // -------------------------------------------------------------------------
    final allCommands = <AutodrawCommand>[
      ...lineCommands,
      ...fillCommands,
      ...highlightCommands,
    ];

    allCommands.sort(
      (a, b) => a.actionType.orderIndex.compareTo(b.actionType.orderIndex),
    );

    // Package zero-copy FlatStrokeBuffer
    final flatBuffer = FlatStrokeBuffer.fromCommands(
      allCommands,
      width,
      height,
    );

    return AutodrawVectorizationResult(
      width: width,
      height: height,
      commands: allCommands,
      flatStrokeBuffer: flatBuffer,
    );
  }

  /// Ramer-Douglas-Peucker (RDP) Polyline Simplification
  static List<Offset> _rdpSimplify(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;

    double maxDist = 0.0;
    int index = 0;
    final first = points.first;
    final last = points.last;
    final dx = last.dx - first.dx;
    final dy = last.dy - first.dy;
    final lenSq = dx * dx + dy * dy;

    for (int i = 1; i < points.length - 1; i++) {
      final pt = points[i];
      double dist;
      if (lenSq < 1e-6) {
        final ddx = pt.dx - first.dx;
        final ddy = pt.dy - first.dy;
        dist = math.sqrt(ddx * ddx + ddy * ddy);
      } else {
        final t = ((pt.dx - first.dx) * dx + (pt.dy - first.dy) * dy) / lenSq;
        final projX = first.dx + t.clamp(0.0, 1.0) * dx;
        final projY = first.dy + t.clamp(0.0, 1.0) * dy;
        final ddx = pt.dx - projX;
        final ddy = pt.dy - projY;
        dist = math.sqrt(ddx * ddx + ddy * ddy);
      }
      if (dist > maxDist) {
        maxDist = dist;
        index = i;
      }
    }

    if (maxDist > epsilon) {
      final left = _rdpSimplify(points.sublist(0, index + 1), epsilon);
      final right = _rdpSimplify(points.sublist(index), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [first, last];
    }
  }

  /// Attempts to call the C++ native skeletonization engine via FFI.
  static AutodrawVectorizationResult? _tryNativeSkeletonTrace(
    _VectorizeTaskParams params,
  ) {
    try {
      ffi.DynamicLibrary? lib;
      if (Platform.isAndroid) {
        lib = ffi.DynamicLibrary.open('libclassical_engine.so');
      } else if (Platform.isLinux) {
        const paths = [
          'poc/classical_engine/cpp/build/libclassical_engine_native.so',
          'libclassical_engine.so',
        ];
        for (final p in paths) {
          if (File(p).existsSync()) {
            lib = ffi.DynamicLibrary.open(p);
            break;
          }
        }
      }

      if (lib == null) return null;

      final traceFunc = lib
          .lookupFunction<_NativeSkeletonTraceC, _NativeSkeletonTraceDart>(
            'native_skeleton_trace',
          );
      final freeFunc = lib
          .lookupFunction<
            _NativeStrokeBufferFreeC,
            _NativeStrokeBufferFreeDart
          >('native_stroke_buffer_free');

      final total = params.width * params.height;
      final ptr = callocBytes(total * 4);
      ptr.asTypedList(total * 4).setAll(0, params.rgbaBytes);

      final nativeBuf = traceFunc(
        ptr,
        params.width,
        params.height,
        params.maxPaths,
      );
      freeBytes(ptr);

      if (nativeBuf.address == 0) return null;

      final sCount = nativeBuf.ref.strokeCount;
      final tPoints = nativeBuf.ref.totalPoints;

      final ptsList = nativeBuf.ref.pointsXY.asTypedList(tPoints * 2);
      final wList = nativeBuf.ref.widths.asTypedList(tPoints);
      final oList = nativeBuf.ref.offsets.asTypedList(sCount + 1);

      // Deep copy before freeing native heap buffer
      final pointsXY = Int16List.fromList(ptsList);
      final widths = Uint8List.fromList(wList);
      final offsets = Uint32List.fromList(oList);

      freeFunc(nativeBuf);

      final flatBuffer = FlatStrokeBuffer(
        pointsXY: pointsXY,
        widths: widths,
        offsets: offsets,
        strokeCount: sCount,
        totalPoints: tPoints,
      );

      final commands = <AutodrawCommand>[];
      int nextId = 1;
      for (int s = 0; s < sCount; s++) {
        final start = offsets[s];
        final end = offsets[s + 1];
        if (end - start < 2) continue;

        final p0 = Offset(
          pointsXY[start * 2].toDouble(),
          pointsXY[start * 2 + 1].toDouble(),
        );
        final segs = <BezierSegment>[];
        for (int p = start + 1; p < end; p++) {
          final pEnd = Offset(
            pointsXY[p * 2].toDouble(),
            pointsXY[p * 2 + 1].toDouble(),
          );
          segs.add(BezierSegment(cp1: p0, cp2: pEnd, end: pEnd));
        }

        commands.add(
          AutodrawCommand.drawLine(
            id: nextId++,
            startPoint: p0,
            segments: segs,
            strokeWidth: widths[start].toDouble(),
            color: const Color(0xFF1E1E24),
          ),
        );
      }

      return AutodrawVectorizationResult(
        width: params.width,
        height: params.height,
        commands: commands,
        flatStrokeBuffer: flatBuffer,
      );
    } catch (_) {
      return null;
    }
  }

  static ffi.Pointer<ffi.Uint8> callocBytes(int byteCount) {
    final alloc = ffi.DynamicLibrary.process()
        .lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.Size),
          ffi.Pointer<ffi.Uint8> Function(int)
        >('malloc');
    return alloc(byteCount);
  }

  static void freeBytes(ffi.Pointer<ffi.Uint8> ptr) {
    final freeFn = ffi.DynamicLibrary.process()
        .lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Void>),
          void Function(ffi.Pointer<ffi.Void>)
        >('free');
    freeFn(ptr.cast());
  }
}
