import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Academic Adversarial Robustness Research node:
/// Injects targeted Fast Gradient Sign Method (FGSM) and frequency-domain perturbations
/// into the rendered pixel buffer to alter CNN-based AI detector confidence scores
/// while preserving visual quality (PSNR > 35 dB).
class AdversarialStealthNode extends RenderGraphNode {
  static const String nodeType = 'AdversarialStealthNode';

  final double strength; // Epsilon scale in [0.0, 1.0]
  final bool applyFrequencyPerturbation;

  AdversarialStealthNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.strength = 0.5,
    this.applyFrequencyPerturbation = true,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'strength': strength,
           'applyFrequencyPerturbation': applyFrequencyPerturbation,
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
    if (strength < 0.0 || strength > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'strength',
        actualValue: strength,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory AdversarialStealthNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return AdversarialStealthNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: (json['inputNodeIds'] as List<dynamic>).first as String,
      strength: (params['strength'] as num?)?.toDouble() ?? 0.5,
      applyFrequencyPerturbation:
          params['applyFrequencyPerturbation'] as bool? ?? true,
    );
  }
}
