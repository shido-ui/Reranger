import '../recipes/render_graph.dart';
import 'preset_parameter.dart';

/// Complete declarative specification of a high-quality style preset recipe.
/// Enforces:
/// - Invariant 3: Single-tap beginner-friendly defaults with progressive disclosure sliders.
/// - Invariant 7: Honest implementation mapping to actual validated DAG nodes (no fake presets).
/// - Invariant 10: Documented asset provenance for thumbnails.
class PresetDefinition {
  final String id;
  final String displayName;
  final String category;
  final String description;
  final int version;
  final List<PresetParameter> parameters;
  final String thumbnailAssetPath;
  final String thumbnailProvenance;
  final String accessibleLabel;

  /// Pure function constructing the executable DAG [RenderGraph] for this preset.
  final RenderGraph Function(
    String sourceHash,
    int sourceWidth,
    int sourceHeight,
    Map<String, double> paramValues,
  )
  buildGraph;

  const PresetDefinition({
    required this.id,
    required this.displayName,
    required this.category,
    required this.description,
    this.version = 1,
    required this.parameters,
    required this.thumbnailAssetPath,
    required this.thumbnailProvenance,
    required this.accessibleLabel,
    required this.buildGraph,
  }) : assert(id.length > 0, 'Preset ID cannot be empty'),
       assert(displayName.length > 0, 'Display name cannot be empty'),
       assert(version >= 1, 'Version must be >= 1');

  /// Resolves parameters by applying user overrides onto default values with bounds clamping.
  Map<String, double> resolveParameters(Map<String, double>? userValues) {
    final result = <String, double>{};
    for (final param in parameters) {
      final userVal = userValues?[param.id];
      if (userVal != null) {
        result[param.id] = param.clamp(userVal);
      } else {
        result[param.id] = param.defaultValue;
      }
    }
    return result;
  }

  /// Whether this preset is a locked hyper-premium studio preset
  /// that only exposes a single Studio Strength slider.
  bool get isLockedStudioPreset =>
      id.startsWith('studio_') ||
      (parameters.length == 1 && parameters.first.id == 'studioStrength');

  /// Exports parameter metadata to JSON schema.
  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'category': category,
    'description': description,
    'version': version,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'thumbnailAssetPath': thumbnailAssetPath,
    'thumbnailProvenance': thumbnailProvenance,
    'accessibleLabel': accessibleLabel,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PresetDefinition &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayName == other.displayName &&
          version == other.version;

  @override
  int get hashCode => Object.hash(id, displayName, version);

  @override
  String toString() => 'PresetDefinition($id: "$displayName", v$version)';
}
