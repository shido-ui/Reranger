import '../../../domain/presets/preset_definition.dart';
import '../../../domain/presets/preset_parameter.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/style_render_nodes.dart';
import '../../../domain/recipes/adaptive_vibrancy_node.dart';

/// Batch A Presets (1 to 4):
/// 1. Graphite Pencil
/// 2. Fine Ink
/// 3. Film Noir
/// 4. Duotone
class BatchAPresets {
  static final graphitePencil = PresetDefinition(
    id: 'graphite_pencil',
    displayName: 'Graphite Pencil',
    category: 'Sketch & Line Art',
    description: 'Delicate hand-drawn pencil sketch on fine paper with soft tonal shading.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'pencilHardness',
        label: 'Pencil Hardness',
        min: 0.2,
        max: 1.0,
        defaultValue: 0.65,
        step: 0.05,
      ),
      PresetParameter(
        id: 'grainIntensity',
        label: 'Paper Tooth',
        min: 0.02,
        max: 0.10,
        defaultValue: 0.05,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/graphite_pencil.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Graphite Pencil artistic sketch style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final hardness = params['pencilHardness'] ?? 0.65;
      final grain = params['grainIntensity'] ?? 0.05;

      return RenderGraph(
        id: 'graph_graphite_pencil',
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
            invertOutput: false,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: hardness,
            contrastGamma: 1.0 + hardness * 0.8,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'ink_3',
            intensity: grain,
            seed: 101,
          ),
        },
        outputNodeId: 'grain_4',
      );
    },
  );

  static final fineInk = PresetDefinition(
    id: 'fine_ink',
    displayName: 'Fine Ink',
    category: 'Sketch & Line Art',
    description: 'High-contrast graphic ink etching with deep blacks and crisp line work.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'inkDensity',
        label: 'Ink Density',
        min: 0.4,
        max: 1.0,
        defaultValue: 0.85,
        step: 0.05,
      ),
      PresetParameter(
        id: 'contrast',
        label: 'Contrast Curve',
        min: 1.0,
        max: 3.0,
        defaultValue: 1.6,
        step: 0.1,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/fine_ink.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Fine Ink etching graphic style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final density = params['inkDensity'] ?? 0.85;
      final gamma = params['contrast'] ?? 1.6;

      return RenderGraph(
        id: 'graph_fine_ink',
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
            edgeIntensity: density,
            contrastGamma: gamma,
          ),
        },
        outputNodeId: 'ink_3',
      );
    },
  );

  static final filmNoir = PresetDefinition(
    id: 'film_noir',
    displayName: 'Film Noir',
    category: 'Film & Photography',
    description: '1940s cinematic monochrome with dramatic deep shadows and authentic 35mm grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'contrast',
        label: 'Shadow Contrast',
        min: 1.2,
        max: 2.8,
        defaultValue: 2.0,
        step: 0.1,
      ),
      PresetParameter(
        id: 'grain',
        label: 'Film Grain',
        min: 0.05,
        max: 0.30,
        defaultValue: 0.16,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/film_noir.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Film Noir cinematic black and white style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final gamma = params['contrast'] ?? 2.0;
      final grain = params['grain'] ?? 0.16;

      return RenderGraph(
        id: 'graph_film_noir',
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
            edgeThreshold: 70,
          ),
          'ink_3': EdgeInvertSubtractNode(
            id: 'ink_3',
            grayInputNodeId: 'gray_1',
            edgeInputNodeId: 'sobel_2',
            edgeIntensity: 0.35,
            contrastGamma: gamma,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'ink_3',
            intensity: grain,
            seed: 1947,
          ),
        },
        outputNodeId: 'grain_4',
      );
    },
  );

  static final duotone = PresetDefinition(
    id: 'duotone',
    displayName: 'Duotone',
    category: 'Graphic & Retro',
    description: 'Modern editorial split-toning between deep indigo shadows and warm amber highlights.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'vignette',
        label: 'Vignette Falloff',
        min: 0.0,
        max: 0.8,
        defaultValue: 0.35,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/duotone.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Duotone indigo and amber split-toning style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final vignette = params['vignette'] ?? 0.35;

      return RenderGraph(
        id: 'graph_duotone',
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
            shadowR: 24,
            shadowG: 28,
            shadowB: 64,
            highlightR: 255,
            highlightG: 210,
            highlightB: 140,
            vignetteFalloff: vignette,
          ),
          'vib_2': AdaptiveVibrancyNode(
            id: 'vib_2',
            inputNodeId: 'duo_1',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_2',
      );
    },
  );

  static List<PresetDefinition> get all => [
    graphitePencil,
    fineInk,
    filmNoir,
    duotone,
  ];
}
