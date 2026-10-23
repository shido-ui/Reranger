import '../../../domain/presets/preset_definition.dart';
import '../../../domain/presets/preset_parameter.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/style_render_nodes.dart';

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
    description: 'Simulated translucent watercolor wash via edge-softened contour subtraction, duotone color grading, and cold-press paper grain overlay.',
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
          'gray_1': GrayscaleNode(id: 'gray_1', inputNodeId: 'src_0'),
          'sobel_2': SobelEdgeNode(
            id: 'sobel_2',
            inputNodeId: 'gray_1',
            edgeThreshold: 25,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: 0.35,
            contrastGamma: 1.15,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 30,
            shadowG: 55,
            shadowB: 85,
            highlightR: 252,
            highlightG: 248,
            highlightB: 236,
            vignetteFalloff: bleed,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: tooth,
            seed: 4040,
          ),
        },
        outputNodeId: 'grain_5',
      );
    },
  );

  static final oilPaint = PresetDefinition(
    id: 'oil_paint',
    displayName: 'Oil Paint',
    category: 'Painting Studio',
    description: 'Simulated classical oil impasto via high-contrast edge contour enhancement, warm tone mapping, and textured linen canvas grain overlay.',
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
            edgeIntensity: 0.45,
            contrastGamma: contrast,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 42,
            shadowG: 24,
            shadowB: 16,
            highlightR: 250,
            highlightG: 220,
            highlightB: 160,
            vignetteFalloff: 0.30,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: canvas,
            seed: 8812,
          ),
        },
        outputNodeId: 'grain_5',
      );
    },
  );

  static final halftonePopArt = PresetDefinition(
    id: 'halftone_pop_art',
    displayName: 'Halftone Pop Art',
    category: 'Graphic & Retro',
    description: 'Vibrant high-contrast pop art screenprint with saturated neon duotones and halftone dot tooth.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'dotIntensity',
        label: 'Screen Dot Tooth',
        min: 0.08,
        max: 0.40,
        defaultValue: 0.22,
        step: 0.02,
      ),
      PresetParameter(
        id: 'popContrast',
        label: 'Pop Screen Contrast',
        min: 1.2,
        max: 3.0,
        defaultValue: 1.80,
        step: 0.10,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/halftone_pop_art.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Pop Art Litho graphic screenprint style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final dots = params['dotIntensity'] ?? 0.22;
      final contrast = params['popContrast'] ?? 1.80;

      return RenderGraph(
        id: 'graph_halftone_pop_art',
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
            edgeIntensity: 0.70,
            contrastGamma: contrast,
          ),
          'duo_4': DuoToneNode(
            id: 'duo_4',
            inputNodeId: 'ink_3',
            shadowR: 12,
            shadowG: 45,
            shadowB: 110,
            highlightR: 255,
            highlightG: 230,
            highlightB: 90,
            vignetteFalloff: 0.15,
          ),
          'grain_5': GrainOverlayNode(
            id: 'grain_5',
            inputNodeId: 'duo_4',
            intensity: dots,
            seed: 1968,
          ),
        },
        outputNodeId: 'grain_5',
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
        },
        outputNodeId: 'grain_2',
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
