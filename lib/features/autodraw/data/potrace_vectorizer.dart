import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../domain/autodraw_models.dart';

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

/// Service executing the Pre-Computed Artist Pipeline on a background isolate:
/// Pass 1: The Sketch (Lines) - Sobel/Potrace edge contours (strokeWidth = 1.5, dark ink).
/// Pass 2: The Color (Fills) - Sampled average color from ProcessedBuffer with broad brush.
/// Pass 3: The Highlights - Bright spots (Luminance > 0.85) with crisp highlights.
/// Sorting: Strictly ordered All Lines -> All Fills -> All Highlights.
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
    // PASS 1: The Sketch (Lines)
    // Extract edges using Sobel/Potrace. Create DrawLine commands (strokeWidth = 1.5, dark ink).
    // -------------------------------------------------------------------------
    final lineCommands = <AutodrawCommand>[];
    final edgeMap = Uint8List(total);

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

        // Color gradient difference
        final leftOff = (idx - 1) * 4;
        final rightOff = (idx + 1) * 4;
        final cDiff =
            (rgba[rightOff] - rgba[leftOff]).abs() +
            (rgba[rightOff + 1] - rgba[leftOff + 1]).abs() +
            (rgba[rightOff + 2] - rgba[leftOff + 2]).abs();

        if (mag >= 36 || cDiff >= 70) {
          edgeMap[idx] = 1;
        }
      }
    }

    // Trace edge contours into polylines and fit cubic Bézier curves
    final visitedEdge = Uint8List(total);
    final maxLinePaths = (params.maxPaths * 0.45).round().clamp(10, 1500);

    for (int y = 1; y < height - 1; y++) {
      if (lineCommands.length >= maxLinePaths) break;
      for (int x = 1; x < width - 1; x++) {
        if (lineCommands.length >= maxLinePaths) break;
        final idx = y * width + x;
        if (edgeMap[idx] == 0 || visitedEdge[idx] == 1) continue;

        final contour = <Offset>[];
        int currX = x;
        int currY = y;

        for (int step = 0; step < 72; step++) {
          visitedEdge[currY * width + currX] = 1;
          contour.add(Offset(currX.toDouble(), currY.toDouble()));

          int nextX = -1, nextY = -1;
          const dx = [1, 1, 0, -1, -1, -1, 0, 1];
          const dy = [0, 1, 1, 1, 0, -1, -1, -1];

          for (int d = 0; d < 8; d++) {
            final nx = currX + dx[d];
            final ny = currY + dy[d];
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final nidx = ny * width + nx;
              if (edgeMap[nidx] == 1 && visitedEdge[nidx] == 0) {
                nextX = nx;
                nextY = ny;
                break;
              }
            }
          }
          if (nextX == -1) break;
          currX = nextX;
          currY = nextY;
        }

        if (contour.length < 2) continue;

        // Simplify contour
        final simplified = <Offset>[contour.first];
        for (int k = 2; k < contour.length - 1; k += 2) {
          simplified.add(contour[k]);
        }
        simplified.add(contour.last);

        final numSegs = simplified.length - 1;
        if (numSegs <= 0) continue;

        // Fit cubic Bézier segments with C1 continuity
        final segments = <BezierSegment>[];
        for (int s = 0; s < numSegs; s++) {
          final p0 = simplified[s];
          final p3 = simplified[s + 1];

          final prev = s > 0 ? simplified[s - 1] : p0;
          final next = s + 2 < simplified.length ? simplified[s + 2] : p3;

          final t0 = (p3 - prev) * 0.35;
          final t3 = (next - p0) * 0.35;

          final cp1 = p0 + t0 / 3.0;
          final cp2 = p3 - t3 / 3.0;

          segments.add(BezierSegment(cp1: cp1, cp2: cp2, end: p3));
        }

        // Pass 1: strokeWidth = 1.5, charcoal black/dark grey ink with subtle tone
        lineCommands.add(
          AutodrawCommand.drawLine(
            id: nextCommandId++,
            startPoint: simplified.first,
            segments: segments,
            strokeWidth: 1.5,
            color: const Color(0xFF1E1E24),
            layer: AutodrawTonalLayer.background,
          ),
        );
      }
    }

    // -------------------------------------------------------------------------
    // PASS 2: The Color (Fills)
    // For each region, sample average color from ProcessedBuffer (post-shader).
    // Create FillRegion commands that paint interior with broad brush.
    // -------------------------------------------------------------------------
    final fillCommands = <AutodrawCommand>[];
    final maxFillPaths = (params.maxPaths * 0.40).round().clamp(10, 1500);

    // Multi-band region clustering for accurate tonal and shader color reproduction
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
      int sumR = 0, sumG = 0, sumB = 0;

      for (int i = 0; i < total; i++) {
        final l = lum[i];
        if (l >= low && l < high) {
          bandMask[i] = 1;
          bandPixels++;
          final off = i * 4;
          sumR += rgba[off];
          sumG += rgba[off + 1];
          sumB += rgba[off + 2];
        }
      }

      if (bandPixels == 0) continue;

      // Sample average color of this tonal band directly from ProcessedBuffer
      final avgBandR = (sumR / bandPixels).round().clamp(0, 255);
      final avgBandG = (sumG / bandPixels).round().clamp(0, 255);
      final avgBandB = (sumB / bandPixels).round().clamp(0, 255);

      // Determine tonal layer based on luminance for test and HUD categorization
      final bandMidLum = (low + high) / 2.0;
      final regionLayer = bandMidLum < 85
          ? AutodrawTonalLayer.background
          : bandMidLum > 170
          ? AutodrawTonalLayer.highlights
          : AutodrawTonalLayer.midtones;

      // SBR (Stroke-Based Rendering) broad artist fill strokes across the region
      const fillStride = 6;
      for (int y = 2; y < height - 2; y += fillStride) {
        if (fillCommands.length >= maxFillPaths) break;
        int runStart = -1;
        int runSumR = 0, runSumG = 0, runSumB = 0, runCount = 0;

        for (int x = 2; x < width - 2; x++) {
          if (fillCommands.length >= maxFillPaths) break;
          final idx = y * width + x;

          if (bandMask[idx] == 1) {
            if (runStart == -1) {
              runStart = x;
              runSumR = 0;
              runSumG = 0;
              runSumB = 0;
              runCount = 0;
            }
            final off = idx * 4;
            runSumR += rgba[off];
            runSumG += rgba[off + 1];
            runSumB += rgba[off + 2];
            runCount++;

            final isEnd =
                (x - runStart >= 24) ||
                (x == width - 3) ||
                (bandMask[idx + 1] == 0);

            if (isEnd) {
              if (runCount >= 3) {
                final p0 = Offset(runStart.toDouble(), y.toDouble());
                final p3 = Offset(x.toDouble(), y.toDouble());

                // Subtle painterly curve arc
                final arcY = y + (y % 4 == 0 ? 1.5 : -1.5);
                final cp1 = Offset(
                  runStart + (x - runStart) * 0.33,
                  arcY.toDouble(),
                );
                final cp2 = Offset(
                  runStart + (x - runStart) * 0.66,
                  arcY.toDouble(),
                );

                // Sample local average color from the processed buffer
                final localR = (runSumR / runCount).round().clamp(0, 255);
                final localG = (runSumG / runCount).round().clamp(0, 255);
                final localB = (runSumB / runCount).round().clamp(0, 255);

                final localLum =
                    (0.299 * localR + 0.587 * localG + 0.114 * localB).round();
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
                    color: Color.fromARGB(255, localR, localG, localB),
                    strokeWidth: 8.5, // Broad painterly brush
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
      }

      // Also add closed perimeter fills for the region to guarantee solid contour fill
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
            const dx = [1, 1, 0, -1, -1, -1, 0, 1];
            const dy = [0, 1, 1, 1, 0, -1, -1, -1];
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
            fillCommands.add(
              AutodrawCommand.fillRegion(
                id: nextCommandId++,
                startPoint: contour.first,
                segments: segs,
                color: Color.fromARGB(255, avgBandR, avgBandG, avgBandB),
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
    // PASS 3: The Highlights
    // Extract bright spots (Luminance > 0.85). Create DrawHighlight commands.
    // -------------------------------------------------------------------------
    final highlightCommands = <AutodrawCommand>[];
    final maxHighlightPaths = (params.maxPaths * 0.20).round().clamp(10, 600);

    // 0.85 * 255 = 216.75 -> threshold 217
    const hiThreshold = 217;
    final hiMask = Uint8List(total);
    int hiPixels = 0;

    for (int i = 0; i < total; i++) {
      if (lum[i] >= hiThreshold) {
        hiMask[i] = 1;
        hiPixels++;
      }
    }

    // If few pixels exceed 0.85, sample the top 5% brightest pixels for highlight accents
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
          const dx = [1, 1, 0, -1, -1, -1, 0, 1];
          const dy = [0, 1, 1, 1, 0, -1, -1, -1];
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

          // Sample vibrant highlight color from processed buffer
          final sampleOff = idx * 4;
          final hiR = rgba[sampleOff];
          final hiG = rgba[sampleOff + 1];
          final hiB = rgba[sampleOff + 2];

          // Boost highlight vibrancy towards glistening specular
          final outR = math.max(hiR, 220);
          final outG = math.max(hiG, 220);
          final outB = math.max(hiB, 220);
          final hiColor = (hiR > hiB && hiR > hiG && hiR > 150)
              ? Color.fromARGB(255, hiR, hiG, hiB) // preserve warm/orange tone
              : Color.fromARGB(255, outR, outG, outB);

          highlightCommands.add(
            AutodrawCommand.drawHighlight(
              id: nextCommandId++,
              startPoint: contour.first,
              segments: segs,
              strokeWidth: 2.0,
              color: hiColor,
              layer: AutodrawTonalLayer.highlights,
            ),
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // Fallback: Ensure non-empty command sequence on flat/tiny images
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
    // FINAL SORTING (Mandate 1): Strictly ordered
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

    return AutodrawVectorizationResult(
      width: width,
      height: height,
      commands: allCommands,
    );
  }
}
