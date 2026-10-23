import '../recipes/recolor_render_node.dart';
import '../recipes/render_graph.dart';
import '../recipes/render_graph_node.dart';
import '../recipes/style_render_nodes.dart';

/// Supported, mathematically verified blend modes for non-destructive layer compositing.
enum BlendModeType {
  normal,
  multiply,
  screen,
  overlay,
  softLight;

  static BlendModeType fromString(String val) {
    return BlendModeType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => BlendModeType.normal,
    );
  }

  /// Evaluates the discrete integer blend function for a single color channel.
  /// Inputs [base] and [top] in [0, 255]; output clamped to [0, 255].
  int apply(int base, int top) {
    switch (this) {
      case BlendModeType.normal:
        return top;
      case BlendModeType.multiply:
        // (A * B) / 255
        return (base * top) ~/ 255;
      case BlendModeType.screen:
        // 255 - ((255 - A) * (255 - B)) / 255
        return 255 - (((255 - base) * (255 - top)) ~/ 255);
      case BlendModeType.overlay:
        // base < 128 ? (2 * base * top) / 255 : 255 - (2 * (255 - base) * (255 - top)) / 255
        if (base < 128) {
          return (2 * base * top) ~/ 255;
        } else {
          return 255 - (2 * (255 - base) * (255 - top)) ~/ 255;
        }
      case BlendModeType.softLight:
        // Pegtop formula: (1 - 2*b)*a^2 + 2*b*a where a, b in [0, 1]
        final a = base / 255.0;
        final b = top / 255.0;
        final result = (1.0 - 2.0 * b) * a * a + 2.0 * b * a;
        return (result * 255.0).round().clamp(0, 255);
    }
  }
}

/// Abstract base class for all non-destructive layers in an editing session.
abstract class EditorLayer {
  final String id;
  final String name;
  final double opacity;
  final bool isVisible;

  const EditorLayer({
    required this.id,
    required this.name,
    this.opacity = 1.0,
    this.isVisible = true,
  }) : assert(id.length > 0, 'Layer ID cannot be empty'),
       assert(
         opacity >= 0.0 && opacity <= 1.0,
         'Opacity must be in [0.0, 1.0]',
       );

  bool get isImmutableSource => false;

  EditorLayer copyWith({String? name, double? opacity, bool? isVisible});

  Map<String, dynamic> toJson();

  static EditorLayer fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'source':
        return SourceLayer.fromJson(json);
      case 'adjustment':
        return AdjustmentLayer.fromJson(json);
      case 'mask':
        return MaskLayer.fromJson(json);
      default:
        throw FormatException('Unrecognized layer type: "$type"');
    }
  }
}

/// Root, immutable base layer representing the user's original image media.
/// Source Image Immutability (Invariant 4) enforced: cannot be modified or reordered away from root.
class SourceLayer extends EditorLayer {
  final String sourceHash;
  final int sourceWidth;
  final int sourceHeight;

  const SourceLayer({
    required super.id,
    super.name = 'Original Source',
    required this.sourceHash,
    required this.sourceWidth,
    required this.sourceHeight,
  }) : super(opacity: 1.0, isVisible: true);

  @override
  bool get isImmutableSource => true;

  @override
  SourceLayer copyWith({String? name, double? opacity, bool? isVisible}) {
    // Opacity and visibility are immutable on root source layer
    return SourceLayer(
      id: id,
      name: name ?? this.name,
      sourceHash: sourceHash,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'source',
    'id': id,
    'name': name,
    'sourceHash': sourceHash,
    'sourceWidth': sourceWidth,
    'sourceHeight': sourceHeight,
  };

  factory SourceLayer.fromJson(Map<String, dynamic> json) => SourceLayer(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Original Source',
    sourceHash: json['sourceHash'] as String,
    sourceWidth: json['sourceWidth'] as int,
    sourceHeight: json['sourceHeight'] as int,
  );
}

/// Non-destructive effect or adjustment layer applying a parametric transformation.
class AdjustmentLayer extends EditorLayer {
  final String effectType; // e.g. 'recolor', 'preset', 'duotone', 'grain'
  final Map<String, dynamic> parameters;
  final BlendModeType blendMode;
  final String? maskId;
  final int? seed;

  const AdjustmentLayer({
    required super.id,
    required super.name,
    super.opacity = 1.0,
    super.isVisible = true,
    required this.effectType,
    required this.parameters,
    this.blendMode = BlendModeType.normal,
    this.maskId,
    this.seed,
  });

  @override
  AdjustmentLayer copyWith({
    String? name,
    double? opacity,
    bool? isVisible,
    String? effectType,
    Map<String, dynamic>? parameters,
    BlendModeType? blendMode,
    String? maskId,
    int? seed,
  }) {
    return AdjustmentLayer(
      id: id,
      name: name ?? this.name,
      opacity: opacity ?? this.opacity,
      isVisible: isVisible ?? this.isVisible,
      effectType: effectType ?? this.effectType,
      parameters: parameters ?? this.parameters,
      blendMode: blendMode ?? this.blendMode,
      maskId: maskId ?? this.maskId,
      seed: seed ?? this.seed,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'adjustment',
    'id': id,
    'name': name,
    'opacity': opacity,
    'isVisible': isVisible,
    'effectType': effectType,
    'parameters': parameters,
    'blendMode': blendMode.name,
    if (maskId != null) 'maskId': maskId,
    if (seed != null) 'seed': seed,
  };

  factory AdjustmentLayer.fromJson(Map<String, dynamic> json) =>
      AdjustmentLayer(
        id: json['id'] as String,
        name: json['name'] as String,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
        isVisible: json['isVisible'] as bool? ?? true,
        effectType: json['effectType'] as String,
        parameters: Map<String, dynamic>.from(json['parameters'] as Map),
        blendMode: BlendModeType.fromString(
          json['blendMode'] as String? ?? 'normal',
        ),
        maskId: json['maskId'] as String?,
        seed: json['seed'] as int?,
      );
}

/// Standalone mask layer holding spatial mask data.
class MaskLayer extends EditorLayer {
  final String? maskBase64;

  const MaskLayer({
    required super.id,
    required super.name,
    super.opacity = 1.0,
    super.isVisible = true,
    this.maskBase64,
  });

  @override
  MaskLayer copyWith({
    String? name,
    double? opacity,
    bool? isVisible,
    String? maskBase64,
  }) {
    return MaskLayer(
      id: id,
      name: name ?? this.name,
      opacity: opacity ?? this.opacity,
      isVisible: isVisible ?? this.isVisible,
      maskBase64: maskBase64 ?? this.maskBase64,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'mask',
    'id': id,
    'name': name,
    'opacity': opacity,
    'isVisible': isVisible,
    if (maskBase64 != null) 'maskBase64': maskBase64,
  };

  factory MaskLayer.fromJson(Map<String, dynamic> json) => MaskLayer(
    id: json['id'] as String,
    name: json['name'] as String,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    isVisible: json['isVisible'] as bool? ?? true,
    maskBase64: json['maskBase64'] as String?,
  );
}

/// Ordered collection of non-destructive layers evaluated bottom-to-top.
class LayerStack {
  final List<EditorLayer> layers;

  LayerStack(List<EditorLayer> layers)
    : layers = List.unmodifiable(layers),
      assert(layers.isNotEmpty, 'LayerStack must contain at least 1 layer'),
      assert(
        layers[0] is SourceLayer,
        'Root layer (index 0) must strictly be a SourceLayer (Invariant 4)',
      );

  SourceLayer get sourceLayer => layers[0] as SourceLayer;

  /// Moves layer at [oldIndex] to [newIndex].
  /// Root source layer (index 0) is permanently locked and cannot be moved.
  LayerStack reorder(int oldIndex, int newIndex) {
    if (oldIndex == 0 || newIndex == 0) {
      throw ArgumentError(
        'Cannot reorder the immutable root SourceLayer (index 0)',
      );
    }
    if (oldIndex < 0 ||
        oldIndex >= layers.length ||
        newIndex < 0 ||
        newIndex >= layers.length) {
      throw RangeError(
        'Layer index out of bounds: old=$oldIndex, new=$newIndex',
      );
    }

    final copy = List<EditorLayer>.from(layers);
    final moved = copy.removeAt(oldIndex);
    copy.insert(newIndex, moved);
    return LayerStack(copy);
  }

  /// Appends a new layer to the top of the stack.
  LayerStack addLayer(EditorLayer layer) {
    if (layers.any((l) => l.id == layer.id)) {
      throw ArgumentError('Duplicate layer ID: "${layer.id}"');
    }
    return LayerStack([...layers, layer]);
  }

  /// Removes a layer by ID. Root SourceLayer cannot be removed.
  LayerStack removeLayer(String layerId) {
    if (layers[0].id == layerId) {
      throw ArgumentError('Cannot remove root SourceLayer (Invariant 4)');
    }
    final filtered = layers.where((l) => l.id != layerId).toList();
    return LayerStack(filtered);
  }

  /// Updates an existing layer by matching ID.
  LayerStack updateLayer(EditorLayer updated) {
    final index = layers.indexWhere((l) => l.id == updated.id);
    if (index == -1) {
      throw ArgumentError('Layer "${updated.id}" not found in stack');
    }
    if (index == 0 && updated is! SourceLayer) {
      throw ArgumentError('Root layer must remain a SourceLayer');
    }
    final copy = List<EditorLayer>.from(layers);
    copy[index] = updated;
    return LayerStack(copy);
  }

  /// Flattens the layer stack into a topologically validated [RenderGraph].
  /// If [baseGraph] is supplied, adjustment layers are chained on top of the active base graph.
  RenderGraph toRenderGraph({RenderGraph? baseGraph}) {
    final Map<String, RenderGraphNode> nodesMap;
    String currentOutputId;

    if (baseGraph != null) {
      nodesMap = Map<String, RenderGraphNode>.from(baseGraph.nodes);
      currentOutputId = baseGraph.outputNodeId;
    } else {
      final src = sourceLayer;
      final rootNode = SourceImageNode(
        id: src.id,
        sourceImageHash: src.sourceHash,
        sourceWidth: src.sourceWidth,
        sourceHeight: src.sourceHeight,
      );
      nodesMap = <String, RenderGraphNode>{rootNode.id: rootNode};
      currentOutputId = rootNode.id;
    }

    for (int i = 1; i < layers.length; i++) {
      final layer = layers[i];
      if (!layer.isVisible || layer.opacity <= 1e-4) {
        continue; // Bypasses hidden or 0-opacity layers cleanly
      }

      if (layer is AdjustmentLayer) {
        final nodeId = 'node_${layer.id}';
        RenderGraphNode node;

        if (layer.effectType == 'recolor') {
          node = RecolorNode(
            id: nodeId,
            inputNodeId: currentOutputId,
            sourceR: layer.parameters['sourceR'] as int? ?? 0,
            sourceG: layer.parameters['sourceG'] as int? ?? 0,
            sourceB: layer.parameters['sourceB'] as int? ?? 0,
            targetR: layer.parameters['targetR'] as int? ?? 0,
            targetG: layer.parameters['targetG'] as int? ?? 0,
            targetB: layer.parameters['targetB'] as int? ?? 0,
            tolerance:
                (layer.parameters['tolerance'] as num?)?.toDouble() ?? 0.20,
            feather: (layer.parameters['feather'] as num?)?.toDouble() ?? 0.10,
            preserveLuminance:
                layer.parameters['preserveLuminance'] as bool? ?? true,
            strength: layer.opacity,
            maskBase64: layer.parameters['maskBase64'] as String?,
          );
        } else if (layer.effectType == 'duotone') {
          node = DuoToneNode(
            id: nodeId,
            inputNodeId: currentOutputId,
            shadowR: layer.parameters['shadowR'] as int? ?? 20,
            shadowG: layer.parameters['shadowG'] as int? ?? 15,
            shadowB: layer.parameters['shadowB'] as int? ?? 45,
            highlightR: layer.parameters['highlightR'] as int? ?? 255,
            highlightG: layer.parameters['highlightG'] as int? ?? 220,
            highlightB: layer.parameters['highlightB'] as int? ?? 160,
            vignetteFalloff:
                (layer.parameters['vignetteFalloff'] as num?)?.toDouble() ??
                0.0,
          );
        } else if (layer.effectType == 'grain') {
          node = GrainOverlayNode(
            id: nodeId,
            inputNodeId: currentOutputId,
            intensity:
                (layer.parameters['intensity'] as num?)?.toDouble() ??
                (layer.opacity * 0.25),
            seed: layer.seed ?? 42,
          );
        } else {
          // Default Grayscale / neutral fallback
          node = GrayscaleNode(
            id: nodeId,
            inputNodeId: currentOutputId,
            preserveAlpha: true,
          );
        }

        nodesMap[node.id] = node;
        currentOutputId = node.id;
      }
    }

    return RenderGraph(
      id: 'graph_stack_${DateTime.now().millisecondsSinceEpoch}',
      nodes: nodesMap,
      outputNodeId: currentOutputId,
    );
  }

  Map<String, dynamic> toJson() => {
    'layers': layers.map((l) => l.toJson()).toList(),
  };

  factory LayerStack.fromJson(Map<String, dynamic> json) {
    final list = (json['layers'] as List)
        .map((e) => EditorLayer.fromJson(e as Map<String, dynamic>))
        .toList();
    return LayerStack(list);
  }
}
