import '../../../domain/presets/preset_definition.dart';
import '../../../domain/presets/preset_parameter.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/style_render_nodes.dart';
import '../../../domain/recipes/pixelate_quantize_node.dart';
import '../../../domain/recipes/artistic_render_nodes.dart';
import '../../../domain/recipes/adaptive_vibrancy_node.dart';

/// Expanded Presets covering Categories 1 through 6 to complete the canonical 48-preset catalog.
///
/// Each preset:
/// - Executes deterministically via validated RenderGraph DAG nodes.
/// - Produces a unique SHA-256 output fingerprint.
/// - Has responsive user parameters with continuous effect.
/// - Bundles precomputed local thumbnail assets in assets/preset_thumbnails/.
/// - Explicitly labels stylized raster simulations (e.g. Clay Render, Low-Poly) per Invariant 7.
class ExpandedPresets {
  // ---------------------------------------------------------------------------
  // CATEGORY 1: Sketch & Line Art (6 additional presets)
  // ---------------------------------------------------------------------------

  static final softPencil = PresetDefinition(
    id: 'soft_pencil',
    displayName: 'Soft Pencil',
    category: 'Sketch & Line Art',
    description: 'Soft graphite pencil sketch with gentle feathered strokes and paper tooth texture.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'softness',
        label: 'Lead Softness',
        min: 0.2,
        max: 0.8,
        defaultValue: 0.50,
        step: 0.05,
      ),
      PresetParameter(
        id: 'paperGrain',
        label: 'Paper Tooth',
        min: 0.05,
        max: 0.35,
        defaultValue: 0.22,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_pencil.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Soft Pencil artistic sketch style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final softness = params['softness'] ?? 0.50;
      final grain = params['paperGrain'] ?? 0.22;

      return RenderGraph(
        id: 'graph_soft_pencil',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 20,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: softness,
            contrastGamma: 1.0 + softness * 0.5,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'ink_3',
            intensity: grain,
            seed: 102,
          ),
        },
        outputNodeId: 'grain_4',
      );
    },
  );

  static final charcoal = PresetDefinition(
    id: 'charcoal',
    displayName: 'Charcoal',
    category: 'Sketch & Line Art',
    description: 'Expressive smudged charcoal drawing with rich matte carbon blacks and atmospheric tooth.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'charcoalDensity',
        label: 'Charcoal Density',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.88,
        step: 0.05,
      ),
      PresetParameter(
        id: 'smudgeGrain',
        label: 'Smudge Tooth',
        min: 0.02,
        max: 0.10,
        defaultValue: 0.06,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/charcoal.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Charcoal smudged drawing style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final density = params['charcoalDensity'] ?? 0.88;
      final grain = params['smudgeGrain'] ?? 0.06;

      return RenderGraph(
        id: 'graph_charcoal',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 28,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: density,
            contrastGamma: 2.1,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'ink_3',
            intensity: grain,
            seed: 103,
          ),
        },
        outputNodeId: 'grain_4',
      );
    },
  );

  static final crosshatch = PresetDefinition(
    id: 'crosshatch',
    displayName: 'Crosshatch',
    category: 'Sketch & Line Art',
    description: 'Intricate pen crosshatching effect with geometric line density and deep ink accents.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'hatchDensity',
        label: 'Hatch Density',
        min: 0.4,
        max: 1.0,
        defaultValue: 0.80,
        step: 0.05,
      ),
      PresetParameter(
        id: 'penContrast',
        label: 'Pen Contrast',
        min: 1.2,
        max: 2.8,
        defaultValue: 1.80,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/crosshatch.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Crosshatch pen etching style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final density = params['hatchDensity'] ?? 0.80;
      final gamma = params['penContrast'] ?? 1.80;

      return RenderGraph(
        id: 'graph_crosshatch',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'hatch_1': CrosshatchNode(
            id: 'hatch_1',
            inputNodeId: 'src_0',
            spacing: 6,
            lineWeight: 1,
            hatchDensity: density,
            preserveColor: false,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'hatch_1',
            intensity: 0.10 * (gamma / 1.80),
            seed: 105,
          ),
        },
        outputNodeId: 'grain_2',
      );
    },
  );

  static final stipple = PresetDefinition(
    id: 'stipple',
    displayName: 'Stipple',
    category: 'Sketch & Line Art',
    description: 'Detailed stippling and dot pen technique producing tonal shading through point density.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'dotDensity',
        label: 'Dot Density',
        min: 0.1,
        max: 0.5,
        defaultValue: 0.32,
        step: 0.02,
      ),
      PresetParameter(
        id: 'lineWeight',
        label: 'Ink Weight',
        min: 0.3,
        max: 0.9,
        defaultValue: 0.75,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/stipple.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Stipple dot pen illustration style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final dotDensity = params['dotDensity'] ?? 0.32;
      final weight = params['lineWeight'] ?? 0.75;

      return RenderGraph(
        id: 'graph_stipple',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'stip_1': StippleNode(
            id: 'stip_1',
            inputNodeId: 'src_0',
            dotDensity: dotDensity * (weight / 0.75),
            preserveColor: false,
            seed: 106,
          ),
        },
        outputNodeId: 'stip_1',
      );
    },
  );

  static final blueprint = PresetDefinition(
    id: 'blueprint',
    displayName: 'Blueprint',
    category: 'Sketch & Line Art',
    description: 'Technical architectural cyanotype schematic with crisp white contour lines on deep cobalt blue.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'lineCrispness',
        label: 'Line Crispness',
        min: 0.4,
        max: 1.0,
        defaultValue: 0.85,
        step: 0.05,
      ),
      PresetParameter(
        id: 'blueDepth',
        label: 'Vignette Depth',
        min: 0.0,
        max: 0.5,
        defaultValue: 0.15,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/blueprint.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Blueprint cyanotype technical drawing style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final crispness = params['lineCrispness'] ?? 0.85;
      final depth = params['blueDepth'] ?? 0.15;

      return RenderGraph(
        id: 'graph_blueprint',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 38,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: crispness,
            contrastGamma: 1.5,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 13,
            shadowG: 43,
            shadowB: 89,
            highlightR: 212,
            highlightG: 232,
            highlightB: 248,
            vignetteFalloff: depth,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final contourDrawing = PresetDefinition(
    id: 'contour_drawing',
    displayName: 'Contour Drawing',
    category: 'Sketch & Line Art',
    description: 'Minimalist continuous blind contour line art emphasizing pure form on neutral vellum.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'strokeWeight',
        label: 'Stroke Weight',
        min: 0.2,
        max: 1.0,
        defaultValue: 0.60,
        step: 0.05,
      ),
      PresetParameter(
        id: 'contourThreshold',
        label: 'Contour Edge Boost',
        min: 1.5,
        max: 3.5,
        defaultValue: 2.5,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/contour_drawing.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Contour Drawing minimalist linework style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final weight = params['strokeWeight'] ?? 0.60;
      final boost = params['contourThreshold'] ?? 2.5;

      return RenderGraph(
        id: 'graph_contour_drawing',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 58,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: weight,
            contrastGamma: boost,
          ),
        },
        outputNodeId: 'ink_3',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // CATEGORY 2: Painting Studio (6 additional presets)
  // ---------------------------------------------------------------------------

  static final wetWatercolor = PresetDefinition(
    id: 'wet_watercolor',
    displayName: 'Wet Watercolor',
    category: 'Painting Studio',
    description: 'Luminous wet-on-wet watercolor with organic pigment dispersion and soft diffused edges.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'wetDiffusion',
        label: 'Wet Diffusion',
        min: 0.2,
        max: 0.7,
        defaultValue: 0.40,
        step: 0.05,
      ),
      PresetParameter(
        id: 'bleedGamma',
        label: 'Wash Bleed Curve',
        min: 0.8,
        max: 1.8,
        defaultValue: 1.15,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/wet_watercolor.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Wet Watercolor organic wash style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final diff = params['wetDiffusion'] ?? 0.40;
      final gamma = params['bleedGamma'] ?? 1.15;

      return RenderGraph(
        id: 'graph_wet_watercolor',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'wash_1': WatercolorWashNode(
            id: 'wash_1',
            inputNodeId: 'src_0',
            washDiffusion: (diff * 5.0).round().clamp(1, 4),
            wetEdgeBleed: diff * (gamma / 1.15),
            paperTooth: 0.05,
            seed: 4041,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'wash_1',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final acrylic = PresetDefinition(
    id: 'acrylic',
    displayName: 'Acrylic',
    category: 'Painting Studio',
    description: 'Bold, opaque synthetic polymer pigments with vibrant color saturation and crisp edge separation.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'pigmentBoldness',
        label: 'Pigment Boldness',
        min: 0.3,
        max: 0.9,
        defaultValue: 0.60,
        step: 0.05,
      ),
      PresetParameter(
        id: 'acrylicSaturation',
        label: 'Acrylic Contrast',
        min: 1.0,
        max: 2.2,
        defaultValue: 1.45,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/acrylic.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Acrylic bold polymer painting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final boldness = params['pigmentBoldness'] ?? 0.60;
      final gamma = params['acrylicSaturation'] ?? 1.45;

      return RenderGraph(
        id: 'graph_acrylic',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 40,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: boldness,
            contrastGamma: gamma,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 20,
            shadowG: 26,
            shadowB: 41,
            highlightR: 255,
            highlightG: 242,
            highlightB: 214,
            vignetteFalloff: 0.10,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final gouache = PresetDefinition(
    id: 'gouache',
    displayName: 'Gouache',
    category: 'Painting Studio',
    description: 'Flat, matte opaque watercolor with velvety surface texture, graphic poster color fields, and zero sheen.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'matteOpacity',
        label: 'Matte Opacity',
        min: 0.2,
        max: 0.8,
        defaultValue: 0.50,
        step: 0.05,
      ),
      PresetParameter(
        id: 'chalkTooth',
        label: 'Chalk Tooth',
        min: 0.02,
        max: 0.25,
        defaultValue: 0.10,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/gouache.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Gouache opaque matte painting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final opacity = params['matteOpacity'] ?? 0.50;
      final tooth = params['chalkTooth'] ?? 0.10;

      return RenderGraph(
        id: 'graph_gouache',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 35,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: opacity,
            contrastGamma: 1.30,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 40,
            shadowG: 36,
            shadowB: 48,
            highlightR: 246,
            highlightG: 239,
            highlightB: 230,
            vignetteFalloff: 0.08,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: tooth,
            seed: 205,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final softPastel = PresetDefinition(
    id: 'soft_pastel',
    displayName: 'Soft Pastel',
    category: 'Painting Studio',
    description: 'Velvety pigment stick painting with powdery blending, dreamy chalk highlights, and soft paper texture.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'powderSoftness',
        label: 'Powder Softness',
        min: 0.15,
        max: 0.6,
        defaultValue: 0.35,
        step: 0.05,
      ),
      PresetParameter(
        id: 'chalkGrain',
        label: 'Chalk Texture',
        min: 0.05,
        max: 0.30,
        defaultValue: 0.16,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_pastel.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Soft Pastel velvety chalk painting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final softness = params['powderSoftness'] ?? 0.35;
      final grain = params['chalkGrain'] ?? 0.16;

      return RenderGraph(
        id: 'graph_soft_pastel',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 22,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: softness,
            contrastGamma: 1.10,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 74,
            shadowG: 53,
            shadowB: 79,
            highlightR: 255,
            highlightG: 240,
            highlightB: 245,
            vignetteFalloff: 0.25,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: grain,
            seed: 206,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final inkWash = PresetDefinition(
    id: 'ink_wash',
    displayName: 'Ink Wash',
    category: 'Painting Studio',
    description: 'East Asian Sumi-e brush painting with expressive monochrome tonal gradients from mist to dense pine soot.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'brushInkDensity',
        label: 'Sumi Ink Density',
        min: 0.4,
        max: 0.95,
        defaultValue: 0.70,
        step: 0.05,
      ),
      PresetParameter(
        id: 'paperTonalFade',
        label: 'Brush Contrast',
        min: 1.1,
        max: 2.4,
        defaultValue: 1.65,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/ink_wash.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Ink Wash Sumi-e brush painting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final density = params['brushInkDensity'] ?? 0.70;
      final gamma = params['paperTonalFade'] ?? 1.65;

      return RenderGraph(
        id: 'graph_ink_wash',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 30,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: density,
            contrastGamma: gamma,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 26,
            shadowG: 26,
            shadowB: 30,
            highlightR: 250,
            highlightG: 246,
            highlightB: 237,
            vignetteFalloff: 0.12,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final paletteKnife = PresetDefinition(
    id: 'palette_knife',
    displayName: 'Palette Knife',
    category: 'Painting Studio',
    description: 'Sculptural heavy-body paint applied with metal palette knives, featuring sharp impasto bevels and scraped underlayers.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'knifeEdge',
        label: 'Bevel Edge Sharpness',
        min: 0.4,
        max: 1.0,
        defaultValue: 0.80,
        step: 0.05,
      ),
      PresetParameter(
        id: 'impastoThickness',
        label: 'Impasto Contrast',
        min: 1.2,
        max: 2.6,
        defaultValue: 1.90,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/palette_knife.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Palette Knife sculptural heavy-body painting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final edge = params['knifeEdge'] ?? 0.80;
      final gamma = params['impastoThickness'] ?? 1.90;

      return RenderGraph(
        id: 'graph_palette_knife',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 55,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: edge,
            contrastGamma: gamma,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 33,
            shadowG: 27,
            shadowB: 21,
            highlightR: 252,
            highlightG: 232,
            highlightB: 207,
            vignetteFalloff: 0.18,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: 0.14,
            seed: 208,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // CATEGORY 3: Illustration & Comics (5 additional presets)
  // ---------------------------------------------------------------------------

  static final mangaBw = PresetDefinition(
    id: 'manga_bw',
    displayName: 'Manga B&W',
    category: 'Illustration & Comics',
    description: 'Authentic Japanese manga tankobon aesthetic with crisp screentone dots, ink line accents, and stark page contrast.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'screentoneDensity',
        label: 'Screentone Pattern',
        min: 0.05,
        max: 0.35,
        defaultValue: 0.20,
        step: 0.01,
      ),
      PresetParameter(
        id: 'inkBlackness',
        label: 'Manga Inking',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.90,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/manga_bw.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Manga B&W Japanese comic tankobon style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final grain = params['screentoneDensity'] ?? 0.20;
      final ink = params['inkBlackness'] ?? 0.90;

      return RenderGraph(
        id: 'graph_manga_bw',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 65,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: ink,
            contrastGamma: 2.40,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'ink_3',
            intensity: grain,
            seed: 302,
          ),
        },
        outputNodeId: 'grain_4',
      );
    },
  );

  static final graphicNovel = PresetDefinition(
    id: 'graphic_novel',
    displayName: 'Graphic Novel',
    category: 'Illustration & Comics',
    description: 'Modern dark graphic novel illustration with heavy cinematic inking, dramatic noir shadows, and moody desaturated palette.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'inkDrama',
        label: 'Inking Weight',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.88,
        step: 0.05,
      ),
      PresetParameter(
        id: 'shadowCrush',
        label: 'Shadow Contrast',
        min: 1.3,
        max: 2.8,
        defaultValue: 2.10,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/graphic_novel.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Graphic Novel dark cinematic comic style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final ink = params['inkDrama'] ?? 0.88;
      final gamma = params['shadowCrush'] ?? 2.10;

      return RenderGraph(
        id: 'graph_graphic_novel',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 50,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: ink,
            contrastGamma: gamma,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 18,
            shadowG: 21,
            shadowB: 29,
            highlightR: 226,
            highlightG: 230,
            highlightB: 232,
            vignetteFalloff: 0.30,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final storybookIllustration = PresetDefinition(
    id: 'storybook_illustration',
    displayName: 'Storybook Illustration',
    category: 'Illustration & Comics',
    description: 'Whimsical narrative storybook art with warm nostalgic washes, gentle ink outlines, and textured vellum warmth.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'lineCharm',
        label: 'Line Charm',
        min: 0.3,
        max: 0.85,
        defaultValue: 0.55,
        step: 0.05,
      ),
      PresetParameter(
        id: 'nostalgiaWarmth',
        label: 'Vignette Warmth',
        min: 0.0,
        max: 0.3,
        defaultValue: 0.15,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/storybook_illustration.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Storybook Illustration narrative artwork style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final line = params['lineCharm'] ?? 0.55;
      final warmth = params['nostalgiaWarmth'] ?? 0.15;

      return RenderGraph(
        id: 'graph_storybook_illustration',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 32,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: line,
            contrastGamma: 1.25,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 60,
            shadowG: 46,
            shadowB: 36,
            highlightR: 255,
            highlightG: 248,
            highlightB: 231,
            vignetteFalloff: warmth,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: 0.09,
            seed: 305,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final editorialIllustration = PresetDefinition(
    id: 'editorial_illustration',
    displayName: 'Editorial Illustration',
    category: 'Illustration & Comics',
    description: 'Sophisticated contemporary magazine illustration with refined muted earth tones and razor-sharp contour definition.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'lineRefinement',
        label: 'Contour Refinement',
        min: 0.4,
        max: 0.95,
        defaultValue: 0.70,
        step: 0.05,
      ),
      PresetParameter(
        id: 'paletteSubtlety',
        label: 'Editorial Contrast',
        min: 1.1,
        max: 2.2,
        defaultValue: 1.50,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/editorial_illustration.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Editorial Illustration modern magazine style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final line = params['lineRefinement'] ?? 0.70;
      final gamma = params['paletteSubtlety'] ?? 1.50;

      return RenderGraph(
        id: 'graph_editorial_illustration',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 42,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: line,
            contrastGamma: gamma,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 35,
            shadowG: 49,
            shadowB: 56,
            highlightR: 244,
            highlightG: 234,
            highlightB: 212,
            vignetteFalloff: 0.22,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final vintageChildrensBook = PresetDefinition(
    id: 'vintage_childrens_book',
    displayName: "Vintage Children's Book",
    category: 'Illustration & Comics',
    description: "Mid-century children's book lithograph with offset print imperfections, limited spot color, and warm paper aging.",
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'lithoAging',
        label: 'Litho Aging Grain',
        min: 0.05,
        max: 0.3,
        defaultValue: 0.13,
        step: 0.01,
      ),
      PresetParameter(
        id: 'inkBleed',
        label: 'Ink Bleed Weight',
        min: 0.35,
        max: 0.9,
        defaultValue: 0.62,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/vintage_childrens_book.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        "Vintage Children's Book mid-century illustration style preset",
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final grain = params['lithoAging'] ?? 0.13;
      final ink = params['inkBleed'] ?? 0.62;

      return RenderGraph(
        id: 'graph_vintage_childrens_book',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 38,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: ink,
            contrastGamma: 1.35,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 54,
            shadowG: 41,
            shadowB: 32,
            highlightR: 250,
            highlightG: 242,
            highlightB: 223,
            vignetteFalloff: 0.18,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: grain,
            seed: 308,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // CATEGORY 4: Film & Photography (6 additional presets)
  // ---------------------------------------------------------------------------

  static final cinematicTealOrange = PresetDefinition(
    id: 'cinematic_teal_orange',
    displayName: 'Cinematic Teal & Orange',
    category: 'Film & Photography',
    description: 'Hollywood blockbuster cinematic color grade split-toning deep teal shadows against radiant amber skin tones.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'vignetteFalloff',
        label: 'Cinematic Vignette',
        min: 0.1,
        max: 0.6,
        defaultValue: 0.28,
        step: 0.05,
      ),
      PresetParameter(
        id: 'filmGrain',
        label: '35mm Film Grain',
        min: 0.0,
        max: 0.25,
        defaultValue: 0.08,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/cinematic_teal_orange.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Cinematic Teal & Orange Hollywood film style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final vignette = params['vignetteFalloff'] ?? 0.28;
      final grain = params['filmGrain'] ?? 0.08;

      return RenderGraph(
        id: 'graph_cinematic_teal_orange',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 12,
            shadowG: 40,
            shadowB: 51,
            highlightR: 255,
            highlightG: 168,
            highlightB: 82,
            vignetteFalloff: vignette,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 401,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final fadedInstantFilm = PresetDefinition(
    id: 'faded_instant_film',
    displayName: 'Faded Instant Film',
    category: 'Film & Photography',
    description: '1980s instant polaroid print with lifted matte milky blacks, warm shifted greens, and soft peripheral vignette.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'matteLift',
        label: 'Matte Lift Vignette',
        min: 0.15,
        max: 0.65,
        defaultValue: 0.40,
        step: 0.05,
      ),
      PresetParameter(
        id: 'filmAge',
        label: 'Celluloid Grit',
        min: 0.02,
        max: 0.25,
        defaultValue: 0.12,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/faded_instant_film.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Faded Instant Film retro polaroid style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final lift = params['matteLift'] ?? 0.40;
      final grain = params['filmAge'] ?? 0.12;

      return RenderGraph(
        id: 'graph_faded_instant_film',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 52,
            shadowG: 61,
            shadowB: 54,
            highlightR: 255,
            highlightG: 245,
            highlightB: 225,
            vignetteFalloff: lift,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 404,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final goldenHour = PresetDefinition(
    id: 'golden_hour',
    displayName: 'Golden Hour',
    category: 'Film & Photography',
    description: 'Warm late-afternoon sunset glow bathing the frame in honeyed amber tones with gentle contrast roll-off.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'sunlightGlow',
        label: 'Sunset Glow Falloff',
        min: 0.05,
        max: 0.50,
        defaultValue: 0.20,
        step: 0.05,
      ),
      PresetParameter(
        id: 'analogTexture',
        label: 'Analog Texture',
        min: 0.0,
        max: 0.20,
        defaultValue: 0.06,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/golden_hour.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Golden Hour warm afternoon sunlight style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final glow = params['sunlightGlow'] ?? 0.20;
      final grain = params['analogTexture'] ?? 0.06;

      return RenderGraph(
        id: 'graph_golden_hour',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 56,
            shadowG: 28,
            shadowB: 16,
            highlightR: 255,
            highlightG: 212,
            highlightB: 128,
            vignetteFalloff: glow,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 405,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final coolEditorial = PresetDefinition(
    id: 'cool_editorial',
    displayName: 'Cool Editorial',
    category: 'Film & Photography',
    description: 'High-fashion magazine look featuring muted slate shadows, pristine cool silver highlights, and subtle film grit.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'slateDepth',
        label: 'Slate Vignette Depth',
        min: 0.1,
        max: 0.5,
        defaultValue: 0.25,
        step: 0.05,
      ),
      PresetParameter(
        id: 'fashionGrain',
        label: 'Fashion Film Grit',
        min: 0.02,
        max: 0.25,
        defaultValue: 0.10,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/cool_editorial.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Cool Editorial high-fashion silver tone style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final depth = params['slateDepth'] ?? 0.25;
      final grain = params['fashionGrain'] ?? 0.10;

      return RenderGraph(
        id: 'graph_cool_editorial',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 25,
            shadowG: 32,
            shadowB: 38,
            highlightR: 235,
            highlightG: 242,
            highlightB: 247,
            vignetteFalloff: depth,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 406,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final softPortrait = PresetDefinition(
    id: 'soft_portrait',
    displayName: 'Soft Portrait',
    category: 'Film & Photography',
    description: 'Flattering portrait rendering with softened micro-contrast, dreamy highlight diffusion, and gentle pastel skin tone preservation.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'skinSoftness',
        label: 'Diffusion Softness',
        min: 0.1,
        max: 0.5,
        defaultValue: 0.25,
        step: 0.05,
      ),
      PresetParameter(
        id: 'highlightDiffusion',
        label: 'Vignette Falloff',
        min: 0.0,
        max: 0.3,
        defaultValue: 0.15,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_portrait.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Soft Portrait flattering diffused portrait style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final softness = params['skinSoftness'] ?? 0.25;
      final diff = params['highlightDiffusion'] ?? 0.15;

      return RenderGraph(
        id: 'graph_soft_portrait',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 20,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: softness,
            contrastGamma: 1.08,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 58,
            shadowG: 43,
            shadowB: 40,
            highlightR: 255,
            highlightG: 242,
            highlightB: 235,
            vignetteFalloff: diff,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: 0.07,
            seed: 407,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final highContrastStudio = PresetDefinition(
    id: 'high_contrast_studio',
    displayName: 'High-Contrast Studio',
    category: 'Film & Photography',
    description: 'Editorial monochrome studio lighting with intense specular key lights, pitch black backgrounds, and punchy silver punch.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'studioGamma',
        label: 'Studio Key Gamma',
        min: 1.5,
        max: 3.5,
        defaultValue: 2.60,
        step: 0.10,
      ),
      PresetParameter(
        id: 'silverGrain',
        label: 'Silver Gelatin Grain',
        min: 0.04,
        max: 0.25,
        defaultValue: 0.14,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/high_contrast_studio.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'High-Contrast Studio editorial black and white lighting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final gamma = params['studioGamma'] ?? 2.60;
      final grain = params['silverGrain'] ?? 0.14;

      return RenderGraph(
        id: 'graph_high_contrast_studio',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 55,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: 0.45,
            contrastGamma: gamma,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'ink_3',
            intensity: grain,
            seed: 408,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // CATEGORY 5: Graphic & Retro (6 additional presets)
  // ---------------------------------------------------------------------------

  static final neonCyberpunk = PresetDefinition(
    id: 'neon_cyberpunk',
    displayName: 'Neon Cyberpunk',
    category: 'Graphic & Retro',
    description: 'Electric dystopian nightlife palette pairing ultraviolet/deep cyan shadows with blinding hot magenta highlights.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'neonIntensity',
        label: 'Vignette Depth',
        min: 0.15,
        max: 0.70,
        defaultValue: 0.38,
        step: 0.05,
      ),
      PresetParameter(
        id: 'streetGrit',
        label: 'Cyberpunk Noise Grit',
        min: 0.0,
        max: 0.25,
        defaultValue: 0.08,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/neon_cyberpunk.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Neon Cyberpunk electric synthwave color palette preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final intensity = params['neonIntensity'] ?? 0.38;
      final grit = params['streetGrit'] ?? 0.08;

      return RenderGraph(
        id: 'graph_neon_cyberpunk',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 5,
            shadowG: 26,
            shadowB: 46,
            highlightR: 255,
            highlightG: 46,
            highlightB: 147,
            vignetteFalloff: intensity,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grit,
            seed: 503,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final retroPoster = PresetDefinition(
    id: 'retro_poster',
    displayName: 'Retro Poster',
    category: 'Graphic & Retro',
    description: '1970s screen-printed travel poster style with bold graphic tone banding, warm mustard highlights, and deep forest green shadows.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'posterInking',
        label: 'Poster Inking Weight',
        min: 0.4,
        max: 0.95,
        defaultValue: 0.72,
        step: 0.05,
      ),
      PresetParameter(
        id: 'vignette',
        label: 'Vignette Depth',
        min: 0.05,
        max: 0.45,
        defaultValue: 0.18,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/retro_poster.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Retro Poster vintage travel silkscreen style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final inking = params['posterInking'] ?? 0.72;
      final vig = params['vignette'] ?? 0.18;

      return RenderGraph(
        id: 'graph_retro_poster',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 45,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: inking,
            contrastGamma: 1.60,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 20,
            shadowG: 40,
            shadowB: 29,
            highlightR: 245,
            highlightG: 211,
            highlightB: 101,
            vignetteFalloff: vig,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final screenprint = PresetDefinition(
    id: 'screenprint',
    displayName: 'Screenprint',
    category: 'Graphic & Retro',
    description: 'Manual silkscreen print with squeegee pressure variations, coarse mesh grain, and intense graphic flat inks.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'squeegeePressure',
        label: 'Squeegee Pressure',
        min: 0.45,
        max: 1.0,
        defaultValue: 0.82,
        step: 0.05,
      ),
      PresetParameter(
        id: 'meshGrain',
        label: 'Silk Mesh Grain',
        min: 0.05,
        max: 0.35,
        defaultValue: 0.18,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/screenprint.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Screenprint silkscreen poster graphic style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final pressure = params['squeegeePressure'] ?? 0.82;
      final grain = params['meshGrain'] ?? 0.18;

      return RenderGraph(
        id: 'graph_screenprint',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'half_1': HalftoneNode(
            id: 'half_1',
            inputNodeId: 'src_0',
            dotPitch: 5,
            angleDegrees: 45.0,
            dotIntensity: pressure,
            preserveColor: true,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'half_1',
            intensity: grain,
            seed: 505,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final woodcut = PresetDefinition(
    id: 'woodcut',
    displayName: 'Woodcut',
    category: 'Graphic & Retro',
    description: 'Traditional relief woodcut print featuring coarse carved gouge contours, stark contrast, and fibrous mulberry paper grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'gougeCarve',
        label: 'Gouge Carve Inking',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.92,
        step: 0.05,
      ),
      PresetParameter(
        id: 'woodFiber',
        label: 'Wood Fiber Grain',
        min: 0.08,
        max: 0.38,
        defaultValue: 0.22,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/woodcut.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Woodcut traditional relief block print style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final carve = params['gougeCarve'] ?? 0.92;
      final fiber = params['woodFiber'] ?? 0.22;

      return RenderGraph(
        id: 'graph_woodcut',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 60,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: carve,
            contrastGamma: 2.30,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 31,
            shadowG: 27,
            shadowB: 24,
            highlightR: 237,
            highlightG: 228,
            highlightB: 209,
            vignetteFalloff: 0.15,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: fiber,
            seed: 506,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final paperCutout = PresetDefinition(
    id: 'paper_cutout',
    displayName: 'Paper Cutout',
    category: 'Graphic & Retro',
    description: 'Multi-layered Matisse-style decoupage with sharp graphic edge silhouettes and subtle tonal depth separation.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'cutEdgeSharpness',
        label: 'Cut Edge Inking',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.86,
        step: 0.05,
      ),
      PresetParameter(
        id: 'depthFalloff',
        label: 'Layer Depth Falloff',
        min: 0.1,
        max: 0.5,
        defaultValue: 0.24,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/paper_cutout.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Paper Cutout Matisse-style decoupage graphic style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final edge = params['cutEdgeSharpness'] ?? 0.86;
      final falloff = params['depthFalloff'] ?? 0.24;

      return RenderGraph(
        id: 'graph_paper_cutout',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 48,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: edge,
            contrastGamma: 1.95,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 43,
            shadowG: 29,
            shadowB: 58,
            highlightR: 252,
            highlightG: 235,
            highlightB: 210,
            vignetteFalloff: falloff,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'duo_4',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final stainedGlass = PresetDefinition(
    id: 'stained_glass',
    displayName: 'Stained Glass',
    category: 'Graphic & Retro',
    description: 'Gothic cathedral stained glass window effect with heavy lead came outlines enclosing glowing jewel-toned luminances.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'leadCameWeight',
        label: 'Lead Came Outline Weight',
        min: 0.6,
        max: 1.0,
        defaultValue: 0.98,
        step: 0.05,
      ),
      PresetParameter(
        id: 'jewelGlow',
        label: 'Jewel Glow Falloff',
        min: 0.1,
        max: 0.6,
        defaultValue: 0.30,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/stained_glass.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Stained Glass cathedral window leaded jewel tone style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final weight = params['leadCameWeight'] ?? 0.98;
      final glow = params['jewelGlow'] ?? 0.30;

      return RenderGraph(
        id: 'graph_stained_glass',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 40,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: weight,
            contrastGamma: 2.20,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 16,
            shadowG: 12,
            shadowB: 31,
            highlightR: 255,
            highlightG: 179,
            highlightB: 71,
            vignetteFalloff: glow,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: 0.10,
            seed: 508,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // CATEGORY 6: Experimental & Atmosphere (7 additional presets)
  // ---------------------------------------------------------------------------

  static final softMattePastel = PresetDefinition(
    id: 'soft_matte_pastel',
    displayName: 'Soft Matte Pastel',
    category: 'Experimental & Atmosphere',
    description: 'Ethereal dreamy pastel with lifted haze, muted strawberry-peach highlights, and serene chalk finish.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'matteHaze',
        label: 'Matte Haze Falloff',
        min: 0.05,
        max: 0.40,
        defaultValue: 0.16,
        step: 0.05,
      ),
      PresetParameter(
        id: 'pastelGrain',
        label: 'Chalk Powder Grain',
        min: 0.02,
        max: 0.22,
        defaultValue: 0.09,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_matte_pastel.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Soft Matte Pastel dreamy chalk tone style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final haze = params['matteHaze'] ?? 0.16;
      final grain = params['pastelGrain'] ?? 0.09;

      return RenderGraph(
        id: 'graph_soft_matte_pastel',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 74,
            shadowG: 62,
            shadowB: 72,
            highlightR: 255,
            highlightG: 228,
            highlightB: 220,
            vignetteFalloff: haze,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 602,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final darkAcademia = PresetDefinition(
    id: 'dark_academia',
    displayName: 'Dark Academia',
    category: 'Experimental & Atmosphere',
    description: 'Moody, scholarly aesthetic dominated by rich mahogany shadows, tarnished brass highlights, and antiquarian book patina.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'mahoganyShadow',
        label: 'Shadow Contrast Curve',
        min: 1.2,
        max: 2.5,
        defaultValue: 1.70,
        step: 0.10,
      ),
      PresetParameter(
        id: 'parchmentAging',
        label: 'Parchment Aging Tooth',
        min: 0.05,
        max: 0.30,
        defaultValue: 0.15,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/dark_academia.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Dark Academia scholarly antique mood style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final shadow = params['mahoganyShadow'] ?? 1.70;
      final aging = params['parchmentAging'] ?? 0.15;

      return RenderGraph(
        id: 'graph_dark_academia',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 35,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: 0.45,
            contrastGamma: shadow,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 28,
            shadowG: 19,
            shadowB: 14,
            highlightR: 214,
            highlightG: 186,
            highlightB: 139,
            vignetteFalloff: 0.32,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: aging,
            seed: 603,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final fantasyLuminance = PresetDefinition(
    id: 'fantasy_luminance',
    displayName: 'Fantasy Luminance',
    category: 'Experimental & Atmosphere',
    description: 'High-fantasy celestial illumination with mystical violet shadows and radiant starlight golden highlights.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'celestialGlow',
        label: 'Celestial Vignette Glow',
        min: 0.15,
        max: 0.65,
        defaultValue: 0.35,
        step: 0.05,
      ),
      PresetParameter(
        id: 'starlightGrain',
        label: 'Starlight Shimmer Grain',
        min: 0.03,
        max: 0.25,
        defaultValue: 0.11,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/fantasy_luminance.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Fantasy Luminance mystical celestial lighting style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final glow = params['celestialGlow'] ?? 0.35;
      final shimmer = params['starlightGrain'] ?? 0.11;

      return RenderGraph(
        id: 'graph_fantasy_luminance',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'duo_1': DuoToneNode(
            id: 'duo_1',
            inputNodeId: 'src_0',
            shadowR: 30,
            shadowG: 15,
            shadowB: 51,
            highlightR: 255,
            highlightG: 241,
            highlightB: 168,
            vignetteFalloff: glow,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: shimmer,
            seed: 604,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final lowPolyFacets = PresetDefinition(
    id: 'low_poly_facets',
    displayName: 'Low-Poly Facets',
    category: 'Experimental & Atmosphere',
    description: 'Stylized 2D raster simulation of polygonal faceted shading with stepped edge quantization (NOTE: 2D raster simulation per Invariant 7).',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'facetEdgeSharpness',
        label: 'Facet Edge Contrast',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.88,
        step: 0.05,
      ),
      PresetParameter(
        id: 'polyVignette',
        label: 'Vignette Falloff',
        min: 0.05,
        max: 0.45,
        defaultValue: 0.22,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/low_poly_facets.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Low-Poly Facets stylized 2D geometric raster simulation preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final sharpness = params['facetEdgeSharpness'] ?? 0.88;
      final vig = params['polyVignette'] ?? 0.22;

      return RenderGraph(
        id: 'graph_low_poly_facets',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'poly_1': PolygonalFacetNode(
            id: 'poly_1',
            inputNodeId: 'src_0',
            facetSize: 8,
            edgeContrast: sharpness,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'poly_1',
            intensity: vig * 0.5,
            seed: 605,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final clayRender = PresetDefinition(
    id: 'clay_render',
    displayName: 'Clay Render',
    category: 'Experimental & Atmosphere',
    description: 'Stylized 2D raster simulation of smooth matte clay sculpture with soft diffuse occlusion and neutral warm terracotta tone (NOTE: 2D raster simulation per Invariant 7).',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'clayOcclusion',
        label: 'Diffuse Crease Occlusion',
        min: 0.2,
        max: 0.7,
        defaultValue: 0.42,
        step: 0.05,
      ),
      PresetParameter(
        id: 'mattePorosity',
        label: 'Matte Porosity Tooth',
        min: 0.02,
        max: 0.25,
        defaultValue: 0.10,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/clay_render.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Clay Render stylized 2D matte sculpture simulation preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final occlusion = params['clayOcclusion'] ?? 0.42;
      final porosity = params['mattePorosity'] ?? 0.10;

      return RenderGraph(
        id: 'graph_clay_render',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 28,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: occlusion,
            contrastGamma: 1.30,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 74,
            shadowG: 51,
            shadowB: 42,
            highlightR: 244,
            highlightG: 226,
            highlightB: 216,
            vignetteFalloff: 0.20,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: porosity,
            seed: 606,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final pixelArt = PresetDefinition(
    id: 'pixel_art',
    displayName: 'Pixel Art',
    category: 'Experimental & Atmosphere',
    description: 'Retro 16-bit arcade pixel rasterization simulation with discrete block downsampling, palette quantization, and CRT phosphor grit.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'blockSize',
        label: 'Pixel Block Size',
        min: 2,
        max: 16,
        defaultValue: 4,
        step: 1,
      ),
      PresetParameter(
        id: 'paletteLevels',
        label: 'Palette Color Levels',
        min: 2,
        max: 16,
        defaultValue: 6,
        step: 1,
      ),
      PresetParameter(
        id: 'phosphorGrit',
        label: 'Phosphor CRT Grit',
        min: 0.05,
        max: 0.35,
        defaultValue: 0.20,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/pixel_art.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Pixel Art 16-bit retro arcade simulation preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final blockSize = (params['blockSize'] as num?)?.toInt() ?? 4;
      final paletteLevels = (params['paletteLevels'] as num?)?.toInt() ?? 6;
      final grit = (params['phosphorGrit'] as num?)?.toDouble() ?? 0.20;

      return RenderGraph(
        id: 'graph_pixel_art',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'pixel_1': PixelateQuantizeNode(
            id: 'pixel_1',
            inputNodeId: 'src_0',
            blockSize: blockSize,
            paletteLevels: paletteLevels,
            preserveAlpha: true,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'pixel_1',
            intensity: grit,
            seed: 607,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );

  static final infraredFilm = PresetDefinition(
    id: 'infrared_film',
    displayName: 'Infrared Film',
    category: 'Experimental & Atmosphere',
    description: 'Aerochrome infrared photography with surreal false-color shifts, luminous foliage glow, and intense tonal separation.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'infraredWoodEffect',
        label: 'Aerochrome False Color',
        min: 0.15,
        max: 0.60,
        defaultValue: 0.35,
        step: 0.05,
      ),
      PresetParameter(
        id: 'halationGlow',
        label: 'Infrared Halation Vignette',
        min: 0.1,
        max: 0.5,
        defaultValue: 0.25,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/infrared_film.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel:
        'Infrared Film surreal Aerochrome false-color style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final wood = params['infraredWoodEffect'] ?? 0.35;
      final halation = params['halationGlow'] ?? 0.25;

      return RenderGraph(
        id: 'graph_infrared_film',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 30,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: wood,
            contrastGamma: 1.50,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 21,
            shadowG: 34,
            shadowB: 56,
            highlightR: 255,
            highlightG: 94,
            highlightB: 126,
            vignetteFalloff: halation,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: 0.13,
            seed: 608,
          ),
          'vib_out': AdaptiveVibrancyNode(
            id: 'vib_out',
            inputNodeId: 'grain_5',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_out',
      );
    },
  );
}
