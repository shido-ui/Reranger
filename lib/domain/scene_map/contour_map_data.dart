import 'coordinate_transform.dart';

/// A single continuous perimeter contour in normalized device coordinates [0.0, 1.0].
class ContourPath {
  final List<NormalizedPoint> points;
  final NormalizedRect bounds;
  final double length;
  final bool isClosed;

  const ContourPath({
    required this.points,
    required this.bounds,
    required this.length,
    this.isClosed = true,
  }) : assert(points.length >= 2, 'Contour must contain at least 2 points'),
       assert(length >= 0.0, 'Length must be non-negative');

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
    'bounds': bounds.toJson(),
    'length': length,
    'isClosed': isClosed,
  };

  factory ContourPath.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List)
        .map((e) => NormalizedPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    final rawBounds = NormalizedRect.fromJson(
      json['bounds'] as Map<String, dynamic>,
    );
    return ContourPath(
      points: rawPoints,
      bounds: rawBounds,
      length: (json['length'] as num).toDouble(),
      isClosed: json['isClosed'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContourPath &&
          runtimeType == other.runtimeType &&
          isClosed == other.isClosed &&
          (length - other.length).abs() < 1e-5 &&
          bounds == other.bounds &&
          _pointsEqual(points, other.points);

  @override
  int get hashCode => Object.hash(points.length, bounds, length, isClosed);

  static bool _pointsEqual(List<NormalizedPoint> a, List<NormalizedPoint> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Collection of structural contours extracted from the image.
class ContourMapData {
  final List<ContourPath> contours;
  final int totalContourPoints;
  final double
  contourDensity; // Ratio of contour points to total analysis pixels

  const ContourMapData({
    required this.contours,
    required this.totalContourPoints,
    required this.contourDensity,
  }) : assert(totalContourPoints >= 0, 'Point count must be non-negative'),
       assert(
         contourDensity >= 0.0 && contourDensity <= 1.0,
         'Contour density must be in [0.0, 1.0]',
       );

  Map<String, dynamic> toJson() => {
    'contours': contours.map((c) => c.toJson()).toList(),
    'totalContourPoints': totalContourPoints,
    'contourDensity': contourDensity,
  };

  factory ContourMapData.fromJson(Map<String, dynamic> json) {
    final rawList = (json['contours'] as List)
        .map((e) => ContourPath.fromJson(e as Map<String, dynamic>))
        .toList();
    return ContourMapData(
      contours: rawList,
      totalContourPoints: json['totalContourPoints'] as int,
      contourDensity: (json['contourDensity'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContourMapData &&
          runtimeType == other.runtimeType &&
          totalContourPoints == other.totalContourPoints &&
          (contourDensity - other.contourDensity).abs() < 1e-6 &&
          _contoursEqual(contours, other.contours);

  @override
  int get hashCode => Object.hash(contours.length, totalContourPoints);

  static bool _contoursEqual(List<ContourPath> a, List<ContourPath> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
