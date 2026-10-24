import '../../../domain/presets/preset_definition.dart';
import '../../../domain/presets/preset_parameter.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/style_render_nodes.dart';
import '../../../domain/recipes/artistic_render_nodes.dart';
import '../../../domain/recipes/adaptive_vibrancy_node.dart';

/// Batch C Presets (9 to 12):
/// 9. Watercolor (Wet Watercolor Bleed)
/// 10. Oil Paint (Classical Oil Impasto)
/// 11. Halftone Pop Art (Pop Art Litho)
/// 12. Dreamy Bloom (Ambient Lens Bloom)
class BatchCPresets {
  static final watercolor = PresetDefinition(
    id: 'watercolor',
    displayName: 'Watercolor',
    category: 'Painting Studio',
    description: 'Source-conditioned translucent watercolor wash with regional pigment diffusion, wet-edge pigment pooling, and cold-press paper grain overlay.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'paperTooth',
        label: 'Cold-Press Tooth',
        min: 0.05,
        max: 0.35,
        defaultValue: 0.18,
        step: 0.01,
      ),
      PresetParameter(
        id: 'bleedSoftness',
        label: 'Wash Bleed Softness',
        min: 0.10,
        max: 0.80,
        defaultValue: 0.45,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/watercolor.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Wet Watercolor Bleed artistic media style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final tooth = params['paperTooth'] ?? 0.18;
      final bleed = params['bleedSoftness'] ?? 0.45;

      return RenderGraph(
        id: 'graph_watercolor',
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
            washDiffusion: (bleed * 4.0).round().clamp(1, 5),
            wetEdgeBleed: bleed,
            paperTooth: tooth,
            seed: 4040,
          ),
          'vib_2': AdaptiveVibrancyNode(
            id: 'vib_2',
            inputNodeId: 'wash_1',
            vibrancy: 0.35,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_2',
      );
    },
  );

  static final oilPaint = PresetDefinition(
    id: 'oil_paint',
    displayName: 'Oil Paint',
    category: 'Painting Studio',
    description: 'Classical oil impasto with rich pigment body, edge contour structure, and textured linen canvas grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'canvasTooth',
        label: 'Linen Canvas Tooth',
        min: 0.05,
        max: 0.30,
        defaultValue: 0.16,
        step: 0.01,
      ),
      PresetParameter(
        id: 'impastoContrast',
        label: 'Impasto Contrast',
        min: 1.0,
        max: 2.5,
        defaultValue: 1.45,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/oil_paint.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Classical Oil Impasto artistic media style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final canvas = params['canvasTooth'] ?? 0.16;
      final contrast = params['impastoContrast'] ?? 1.45;

      return RenderGraph(
        id: 'graph_oil_paint',
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
            washDiffusion: 2,
            wetEdgeBleed: 0.25,
            paperTooth: canvas,
            seed: 8812,
          ),
          'cel_2': CelShadeColorNode(
            id: 'cel_2',
            colorInputNodeId: 'wash_1',
            shadeLevels: 6,
            inkStrength: 0.0,
            contrastGamma: contrast,
          ),
          'vib_3': AdaptiveVibrancyNode(
            id: 'vib_3',
            inputNodeId: 'cel_2',
            vibrancy: 0.30,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_3',
      );
    },
  );

  static final halftonePopArt = PresetDefinition(
    id: 'halftone_pop_art',
    displayName: 'Halftone Pop Art',
    category: 'Graphic & Retro',
    description: 'Vibrant pop art screenprint with genuine tone-responsive halftone screen dots and bold pop colors.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'dotIntensity',
        label: 'Screen Dot Density',
        min: 0.10,
        max: 1.00,
        defaultValue: 0.80,
        step: 0.05,
      ),
      PresetParameter(
        id: 'popContrast',
        label: 'Pop Screen Contrast',
        min: 1.0,
        max: 3.0,
        defaultValue: 1.60,
        step: 0.10,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/halftone_pop_art.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Pop Art Litho graphic screenprint style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final dots = params['dotIntensity'] ?? 0.80;
      final contrast = params['popContrast'] ?? 1.60;

      return RenderGraph(
        id: 'graph_halftone_pop_art',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'cel_1': CelShadeColorNode(
            id: 'cel_1',
            colorInputNodeId: 'src_0',
            shadeLevels: 4,
            inkStrength: 0.0,
            contrastGamma: contrast,
          ),
          'half_2': HalftoneNode(
            id: 'half_2',
            inputNodeId: 'cel_1',
            dotPitch: 6,
            angleDegrees: 45.0,
            dotIntensity: dots,
            preserveColor: true,
          ),
          'vib_3': AdaptiveVibrancyNode(
            id: 'vib_3',
            inputNodeId: 'half_2',
            vibrancy: 0.35,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_3',
      );
    },
  );

  static final dreamyBloom = PresetDefinition(
    id: 'dreamy_bloom',
    displayName: 'Dreamy Bloom',
    category: 'Experimental & Atmosphere',
    description: 'Ethereal luminous pastel glow with soft diffuse highlights and dreamy halation grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'bloomGrain',
        label: 'Halation Tooth',
        min: 0.02,
        max: 0.20,
        defaultValue: 0.09,
        step: 0.01,
      ),
      PresetParameter(
        id: 'glowWarmth',
        label: 'Ambient Glow Falloff',
        min: 0.0,
        max: 0.50,
        defaultValue: 0.25,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/dreamy_bloom.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Ambient Lens Bloom ethereal glow style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final grain = params['bloomGrain'] ?? 0.09;
      final warmth = params['glowWarmth'] ?? 0.25;

      return RenderGraph(
        id: 'graph_dreamy_bloom',
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
            shadowR: 70,
            shadowG: 50,
            shadowB: 95,
            highlightR: 255,
            highlightG: 238,
            highlightB: 220,
            vignetteFalloff: warmth,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 2026,
          ),
          'vib_3': AdaptiveVibrancyNode(
            id: 'vib_3',
            inputNodeId: 'grain_2',
            vibrancy: 0.30,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_3',
      );
    },
  );

  static List<PresetDefinition> get all => [
    watercolor,
    oilPaint,
    halftonePopArt,
    dreamyBloom,
  ];
}
