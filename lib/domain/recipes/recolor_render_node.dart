import 'dart:convert';

import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Render Graph node that applies region-aware, luminance-conscious recoloring.
/// Strictly enforces:
/// - Exact preservation of unselected pixels (0 pixel diff)
/// - Alpha channel preservation (A_out == A_in)
/// - Lighting & shading preservation via perceptual luminance matching
/// - Deterministic caching via SHA-256 parameter hashing
class RecolorNode extends RenderGraphNode {
  static const String nodeType = 'recolor';

  final int sourceR;
  final int sourceG;
  final int sourceB;
  final int targetR;
  final int targetG;
  final int targetB;
  final double tolerance;
  final double feather;
  final bool preserveLuminance;
  final double strength;
  final String? maskBase64;

  RecolorNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    required this.sourceR,
    required this.sourceG,
    required this.sourceB,
    required this.targetR,
    required this.targetG,
    required this.targetB,
    this.tolerance = 0.20,
    this.feather = 0.10,
    this.preserveLuminance = true,
    this.strength = 1.0,
    this.maskBase64,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'sourceR': sourceR,
           'sourceG': sourceG,
           'sourceB': sourceB,
           'targetR': targetR,
           'targetG': targetG,
           'targetB': targetB,
           'tolerance': tolerance,
           'feather': feather,
           'preserveLuminance': preserveLuminance,
           'strength': strength,
           ...?maskBase64 != null ? {'maskBase64': maskBase64} : null,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 1) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 1 input node required',
      );
    }
    if (sourceR < 0 ||
        sourceR > 255 ||
        sourceG < 0 ||
        sourceG > 255 ||
        sourceB < 0 ||
        sourceB > 255) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'sourceRGB',
        actualValue: '[$sourceR, $sourceG, $sourceB]',
        expectedCriteria: 'Source RGB values must be in [0, 255]',
      );
    }
    if (targetR < 0 ||
        targetR > 255 ||
        targetG < 0 ||
        targetG > 255 ||
        targetB < 0 ||
        targetB > 255) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'targetRGB',
        actualValue: '[$targetR, $targetG, $targetB]',
        expectedCriteria: 'Target RGB values must be in [0, 255]',
      );
    }
    if (tolerance < 0.0 || tolerance > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'tolerance',
        actualValue: tolerance,
        expectedCriteria: 'Tolerance must be in [0.0, 1.0]',
      );
    }
    if (feather < 0.0 || feather > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'feather',
        actualValue: feather,
        expectedCriteria: 'Feather must be in [0.0, 1.0]',
      );
    }
    if (strength < 0.0 || strength > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'strength',
        actualValue: strength,
        expectedCriteria: 'Strength must be in [0.0, 1.0]',
      );
    }
    if (maskBase64 != null) {
      if (maskBase64!.isEmpty) {
        throw RenderInvalidParametersFailure(
          nodeId: id,
          parameterName: 'maskBase64',
          actualValue: maskBase64,
          expectedCriteria: 'Non-empty base64-encoded mask string',
        );
      }
      try {
        base64.decode(maskBase64!);
      } catch (_) {
        throw RenderInvalidParametersFailure(
          nodeId: id,
          parameterName: 'maskBase64',
          actualValue: 'corrupt_base64_data',
          expectedCriteria: 'Valid base64-encoded binary mask string',
        );
      }
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) {
    final rgba = width * height * 4;
    final mask = (maskBase64 != null) ? (width * height) : 0;
    return rgba + mask;
  }

  factory RecolorNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>;
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    return RecolorNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs[0],
      sourceR: params['sourceR'] as int,
      sourceG: params['sourceG'] as int,
      sourceB: params['sourceB'] as int,
      targetR: params['targetR'] as int,
      targetG: params['targetG'] as int,
      targetB: params['targetB'] as int,
      tolerance: (params['tolerance'] as num?)?.toDouble() ?? 0.20,
      feather: (params['feather'] as num?)?.toDouble() ?? 0.10,
      preserveLuminance: params['preserveLuminance'] as bool? ?? true,
      strength: (params['strength'] as num?)?.toDouble() ?? 1.0,
      maskBase64: params['maskBase64'] as String?,
    );
  }
}
