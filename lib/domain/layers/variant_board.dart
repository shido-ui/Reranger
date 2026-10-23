import 'editor_layer.dart';

/// Single creative variant / snapshot branch within a project.
class ProjectVariant {
  final String id;
  final String name;
  final LayerStack layerStack;
  final int? randomSeed;
  final bool isStochastic;
  final String? stochasticWarning;
  final DateTime createdAt;

  const ProjectVariant({
    required this.id,
    required this.name,
    required this.layerStack,
    this.randomSeed,
    this.isStochastic = false,
    this.stochasticWarning,
    required this.createdAt,
  }) : assert(id.length > 0, 'Variant ID cannot be empty'),
       assert(name.length > 0, 'Variant name cannot be empty');

  ProjectVariant copyWith({
    String? name,
    LayerStack? layerStack,
    int? randomSeed,
    bool? isStochastic,
    String? stochasticWarning,
    DateTime? createdAt,
  }) {
    return ProjectVariant(
      id: id,
      name: name ?? this.name,
      layerStack: layerStack ?? this.layerStack,
      randomSeed: randomSeed ?? this.randomSeed,
      isStochastic: isStochastic ?? this.isStochastic,
      stochasticWarning: stochasticWarning ?? this.stochasticWarning,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'layerStack': layerStack.toJson(),
    if (randomSeed != null) 'randomSeed': randomSeed,
    'isStochastic': isStochastic,
    if (stochasticWarning != null) 'stochasticWarning': stochasticWarning,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ProjectVariant.fromJson(Map<String, dynamic> json) => ProjectVariant(
    id: json['id'] as String,
    name: json['name'] as String,
    layerStack: LayerStack.fromJson(json['layerStack'] as Map<String, dynamic>),
    randomSeed: json['randomSeed'] as int?,
    isStochastic: json['isStochastic'] as bool? ?? false,
    stochasticWarning: json['stochasticWarning'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

/// Variant board managing multi-version exploration and branch switching.
class VariantBoard {
  final List<ProjectVariant> variants;
  final String activeVariantId;

  VariantBoard({
    required List<ProjectVariant> variants,
    required this.activeVariantId,
  }) : variants = List.unmodifiable(variants),
       assert(
         variants.isNotEmpty,
         'VariantBoard must contain at least 1 variant',
       ),
       assert(
         variants.any((v) => v.id == activeVariantId),
         'Active variant ID "$activeVariantId" not found in variants list',
       );

  ProjectVariant get activeVariant =>
      variants.firstWhere((v) => v.id == activeVariantId);

  /// Creates a new variant branch.
  VariantBoard createVariant({
    required String id,
    required String name,
    required LayerStack layerStack,
    int? randomSeed,
    bool isStochastic = false,
    String? stochasticWarning,
    bool makeActive = true,
  }) {
    if (variants.any((v) => v.id == id)) {
      throw ArgumentError('Variant ID "$id" already exists');
    }
    final variant = ProjectVariant(
      id: id,
      name: name,
      layerStack: layerStack,
      randomSeed: randomSeed,
      isStochastic: isStochastic,
      stochasticWarning: isStochastic
          ? (stochasticWarning ??
                'Stochastic AI model: minor variations across device neural runtimes may occur.')
          : null,
      createdAt: DateTime.now().toUtc(),
    );

    final updated = [...variants, variant];
    return VariantBoard(
      variants: updated,
      activeVariantId: makeActive ? id : activeVariantId,
    );
  }

  /// Duplicates the active variant into a new branch.
  VariantBoard duplicateActive({
    required String newId,
    required String newName,
  }) {
    return createVariant(
      id: newId,
      name: newName,
      layerStack: activeVariant.layerStack,
      randomSeed: activeVariant.randomSeed,
      isStochastic: activeVariant.isStochastic,
      stochasticWarning: activeVariant.stochasticWarning,
      makeActive: true,
    );
  }

  /// Switches active variant without re-decoding source media.
  VariantBoard switchVariant(String variantId) {
    if (!variants.any((v) => v.id == variantId)) {
      throw ArgumentError('Variant ID "$variantId" not found');
    }
    return VariantBoard(variants: variants, activeVariantId: variantId);
  }

  /// Updates the active variant's layer stack.
  VariantBoard updateActiveStack(LayerStack newStack) {
    final updatedList = variants.map((v) {
      if (v.id == activeVariantId) {
        return v.copyWith(layerStack: newStack);
      }
      return v;
    }).toList();

    return VariantBoard(
      variants: updatedList,
      activeVariantId: activeVariantId,
    );
  }

  /// Renames an existing variant.
  VariantBoard renameVariant(String variantId, String newName) {
    if (newName.trim().isEmpty) {
      throw ArgumentError('Variant name cannot be empty');
    }
    if (!variants.any((v) => v.id == variantId)) {
      throw ArgumentError('Variant "$variantId" not found');
    }
    final updatedList = variants.map((v) {
      if (v.id == variantId) {
        return v.copyWith(name: newName.trim());
      }
      return v;
    }).toList();
    return VariantBoard(
      variants: updatedList,
      activeVariantId: activeVariantId,
    );
  }

  /// Deletes a variant. Requires at least 1 remaining variant.
  VariantBoard deleteVariant(String variantId) {
    if (variants.length <= 1) {
      throw StateError('Cannot delete the last remaining variant');
    }
    final filtered = variants.where((v) => v.id != variantId).toList();
    final newActiveId = (activeVariantId == variantId)
        ? filtered.first.id
        : activeVariantId;

    return VariantBoard(variants: filtered, activeVariantId: newActiveId);
  }

  Map<String, dynamic> toJson() => {
    'activeVariantId': activeVariantId,
    'variants': variants.map((v) => v.toJson()).toList(),
  };

  factory VariantBoard.fromJson(Map<String, dynamic> json) {
    final activeId = json['activeVariantId'] as String;
    final list = (json['variants'] as List)
        .map((e) => ProjectVariant.fromJson(e as Map<String, dynamic>))
        .toList();
    return VariantBoard(variants: list, activeVariantId: activeId);
  }
}
