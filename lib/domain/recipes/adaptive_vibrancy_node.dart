import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Render graph node that converts an image to CIELAB color space,
/// applies adaptive histogram equalization on the L* channel for natural contrast,
/// and applies a saliency-weighted chroma boost on a* and b* with strict hue preservation.
class AdaptiveVibrancyNode extends RenderGraphNode {
  static const String nodeType = 'adaptive_vibrancy';
  static const int currentVersion = 1;

  final String inputNodeId;
  final double vibrancy;
  final double contrast;
  final bool preserveAlpha;
  final String?
  splitTone; // 'cinematic', 'ethereal', 'vintage', 'cyberpunk', 'pastel'
  final double splitToneStrength;

  AdaptiveVibrancyNode({
    required super.id,
    required this.inputNodeId,
    this.vibrancy = 0.35,
    this.contrast = 0.20,
    this.preserveAlpha = true,
    this.splitTone,
    this.splitToneStrength = 1.0,
  }) : super(
         type: nodeType,
         version: currentVersion,
         inputNodeIds: [inputNodeId],
         parameters: {
           'vibrancy': vibrancy,
           'contrast': contrast,
           'preserveAlpha': preserveAlpha,
           'splitTone': ?splitTone,
           'splitToneStrength': splitToneStrength,
         },
       );

  factory AdaptiveVibrancyNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    final inputs = json['inputNodeIds'] as List<dynamic>? ?? [];

    return AdaptiveVibrancyNode(
      id: json['id'] as String,
      inputNodeId: inputs.isNotEmpty ? inputs[0] as String : 'src_0',
      vibrancy: (params['vibrancy'] as num?)?.toDouble() ?? 0.35,
      contrast: (params['contrast'] as num?)?.toDouble() ?? 0.20,
      preserveAlpha: params['preserveAlpha'] as bool? ?? true,
      splitTone: params['splitTone'] as String?,
      splitToneStrength:
          (params['splitToneStrength'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  void validate() {
    if (vibrancy < 0.0 || vibrancy > 2.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'vibrancy',
        actualValue: vibrancy,
        expectedCriteria: '0.0 <= vibrancy <= 2.0',
      );
    }
    if (contrast < 0.0 || contrast > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'contrast',
        actualValue: contrast,
        expectedCriteria: '0.0 <= contrast <= 1.0',
      );
    }
    if (splitTone != null) {
      const validModes = {
        'cinematic',
        'ethereal',
        'vintage',
        'cyberpunk',
        'pastel',
      };
      if (!validModes.contains(splitTone)) {
        throw RenderInvalidParametersFailure(
          nodeId: id,
          parameterName: 'splitTone',
          actualValue: splitTone,
          expectedCriteria: 'Must be one of $validModes',
        );
      }
    }
    if (splitToneStrength < 0.0 || splitToneStrength > 2.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'splitToneStrength',
        actualValue: splitToneStrength,
        expectedCriteria: '0.0 <= splitToneStrength <= 2.0',
      );
    }
    if (inputNodeIds.isEmpty) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds,
        expectedCriteria: 'Must have at least one input node ID',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) {
    // 4 bytes per pixel RGBA buffer
    return width * height * 4;
  }
}
