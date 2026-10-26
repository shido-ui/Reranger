import 'dart:math' as math;
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
  }) : actionType = actionType ??
           (layer == AutodrawTonalLayer.background
               ? AutodrawActionType.drawLine
               : layer == AutodrawTonalLayer.midtones
                   ? AutodrawActionType.fillRegion
                   : AutodrawActionType.drawHighlight),
       layer = layer ??
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

/// Backwards compatible alias for [AutodrawCommand].
typedef AutodrawStroke = AutodrawCommand;

/// The complete vectorization result containing pre-computed artist commands.
class AutodrawVectorizationResult {
  final int width;
  final int height;
  final List<AutodrawCommand> commands;
  List<AutodrawCommand> get strokes => commands;

  AutodrawVectorizationResult({
    required this.width,
    required this.height,
    List<AutodrawCommand>? commands,
    List<AutodrawCommand>? strokes,
  }) : commands = commands ?? strokes ?? const [];

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
