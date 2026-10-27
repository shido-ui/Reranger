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
  final bool isThermalThrottled;
  final SendPort? sendPort;

  const _VectorizeTaskParams({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.maxPaths,
    this.isThermalThrottled = false,
    this.sendPort,
  });
}

/// Autodraw Engine V4 (Progressive Playback, Resolution Ladder & Thermal Governor):
/// - Mandate 1 (Progressive Playback): Splits vectorization into Phase 1 (Base Layer fills ~20%)
///   and Phase 2 (Fine line details and highlights), yielding immediate zero-latency start.
/// - Mandate 2 (Resolution Ladder): Downscales images to max 512x512 for skeletonization & RDP,
///   then scales int16 coordinates up to final screen resolution via bilinear scale factors.
/// - Mandate 3 (Thermal Governor): Increases RDP epsilon to 2.0px under thermal throttle to drop
///   stroke count and protect hardware.
/// - Mandate 4 (Memory Optimization): FlatStrokeBuffer strictly uses Int16List coordinates & Uint8List colors.
class PotraceVectorizer {
  const PotraceVectorizer();

  /// Executes the Pre-Computed Artist Pipeline on a background isolate via [Isolate.run].
  /// Backwards compatible method returning the complete vectorization result.
  Future<AutodrawVectorizationResult> vectorizeImage({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    int maxPaths = 2500,
    bool isThermalThrottled = false,
  }) async {
    final params = _VectorizeTaskParams(
      rgbaBytes: rgbaBytes,
      width: width,
      height: height,
      maxPaths: maxPaths,
      isThermalThrottled: isThermalThrottled,
    );

    return await Isolate.run(() => _vectorizeWorker(params));
  }

  /// Streams progressive batches from a background isolate via [Isolate.spawn]:
  /// - Phase 1 (Base Layer): Background and base color fills (~first 20% of strokes) yielded immediately.
  /// - Phase 2 (Details): Detailed skeleton linework and highlights yielded as they complete.
  Stream<AutodrawProgressiveBatch> vectorizeProgressive({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    int maxPaths = 2500,
    bool isThermalThrottled = false,
  }) async* {
    final receivePort = ReceivePort();
    final params = _VectorizeTaskParams(
      rgbaBytes: rgbaBytes,
      width: width,
      height: height,
      maxPaths: maxPaths,
      isThermalThrottled: isThermalThrottled,
      sendPort: receivePort.sendPort,
    );

    final isolate = await Isolate.spawn(_progressiveVectorizeWorker, params);

    try {
      await for (final msg in receivePort) {
        if (msg is AutodrawProgressiveBatch) {
          yield msg;
          if (msg.isComplete) {
            break;
          }
        } else if (msg == null) {
          break;
        }
      }
    } finally {
      receivePort.close();
      isolate.kill(priority: Isolate.immediate);
    }
  }

  // ==========================================================================
  // Mandate 2: Resolution Ladder Downscaling & Bilinear Scaling
  // ==========================================================================

  static ({Uint8List rgba, int width, int height, double scaleX, double scaleY})
  _applyResolutionLadder(Uint8List rgba, int width, int height) {
    if (width <= 512 && height <= 512) {
      return (
        rgba: rgba,
        width: width,
        height: height,
        scaleX: 1.0,
        scaleY: 1.0,
      );
    }

    int ladderW;
    int ladderH;
    if (width >= height) {
      ladderW = 512;
      ladderH = math.max(1, ((512 * height) / width).round());
    } else {
      ladderH = 512;
      ladderW = math.max(1, ((512 * width) / height).round());
    }

    final downscaled = _downscaleRgba(rgba, width, height, ladderW, ladderH);
    final scaleX = width / ladderW;
    final scaleY = height / ladderH;

    return (
      rgba: downscaled,
      width: ladderW,
      height: ladderH,
      scaleX: scaleX,
      scaleY: scaleY,
    );
  }

  static Uint8List _downscaleRgba(
    Uint8List srcRgba,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    if (srcW == dstW && srcH == dstH) return srcRgba;
    final dst = Uint8List(dstW * dstH * 4);
    final stepX = srcW / dstW;
    final stepY = srcH / dstH;

    for (int y = 0; y < dstH; y++) {
      final sy = (y * stepY).floor().clamp(0, srcH - 1);
      final rowDst = y * dstW * 4;
      final rowSrc = sy * srcW * 4;
      for (int x = 0; x < dstW; x++) {
        final sx = (x * stepX).floor().clamp(0, srcW - 1);
        final dIdx = rowDst + x * 4;
        final sIdx = rowSrc + sx * 4;
        dst[dIdx] = srcRgba[sIdx];
        dst[dIdx + 1] = srcRgba[sIdx + 1];
        dst[dIdx + 2] = srcRgba[sIdx + 2];
        dst[dIdx + 3] = srcRgba[sIdx + 3];
      }
    }
    return dst;
  }

  // ==========================================================================
  // Mandate 1: Progressive Vectorize Worker
  // ==========================================================================

  static void _progressiveVectorizeWorker(_VectorizeTaskParams params) {
    final sendPort = params.sendPort;
    final targetW = params.width;
    final targetH = params.height;

    if (targetW <= 0 ||
        targetH <= 0 ||
        params.rgbaBytes.length < targetW * targetH * 4) {
      sendPort?.send(
        AutodrawProgressiveBatch(
          phase: 1,
          isComplete: true,
          commands: const [],
          flatStrokeBuffer: FlatStrokeBuffer(
            pointsXY: Int16List(0),
            widths: Uint8List(0),
            offsets: Uint32List.fromList([0]),
            strokeCount: 0,
            totalPoints: 0,
          ),
          width: targetW,
          height: targetH,
        ),
      );
      return;
    }

    // 1. Mandate 2: Resolution ladder downscaling (512x512 cap)
    final ladder = _applyResolutionLadder(params.rgbaBytes, targetW, targetH);
    final procW = ladder.width;
    final procH = ladder.height;
    final procRgba = ladder.rgba;
    final scaleX = ladder.scaleX;
    final scaleY = ladder.scaleY;
    final total = procW * procH;

    // Luminance computation
    final lum = Uint8List(total);
    for (int i = 0; i < total; i++) {
      final off = i * 4;
      lum[i] =
          (0.299 * procRgba[off] +
                  0.587 * procRgba[off + 1] +
                  0.114 * procRgba[off + 2])
              .round()
              .clamp(0, 255);
    }

    int nextCommandId = 1;

    // -----------------------------------------------------------------------
    // PHASE 1: Base Layer (Background & Base Color Fills)
    // Extract ONLY the background and base color fills (~20% of strokes)
    // Yield immediately for zero-latency start!
    // -----------------------------------------------------------------------
    final fillCommands = _extractFillCommands(
      procRgba,
      lum,
      procW,
      procH,
      params.maxPaths,
      scaleX,
      scaleY,
      nextCommandId,
    );
    nextCommandId += fillCommands.length;

    // Fallback fill if empty
    if (fillCommands.isEmpty && targetW > 0 && targetH > 0) {
      final midX = targetW ~/ 2;
      final midY = targetH ~/ 2;
      final off = (midY * targetW + midX) * 4;
      final c = (off + 2 < params.rgbaBytes.length)
          ? Color.fromARGB(
              255,
              params.rgbaBytes[off],
              params.rgbaBytes[off + 1],
              params.rgbaBytes[off + 2],
            )
          : const Color(0xFF808080);
      fillCommands.add(
        AutodrawCommand.fillRegion(
          id: nextCommandId++,
          startPoint: Offset(targetW * 0.2, targetH * 0.5),
          segments: [
            BezierSegment(
              cp1: Offset(targetW * 0.4, targetH * 0.48),
              cp2: Offset(targetW * 0.6, targetH * 0.52),
              end: Offset(targetW * 0.8, targetH * 0.5),
            ),
          ],
          color: c,
          strokeWidth: 10.0,
          isClosed: false,
          layer: AutodrawTonalLayer.midtones,
        ),
      );
    }

    final phase1Buffer = FlatStrokeBuffer.fromCommands(
      fillCommands,
      targetW,
      targetH,
    );

    // Yield Phase 1 immediately
    sendPort?.send(
      AutodrawProgressiveBatch(
        phase: 1,
        isComplete: false,
        commands: List.unmodifiable(fillCommands),
        flatStrokeBuffer: phase1Buffer,
        width: targetW,
        height: targetH,
        isThermalThrottled: params.isThermalThrottled,
      ),
    );

    // -----------------------------------------------------------------------
    // PHASE 2: Fine Line Details & Highlights
    // While UI plays Phase 1, background Isolate continues calculating details
    // -----------------------------------------------------------------------
    // Mandate 3: Thermal Governor epsilon adjustment (2.0px if throttled)
    final double rdpEpsilon = params.isThermalThrottled ? 2.0 : 0.3;

    final lineCommands = _extractLineCommands(
      procRgba,
      lum,
      procW,
      procH,
      params.maxPaths,
      scaleX,
      scaleY,
      rdpEpsilon,
      nextCommandId,
    );
    nextCommandId += lineCommands.length;

    // Fallback line if empty
    if (lineCommands.isEmpty && targetW > 0 && targetH > 0) {
      final fw = targetW.toDouble();
      final fh = targetH.toDouble();
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

    final highlightCommands = _extractHighlightCommands(
      procRgba,
      lum,
      procW,
      procH,
      params.maxPaths,
      scaleX,
      scaleY,
      nextCommandId,
    );
    nextCommandId += highlightCommands.length;

    final phase2Details = <AutodrawCommand>[
      ...lineCommands,
      ...highlightCommands,
    ];

    final allCommands = <AutodrawCommand>[...fillCommands, ...phase2Details];

    final completeBuffer = FlatStrokeBuffer.fromCommands(
      allCommands,
      targetW,
      targetH,
    );

    sendPort?.send(
      AutodrawProgressiveBatch(
        phase: 2,
        isComplete: true,
        commands: List.unmodifiable(phase2Details),
        flatStrokeBuffer: completeBuffer,
        width: targetW,
        height: targetH,
        isThermalThrottled: params.isThermalThrottled,
      ),
    );
  }

  // ==========================================================================
  // Synchronous Isolate Worker for vectorizeImage
  // ==========================================================================

  static AutodrawVectorizationResult _vectorizeWorker(
    _VectorizeTaskParams params,
  ) {
    final targetW = params.width;
    final targetH = params.height;

    if (targetW <= 0 ||
        targetH <= 0 ||
        params.rgbaBytes.length < targetW * targetH * 4) {
      return AutodrawVectorizationResult(
        width: targetW,
        height: targetH,
        commands: const [],
      );
    }

    // Attempt native C++ FFI first if dynamic library is available
    final nativeResult = _tryNativeSkeletonTrace(params);
    if (nativeResult != null) {
      return nativeResult;
    }

    // 1. Mandate 2: Resolution ladder downscaling
    final ladder = _applyResolutionLadder(params.rgbaBytes, targetW, targetH);
    final procW = ladder.width;
    final procH = ladder.height;
    final procRgba = ladder.rgba;
    final scaleX = ladder.scaleX;
    final scaleY = ladder.scaleY;
    final total = procW * procH;

    // Luminance
    final lum = Uint8List(total);
    for (int i = 0; i < total; i++) {
      final off = i * 4;
      lum[i] =
          (0.299 * procRgba[off] +
                  0.587 * procRgba[off + 1] +
                  0.114 * procRgba[off + 2])
              .round()
              .clamp(0, 255);
    }

    int nextCommandId = 1;

    // Mandate 3: Thermal Governor epsilon adjustment
    final double rdpEpsilon = params.isThermalThrottled ? 2.0 : 0.3;

    // Extract all passes
    final lineCommands = _extractLineCommands(
      procRgba,
      lum,
      procW,
      procH,
      params.maxPaths,
      scaleX,
      scaleY,
      rdpEpsilon,
      nextCommandId,
    );
    nextCommandId += lineCommands.length;

    final fillCommands = _extractFillCommands(
      procRgba,
      lum,
      procW,
      procH,
      params.maxPaths,
      scaleX,
      scaleY,
      nextCommandId,
    );
    nextCommandId += fillCommands.length;

    final highlightCommands = _extractHighlightCommands(
      procRgba,
      lum,
      procW,
      procH,
      params.maxPaths,
      scaleX,
      scaleY,
      nextCommandId,
    );
    nextCommandId += highlightCommands.length;

    // Fallbacks
    if (lineCommands.isEmpty && targetW > 0 && targetH > 0) {
      final fw = targetW.toDouble();
      final fh = targetH.toDouble();
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

    if (fillCommands.isEmpty && targetW > 0 && targetH > 0) {
      final midX = targetW ~/ 2;
      final midY = targetH ~/ 2;
      final off = (midY * targetW + midX) * 4;
      final c = (off + 2 < params.rgbaBytes.length)
          ? Color.fromARGB(
              255,
              params.rgbaBytes[off],
              params.rgbaBytes[off + 1],
              params.rgbaBytes[off + 2],
            )
          : const Color(0xFF808080);
      fillCommands.add(
        AutodrawCommand.fillRegion(
          id: nextCommandId++,
          startPoint: Offset(targetW * 0.2, targetH * 0.5),
          segments: [
            BezierSegment(
              cp1: Offset(targetW * 0.4, targetH * 0.48),
              cp2: Offset(targetW * 0.6, targetH * 0.52),
              end: Offset(targetW * 0.8, targetH * 0.5),
            ),
          ],
          color: c,
          strokeWidth: 10.0,
          isClosed: false,
          layer: AutodrawTonalLayer.midtones,
        ),
      );
    }

    if (highlightCommands.isEmpty && targetW > 0 && targetH > 0) {
      highlightCommands.add(
        AutodrawCommand.drawHighlight(
          id: nextCommandId++,
          startPoint: Offset(targetW * 0.45, targetH * 0.45),
          segments: [
            BezierSegment(
              cp1: Offset(targetW * 0.48, targetH * 0.45),
              cp2: Offset(targetW * 0.52, targetH * 0.45),
              end: Offset(targetW * 0.55, targetH * 0.45),
            ),
          ],
          strokeWidth: 2.0,
          color: const Color(0xFFFFFFFF),
          layer: AutodrawTonalLayer.highlights,
        ),
      );
    }

    // Strictly ordered: Lines -> Fills -> Highlights
    final allCommands = <AutodrawCommand>[
      ...lineCommands,
      ...fillCommands,
      ...highlightCommands,
    ];

    allCommands.sort(
      (a, b) => a.actionType.orderIndex.compareTo(b.actionType.orderIndex),
    );

    final flatBuffer = FlatStrokeBuffer.fromCommands(
      allCommands,
      targetW,
      targetH,
    );

    return AutodrawVectorizationResult(
      width: targetW,
      height: targetH,
      commands: allCommands,
      flatStrokeBuffer: flatBuffer,
    );
  }

  // ==========================================================================
  // Modular Pass Extractors
  // ==========================================================================

  /// Pass 1: The Sketch (Centerline Lines via Guo-Hall Thinning & Medial Axis)
  static List<AutodrawCommand> _extractLineCommands(
    Uint8List rgba,
    Uint8List lum,
    int width,
    int height,
    int maxPaths,
    double scaleX,
    double scaleY,
    double rdpEpsilon,
    int startId,
  ) {
    final total = width * height;
    final lineCommands = <AutodrawCommand>[];
    final maxLinePaths = (maxPaths * 0.45).round().clamp(10, 1500);

    // 1. Integral Image Adaptive Thresholding + Sobel Edge detection
    final binaryMap = Uint8List(total);
    final edgeMap = Uint8List(total);

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

        final leftOff = (idx - 1) * 4;
        final rightOff = (idx + 1) * 4;
        final cDiff =
            (rgba[rightOff] - rgba[leftOff]).abs() +
            (rgba[rightOff + 1] - rgba[leftOff + 1]).abs() +
            (rgba[rightOff + 2] - rgba[leftOff + 2]).abs();

        if (mag >= 36 || cDiff >= 70) {
          edgeMap[idx] = 1;
        }

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

    // 3x3 Median Filter to remove salt-and-pepper noise
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

    // Connected Component Analysis (CCA) - Delete components < 15 px
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

        if (component.length < 15) {
          for (final cIdx in component) {
            binaryMap[cIdx] = 0;
          }
        }
      }
    }

    // Medial Axis via 2-Pass Chamfer Distance Transform
    final distMap = Uint16List(total);
    for (int i = 0; i < total; i++) {
      distMap[i] = binaryMap[i] == 1 ? 9999 : 0;
    }

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

    // Guo-Hall Thinning (Parallel 2-Subiteration Centerline Thinning)
    final skeleton = Uint8List.fromList(binaryMap);
    final toDelete = <int>[];

    for (int iter = 0; iter < 48; iter++) {
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

    // Polyline tracing
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

        // Spur pruning (< 6px)
        double strokeLen = 0.0;
        for (int k = 1; k < polyline.length; k++) {
          strokeLen += (polyline[k] - polyline[k - 1]).distance;
        }
        if (strokeLen < 6.0 && polyline.length < 5) continue;

        // RDP Simplification (with rdpEpsilon)
        final simplified = _rdpSimplify(polyline, rdpEpsilon);
        if (simplified.length < 2) continue;

        candidateStrokes.add(simplified);
        strokeWidths.add((sumWidth / polyline.length).clamp(1.0, 2.5));
      }
    }

    // 256x256 Tone Coverage Buffer
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
        continue;
      }

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

    // TSP Ordering
    final orderedStrokes = <List<Offset>>[];
    final orderedWidths = <double>[];
    if (acceptedStrokes.isNotEmpty) {
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

    // Bézier curve fitting scaled up to screen resolution (scaleX, scaleY)
    final avgScale = (scaleX + scaleY) * 0.5;
    int curId = startId;
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
          ((p0.dx + t0.dx / 3.0).clamp(0.0, width.toDouble())) * scaleX,
          ((p0.dy + t0.dy / 3.0).clamp(0.0, height.toDouble())) * scaleY,
        );
        final cp2 = Offset(
          ((p3.dx - t3.dx / 3.0).clamp(0.0, width.toDouble())) * scaleX,
          ((p3.dy - t3.dy / 3.0).clamp(0.0, height.toDouble())) * scaleY,
        );
        final scaledP3 = Offset(p3.dx * scaleX, p3.dy * scaleY);
        segments.add(BezierSegment(cp1: cp1, cp2: cp2, end: scaledP3));
      }

      lineCommands.add(
        AutodrawCommand.drawLine(
          id: curId++,
          startPoint: Offset(poly.first.dx * scaleX, poly.first.dy * scaleY),
          segments: segments,
          strokeWidth: (orderedWidths[i] * avgScale).clamp(1.0, 3.5),
          color: const Color(0xFF1E1E24),
          layer: AutodrawTonalLayer.background,
        ),
      );
    }

    return lineCommands;
  }

  /// Pass 2: The Color (Fills) - Sampled average color with broad brush
  static List<AutodrawCommand> _extractFillCommands(
    Uint8List rgba,
    Uint8List lum,
    int width,
    int height,
    int maxPaths,
    double scaleX,
    double scaleY,
    int startId,
  ) {
    final total = width * height;
    final fillCommands = <AutodrawCommand>[];
    final maxFillPaths = (maxPaths * 0.40).round().clamp(10, 1500);

    final tonalBands = const [
      (0, 50),
      (50, 100),
      (100, 150),
      (150, 200),
      (200, 256),
    ];

    final avgScale = (scaleX + scaleY) * 0.5;
    int curId = startId;

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
                final p0 = Offset(runStart * scaleX, y * scaleY);
                final p3 = Offset(x * scaleX, y * scaleY);

                final arcY = (y + (y % 4 == 0 ? 1.5 : -1.5)).toDouble().clamp(
                  0.0,
                  height.toDouble(),
                );
                final cp1 = Offset(
                  (runStart + (x - runStart) * 0.33) * scaleX,
                  arcY * scaleY,
                );
                final cp2 = Offset(
                  (runStart + (x - runStart) * 0.66) * scaleX,
                  arcY * scaleY,
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
                    id: curId++,
                    startPoint: p0,
                    segments: [BezierSegment(cp1: cp1, cp2: cp2, end: p3)],
                    color: perceptualColor,
                    strokeWidth: (dynFillWidth * avgScale).clamp(4.0, 30.0),
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

      // Add closed perimeter fills for the region
      final visitedPerimeter = Uint8List(total);
      const dx = [1, 1, 0, -1, -1, -1, 0, 1];
      const dy = [0, 1, 1, 1, 0, -1, -1, -1];

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
              segs.add(
                BezierSegment(
                  cp1: Offset(cp.dx * scaleX, cp.dy * scaleY),
                  cp2: Offset(p1.dx * scaleX, p1.dy * scaleY),
                  end: Offset(p1.dx * scaleX, p1.dy * scaleY),
                ),
              );
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
                id: curId++,
                startPoint: Offset(
                  contour.first.dx * scaleX,
                  contour.first.dy * scaleY,
                ),
                segments: segs,
                color: contourColor,
                strokeWidth: (6.0 * avgScale).clamp(3.0, 18.0),
                isClosed: true,
                layer: regionLayer,
              ),
            );
          }
        }
      }
    }

    return fillCommands;
  }

  /// Pass 3: The Highlights - Bright spots (Luminance > 0.85)
  static List<AutodrawCommand> _extractHighlightCommands(
    Uint8List rgba,
    Uint8List lum,
    int width,
    int height,
    int maxPaths,
    double scaleX,
    double scaleY,
    int startId,
  ) {
    final total = width * height;
    final highlightCommands = <AutodrawCommand>[];
    final maxHighlightPaths = (maxPaths * 0.20).round().clamp(10, 600);

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
    const dx = [1, 1, 0, -1, -1, -1, 0, 1];
    const dy = [0, 1, 1, 1, 0, -1, -1, -1];
    final avgScale = (scaleX + scaleY) * 0.5;
    int curId = startId;

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
            segs.add(
              BezierSegment(
                cp1: Offset(cp.dx * scaleX, cp.dy * scaleY),
                cp2: Offset(p1.dx * scaleX, p1.dy * scaleY),
                end: Offset(p1.dx * scaleX, p1.dy * scaleY),
              ),
            );
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
              id: curId++,
              startPoint: Offset(
                contour.first.dx * scaleX,
                contour.first.dy * scaleY,
              ),
              segments: segs,
              strokeWidth: (hiWidth * avgScale).clamp(1.0, 3.5),
              color: hiColor,
              layer: AutodrawTonalLayer.highlights,
            ),
          );
        }
      }
    }

    return highlightCommands;
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
