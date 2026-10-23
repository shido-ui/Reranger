import '../../../domain/presets/preset_definition.dart';
import 'batch_a_presets.dart';
import 'batch_b_presets.dart';
import 'batch_c_presets.dart';
import 'expanded_presets.dart';

/// Central canonical registry for Reranger's artistic style presets.
/// Provides safe lookup, category filtering, and access to all 48 validated presets.
class PresetCatalog {
  PresetCatalog._();

  /// Canonical list of all 48 verified presets across 6 categories (8 per category).
  static final List<PresetDefinition> all = List.unmodifiable([
    // Category 1: Sketch & Line Art (1 to 8)
    BatchAPresets.graphitePencil,
    ExpandedPresets.softPencil,
    ExpandedPresets.charcoal,
    BatchAPresets.fineInk,
    ExpandedPresets.crosshatch,
    ExpandedPresets.stipple,
    ExpandedPresets.blueprint,
    ExpandedPresets.contourDrawing,

    // Category 2: Painting Studio (9 to 16)
    BatchCPresets.watercolor,
    ExpandedPresets.wetWatercolor,
    BatchCPresets.oilPaint,
    ExpandedPresets.acrylic,
    ExpandedPresets.gouache,
    ExpandedPresets.softPastel,
    ExpandedPresets.inkWash,
    ExpandedPresets.paletteKnife,

    // Category 3: Illustration & Comics (17 to 24)
    BatchBPresets.animeCelShade,
    ExpandedPresets.mangaBw,
    BatchBPresets.comicBook,
    ExpandedPresets.graphicNovel,
    ExpandedPresets.storybookIllustration,
    BatchBPresets.flatVector,
    ExpandedPresets.editorialIllustration,
    ExpandedPresets.vintageChildrensBook,

    // Category 4: Film & Photography (25 to 32)
    ExpandedPresets.cinematicTealOrange,
    BatchAPresets.filmNoir,
    BatchBPresets.vintage35mm,
    ExpandedPresets.fadedInstantFilm,
    ExpandedPresets.goldenHour,
    ExpandedPresets.coolEditorial,
    ExpandedPresets.softPortrait,
    ExpandedPresets.highContrastStudio,

    // Category 5: Graphic & Retro (33 to 40)
    BatchCPresets.halftonePopArt,
    BatchAPresets.duotone,
    ExpandedPresets.neonCyberpunk,
    ExpandedPresets.retroPoster,
    ExpandedPresets.screenprint,
    ExpandedPresets.woodcut,
    ExpandedPresets.paperCutout,
    ExpandedPresets.stainedGlass,

    // Category 6: Experimental & Atmosphere (41 to 48)
    BatchCPresets.dreamyBloom,
    ExpandedPresets.softMattePastel,
    ExpandedPresets.darkAcademia,
    ExpandedPresets.fantasyLuminance,
    ExpandedPresets.lowPolyFacets,
    ExpandedPresets.clayRender,
    ExpandedPresets.pixelArt,
    ExpandedPresets.infraredFilm,
  ]);

  static final Map<String, PresetDefinition> _byId = {
    for (final p in all) p.id: p,
    // Backward-compatible alias lookups:
    'flat_illustration': BatchBPresets.flatVector,
    'vintage_film': BatchBPresets.vintage35mm,
    'default_natural': BatchAPresets.graphitePencil,
  };

  /// Canonical default preset for new projects and fallback migrations.
  static PresetDefinition get defaultPreset => all.first;
  static String get defaultPresetId => defaultPreset.id;

  /// Returns preset definition by unique [id], or `null` if not found.
  static PresetDefinition? getById(String id) => _byId[id];

  /// Returns true if a preset with [id] is registered (including legacy aliases).
  static bool containsId(String id) => _byId.containsKey(id);

  /// Returns list of all presets belonging to [category].
  static List<PresetDefinition> getByCategory(String category) =>
      all.where((p) => p.category == category).toList(growable: false);

  /// Returns distinct list of all registered categories in canonical appearance order.
  static List<String> get categories {
    final seen = <String>{};
    final result = <String>[];
    for (final p in all) {
      if (seen.add(p.category)) {
        result.add(p.category);
      }
    }
    return List.unmodifiable(result);
  }
}
