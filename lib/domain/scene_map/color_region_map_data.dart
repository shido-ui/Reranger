import 'dart:convert';
import 'dart:typed_data';

import 'coordinate_transform.dart';

/// Spatial color region map assigning each discrete grid pixel to a palette cluster.
class ColorRegionMapData {
  final int gridWidth;
  final int gridHeight;
  final int regionCount; // Number of unique color regions (K)
  final Uint8List
  regionLabels; // 1 byte per pixel: cluster index in [0, regionCount - 1]
  final Map<int, NormalizedPoint>
  regionCentroids; // Spatial center of gravity per region
  final Map<int, double>
  regionCoverage; // Fraction of total pixels in [0.0, 1.0]

  const ColorRegionMapData({
    required this.gridWidth,
    required this.gridHeight,
    required this.regionCount,
    required this.regionLabels,
    required this.regionCentroids,
    required this.regionCoverage,
  }) : assert(
         gridWidth > 0 && gridHeight > 0,
         'Grid dimensions must be positive',
       ),
       assert(regionCount > 0, 'Region count must be positive'),
       assert(
         regionLabels.length == gridWidth * gridHeight,
         'Label buffer length must match gridWidth * gridHeight',
       );

  /// Retrieves the region cluster index for pixel (x, y). Clamps safely at edges.
  int getRegion(int x, int y) {
    final cx = x.clamp(0, gridWidth - 1);
    final cy = y.clamp(0, gridHeight - 1);
    return regionLabels[cy * gridWidth + cx];
  }

  Map<String, dynamic> toJson() {
    final centroidsMap = <String, dynamic>{};
    for (final entry in regionCentroids.entries) {
      centroidsMap[entry.key.toString()] = entry.value.toJson();
    }

    final coverageMap = <String, dynamic>{};
    for (final entry in regionCoverage.entries) {
      coverageMap[entry.key.toString()] = entry.value;
    }

    return {
      'gridWidth': gridWidth,
      'gridHeight': gridHeight,
      'regionCount': regionCount,
      'labelsBase64': base64Encode(regionLabels),
      'regionCentroids': centroidsMap,
      'regionCoverage': coverageMap,
    };
  }

  factory ColorRegionMapData.fromJson(Map<String, dynamic> json) {
    final w = json['gridWidth'] as int;
    final h = json['gridHeight'] as int;
    final count = json['regionCount'] as int;
    final bytes = base64Decode(json['labelsBase64'] as String);

    final rawCentroids = json['regionCentroids'] as Map<String, dynamic>? ?? {};
    final centroids = <int, NormalizedPoint>{};
    for (final entry in rawCentroids.entries) {
      final key = int.parse(entry.key);
      centroids[key] = NormalizedPoint.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    final rawCoverage = json['regionCoverage'] as Map<String, dynamic>? ?? {};
    final coverage = <int, double>{};
    for (final entry in rawCoverage.entries) {
      final key = int.parse(entry.key);
      coverage[key] = (entry.value as num).toDouble();
    }

    return ColorRegionMapData(
      gridWidth: w,
      gridHeight: h,
      regionCount: count,
      regionLabels: Uint8List.fromList(bytes),
      regionCentroids: centroids,
      regionCoverage: coverage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorRegionMapData &&
          runtimeType == other.runtimeType &&
          gridWidth == other.gridWidth &&
          gridHeight == other.gridHeight &&
          regionCount == other.regionCount &&
          _bytesEqual(regionLabels, other.regionLabels);

  @override
  int get hashCode => Object.hash(gridWidth, gridHeight, regionCount);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
