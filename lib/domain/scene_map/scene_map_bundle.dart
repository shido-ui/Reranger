import 'dart:convert';

import 'analysis_bundle_metadata.dart';
import 'color_region_map_data.dart';
import 'contour_map_data.dart';
import 'coordinate_transform.dart';
import 'edge_map_data.dart';
import 'pyramid_level.dart';
import 'scene_map_failure.dart';
import 'tonal_palette_map_data.dart';

/// Complete, versioned Analysis Bundle / Scene Map artifact.
/// Contains verified multi-scale pyramids, edge gradients, contour paths,
/// dominant harmonic palette, tonal distribution, and spatial color regions.
///
/// Invariant 7: Does NOT contain fabricated subject, face, or depth maps.
class SceneMapBundle {
  final AnalysisBundleMetadata metadata;
  final CoordinateTransform transform;
  final List<PyramidLevel> pyramidLevels;
  final EdgeMapData edgeMap;
  final ContourMapData contourMap;
  final TonalPaletteMapData tonalPaletteMap;
  final ColorRegionMapData colorRegionMap;

  const SceneMapBundle({
    required this.metadata,
    required this.transform,
    required this.pyramidLevels,
    required this.edgeMap,
    required this.contourMap,
    required this.tonalPaletteMap,
    required this.colorRegionMap,
  }) : assert(
         pyramidLevels.length > 0,
         'Must contain at least 1 pyramid level',
       );

  /// Primary display preview scale level (Level 0).
  PyramidLevel get primaryPreview => pyramidLevels.first;

  // Invariant 7 Capability Getters (honest representation of capabilities)
  bool get hasSubjectMap => metadata.hasSubjectMap;
  bool get hasDepthMap => metadata.hasDepthMap;
  bool get hasFaceMap => metadata.hasFaceMap;

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'transform': transform.toJson(),
    'pyramidLevels': pyramidLevels.map((lvl) => lvl.toJson()).toList(),
    'edgeMap': edgeMap.toJson(),
    'contourMap': contourMap.toJson(),
    'tonalPaletteMap': tonalPaletteMap.toJson(),
    'colorRegionMap': colorRegionMap.toJson(),
  };

  String encodeJson() => jsonEncode(toJson());

  factory SceneMapBundle.fromJson(Map<String, dynamic> json) {
    try {
      final rawMeta = json['metadata'] as Map<String, dynamic>?;
      final rawTransform = json['transform'] as Map<String, dynamic>?;
      final rawPyramids = json['pyramidLevels'] as List?;
      final rawEdge = json['edgeMap'] as Map<String, dynamic>?;
      final rawContour = json['contourMap'] as Map<String, dynamic>?;
      final rawTonal = json['tonalPaletteMap'] as Map<String, dynamic>?;
      final rawRegions = json['colorRegionMap'] as Map<String, dynamic>?;

      if (rawMeta == null ||
          rawTransform == null ||
          rawPyramids == null ||
          rawEdge == null ||
          rawContour == null ||
          rawTonal == null ||
          rawRegions == null) {
        throw const FormatException('Missing required SceneMapBundle sections');
      }

      return SceneMapBundle(
        metadata: AnalysisBundleMetadata.fromJson(rawMeta),
        transform: CoordinateTransform.fromJson(rawTransform),
        pyramidLevels: rawPyramids
            .map((e) => PyramidLevel.fromJson(e as Map<String, dynamic>))
            .toList(),
        edgeMap: EdgeMapData.fromJson(rawEdge),
        contourMap: ContourMapData.fromJson(rawContour),
        tonalPaletteMap: TonalPaletteMapData.fromJson(rawTonal),
        colorRegionMap: ColorRegionMapData.fromJson(rawRegions),
      );
    } catch (e, st) {
      throw SceneMapCorruptCacheFailure(
        json['metadata']?['sourceHash']?.toString() ?? 'unknown',
        'Failed to parse SceneMapBundle JSON: $e\n$st',
      );
    }
  }

  factory SceneMapBundle.decodeJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SceneMapBundle.fromJson(map);
    } catch (e, st) {
      throw SceneMapCorruptCacheFailure(
        'raw_json_stream',
        'Invalid JSON formatting: $e\n$st',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneMapBundle &&
          runtimeType == other.runtimeType &&
          metadata == other.metadata &&
          transform == other.transform &&
          edgeMap == other.edgeMap &&
          contourMap == other.contourMap &&
          tonalPaletteMap == other.tonalPaletteMap &&
          colorRegionMap == other.colorRegionMap;

  @override
  int get hashCode => Object.hash(
    metadata,
    transform,
    edgeMap,
    contourMap,
    tonalPaletteMap,
    colorRegionMap,
  );
}
