import 'dart:math' as math;

/// Normalized 2D spatial coordinate strictly bounded to [0.0, 1.0].
/// (0.0, 0.0) represents top-left and (1.0, 1.0) represents bottom-right.
class NormalizedPoint {
  final double x;
  final double y;

  const NormalizedPoint(this.x, this.y)
    : assert(x >= 0.0 && x <= 1.0, 'x ($x) must be within [0.0, 1.0]'),
      assert(y >= 0.0 && y <= 1.0, 'y ($y) must be within [0.0, 1.0]');

  /// Safe constructor clamping coordinates to [0.0, 1.0] without asserting.
  factory NormalizedPoint.clamped(double x, double y) {
    final cx = x.isFinite ? x.clamp(0.0, 1.0) : 0.0;
    final cy = y.isFinite ? y.clamp(0.0, 1.0) : 0.0;
    return NormalizedPoint(cx, cy);
  }

  bool get isFinite => x.isFinite && y.isFinite;

  NormalizedPoint lerp(NormalizedPoint other, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    return NormalizedPoint(
      x + (other.x - x) * clampedT,
      y + (other.y - y) * clampedT,
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory NormalizedPoint.fromJson(Map<String, dynamic> json) {
    return NormalizedPoint.clamped(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedPoint &&
          runtimeType == other.runtimeType &&
          (x - other.x).abs() < 1e-7 &&
          (y - other.y).abs() < 1e-7;

  @override
  int get hashCode => Object.hash(x.toStringAsFixed(6), y.toStringAsFixed(6));

  @override
  String toString() =>
      'NormalizedPoint(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';
}

/// Normalized 2D bounding rectangle bounded to [0.0, 1.0].
class NormalizedRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const NormalizedRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : assert(left >= 0.0 && left <= 1.0, 'left out of normalized range'),
       assert(top >= 0.0 && top <= 1.0, 'top out of normalized range'),
       assert(
         width >= 0.0 && left + width <= 1.0000001,
         'right extends beyond 1.0',
       ),
       assert(
         height >= 0.0 && top + height <= 1.0000001,
         'bottom extends beyond 1.0',
       );

  factory NormalizedRect.clamped({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final cl = (left.isFinite ? left : 0.0).clamp(0.0, 1.0);
    final ct = (top.isFinite ? top : 0.0).clamp(0.0, 1.0);
    final maxW = 1.0 - cl;
    final maxH = 1.0 - ct;
    final cw = (width.isFinite ? width : 0.0).clamp(0.0, maxW);
    final ch = (height.isFinite ? height : 0.0).clamp(0.0, maxH);
    return NormalizedRect(left: cl, top: ct, width: cw, height: ch);
  }

  factory NormalizedRect.fromPoints(NormalizedPoint p1, NormalizedPoint p2) {
    final l = math.min(p1.x, p2.x);
    final t = math.min(p1.y, p2.y);
    final r = math.max(p1.x, p2.x);
    final b = math.max(p1.y, p2.y);
    return NormalizedRect.clamped(left: l, top: t, width: r - l, height: b - t);
  }

  double get right => left + width;
  double get bottom => top + height;
  NormalizedPoint get center =>
      NormalizedPoint.clamped(left + width / 2.0, top + height / 2.0);

  bool containsPoint(NormalizedPoint p) {
    return p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  factory NormalizedRect.fromJson(Map<String, dynamic> json) {
    return NormalizedRect.clamped(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedRect &&
          runtimeType == other.runtimeType &&
          (left - other.left).abs() < 1e-7 &&
          (top - other.top).abs() < 1e-7 &&
          (width - other.width).abs() < 1e-7 &&
          (height - other.height).abs() < 1e-7;

  @override
  int get hashCode => Object.hash(
    left.toStringAsFixed(6),
    top.toStringAsFixed(6),
    width.toStringAsFixed(6),
    height.toStringAsFixed(6),
  );

  @override
  String toString() =>
      'NormalizedRect(L:${left.toStringAsFixed(4)}, T:${top.toStringAsFixed(4)}, W:${width.toStringAsFixed(4)}, H:${height.toStringAsFixed(4)})';
}

/// Bidirectional coordinate transformer between:
/// 1. Source full-resolution pixel space (e.g. 4000x3000)
/// 2. Preview downscaled display pixel space (e.g. 512x384)
/// 3. Scene map grid pixel space (e.g. 256x192)
/// 4. Normalized device coordinates [0.0, 1.0]
class CoordinateTransform {
  final int sourceWidth;
  final int sourceHeight;
  final int previewWidth;
  final int previewHeight;
  final int mapWidth;
  final int mapHeight;

  const CoordinateTransform({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.previewWidth,
    required this.previewHeight,
    required this.mapWidth,
    required this.mapHeight,
  }) : assert(sourceWidth > 0 && sourceHeight > 0, 'Invalid source dimensions'),
       assert(
         previewWidth > 0 && previewHeight > 0,
         'Invalid preview dimensions',
       ),
       assert(mapWidth > 0 && mapHeight > 0, 'Invalid map dimensions');

  double get sourceAspectRatio => sourceWidth / sourceHeight;
  double get previewAspectRatio => previewWidth / previewHeight;
  double get mapAspectRatio => mapWidth / mapHeight;

  // --- Normalized <-> Source Space ---

  NormalizedPoint sourceToNormalized(double px, double py) {
    final x = (sourceWidth > 1) ? (px / (sourceWidth - 1)) : 0.0;
    final y = (sourceHeight > 1) ? (py / (sourceHeight - 1)) : 0.0;
    return NormalizedPoint.clamped(x, y);
  }

  (double, double) normalizedToSource(NormalizedPoint p) {
    final px = p.x * (sourceWidth - 1);
    final py = p.y * (sourceHeight - 1);
    return (px, py);
  }

  // --- Normalized <-> Preview Space ---

  NormalizedPoint previewToNormalized(double px, double py) {
    final x = (previewWidth > 1) ? (px / (previewWidth - 1)) : 0.0;
    final y = (previewHeight > 1) ? (py / (previewHeight - 1)) : 0.0;
    return NormalizedPoint.clamped(x, y);
  }

  (double, double) normalizedToPreview(NormalizedPoint p) {
    final px = p.x * (previewWidth - 1);
    final py = p.y * (previewHeight - 1);
    return (px, py);
  }

  // --- Normalized <-> Map Space ---

  NormalizedPoint mapToNormalized(double px, double py) {
    final x = (mapWidth > 1) ? (px / (mapWidth - 1)) : 0.0;
    final y = (mapHeight > 1) ? (py / (mapHeight - 1)) : 0.0;
    return NormalizedPoint.clamped(x, y);
  }

  (double, double) normalizedToMap(NormalizedPoint p) {
    final px = p.x * (mapWidth - 1);
    final py = p.y * (mapHeight - 1);
    return (px, py);
  }

  // --- Direct Coordinate Mapping ---

  (double, double) sourceToPreview(double sx, double sy) {
    final norm = sourceToNormalized(sx, sy);
    return normalizedToPreview(norm);
  }

  (double, double) previewToSource(double px, double py) {
    final norm = previewToNormalized(px, py);
    return normalizedToSource(norm);
  }

  (double, double) sourceToMap(double sx, double sy) {
    final norm = sourceToNormalized(sx, sy);
    return normalizedToMap(norm);
  }

  (double, double) mapToSource(double mx, double my) {
    final norm = mapToNormalized(mx, my);
    return normalizedToSource(norm);
  }

  /// Calculates the aspect-ratio preserved fitted rect inside a viewport of [viewportWidth]x[viewportHeight].
  /// Returns the offset (dx, dy) and scaled display dimensions (width, height) in viewport points.
  ({double left, double top, double width, double height}) calculateFitLayout(
    double viewportWidth,
    double viewportHeight,
  ) {
    final vpAspect = viewportWidth / viewportHeight;
    final imgAspect = sourceAspectRatio;

    double renderW;
    double renderH;
    if (imgAspect > vpAspect) {
      // Width constrained (letterbox top/bottom)
      renderW = viewportWidth;
      renderH = viewportWidth / imgAspect;
    } else {
      // Height constrained (pillarbox left/right)
      renderH = viewportHeight;
      renderW = viewportHeight * imgAspect;
    }

    final offsetX = (viewportWidth - renderW) / 2.0;
    final offsetY = (viewportHeight - renderH) / 2.0;

    return (left: offsetX, top: offsetY, width: renderW, height: renderH);
  }

  Map<String, dynamic> toJson() => {
    'sourceWidth': sourceWidth,
    'sourceHeight': sourceHeight,
    'previewWidth': previewWidth,
    'previewHeight': previewHeight,
    'mapWidth': mapWidth,
    'mapHeight': mapHeight,
  };

  factory CoordinateTransform.fromJson(Map<String, dynamic> json) {
    return CoordinateTransform(
      sourceWidth: json['sourceWidth'] as int,
      sourceHeight: json['sourceHeight'] as int,
      previewWidth: json['previewWidth'] as int,
      previewHeight: json['previewHeight'] as int,
      mapWidth: json['mapWidth'] as int,
      mapHeight: json['mapHeight'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoordinateTransform &&
          runtimeType == other.runtimeType &&
          sourceWidth == other.sourceWidth &&
          sourceHeight == other.sourceHeight &&
          previewWidth == other.previewWidth &&
          previewHeight == other.previewHeight &&
          mapWidth == other.mapWidth &&
          mapHeight == other.mapHeight;

  @override
  int get hashCode => Object.hash(
    sourceWidth,
    sourceHeight,
    previewWidth,
    previewHeight,
    mapWidth,
    mapHeight,
  );
}
