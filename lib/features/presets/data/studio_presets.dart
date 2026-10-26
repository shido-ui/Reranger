import '../../../domain/presets/preset_definition.dart';
import '../../../domain/presets/preset_parameter.dart';
import '../../../domain/recipes/adaptive_vibrancy_node.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/style_render_nodes.dart';

/// Hyper-premium Studio Presets and Utility Pass-Through Presets.
class StudioPresets {
  StudioPresets._();

  /// Pure pass-through preset (ID: original) with no visual transformations.
  /// Allows users to strip C2PA/EXIF metadata without altering pixel content.
  static final original = PresetDefinition(
    id: 'original',
    displayName: 'Original',
    category: 'Studio',
    description: 'Pure pass-through with zero visual alterations. Preserves 100% of image pixel fidelity while stripping C2PA and EXIF metadata.',
    version: 1,
    parameters: const [],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_portrait.png',
    thumbnailProvenance:
        'Synthetically generated from standard Reranger benchmark fixture',
    accessibleLabel: 'Original unmodified source image pass-through',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      return RenderGraph(
        id: 'graph_original',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
        },
        outputNodeId: 'src_0',
      );
    },
  );

  /// 1. Cinematic Teal & Orange Studio Preset
  static final cinematicTealOrange = PresetDefinition(
    id: 'studio_cinematic_teal_orange',
    displayName: 'Cinematic Teal & Orange',
    category: 'Studio',
    description: 'Hollywood blockbuster cinematic color grading with rich split-toning in CIELAB color space and fine analog film grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'studioStrength',
        label: 'Studio Strength',
        min: 0.0,
        max: 1.0,
        defaultValue: 1.0,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/cinematic_teal_orange.png',
    thumbnailProvenance:
        'Synthetically generated from standard Reranger benchmark fixture',
    accessibleLabel: 'Cinematic Teal and Orange hyper-premium studio preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final strength = params['studioStrength'] ?? 1.0;

      return RenderGraph(
        id: 'graph_studio_cinematic_teal_orange',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'vib_1': AdaptiveVibrancyNode(
            id: 'vib_1',
            inputNodeId: 'src_0',
            vibrancy: 0.35 * strength,
            contrast: 0.25 * strength,
            splitTone: 'cinematic',
            splitToneStrength: strength,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'vib_1',
            intensity: 0.04 * strength,
            seed: 101,
          ),
        },
        outputNodeId: 'grain_2',
      );
    },
  );

  /// 2. Ethereal Portrait Studio Preset
  static final etherealPortrait = PresetDefinition(
    id: 'studio_ethereal_portrait',
    displayName: 'Ethereal Portrait',
    category: 'Studio',
    description: 'Dreamy, soft-focus magazine portrait aesthetic with delicate pastel highlights and skin tone protection.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'studioStrength',
        label: 'Studio Strength',
        min: 0.0,
        max: 1.0,
        defaultValue: 1.0,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_portrait.png',
    thumbnailProvenance:
        'Synthetically generated from standard Reranger benchmark fixture',
    accessibleLabel: 'Ethereal Portrait hyper-premium studio preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final strength = params['studioStrength'] ?? 1.0;

      return RenderGraph(
        id: 'graph_studio_ethereal_portrait',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'vib_1': AdaptiveVibrancyNode(
            id: 'vib_1',
            inputNodeId: 'src_0',
            vibrancy: 0.20 * strength,
            contrast: 0.10 * strength,
            splitTone: 'ethereal',
            splitToneStrength: strength,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'vib_1',
            intensity: 0.03 * strength,
            seed: 202,
          ),
        },
        outputNodeId: 'grain_2',
      );
    },
  );

  /// 3. Vintage Film Pro Studio Preset
  static final vintageFilmPro = PresetDefinition(
    id: 'studio_vintage_film_pro',
    displayName: 'Vintage Film Pro',
    category: 'Studio',
    description: 'Authentic 35mm chemical emulsion rendition with warm nostalgic shadows and organic halation grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'studioStrength',
        label: 'Studio Strength',
        min: 0.0,
        max: 1.0,
        defaultValue: 1.0,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/vintage_35mm.png',
    thumbnailProvenance:
        'Synthetically generated from standard Reranger benchmark fixture',
    accessibleLabel: 'Vintage Film Pro hyper-premium studio preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final strength = params['studioStrength'] ?? 1.0;

      return RenderGraph(
        id: 'graph_studio_vintage_film_pro',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'vib_1': AdaptiveVibrancyNode(
            id: 'vib_1',
            inputNodeId: 'src_0',
            vibrancy: 0.20 * strength,
            contrast: 0.22 * strength,
            splitTone: 'vintage',
            splitToneStrength: strength,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'vib_1',
            intensity: 0.04 * strength,
            seed: 303,
          ),
        },
        outputNodeId: 'grain_2',
      );
    },
  );

  /// 4. Cyberpunk Neon Studio Preset
  static final cyberpunkNeon = PresetDefinition(
    id: 'studio_cyberpunk_neon',
    displayName: 'Cyberpunk Neon',
    category: 'Studio',
    description: 'High-energy futuristic neon aesthetic with hyper-saturated cyan/magenta contrast curves and deep noir shadows.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'studioStrength',
        label: 'Studio Strength',
        min: 0.0,
        max: 1.0,
        defaultValue: 1.0,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/neon_cyberpunk.png',
    thumbnailProvenance:
        'Synthetically generated from standard Reranger benchmark fixture',
    accessibleLabel: 'Cyberpunk Neon hyper-premium studio preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final strength = params['studioStrength'] ?? 1.0;

      return RenderGraph(
        id: 'graph_studio_cyberpunk_neon',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'vib_1': AdaptiveVibrancyNode(
            id: 'vib_1',
            inputNodeId: 'src_0',
            vibrancy: 0.65 * strength,
            contrast: 0.35 * strength,
            splitTone: 'cyberpunk',
            splitToneStrength: strength,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'vib_1',
            intensity: 0.03 * strength,
            seed: 404,
          ),
        },
        outputNodeId: 'grain_2',
      );
    },
  );

  /// 5. Soft Pastel Dream Studio Preset
  static final softPastelDream = PresetDefinition(
    id: 'studio_soft_pastel_dream',
    displayName: 'Soft Pastel Dream',
    category: 'Studio',
    description: 'Whimsical storybook aesthetic with delicate low-contrast pastel tones, smooth luminance compression, and soft paper grain.',
    version: 1,
    parameters: const [
      PresetParameter(
        id: 'studioStrength',
        label: 'Studio Strength',
        min: 0.0,
        max: 1.0,
        defaultValue: 1.0,
        step: 0.01,
      ),
    ],
    thumbnailAssetPath: 'assets/preset_thumbnails/soft_pastel.png',
    thumbnailProvenance:
        'Synthetically generated from standard Reranger benchmark fixture',
    accessibleLabel: 'Soft Pastel Dream hyper-premium studio preset',
    buildGraph: (sourceHash, sourceWidth, sourceHeight, params) {
      final strength = params['studioStrength'] ?? 1.0;

      return RenderGraph(
        id: 'graph_studio_soft_pastel_dream',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
          ),
          'vib_1': AdaptiveVibrancyNode(
            id: 'vib_1',
            inputNodeId: 'src_0',
            vibrancy: 0.25 * strength,
            contrast: 0.08 * strength,
            splitTone: 'pastel',
            splitToneStrength: strength,
          ),
          'grain_2': GrainOverlayNode(
            id: 'grain_2',
            inputNodeId: 'vib_1',
            intensity: 0.03 * strength,
            seed: 505,
          ),
        },
        outputNodeId: 'grain_2',
      );
    },
  );

  /// List of all 5 locked studio presets.
  static final List<PresetDefinition> allStudioPresets = List.unmodifiable([
    cinematicTealOrange,
    etherealPortrait,
    vintageFilmPro,
    cyberpunkNeon,
    softPastelDream,
  ]);
}
