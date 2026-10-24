import '../../../domain/presets/preset_definition.dart';
import '../../../domain/presets/preset_parameter.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/style_render_nodes.dart';
import '../../../domain/recipes/artistic_render_nodes.dart';
import '../../../domain/recipes/adaptive_vibrancy_node.dart';

/// Batch B Presets (5 to 8):
/// 5. Anime Cel Shade
/// 6. Comic Book
/// 7. Flat Illustration
/// 8. Vintage Film
class BatchBPresets {
  static final animeCelShade = PresetDefinition(
    id: 'anime_cel_shade',
    displayName: 'Anime Cel Shade',
    category: 'Illustration & Comics',
    description: 'Crisp anime cel illustration with sharp contour line art and clean tonal fills.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'inkStrength',
        label: 'Cel Ink Strength',
        min: 0.3,
        max: 1.0,
        defaultValue: 0.75,
        step: 0.05,
      ),
      PresetParameter(
        id: 'celContrast',
        label: 'Cel Contrast',
        min: 1.0,
        max: 2.5,
        defaultValue: 1.35,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/anime_cel_shade.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Anime Cel Shade graphic illustration style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final inkStr = params['inkStrength'] ?? 0.75;
      final gamma = params['celContrast'] ?? 1.35;

      return RenderGraph(
        id: 'graph_anime_cel_shade',
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
          'cel_3': CelShadeColorNode(
            id: 'cel_3',
            colorInputNodeId: 'src_0',
            edgeInputNodeId: 'sobel_2',
            shadeLevels: 4,
            inkStrength: inkStr,
            contrastGamma: gamma,
          ),
          'vib_4': AdaptiveVibrancyNode(
            id: 'vib_4',
            inputNodeId: 'cel_3',
            vibrancy: 0.35,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_4',
      );
    },
  );

  static final comicBook = PresetDefinition(
    id: 'comic_book',
    displayName: 'Comic Book',
    category: 'Illustration & Comics',
    description: 'Vintage comic book with heavy dynamic ink outlines and aged pulp paper grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'inkWeight',
        label: 'Ink Weight',
        min: 0.5,
        max: 1.0,
        defaultValue: 0.90,
        step: 0.05,
      ),
      PresetParameter(
        id: 'pulpGrain',
        label: 'Pulp Grain',
        min: 0.05,
        max: 0.30,
        defaultValue: 0.16,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/comic_book.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Comic Book graphic print style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final ink = params['inkWeight'] ?? 0.90;
      final grain = params['pulpGrain'] ?? 0.16;

      return RenderGraph(
        id: 'graph_comic_book',
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
          'cel_3': CelShadeColorNode(
            id: 'cel_3',
            colorInputNodeId: 'src_0',
            edgeInputNodeId: 'sobel_2',
            shadeLevels: 3,
            inkStrength: ink,
            contrastGamma: 1.6,
          ),
          'grain_4': GrainOverlayNode(
            id: 'grain_4',
            inputNodeId: 'cel_3',
            intensity: grain,
            seed: 1962,
          ),
          'vib_5': AdaptiveVibrancyNode(
            id: 'vib_5',
            inputNodeId: 'grain_4',
            vibrancy: 0.30,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_5',
      );
    },
  );

  static final flatVector = PresetDefinition(
    id: 'flat_vector',
    displayName: 'Flat Vector',
    category: 'Illustration & Comics',
    description: 'Modern minimalist vector poster with simplified flat tones and subtle edge accents.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'vignette',
        label: 'Vector Edge Accent',
        min: 0.0,
        max: 0.60,
        defaultValue: 0.20,
        step: 0.05,
      ),
      PresetParameter(
        id: 'contrast',
        label: 'Poster Contrast',
        min: 0.8,
        max: 2.0,
        defaultValue: 1.20,
        step: 0.05,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/flat_vector.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Flat Vector modern graphic poster style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final vig = params['vignette'] ?? 0.20;
      final gamma = params['contrast'] ?? 1.20;

      return RenderGraph(
        id: 'graph_flat_vector',
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
          'cel_3': CelShadeColorNode(
            id: 'cel_3',
            colorInputNodeId: 'src_0',
            edgeInputNodeId: 'sobel_2',
            shadeLevels: 4,
            inkStrength: vig,
            contrastGamma: gamma,
          ),
          'vib_4': AdaptiveVibrancyNode(
            id: 'vib_4',
            inputNodeId: 'cel_3',
            vibrancy: 0.35,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_4',
      );
    },
  );

  /// Backward-compatible alias for [flatVector].
  static PresetDefinition get flatIllustration => flatVector;

  static final vintage35mm = PresetDefinition(
    id: 'vintage_35mm',
    displayName: 'Vintage 35mm',
    category: 'Film & Photography',
    description: 'Warm 1970s analog 35mm color print with lifted shadows and organic celluloid grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'fade',
        label: 'Analog Fade',
        min: 0.0,
        max: 0.60,
        defaultValue: 0.28,
        step: 0.05,
      ),
      PresetParameter(
        id: 'filmGrain',
        label: 'Celluloid Grain',
        min: 0.05,
        max: 0.25,
        defaultValue: 0.14,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/vintage_35mm.png',
    thumbnailProvenance: 'Synthetically generated from standard Reranger benchmark fixture via IsolateSceneMapGenerator',
    accessibleLabel: 'Vintage 35mm analog print style preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final fade = params['fade'] ?? 0.28;
      final grain = params['filmGrain'] ?? 0.14;

      return RenderGraph(
        id: 'graph_vintage_35mm',
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
            shadowR: 45,
            shadowG: 40,
            shadowB: 35,
            highlightR: 250,
            highlightG: 225,
            highlightB: 185,
            vignetteFalloff: fade,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'duo_1',
            intensity: grain,
            seed: 1974,
          ),
          'vib_3': AdaptiveVibrancyNode(
            id: 'vib_3',
            inputNodeId: 'grain_2',
            vibrancy: 0.25,
            contrast: 0.15,
          ),
        },
        outputNodeId: 'vib_3',
      );
    },
  );

  /// Backward-compatible alias for [vintage35mm].
  static PresetDefinition get vintageFilm => vintage35mm;

  static List<PresetDefinition> get all => [
    animeCelShade,
    comicBook,
    flatVector,
    vintage35mm,
  ];
}
