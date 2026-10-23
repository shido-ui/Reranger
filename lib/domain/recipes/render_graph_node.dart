import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'render_pipeline_failure.dart';
import 'style_render_nodes.dart';
import 'recolor_render_node.dart';
import 'adversarial_stealth_node.dart';
import 'pixelate_quantize_node.dart';
import 'artistic_render_nodes.dart';
import 'blend_composite_node.dart';

/// Abstract base class for all versioned nodes in the Render Graph.
/// Enforces:
/// - Deterministic cache key derivation factoring upstream inputs, versions, and parameters.
/// - Memory footprint estimation (Invariant 11).
/// - Parameter validation.
/// - Lossless JSON serialization.
abstract class RenderGraphNode {
  final String id;
  final String type;
  final int version;
  final List<String> inputNodeIds;
  final Map<String, dynamic> parameters;

  const RenderGraphNode({
    required this.id,
    required this.type,
    required this.version,
    required this.inputNodeIds,
    required this.parameters,
  }) : assert(id.length > 0, 'Node ID cannot be empty'),
       assert(version >= 1, 'Node version must be >= 1');

  /// Validates node parameters against domain boundaries.
  /// Throws [RenderInvalidParametersFailure] on violation.
  void validate();

  /// Estimates the working memory buffer size in bytes for this node given dimensions.
  int estimateMemoryBytes(int width, int height);

  /// Computes a deterministic SHA-256 cache key for this node.
  /// Changes to upstream keys, target dimensions, node version, parameters, or verified source hash
  /// will strictly yield a new cache key (Cache Miss).
  String computeNodeCacheKey(
    List<String> upstreamCacheKeys, {
    required int targetWidth,
    required int targetHeight,
    String? verifiedSourceHash,
  }) {
    final buffer = StringBuffer();
    buffer.write('type:$type|');
    buffer.write('v:$version|');
    buffer.write('dim:${targetWidth}x$targetHeight|');

    // Upstream dependencies
    buffer.write('up:[');
    for (final upKey in upstreamCacheKeys) {
      buffer.write('$upKey;');
    }
    buffer.write(']|');

    if (this is SourceImageNode && verifiedSourceHash != null) {
      buffer.write('verifiedHash:$verifiedSourceHash|');
    }

    // Canonical sorted parameters
    final sortedParamKeys = parameters.keys.toList()..sort();
    buffer.write('params:[');
    for (final k in sortedParamKeys) {
      final v = parameters[k];
      if (v is double) {
        buffer.write('$k:${v.toStringAsFixed(4)};');
      } else {
        buffer.write('$k:$v;');
      }
    }
    buffer.write(']');

    final bytes = utf8.encode(buffer.toString());
    return crypto.sha256.convert(bytes).toString();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'version': version,
    'inputNodeIds': inputNodeIds,
    'parameters': parameters,
  };

  static RenderGraphNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case SourceImageNode.nodeType:
        return SourceImageNode.fromJson(json);
      case GrayscaleNode.nodeType:
        return GrayscaleNode.fromJson(json);
      case SobelEdgeNode.nodeType:
        return SobelEdgeNode.fromJson(json);
      case EdgeInvertSubtractNode.nodeType:
        return EdgeInvertSubtractNode.fromJson(json);
      case GrainOverlayNode.nodeType:
        return GrainOverlayNode.fromJson(json);
      case DuoToneNode.nodeType:
        return DuoToneNode.fromJson(json);
      case RecolorNode.nodeType:
        return RecolorNode.fromJson(json);
      case AdversarialStealthNode.nodeType:
        return AdversarialStealthNode.fromJson(json);
      case PixelateQuantizeNode.nodeType:
        return PixelateQuantizeNode.fromJson(json);
      case HalftoneNode.nodeType:
        return HalftoneNode.fromJson(json);
      case CrosshatchNode.nodeType:
        return CrosshatchNode.fromJson(json);
      case StippleNode.nodeType:
        return StippleNode.fromJson(json);
      case CelShadeColorNode.nodeType:
        return CelShadeColorNode.fromJson(json);
      case WatercolorWashNode.nodeType:
        return WatercolorWashNode.fromJson(json);
      case PolygonalFacetNode.nodeType:
        return PolygonalFacetNode.fromJson(json);
      case BlendCompositeNode.nodeType:
        return BlendCompositeNode.fromJson(json);
      default:
        throw RenderInvalidParametersFailure(
          nodeId: json['id'] as String? ?? 'unknown',
          parameterName: 'type',
          actualValue: type,
          expectedCriteria: 'Registered RenderGraphNode type',
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderGraphNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          version == other.version &&
          _listEquals(inputNodeIds, other.inputNodeIds) &&
          _mapEquals(parameters, other.parameters);

  @override
  int get hashCode => Object.hash(id, type, version);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// CONCRETE VALIDATED NODES (Batch A)
// ---------------------------------------------------------------------------

/// Root node providing the immutable source image stream.
class SourceImageNode extends RenderGraphNode {
  static const String nodeType = 'SourceImageNode';

  final String sourceImageHash;
  final int sourceWidth;
  final int sourceHeight;

  SourceImageNode({
    required super.id,
    super.version = 1,
    required this.sourceImageHash,
    required this.sourceWidth,
    required this.sourceHeight,
  }) : super(
         type: nodeType,
         inputNodeIds: const [],
         parameters: {
           'sourceImageHash': sourceImageHash,
           'sourceWidth': sourceWidth,
           'sourceHeight': sourceHeight,
         },
       );

  @override
  void validate() {
    if (sourceImageHash.length != 64) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'sourceImageHash',
        actualValue: sourceImageHash,
        expectedCriteria: '64-character SHA-256 hexadecimal string',
      );
    }
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'dimensions',
        actualValue: '${sourceWidth}x$sourceHeight',
        expectedCriteria: 'Positive non-zero width and height',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4; // RGBA 32-bit

  factory SourceImageNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>;
    return SourceImageNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      sourceImageHash: params['sourceImageHash'] as String,
      sourceWidth: params['sourceWidth'] as int,
      sourceHeight: params['sourceHeight'] as int,
    );
  }
}

/// Node converting RGB pixels to ITU-R BT.601 integer luminance while preserving alpha.
/// OP-02 from Classical Engine PoC: Y = (299*R + 587*G + 114*B) / 1000.
class GrayscaleNode extends RenderGraphNode {
  static const String nodeType = 'GrayscaleNode';

  final bool preserveAlpha;

  GrayscaleNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.preserveAlpha = true,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {'preserveAlpha': preserveAlpha},
       );

  @override
  void validate() {
    if (inputNodeIds.length != 1) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 1 upstream input node',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4; // RGBA output

  factory GrayscaleNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>;
    return GrayscaleNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      preserveAlpha: params['preserveAlpha'] as bool? ?? true,
    );
  }
}

/// Node computing 3x3 Sobel gradient edge convolution.
/// OP-03 from Classical Engine PoC.
class SobelEdgeNode extends RenderGraphNode {
  static const String nodeType = 'SobelEdgeNode';

  final int edgeThreshold;
  final bool invertOutput;

  SobelEdgeNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.edgeThreshold = 50,
    this.invertOutput = false,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'edgeThreshold': edgeThreshold,
           'invertOutput': invertOutput,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 1) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 1 upstream input node',
      );
    }
    if (edgeThreshold < 0 || edgeThreshold > 255) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'edgeThreshold',
        actualValue: edgeThreshold,
        expectedCriteria: 'Integer in range [0, 255]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4; // RGBA edge map

  factory SobelEdgeNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>;
    return SobelEdgeNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      edgeThreshold: params['edgeThreshold'] as int? ?? 50,
      invertOutput: params['invertOutput'] as bool? ?? false,
    );
  }
}
