import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../layers/editor_layer.dart';
import '../layers/variant_board.dart';

/// Base class for project and storage failures.
sealed class ProjectFailure implements Exception {
  final String message;
  final String? technicalDetails;

  const ProjectFailure(this.message, [this.technicalDetails]);

  @override
  String toString() =>
      'ProjectFailure: $message${technicalDetails != null ? ' ($technicalDetails)' : ''}';
}

class StorageFailure extends ProjectFailure {
  const StorageFailure(super.message, [super.technicalDetails]);
}

class CorruptedProjectFailure extends ProjectFailure {
  const CorruptedProjectFailure(super.message, [super.technicalDetails]);
}

class MissingFileFailure extends ProjectFailure {
  final String path;
  const MissingFileFailure(this.path, [String? technicalDetails])
    : super('Required project file is missing: $path', technicalDetails);
}

class ChecksumMismatchFailure extends ProjectFailure {
  final String expectedHash;
  final String actualHash;
  const ChecksumMismatchFailure(this.expectedHash, this.actualHash)
    : super(
        'File integrity violation: expected $expectedHash but got $actualHash',
      );
}

class LowStorageFailure extends ProjectFailure {
  final int requiredBytes;
  final int availableBytes;
  const LowStorageFailure(this.requiredBytes, this.availableBytes)
    : super(
        'Insufficient disk storage: required $requiredBytes bytes, but only $availableBytes bytes available',
      );
}

class DuplicateProjectNameFailure extends ProjectFailure {
  final String name;
  const DuplicateProjectNameFailure(this.name)
    : super('A project named "$name" already exists.');
}

class FormatFailure extends ProjectFailure {
  const FormatFailure(super.message, [super.technicalDetails]);
}

class SecurityFailure extends ProjectFailure {
  const SecurityFailure(super.message, [super.technicalDetails]);
}

/// Linear RGBA float vector for shader uniforms and color mathematics.
class ColorVector {
  final double r;
  final double g;
  final double b;
  final double a;

  const ColorVector(this.r, this.g, this.b, [this.a = 1.0]);

  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b, 'a': a};

  factory ColorVector.fromJson(Map<String, dynamic> json) {
    return ColorVector(
      (json['r'] as num).toDouble(),
      (json['g'] as num).toDouble(),
      (json['b'] as num).toDouble(),
      (json['a'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorVector &&
          runtimeType == other.runtimeType &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          a == other.a;

  @override
  int get hashCode => Object.hash(r, g, b, a);
}

/// Immutable recipe capturing the full non-destructive transformation graph.
class RenderRecipe {
  final String recipeId;
  final int recipeVersion;
  final String sourceImageHash;
  final String sourceImagePath;
  final String activeStudio; // 'recolor' | 'style' | 'humanize'
  final String activePresetId;
  final double masterIntensity;
  final Map<String, double> fineTuneParameters;
  final List<int> curveLut256;
  final List<ColorVector> paletteRemap;
  final String? maskPath;
  final LayerStack? layerStack;
  final VariantBoard? variantBoard;
  final DateTime updatedAt;

  const RenderRecipe({
    required this.recipeId,
    this.recipeVersion = 1,
    required this.sourceImageHash,
    required this.sourceImagePath,
    required this.activeStudio,
    required this.activePresetId,
    required this.masterIntensity,
    required this.fineTuneParameters,
    required this.curveLut256,
    required this.paletteRemap,
    this.maskPath,
    this.layerStack,
    this.variantBoard,
    required this.updatedAt,
  });

  /// Factory for a brand-new default non-destructive recipe.
  factory RenderRecipe.initial({
    required String recipeId,
    required String sourceImageHash,
    required String sourceImagePath,
    String activeStudio = 'style',
    String activePresetId = 'graphite_pencil',
  }) {
    return RenderRecipe(
      recipeId: recipeId,
      recipeVersion: 1,
      sourceImageHash: sourceImageHash,
      sourceImagePath: sourceImagePath,
      activeStudio: activeStudio,
      activePresetId: activePresetId,
      masterIntensity: 1.0,
      fineTuneParameters: const {
        'temperature': 0.0,
        'tint': 0.0,
        'vibrance': 0.0,
        'contrast': 0.0,
      },
      curveLut256: List<int>.generate(256, (i) => i),
      paletteRemap: const [],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Returns true if the studio is one of the recognized functional studios.
  bool get isValidStudio =>
      const {'style', 'recolor', 'humanize'}.contains(activeStudio);

  RenderRecipe copyWith({
    String? activeStudio,
    String? activePresetId,
    double? masterIntensity,
    Map<String, double>? fineTuneParameters,
    List<int>? curveLut256,
    List<ColorVector>? paletteRemap,
    String? maskPath,
    LayerStack? layerStack,
    VariantBoard? variantBoard,
    int? recipeVersion,
    DateTime? updatedAt,
  }) {
    return RenderRecipe(
      recipeId: recipeId,
      recipeVersion: recipeVersion ?? this.recipeVersion,
      sourceImageHash: sourceImageHash,
      sourceImagePath: sourceImagePath,
      activeStudio: activeStudio ?? this.activeStudio,
      activePresetId: activePresetId ?? this.activePresetId,
      masterIntensity: masterIntensity ?? this.masterIntensity,
      fineTuneParameters: fineTuneParameters ?? this.fineTuneParameters,
      curveLut256: curveLut256 ?? this.curveLut256,
      paletteRemap: paletteRemap ?? this.paletteRemap,
      maskPath: maskPath ?? this.maskPath,
      layerStack: layerStack ?? this.layerStack,
      variantBoard: variantBoard ?? this.variantBoard,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'recipeId': recipeId,
    'recipeVersion': recipeVersion,
    'sourceImageHash': sourceImageHash,
    'sourceImagePath': sourceImagePath,
    'activeStudio': activeStudio,
    'activePresetId': activePresetId,
    'masterIntensity': masterIntensity,
    'fineTuneParameters': fineTuneParameters,
    'curveLut256': curveLut256,
    'paletteRemap': paletteRemap.map((c) => c.toJson()).toList(),
    'maskPath': maskPath,
    if (layerStack != null) 'layerStack': layerStack!.toJson(),
    if (variantBoard != null) 'variantBoard': variantBoard!.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory RenderRecipe.fromJson(Map<String, dynamic> json) {
    return RenderRecipe(
      recipeId: json['recipeId'] as String,
      recipeVersion: json['recipeVersion'] as int? ?? 1,
      sourceImageHash: json['sourceImageHash'] as String,
      sourceImagePath: json['sourceImagePath'] as String,
      activeStudio: json['activeStudio'] as String,
      activePresetId: json['activePresetId'] as String,
      masterIntensity: (json['masterIntensity'] as num).toDouble(),
      fineTuneParameters: (json['fineTuneParameters'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      curveLut256: (json['curveLut256'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(),
      paletteRemap:
          (json['paletteRemap'] as List<dynamic>?)
              ?.map((e) => ColorVector.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      maskPath: json['maskPath'] as String?,
      layerStack: json['layerStack'] != null
          ? LayerStack.fromJson(json['layerStack'] as Map<String, dynamic>)
          : null,
      variantBoard: json['variantBoard'] != null
          ? VariantBoard.fromJson(json['variantBoard'] as Map<String, dynamic>)
          : null,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Calculates a SHA-256 hash of the parameter values to invalidate/validate render cache.
  String computeParameterHash() {
    final payload = jsonEncode({
      'studio': activeStudio,
      'preset': activePresetId,
      'intensity': masterIntensity,
      'params': fineTuneParameters,
      'lut': curveLut256,
      'palette': paletteRemap.map((c) => c.toJson()).toList(),
      'mask': maskPath,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}

/// Core domain entity representing a complete Reranger project.
class ProjectEntity {
  final String id;
  final String name;
  final String sourceImagePath;
  final String sourceImageHash;
  final int sourceWidth;
  final int sourceHeight;
  final DateTime createdAt;
  final DateTime updatedAt;
  final RenderRecipe recipe;
  final String? sceneMapCacheKey;
  final String? outputReferencePath;
  final String? outputChecksum;
  final bool isDirty;
  final bool isCorrupted;

  const ProjectEntity({
    required this.id,
    required this.name,
    required this.sourceImagePath,
    required this.sourceImageHash,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.createdAt,
    required this.updatedAt,
    required this.recipe,
    this.sceneMapCacheKey,
    this.outputReferencePath,
    this.outputChecksum,
    this.isDirty = false,
    this.isCorrupted = false,
  });

  ProjectEntity copyWith({
    String? name,
    RenderRecipe? recipe,
    String? sceneMapCacheKey,
    String? outputReferencePath,
    String? outputChecksum,
    bool clearOutputReference = false,
    bool? isDirty,
    bool? isCorrupted,
    DateTime? updatedAt,
  }) {
    return ProjectEntity(
      id: id,
      name: name ?? this.name,
      sourceImagePath: sourceImagePath,
      sourceImageHash: sourceImageHash,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      recipe: recipe ?? this.recipe,
      sceneMapCacheKey: sceneMapCacheKey ?? this.sceneMapCacheKey,
      outputReferencePath: clearOutputReference
          ? null
          : (outputReferencePath ?? this.outputReferencePath),
      outputChecksum: clearOutputReference
          ? null
          : (outputChecksum ?? this.outputChecksum),
      isDirty: isDirty ?? this.isDirty,
      isCorrupted: isCorrupted ?? this.isCorrupted,
    );
  }
}

/// Lightweight summary for project lists and gallery cards.
class ProjectSummary {
  final String id;
  final String name;
  final String sourceImagePath;
  final String activeStudio;
  final String activePresetId;
  final DateTime updatedAt;
  final String? outputReferencePath;

  const ProjectSummary({
    required this.id,
    required this.name,
    required this.sourceImagePath,
    required this.activeStudio,
    required this.activePresetId,
    required this.updatedAt,
    this.outputReferencePath,
  });
}
