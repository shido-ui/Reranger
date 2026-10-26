import 'dart:math' as math;
import 'dart:ui';

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

/// A vectorized stroke consisting of a starting point and smooth Bézier curve segments.
class AutodrawStroke {
  final int id;
  final AutodrawTonalLayer layer;
  final Color strokeColor;
  Color get color => strokeColor;
  final double strokeWidth;
  final Offset startPoint;
  final List<BezierSegment> segments;

  Path? _cachedPath;
  double? _cachedScaleX;
  double? _cachedScaleY;
  double? _cachedLength;

  AutodrawStroke({
    required this.id,
    required this.layer,
    Color? strokeColor,
    Color? color,
    required this.strokeWidth,
    required this.startPoint,
    required this.segments,
  }) : strokeColor = strokeColor ?? color ?? const Color(0xFF000000);

  /// Constructs a Flutter [Path] representing this stroke, scaling every x and y coordinate by [scaleX] and [scaleY].
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
    _cachedPath = p;
    _cachedScaleX = scaleX;
    _cachedScaleY = scaleY;
    return p;
  }

  /// Constructs an unscaled Flutter [Path] representing this stroke in native bitmap coordinates.
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

/// The complete vectorization result containing strokes sorted by tonal layer.
class AutodrawVectorizationResult {
  final int width;
  final int height;
  final List<AutodrawStroke> strokes;

  const AutodrawVectorizationResult({
    required this.width,
    required this.height,
    required this.strokes,
  });

  /// Verifies that strokes are strictly sorted Background -> Midtones -> Highlights.
  bool get isSortedByTonalLayer {
    for (int i = 1; i < strokes.length; i++) {
      if (strokes[i].layer.indexValue < strokes[i - 1].layer.indexValue) {
        return false;
      }
    }
    return true;
  }

  int get backgroundCount =>
      strokes.where((s) => s.layer == AutodrawTonalLayer.background).length;

  int get midtonesCount =>
      strokes.where((s) => s.layer == AutodrawTonalLayer.midtones).length;

  int get highlightsCount =>
      strokes.where((s) => s.layer == AutodrawTonalLayer.highlights).length;
}
