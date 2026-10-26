import 'dart:async';
import 'dart:isolate';
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

/// Service executing Potrace contour extraction and Bézier curve fitting.
/// Invariant: Always executes vectorization on a background isolate.
class PotraceVectorizer {
  const PotraceVectorizer();

  /// Vectorizes an RGBA8888 image into sorted Bézier curves (Background -> Midtones -> Highlights).
  /// Execution is strictly offloaded to a background isolate via [Isolate.run].
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
        strokes: [],
      );
    }

    // 1. Luminance computation
    final lum = Uint8List(total);
    for (int i = 0; i < total; i++) {
      final off = i * 4;
      lum[i] =
          (0.299 * rgba[off] + 0.587 * rgba[off + 1] + 0.114 * rgba[off + 2])
              .round()
              .clamp(0, 255);
    }

    final bgStrokes = <AutodrawStroke>[];
    final midStrokes = <AutodrawStroke>[];
    final hiStrokes = <AutodrawStroke>[];

    final maxPerBand = (params.maxPaths / 3).ceil().clamp(10, 3000);

    // 2. Trace each tonal band in deterministic order across multi-level sub-bands
    void traceTonalBand(
      AutodrawTonalLayer layer,
      List<AutodrawStroke> outList,
      double strokeWidth,
    ) {
      final subRanges = layer == AutodrawTonalLayer.background
          ? const [(0, 45), (45, 85)]
          : layer == AutodrawTonalLayer.midtones
          ? const [(85, 128), (128, 170)]
          : const [(170, 215), (215, 256)];

      for (final (low, high) in subRanges) {
        if (outList.length >= maxPerBand) break;

        final mask = Uint8List(total);
        int bandPixels = 0;

        for (int i = 0; i < total; i++) {
          final l = lum[i];
          if (l >= low && l < high) {
            mask[i] = 1;
            bandPixels++;
          }
        }

        if (bandPixels == 0) continue;

        final visited = Uint8List(total);

        for (int y = 1; y < height - 1; y++) {
          if (outList.length >= maxPerBand) break;
          for (int x = 1; x < width - 1; x++) {
            if (outList.length >= maxPerBand) break;
            final idx = y * width + x;
            if (mask[idx] == 0 || visited[idx] == 1) continue;

            // Boundary edge detection
            final isEdge =
                mask[idx - 1] == 0 ||
                mask[idx + 1] == 0 ||
                mask[idx - width] == 0 ||
                mask[idx + width] == 0;
            if (!isEdge) continue;

            // Trace boundary contour
            final contour = <Offset>[];
            int currX = x;
            int currY = y;

            for (int step = 0; step < 64; step++) {
              visited[currY * width + currX] = 1;
              contour.add(Offset(currX.toDouble(), currY.toDouble()));

              int nextX = -1, nextY = -1;
              const dx = [1, 1, 0, -1, -1, -1, 0, 1];
              const dy = [0, 1, 1, 1, 0, -1, -1, -1];

              for (int d = 0; d < 8; d++) {
                final nx = currX + dx[d];
                final ny = currY + dy[d];
                if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                  final nidx = ny * width + nx;
                  if (mask[nidx] == 1 && visited[nidx] == 0) {
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

            // Polygon simplification (sample key points)
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

            // Sample local vibrant color at stroke starting position
            final startOff = (y * width + x) * 4;
            final strokeColor = Color.fromARGB(
              255,
              rgba[startOff],
              rgba[startOff + 1],
              rgba[startOff + 2],
            );

            outList.add(
              AutodrawStroke(
                id: outList.length + 1,
                layer: layer,
                color: strokeColor,
                strokeWidth: strokeWidth,
                startPoint: simplified.first,
                segments: segments,
              ),
            );
          }
        }

        // SBR (Stroke-Based Rendering) interior tonal fill strokes
        const fillStride = 5;
        for (int y = 2; y < height - 2; y += fillStride) {
          if (outList.length >= maxPerBand) break;
          int runStart = -1;
          for (int x = 2; x < width - 2; x++) {
            if (outList.length >= maxPerBand) break;
            final idx = y * width + x;
            if (mask[idx] == 1) {
              if (runStart == -1) runStart = x;
              if (x - runStart >= 16 || x == width - 3 || mask[idx + 1] == 0) {
                if (x - runStart >= 4) {
                  final p0 = Offset(runStart.toDouble(), y.toDouble());
                  final p3 = Offset(x.toDouble(), y.toDouble());
                  final cp1 = Offset(
                    runStart + (x - runStart) * 0.33,
                    y + (y % 4 == 0 ? 1.0 : -1.0),
                  );
                  final cp2 = Offset(
                    runStart + (x - runStart) * 0.66,
                    y + (y % 4 == 0 ? -1.0 : 1.0),
                  );
                  final midX = (runStart + x) ~/ 2;
                  final sampleOff = (y * width + midX) * 4;
                  final strokeColor = Color.fromARGB(
                    255,
                    rgba[sampleOff],
                    rgba[sampleOff + 1],
                    rgba[sampleOff + 2],
                  );
                  outList.add(
                    AutodrawStroke(
                      id: outList.length + 1,
                      layer: layer,
                      color: strokeColor,
                      strokeWidth: strokeWidth * 0.85,
                      startPoint: p0,
                      segments: [BezierSegment(cp1: cp1, cp2: cp2, end: p3)],
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
      }
    }

    // Trace in strict order: Background (stroke 2.5) -> Midtones (stroke 2.0) -> Highlights (stroke 1.5)
    traceTonalBand(AutodrawTonalLayer.background, bgStrokes, 2.5);
    traceTonalBand(AutodrawTonalLayer.midtones, midStrokes, 2.0);
    traceTonalBand(AutodrawTonalLayer.highlights, hiStrokes, 1.5);

    final allStrokes = <AutodrawStroke>[
      ...bgStrokes,
      ...midStrokes,
      ...hiStrokes,
    ];

    // Fallback perimeter stroke to guarantee > 0 strokes on uniform/flat images
    if (allStrokes.isEmpty && width > 0 && height > 0) {
      final fw = width.toDouble();
      final fh = height.toDouble();
      final firstColor = rgba.length >= 4
          ? Color.fromARGB(255, rgba[0], rgba[1], rgba[2])
          : const Color(0xFF808080);
      allStrokes.add(
        AutodrawStroke(
          id: 1,
          layer: AutodrawTonalLayer.midtones,
          color: firstColor,
          strokeWidth: 2.0,
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
        ),
      );
    }

    return AutodrawVectorizationResult(
      width: width,
      height: height,
      strokes: allStrokes,
    );
  }
}
