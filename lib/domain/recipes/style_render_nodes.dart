import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Node performing inverted edge subtraction and contrast curve adjustments.
/// Implements Recipe 1 (Dramatic Monochrome Ink) from Classical Engine PoC:
/// G_ink = clamp(G_gray - edgeIntensity * G_edge, 0, 255) with gamma contrast curve.
class EdgeInvertSubtractNode extends RenderGraphNode {
  static const String nodeType = 'EdgeInvertSubtractNode';

  final double edgeIntensity;
  final double contrastGamma;

  EdgeInvertSubtractNode({
    required super.id,
    super.version = 1,
    required String grayInputNodeId,
    required String edgeInputNodeId,
    this.edgeIntensity = 0.85,
    this.contrastGamma = 1.5,
  }) : super(
         type: nodeType,
         inputNodeIds: [grayInputNodeId, edgeInputNodeId],
         parameters: {
           'edgeIntensity': edgeIntensity,
           'contrastGamma': contrastGamma,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 2) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 2 upstream input nodes (gray and edge)',
      );
    }
    if (edgeIntensity < 0.0 || edgeIntensity > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'edgeIntensity',
        actualValue: edgeIntensity,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
    if (contrastGamma <= 0.0 || contrastGamma > 5.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'contrastGamma',
        actualValue: contrastGamma,
        expectedCriteria: 'Positive floating point value in (0.0, 5.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory EdgeInvertSubtractNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>;
    return EdgeInvertSubtractNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      grayInputNodeId: inputs[0],
      edgeInputNodeId: inputs[1],
      edgeIntensity: (params['edgeIntensity'] as num?)?.toDouble() ?? 0.85,
      contrastGamma: (params['contrastGamma'] as num?)?.toDouble() ?? 1.5,
    );
  }
}

/// Node applying procedural film/paper grain noise overlay.
/// Implements OP-07 from Classical Engine PoC using 32-bit Linear Congruential PRNG:
/// S_{n+1} = (S_n * 1664525 + 1013904223) mod 2^32.
class GrainOverlayNode extends RenderGraphNode {
  static const String nodeType = 'GrainOverlayNode';

  final double intensity;
  final int seed;

  GrainOverlayNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.intensity = 0.12,
    this.seed = 1337,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {'intensity': intensity, 'seed': seed},
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
    if (intensity < 0.0 || intensity > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'intensity',
        actualValue: intensity,
        expectedCriteria: 'Floating point value in [0.0, 1.0]',
      );
    }
    if (seed < 0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'seed',
        actualValue: seed,
        expectedCriteria: 'Non-negative integer seed',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory GrainOverlayNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>;
    return GrainOverlayNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      intensity: (params['intensity'] as num?)?.toDouble() ?? 0.12,
      seed: params['seed'] as int? ?? 1337,
    );
  }
}

/// Node applying editorial duo-tone color remapping with radial vignette falloff.
/// Implements Recipe 3 (Warm DuoTone) from Classical Engine PoC:
/// Maps BT.601 luminance between shadow color (e.g. Deep Indigo) and highlight color (e.g. Warm Amber)
/// modulated by a quadratic radial vignette.
class DuoToneNode extends RenderGraphNode {
  static const String nodeType = 'DuoToneNode';

  final int shadowR;
  final int shadowG;
  final int shadowB;
  final int highlightR;
  final int highlightG;
  final int highlightB;
  final double vignetteFalloff;

  DuoToneNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.shadowR = 24,
    this.shadowG = 28,
    this.shadowB = 64,
    this.highlightR = 255,
    this.highlightG = 210,
    this.highlightB = 140,
    this.vignetteFalloff = 0.35,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'shadowR': shadowR,
           'shadowG': shadowG,
           'shadowB': shadowB,
           'highlightR': highlightR,
           'highlightG': highlightG,
           'highlightB': highlightB,
           'vignetteFalloff': vignetteFalloff,
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
    for (final (name, val) in [
      ('shadowR', shadowR),
      ('shadowG', shadowG),
      ('shadowB', shadowB),
      ('highlightR', highlightR),
      ('highlightG', highlightG),
      ('highlightB', highlightB),
    ]) {
      if (val < 0 || val > 255) {
        throw RenderInvalidParametersFailure(
          nodeId: id,
          parameterName: name,
          actualValue: val,
          expectedCriteria: 'Color channel in range [0, 255]',
        );
      }
    }
    if (vignetteFalloff < 0.0 || vignetteFalloff > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'vignetteFalloff',
        actualValue: vignetteFalloff,
        expectedCriteria: 'Falloff in range [0.0, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory DuoToneNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>;
    return DuoToneNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      shadowR: params['shadowR'] as int? ?? 24,
      shadowG: params['shadowG'] as int? ?? 28,
      shadowB: params['shadowB'] as int? ?? 64,
      highlightR: params['highlightR'] as int? ?? 255,
      highlightG: params['highlightG'] as int? ?? 210,
      highlightB: params['highlightB'] as int? ?? 140,
      vignetteFalloff: (params['vignetteFalloff'] as num?)?.toDouble() ?? 0.35,
    );
  }
}
