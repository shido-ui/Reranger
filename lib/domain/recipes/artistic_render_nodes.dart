import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Node applying genuine screen-dot halftone rasterization modulated by tonal luminance.
class HalftoneNode extends RenderGraphNode {
  static const String nodeType = 'HalftoneNode';

  final int dotPitch; // Spacing between screen dots in pixels [2, 32]
  final double angleDegrees; // Halftone screen angle in degrees [0.0, 90.0]
  final double dotIntensity; // Halftone ink intensity [0.0, 1.0]
  final bool
  preserveColor; // Whether to retain source hue/chroma or render monochrome

  HalftoneNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.dotPitch = 6,
    this.angleDegrees = 45.0,
    this.dotIntensity = 0.8,
    this.preserveColor = true,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'dotPitch': dotPitch,
           'angleDegrees': angleDegrees,
           'dotIntensity': dotIntensity,
           'preserveColor': preserveColor,
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
    if (dotPitch < 2 || dotPitch > 32) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'dotPitch',
        actualValue: dotPitch,
        expectedCriteria: 'Integer screen dot pitch in [2, 32]',
      );
    }
    if (angleDegrees < 0.0 || angleDegrees > 90.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'angleDegrees',
        actualValue: angleDegrees,
        expectedCriteria: 'Screen angle in degrees [0.0, 90.0]',
      );
    }
    if (dotIntensity < 0.0 || dotIntensity > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'dotIntensity',
        actualValue: dotIntensity,
        expectedCriteria: 'Dot intensity in [0.0, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory HalftoneNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return HalftoneNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      dotPitch: (params['dotPitch'] as num?)?.toInt() ?? 6,
      angleDegrees: (params['angleDegrees'] as num?)?.toDouble() ?? 45.0,
      dotIntensity: (params['dotIntensity'] as num?)?.toDouble() ?? 0.8,
      preserveColor: params['preserveColor'] as bool? ?? true,
    );
  }
}

/// Node applying directional tone-responsive crosshatching.
/// Activates multi-directional stroke layers (45°, 135°, horizontal, vertical) based on luminance tiers.
class CrosshatchNode extends RenderGraphNode {
  static const String nodeType = 'CrosshatchNode';

  final int spacing; // Spacing between hatch lines in pixels [3, 24]
  final int lineWeight; // Stroke width in pixels [1, 4]
  final double hatchDensity; // Pen ink opacity [0.1, 1.0]
  final bool
  preserveColor; // Whether to retain source color underneath hatching

  CrosshatchNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.spacing = 6,
    this.lineWeight = 1,
    this.hatchDensity = 0.85,
    this.preserveColor = false,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'spacing': spacing,
           'lineWeight': lineWeight,
           'hatchDensity': hatchDensity,
           'preserveColor': preserveColor,
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
    if (spacing < 3 || spacing > 24) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'spacing',
        actualValue: spacing,
        expectedCriteria: 'Integer line spacing in [3, 24]',
      );
    }
    if (lineWeight < 1 || lineWeight > 4) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'lineWeight',
        actualValue: lineWeight,
        expectedCriteria: 'Integer line weight in [1, 4]',
      );
    }
    if (hatchDensity < 0.1 || hatchDensity > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'hatchDensity',
        actualValue: hatchDensity,
        expectedCriteria: 'Hatch density in [0.1, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory CrosshatchNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return CrosshatchNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      spacing: (params['spacing'] as num?)?.toInt() ?? 6,
      lineWeight: (params['lineWeight'] as num?)?.toInt() ?? 1,
      hatchDensity: (params['hatchDensity'] as num?)?.toDouble() ?? 0.85,
      preserveColor: params['preserveColor'] as bool? ?? false,
    );
  }
}

/// Node applying pointillist tone-responsive dot stippling via deterministic pseudo-random error distribution.
class StippleNode extends RenderGraphNode {
  static const String nodeType = 'StippleNode';

  final double
  dotDensity; // Density factor modulating dot probability [0.05, 1.0]
  final bool preserveColor; // Whether to retain underlying source chroma
  final int seed; // Deterministic PRNG seed

  StippleNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.dotDensity = 0.35,
    this.preserveColor = false,
    this.seed = 1337,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'dotDensity': dotDensity,
           'preserveColor': preserveColor,
           'seed': seed,
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
    if (dotDensity < 0.05 || dotDensity > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'dotDensity',
        actualValue: dotDensity,
        expectedCriteria: 'Dot density factor in [0.05, 1.0]',
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

  factory StippleNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return StippleNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      dotDensity: (params['dotDensity'] as num?)?.toDouble() ?? 0.35,
      preserveColor: params['preserveColor'] as bool? ?? false,
      seed: params['seed'] as int? ?? 1337,
    );
  }
}

/// Node applying genuine cel-shading quantization over full RGB color space.
/// Discretizes tonal luminance while preserving source chroma and overlaying contour ink.
class CelShadeColorNode extends RenderGraphNode {
  static const String nodeType = 'CelShadeColorNode';

  final int shadeLevels; // Discrete stepped tonal levels [2, 16]
  final double inkStrength; // Edge contour ink overlay intensity [0.0, 1.0]
  final double
  contrastGamma; // Contrast gamma applied to tonal steps [0.5, 3.0]

  CelShadeColorNode({
    required super.id,
    super.version = 1,
    required String colorInputNodeId,
    String? edgeInputNodeId,
    this.shadeLevels = 4,
    this.inkStrength = 0.75,
    this.contrastGamma = 1.2,
  }) : super(
         type: nodeType,
         inputNodeIds: [colorInputNodeId, ?edgeInputNodeId],
         parameters: {
           'shadeLevels': shadeLevels,
           'inkStrength': inkStrength,
           'contrastGamma': contrastGamma,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.isEmpty || inputNodeIds.length > 2) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria:
            '1 or 2 upstream input nodes (color and optional edge)',
      );
    }
    if (shadeLevels < 2 || shadeLevels > 16) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'shadeLevels',
        actualValue: shadeLevels,
        expectedCriteria: 'Integer shade levels in [2, 16]',
      );
    }
    if (inkStrength < 0.0 || inkStrength > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inkStrength',
        actualValue: inkStrength,
        expectedCriteria: 'Ink strength in [0.0, 1.0]',
      );
    }
    if (contrastGamma <= 0.0 || contrastGamma > 5.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'contrastGamma',
        actualValue: contrastGamma,
        expectedCriteria: 'Contrast gamma in (0.0, 5.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory CelShadeColorNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return CelShadeColorNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      colorInputNodeId: inputs[0],
      edgeInputNodeId: inputs.length > 1 ? inputs[1] : null,
      shadeLevels: (params['shadeLevels'] as num?)?.toInt() ?? 4,
      inkStrength: (params['inkStrength'] as num?)?.toDouble() ?? 0.75,
      contrastGamma: (params['contrastGamma'] as num?)?.toDouble() ?? 1.2,
    );
  }
}

/// Node applying translucent watercolor wash diffusion, wet-edge pigment pooling, and cold-press paper grain.
/// Strictly preserves original color relationships and alpha channel.
class WatercolorWashNode extends RenderGraphNode {
  static const String nodeType = 'WatercolorWashNode';

  final int washDiffusion; // Diffusion smoothing radius [1, 6]
  final double
  wetEdgeBleed; // Pigment accumulation intensity along edges [0.0, 1.0]
  final double paperTooth; // Cold-press paper grain modulation [0.0, 0.5]
  final int seed; // Deterministic PRNG seed

  WatercolorWashNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.washDiffusion = 2,
    this.wetEdgeBleed = 0.45,
    this.paperTooth = 0.18,
    this.seed = 4040,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'washDiffusion': washDiffusion,
           'wetEdgeBleed': wetEdgeBleed,
           'paperTooth': paperTooth,
           'seed': seed,
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
    if (washDiffusion < 1 || washDiffusion > 6) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'washDiffusion',
        actualValue: washDiffusion,
        expectedCriteria: 'Integer wash diffusion radius in [1, 6]',
      );
    }
    if (wetEdgeBleed < 0.0 || wetEdgeBleed > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'wetEdgeBleed',
        actualValue: wetEdgeBleed,
        expectedCriteria: 'Wet edge bleed in [0.0, 1.0]',
      );
    }
    if (paperTooth < 0.0 || paperTooth > 0.5) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'paperTooth',
        actualValue: paperTooth,
        expectedCriteria: 'Paper tooth intensity in [0.0, 0.5]',
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

  factory WatercolorWashNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return WatercolorWashNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      washDiffusion: (params['washDiffusion'] as num?)?.toInt() ?? 2,
      wetEdgeBleed: (params['wetEdgeBleed'] as num?)?.toDouble() ?? 0.45,
      paperTooth: (params['paperTooth'] as num?)?.toDouble() ?? 0.18,
      seed: params['seed'] as int? ?? 4040,
    );
  }
}

/// Node applying genuine 2D polygonal facet quantization with triangular cell grouping and edge contrast.
class PolygonalFacetNode extends RenderGraphNode {
  static const String nodeType = 'PolygonalFacetNode';

  final int facetSize; // Polygonal grid facet size in pixels [2, 32]
  final double edgeContrast; // Wireframe facet boundary contrast [0.0, 1.0]

  PolygonalFacetNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.facetSize = 8,
    this.edgeContrast = 0.5,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {'facetSize': facetSize, 'edgeContrast': edgeContrast},
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
    if (facetSize < 2 || facetSize > 32) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'facetSize',
        actualValue: facetSize,
        expectedCriteria: 'Integer facet size in [2, 32]',
      );
    }
    if (edgeContrast < 0.0 || edgeContrast > 1.0) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'edgeContrast',
        actualValue: edgeContrast,
        expectedCriteria: 'Edge contrast in [0.0, 1.0]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory PolygonalFacetNode.fromJson(Map<String, dynamic> json) {
    final inputs = (json['inputNodeIds'] as List).cast<String>();
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return PolygonalFacetNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: inputs.first,
      facetSize: (params['facetSize'] as num?)?.toInt() ?? 8,
      edgeContrast: (params['edgeContrast'] as num?)?.toDouble() ?? 0.5,
    );
  }
}
