/// Versioned metadata describing an Analysis Bundle / Scene Map.
/// Captures source provenance, algorithm versions, parameters, dimensions,
/// color space, timestamps, and explicit capability flags (Invariant 7).
class AnalysisBundleMetadata {
  static const int currentBundleVersion = 1;
  static const String defaultEngineVersion = '1.0.0';

  final int bundleVersion;
  final String engineVersion;
  final String sourceHash;
  final int sourceWidth;
  final int sourceHeight;
  final String colorSpace;
  final DateTime createdAt;
  final Map<String, dynamic> parameters;

  // Explicit capability flags to prevent illusory AI claims (Invariant 7)
  final bool hasEdgeMap;
  final bool hasContourMap;
  final bool hasPaletteMap;
  final bool hasColorRegions;
  final bool hasSubjectMap;
  final bool hasDepthMap;
  final bool hasFaceMap;

  const AnalysisBundleMetadata({
    this.bundleVersion = currentBundleVersion,
    this.engineVersion = defaultEngineVersion,
    required this.sourceHash,
    required this.sourceWidth,
    required this.sourceHeight,
    this.colorSpace = 'sRGB',
    required this.createdAt,
    this.parameters = const {},
    this.hasEdgeMap = true,
    this.hasContourMap = true,
    this.hasPaletteMap = true,
    this.hasColorRegions = true,
    this.hasSubjectMap = false, // Strictly false when ML model is unavailable
    this.hasDepthMap =
        false, // Strictly false when depth estimator is unavailable
    this.hasFaceMap =
        false, // Strictly false when face landmark model is unavailable
  }) : assert(bundleVersion >= 1, 'Bundle version must be >= 1'),
       assert(sourceHash.length == 64, 'Source hash must be 64-char SHA-256'),
       assert(
         sourceWidth > 0 && sourceHeight > 0,
         'Dimensions must be positive',
       );

  Map<String, dynamic> toJson() => {
    'bundleVersion': bundleVersion,
    'engineVersion': engineVersion,
    'sourceHash': sourceHash,
    'sourceWidth': sourceWidth,
    'sourceHeight': sourceHeight,
    'colorSpace': colorSpace,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'parameters': parameters,
    'capabilities': {
      'hasEdgeMap': hasEdgeMap,
      'hasContourMap': hasContourMap,
      'hasPaletteMap': hasPaletteMap,
      'hasColorRegions': hasColorRegions,
      'hasSubjectMap': hasSubjectMap,
      'hasDepthMap': hasDepthMap,
      'hasFaceMap': hasFaceMap,
    },
  };

  factory AnalysisBundleMetadata.fromJson(Map<String, dynamic> json) {
    final caps = json['capabilities'] as Map<String, dynamic>? ?? {};
    return AnalysisBundleMetadata(
      bundleVersion: json['bundleVersion'] as int? ?? currentBundleVersion,
      engineVersion: json['engineVersion'] as String? ?? defaultEngineVersion,
      sourceHash: json['sourceHash'] as String,
      sourceWidth: json['sourceWidth'] as int,
      sourceHeight: json['sourceHeight'] as int,
      colorSpace: json['colorSpace'] as String? ?? 'sRGB',
      createdAt: DateTime.parse(json['createdAt'] as String),
      parameters: Map<String, dynamic>.from(json['parameters'] as Map? ?? {}),
      hasEdgeMap: caps['hasEdgeMap'] as bool? ?? true,
      hasContourMap: caps['hasContourMap'] as bool? ?? true,
      hasPaletteMap: caps['hasPaletteMap'] as bool? ?? true,
      hasColorRegions: caps['hasColorRegions'] as bool? ?? true,
      hasSubjectMap: caps['hasSubjectMap'] as bool? ?? false,
      hasDepthMap: caps['hasDepthMap'] as bool? ?? false,
      hasFaceMap: caps['hasFaceMap'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisBundleMetadata &&
          runtimeType == other.runtimeType &&
          bundleVersion == other.bundleVersion &&
          engineVersion == other.engineVersion &&
          sourceHash == other.sourceHash &&
          sourceWidth == other.sourceWidth &&
          sourceHeight == other.sourceHeight &&
          colorSpace == other.colorSpace &&
          hasSubjectMap == other.hasSubjectMap &&
          hasDepthMap == other.hasDepthMap &&
          hasFaceMap == other.hasFaceMap;

  @override
  int get hashCode => Object.hash(
    bundleVersion,
    engineVersion,
    sourceHash,
    sourceWidth,
    sourceHeight,
    colorSpace,
  );

  @override
  String toString() =>
      'AnalysisBundleMetadata(v$bundleVersion, eng:$engineVersion, src:${sourceHash.substring(0, 8)}, ${sourceWidth}x$sourceHeight, capabilities: {edge:$hasEdgeMap, contour:$hasContourMap, palette:$hasPaletteMap, subject:$hasSubjectMap})';
}
