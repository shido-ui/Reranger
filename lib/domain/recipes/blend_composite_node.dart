import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Supported discrete blend modes for [BlendCompositeNode].
class BlendCompositeModes {
  static const String normal = 'normal';
  static const String multiply = 'multiply';
  static const String screen = 'screen';
  static const String overlay = 'overlay';
  static const String softLight = 'softLight';

  static const Set<String> supported = {
    normal,
    multiply,
    screen,
    overlay,
    softLight,
  };
}

/// DAG compute node executing deterministic multi-layer compositing.
/// Blends [topInputNodeId] over [baseInputNodeId] using discrete integer
/// channel transfer functions, optional opacity attenuation, and spatial masking.
class BlendCompositeNode extends RenderGraphNode {
  static const String nodeType = 'BlendCompositeNode';

  final String baseInputNodeId;
  final String topInputNodeId;
  final String blendMode;
  final double opacity;
  final String? maskBase64;

  BlendCompositeNode({
    required super.id,
    super.version = 1,
    required this.baseInputNodeId,
    required this.topInputNodeId,
    this.blendMode = BlendCompositeModes.normal,
    this.opacity = 1.0,
    this.maskBase64,
  }) : super(
         type: nodeType,
         inputNodeIds: [baseInputNodeId, topInputNodeId],
         parameters: {
           'blendMode': blendMode,
           'opacity': opacity,
           'maskBase64': ?maskBase64,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 2) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria:
            'Exactly 2 upstream input nodes (baseInput and topInput)',
      );
    }
    if (opacity < 0.0 || opacity > 1.0 || opacity.isNaN || opacity.isInfinite) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'opacity',
        actualValue: opacity,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
    if (!BlendCompositeModes.supported.contains(blendMode)) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'blendMode',
        actualValue: blendMode,
        expectedCriteria:
            'One of supported blend modes: ${BlendCompositeModes.supported.join(", ")}',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4 * 2;

  factory BlendCompositeNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>;
    return BlendCompositeNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      baseInputNodeId: inputs[0],
      topInputNodeId: inputs[1],
      blendMode: params['blendMode'] as String? ?? BlendCompositeModes.normal,
      opacity: (params['opacity'] as num?)?.toDouble() ?? 1.0,
      maskBase64: params['maskBase64'] as String?,
    );
  }
}
