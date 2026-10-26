import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Artist Pipeline Action Type.
/// Strictly ordered: All Lines (0) -> All Fills (1) -> All Highlights (2).
enum AutodrawActionType {
  drawLine(0, 'Lines (Sketch)'),
  fillRegion(1, 'Fills (Color)'),
  drawHighlight(2, 'Highlights');

  final int orderIndex;
  final String label;
  const AutodrawActionType(this.orderIndex, this.label);
}

/// Tonal hierarchy for progressive stroke rendering.
/// Rendered strictly in order: Background -> Midtones -> Highlights.
enum AutodrawTonalLayer {
  background(0, 'Background'),
  midtones(1, 'Midtones'),
  highlights(2, 'Highlights');

  final int indexValue;
  final String label;
  const AutodrawTonalLayer(this.indexValue, this.label);

  static AutodrawTonalLayer fromIndex(int idx) {
    switch (idx) {
      case 0:
        return AutodrawTonalLayer.background;
      case 1:
        return AutodrawTonalLayer.midtones;
      case 2:
      default:
        return AutodrawTonalLayer.highlights;
    }
  }
}

/// Cubic Bézier curve segment connecting the previous endpoint to [end]
/// using control points [cp1] and [cp2].
class BezierSegment {
  final Offset cp1;
  final Offset cp2;
  final Offset end;

  const BezierSegment({
    required this.cp1,
    required this.cp2,
    required this.end,
  });

  /// Approximate arc length of cubic Bézier using chord distance summation.
  double approximateLength(Offset start) {
    const steps = 8;
    double len = 0.0;
    Offset prev = start;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final it = 1.0 - t;
      final x =
          it * it * it * start.dx +
          3 * it * it * t * cp1.dx +
          3 * it * t * t * cp2.dx +
          t * t * t * end.dx;
      final y =
          it * it * it * start.dy +
          3 * it * it * t * cp1.dy +
          3 * it * t * t * cp2.dy +
          t * t * t * end.dy;
      final curr = Offset(x, y);
      len += (curr - prev).distance;
      prev = curr;
    }
    return len;
  }
}

/// Data class representing a pre-computed artist command in the Autodraw pipeline.
/// Encapsulates the path, color, strokeWidth, action type, and tonal layer.
class AutodrawCommand {
  final int id;
  final AutodrawActionType actionType;
  final AutodrawTonalLayer layer;
  final Color strokeColor;
  Color get color => strokeColor;
  final double strokeWidth;
  double get width => strokeWidth;
  final Offset startPoint;
  final List<BezierSegment> segments;
  final bool isClosed;
  final List<Offset>? fillPoints;

  Path? _cachedPath;
  double? _cachedScaleX;
  double? _cachedScaleY;
  double? _cachedLength;

  AutodrawCommand({
    required this.id,
    AutodrawActionType? actionType,
    AutodrawTonalLayer? layer,
    Color? strokeColor,
    Color? color,
    required this.strokeWidth,
    required this.startPoint,
    required this.segments,
    this.isClosed = false,
    this.fillPoints,
  }) : actionType =
           actionType ??
           (layer == AutodrawTonalLayer.background
               ? AutodrawActionType.drawLine
               : layer == AutodrawTonalLayer.midtones
               ? AutodrawActionType.fillRegion
               : AutodrawActionType.drawHighlight),
       layer =
           layer ??
           (actionType == AutodrawActionType.drawLine
               ? AutodrawTonalLayer.background
               : actionType == AutodrawActionType.fillRegion
               ? AutodrawTonalLayer.midtones
               : AutodrawTonalLayer.highlights),
       strokeColor = strokeColor ?? color ?? const Color(0xFF1E1E24);

  /// Pass 1: The Sketch (Lines) - Contours drawn with strokeWidth = 1.5 in dark ink.
  factory AutodrawCommand.drawLine({
    required int id,
    required Offset startPoint,
    required List<BezierSegment> segments,
    double strokeWidth = 1.5,
    Color color = const Color(0xFF1E1E24),
    AutodrawTonalLayer layer = AutodrawTonalLayer.background,
  }) {
    return AutodrawCommand(
      id: id,
      actionType: AutodrawActionType.drawLine,
      layer: layer,
      strokeWidth: strokeWidth,
      strokeColor: color,
      startPoint: startPoint,
      segments: segments,
      isClosed: false,
    );
  }

  /// Pass 2: The Color (Fills) - Sampled average color painted with broad brush.
  factory AutodrawCommand.fillRegion({
    required int id,
    required Offset startPoint,
    required List<BezierSegment> segments,
    required Color color,
    double strokeWidth = 8.0,
    bool isClosed = true,
    List<Offset>? fillPoints,
    AutodrawTonalLayer layer = AutodrawTonalLayer.midtones,
  }) {
    return AutodrawCommand(
      id: id,
      actionType: AutodrawActionType.fillRegion,
      layer: layer,
      strokeWidth: strokeWidth,
      strokeColor: color,
      startPoint: startPoint,
      segments: segments,
      isClosed: isClosed,
      fillPoints: fillPoints,
    );
  }

  /// Pass 3: The Highlights - Bright spots (Luminance > 0.85).
  factory AutodrawCommand.drawHighlight({
    required int id,
    required Offset startPoint,
    required List<BezierSegment> segments,
    double strokeWidth = 2.0,
    Color color = const Color(0xFFFFFFFF),
    AutodrawTonalLayer layer = AutodrawTonalLayer.highlights,
  }) {
    return AutodrawCommand(
      id: id,
      actionType: AutodrawActionType.drawHighlight,
      layer: layer,
      strokeWidth: strokeWidth,
      strokeColor: color,
      startPoint: startPoint,
      segments: segments,
      isClosed: false,
    );
  }

  /// Constructs a Flutter [Path] representing this command, scaling coordinates by [scaleX] and [scaleY].
  Path toScaledPath(double scaleX, double scaleY) {
    if (_cachedPath != null &&
        _cachedScaleX == scaleX &&
        _cachedScaleY == scaleY) {
      return _cachedPath!;
    }
    final p = Path()..moveTo(startPoint.dx * scaleX, startPoint.dy * scaleY);
    for (final seg in segments) {
      p.cubicTo(
        seg.cp1.dx * scaleX,
        seg.cp1.dy * scaleY,
        seg.cp2.dx * scaleX,
        seg.cp2.dy * scaleY,
        seg.end.dx * scaleX,
        seg.end.dy * scaleY,
      );
    }
    if (isClosed) {
      p.close();
    }
    _cachedPath = p;
    _cachedScaleX = scaleX;
    _cachedScaleY = scaleY;
    return p;
  }

  /// Constructs an unscaled Flutter [Path] representing this command in native bitmap coordinates.
  Path get path => toScaledPath(1.0, 1.0);

  /// Estimated total arc length of the stroke.
  double get totalLength {
    if (_cachedLength != null) return _cachedLength!;
    double len = 0.0;
    Offset curr = startPoint;
    for (final seg in segments) {
      len += seg.approximateLength(curr);
      curr = seg.end;
    }
    _cachedLength = math.max(1.0, len);
    return _cachedLength!;
  }
}

/// Zero-copy flat stroke buffer storing centerline skeleton and medial axis widths:
/// - [pointsXY]: Interleaved coordinates (x0, y0, x1, y1, ...) as int16.
/// - [widths]: Local medial axis stroke width per point (1 to 25px).
/// - [offsets]: Prefix offsets marking the start point index of each stroke. Length = strokeCount + 1.
/// - [strokeLengths]: Pre-computed total arc length per stroke.
/// - [cumulativeDistances]: Cumulative arc lengths along each stroke for O(log n) binary search.
class FlatStrokeBuffer {
  final Int16List pointsXY;
  final Uint8List widths;
  final Uint32List offsets;
  final int strokeCount;
  final int totalPoints;
  final Float32List strokeLengths;
  final List<Float32List> cumulativeDistances;

  FlatStrokeBuffer({
    required this.pointsXY,
    required this.widths,
    required this.offsets,
    required this.strokeCount,
    required this.totalPoints,
    Float32List? strokeLengths,
    List<Float32List>? cumulativeDistances,
  }) : strokeLengths =
           strokeLengths ??
           _computeStrokeLengths(pointsXY, offsets, strokeCount),
       cumulativeDistances =
           cumulativeDistances ??
           _computeCumulativeDistances(pointsXY, offsets, strokeCount);

  static Float32List _computeStrokeLengths(
    Int16List pointsXY,
    Uint32List offsets,
    int strokeCount,
  ) {
    final lengths = Float32List(strokeCount);
    for (int s = 0; s < strokeCount; s++) {
      final startIdx = offsets[s];
      final endIdx = offsets[s + 1];
      double len = 0.0;
      for (int i = startIdx + 1; i < endIdx; i++) {
        final dx = (pointsXY[i * 2] - pointsXY[(i - 1) * 2]).toDouble();
        final dy = (pointsXY[i * 2 + 1] - pointsXY[(i - 1) * 2 + 1]).toDouble();
        len += math.sqrt(dx * dx + dy * dy);
      }
      lengths[s] = len > 0 ? len : 1.0;
    }
    return lengths;
  }

  static List<Float32List> _computeCumulativeDistances(
    Int16List pointsXY,
    Uint32List offsets,
    int strokeCount,
  ) {
    final list = <Float32List>[];
    for (int s = 0; s < strokeCount; s++) {
      final startIdx = offsets[s];
      final endIdx = offsets[s + 1];
      final count = endIdx - startIdx;
      final dists = Float32List(count);
      if (count > 0) {
        dists[0] = 0.0;
        double accum = 0.0;
        for (int i = 1; i < count; i++) {
          final curr = startIdx + i;
          final prev = startIdx + i - 1;
          final dx = (pointsXY[curr * 2] - pointsXY[prev * 2]).toDouble();
          final dy = (pointsXY[curr * 2 + 1] - pointsXY[prev * 2 + 1])
              .toDouble();
          accum += math.sqrt(dx * dx + dy * dy);
          dists[i] = accum;
        }
      }
      list.add(dists);
    }
    return list;
  }

  /// Binary search lower_bound on monotonic cumulative arc length array.
  static int lowerBound(Float32List list, double value) {
    int low = 0;
    int high = list.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (list[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Extracts interpolated sub-pixel polyline points for partial stroke playback at [progress].
  List<Offset> getPartialStrokePoints(
    int strokeIndex,
    double progress,
    double scaleX,
    double scaleY,
  ) {
    if (strokeIndex < 0 || strokeIndex >= strokeCount) return const [];
    final startIdx = offsets[strokeIndex];
    final endIdx = offsets[strokeIndex + 1];
    final count = endIdx - startIdx;
    if (count == 0) return const [];
    if (count == 1 || progress <= 0.0) {
      return [
        Offset(
          pointsXY[startIdx * 2] * scaleX,
          pointsXY[startIdx * 2 + 1] * scaleY,
        ),
      ];
    }
    if (progress >= 1.0) {
      return List<Offset>.generate(count, (i) {
        final idx = startIdx + i;
        return Offset(
          pointsXY[idx * 2] * scaleX,
          pointsXY[idx * 2 + 1] * scaleY,
        );
      });
    }

    final totalLen = strokeLengths[strokeIndex];
    final targetLen = totalLen * progress.clamp(0.0, 1.0);
    final dists = cumulativeDistances[strokeIndex];
    final ub = lowerBound(dists, targetLen);

    final pts = <Offset>[];
    final takeCount = math.min(ub, count);
    for (int i = 0; i < takeCount; i++) {
      final idx = startIdx + i;
      pts.add(
        Offset(pointsXY[idx * 2] * scaleX, pointsXY[idx * 2 + 1] * scaleY),
      );
    }

    if (ub > 0 && ub < count) {
      final prevD = dists[ub - 1];
      final nextD = dists[ub];
      final segLen = nextD - prevD;
      final alpha = segLen > 1e-4
          ? ((targetLen - prevD) / segLen).clamp(0.0, 1.0)
          : 0.0;
      final p0Idx = startIdx + ub - 1;
      final p1Idx = startIdx + ub;
      final x =
          pointsXY[p0Idx * 2] +
          (pointsXY[p1Idx * 2] - pointsXY[p0Idx * 2]) * alpha;
      final y =
          pointsXY[p0Idx * 2 + 1] +
          (pointsXY[p1Idx * 2 + 1] - pointsXY[p0Idx * 2 + 1]) * alpha;
      pts.add(Offset(x * scaleX, y * scaleY));
    }

    return pts;
  }

  /// Builds a [FlatStrokeBuffer] from pre-computed [AutodrawCommand] list.
  factory FlatStrokeBuffer.fromCommands(
    List<AutodrawCommand> commands,
    int width,
    int height,
  ) {
    final strokeCount = commands.length;
    final strokePointsList = <List<Offset>>[];
    final strokeWidthsList = <List<int>>[];
    int totalPts = 0;

    for (final cmd in commands) {
      final pts = <Offset>[cmd.startPoint];
      for (final seg in cmd.segments) {
        const steps = 4;
        Offset prev = pts.last;
        for (int k = 1; k <= steps; k++) {
          final t = k / steps;
          final it = 1.0 - t;
          final x =
              it * it * it * prev.dx +
              3 * it * it * t * seg.cp1.dx +
              3 * it * t * t * seg.cp2.dx +
              t * t * t * seg.end.dx;
          final y =
              it * it * it * prev.dy +
              3 * it * it * t * seg.cp1.dy +
              3 * it * t * t * seg.cp2.dy +
              t * t * t * seg.end.dy;
          pts.add(Offset(x, y));
        }
      }
      strokePointsList.add(pts);
      strokeWidthsList.add(
        List<int>.filled(pts.length, cmd.strokeWidth.round().clamp(1, 25)),
      );
      totalPts += pts.length;
    }

    final pointsXY = Int16List(totalPts * 2);
    final widths = Uint8List(totalPts);
    final offsets = Uint32List(strokeCount + 1);

    int curIdx = 0;
    for (int s = 0; s < strokeCount; s++) {
      offsets[s] = curIdx;
      final pts = strokePointsList[s];
      final ws = strokeWidthsList[s];
      for (int i = 0; i < pts.length; i++) {
        pointsXY[curIdx * 2] = pts[i].dx.round().clamp(0, 32767);
        pointsXY[curIdx * 2 + 1] = pts[i].dy.round().clamp(0, 32767);
        widths[curIdx] = ws[i];
        curIdx++;
      }
    }
    offsets[strokeCount] = curIdx;

    return FlatStrokeBuffer(
      pointsXY: pointsXY,
      widths: widths,
      offsets: offsets,
      strokeCount: strokeCount,
      totalPoints: totalPts,
    );
  }
}

/// Backwards compatible alias for [AutodrawCommand].
typedef AutodrawStroke = AutodrawCommand;

/// The complete vectorization result containing pre-computed artist commands.
class AutodrawVectorizationResult {
  final int width;
  final int height;
  final List<AutodrawCommand> commands;
  final FlatStrokeBuffer? flatStrokeBuffer;
  List<AutodrawCommand> get strokes => commands;

  AutodrawVectorizationResult({
    required this.width,
    required this.height,
    List<AutodrawCommand>? commands,
    List<AutodrawCommand>? strokes,
    this.flatStrokeBuffer,
  }) : commands = commands ?? strokes ?? const [];

  FlatStrokeBuffer get flatBuffer =>
      flatStrokeBuffer ??
      FlatStrokeBuffer.fromCommands(commands, width, height);

  /// Verifies that commands are strictly ordered: All Lines -> All Fills -> All Highlights.
  bool get isSortedByTonalLayer {
    for (int i = 1; i < commands.length; i++) {
      if (commands[i].actionType.orderIndex <
          commands[i - 1].actionType.orderIndex) {
        return false;
      }
    }
    return true;
  }

  int get linesCount =>
      commands.where((c) => c.actionType == AutodrawActionType.drawLine).length;

  int get fillsCount => commands
      .where((c) => c.actionType == AutodrawActionType.fillRegion)
      .length;

  int get highlightsCount => commands
      .where((c) => c.actionType == AutodrawActionType.drawHighlight)
      .length;

  int get backgroundCount =>
      commands.where((s) => s.layer == AutodrawTonalLayer.background).length;

  int get midtonesCount =>
      commands.where((s) => s.layer == AutodrawTonalLayer.midtones).length;
}
