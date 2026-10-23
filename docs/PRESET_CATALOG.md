# RERANGER PRESET CATALOG SPECIFICATION

**Document Version:** 2.0.0  
**Status:** PRODUCTION APPROVED (Prompt 22 — 48 Canonical Presets Verified)  
**Governing Documents:** [AGENTS.md](file:///root/reranger/AGENTS.md), [PRD.md](file:///root/reranger/docs/PRD.md), [ENGINE_SPEC.md](file:///root/reranger/docs/ENGINE_SPEC.md), [GATE-C3.md](file:///root/reranger/docs/QA/GATE-C3.md)

---

## 1. Architectural Mission & Invariants

Reranger provides an offline-first, non-destructive image transformation studio. The Preset Catalog provides declarative, versioned style recipes built upon verified compute nodes within the deterministic Render Graph architecture.

### Non-Negotiable Invariants
1. **Source Image Immutability (Invariant 4):** Original user media and input images are opened read-only. Transformations execute via deterministic DAG graphs outputting fresh RGBA buffers without altering input sources.
2. **Offline-First Runtime (Invariant 5):** 100% on-device execution. Zero network calls or external API endpoints.
3. **Zero Telemetry or Accounts (Invariant 6):** No tracking, analytics SDKs, user accounts, or telemetry.
4. **No Placebo Controls (Invariant 7):** Every preset control maps to concrete mathematical parameters that measurably alter the rendered image. Every preset produces a distinct SHA-256 fingerprint on identical input. Stylized raster simulations (e.g. Clay Render, Low-Poly) are explicitly labeled as 2D simulations.
5. **Asset & Licensing Integrity (Invariant 10):** All 48 preset thumbnails are precomputed and bundled in `assets/preset_thumbnails/`, synthetically rendered on-device from standard benchmark fixtures with documented mathematical provenance. The gallery opens instantly without executing 48 full-resolution renders.
6. **Strict Memory Budgets (Invariant 11):** Node buffers are bounded ($W \times H \times 4\text{ bytes}$) with prompt GC and single-pass pipeline execution.

---

## 2. Canonical 48-Preset Catalog Matrix

The catalog contains exactly 48 verified presets organized across 6 canonical categories with exactly 8 presets each:

| # | Preset ID | Canonical Display Name | Category | Primary Node Pipeline | Parameters | Thumbnail Asset |
|---|---|---|---|---|---|---|
| **1** | `graphite_pencil` | Graphite Pencil | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Pencil Hardness, Paper Tooth | `assets/preset_thumbnails/graphite_pencil.png` |
| **2** | `soft_pencil` | Soft Pencil | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Lead Softness, Paper Tooth | `assets/preset_thumbnails/soft_pencil.png` |
| **3** | `charcoal` | Charcoal | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Charcoal Density, Smudge Tooth | `assets/preset_thumbnails/charcoal.png` |
| **4** | `fine_ink` | Fine Ink | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract | Ink Density, Contrast Curve | `assets/preset_thumbnails/fine_ink.png` |
| **5** | `crosshatch` | Crosshatch | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Hatch Density, Pen Contrast | `assets/preset_thumbnails/crosshatch.png` |
| **6** | `stipple` | Stipple | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Dot Density, Ink Weight | `assets/preset_thumbnails/stipple.png` |
| **7** | `blueprint` | Blueprint | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Line Crispness, Vignette Depth | `assets/preset_thumbnails/blueprint.png` |
| **8** | `contour_drawing` | Contour Drawing | Sketch & Line Art | Gray $\to$ Sobel $\to$ EdgeInvertSubtract | Stroke Weight, Contour Edge Boost | `assets/preset_thumbnails/contour_drawing.png` |
| **9** | `watercolor` | Watercolor | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Cold-Press Tooth, Wash Bleed Softness | `assets/preset_thumbnails/watercolor.png` |
| **10** | `wet_watercolor` | Wet Watercolor | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Wet Diffusion, Wash Bleed Curve | `assets/preset_thumbnails/wet_watercolor.png` |
| **11** | `oil_paint` | Oil Paint | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Linen Canvas Tooth, Impasto Contrast | `assets/preset_thumbnails/oil_paint.png` |
| **12** | `acrylic` | Acrylic | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Pigment Boldness, Acrylic Contrast | `assets/preset_thumbnails/acrylic.png` |
| **13** | `gouache` | Gouache | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Matte Opacity, Chalk Tooth | `assets/preset_thumbnails/gouache.png` |
| **14** | `soft_pastel` | Soft Pastel | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Powder Softness, Chalk Texture | `assets/preset_thumbnails/soft_pastel.png` |
| **15** | `ink_wash` | Ink Wash | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Sumi Ink Density, Brush Contrast | `assets/preset_thumbnails/ink_wash.png` |
| **16** | `palette_knife` | Palette Knife | Painting Studio | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Bevel Edge Sharpness, Impasto Contrast | `assets/preset_thumbnails/palette_knife.png` |
| **17** | `anime_cel_shade` | Anime Cel Shade | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract | Cel Ink Strength, Cel Contrast | `assets/preset_thumbnails/anime_cel_shade.png` |
| **18** | `manga_bw` | Manga B&W | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Screentone Pattern, Manga Inking | `assets/preset_thumbnails/manga_bw.png` |
| **19** | `comic_book` | Comic Book | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Ink Weight, Pulp Grain | `assets/preset_thumbnails/comic_book.png` |
| **20** | `graphic_novel` | Graphic Novel | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Inking Weight, Shadow Contrast | `assets/preset_thumbnails/graphic_novel.png` |
| **21** | `storybook_illustration` | Storybook Illustration | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Line Charm, Vignette Warmth | `assets/preset_thumbnails/storybook_illustration.png` |
| **22** | `flat_vector` | Flat Vector | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Vignette Depth, Poster Contrast | `assets/preset_thumbnails/flat_vector.png` |
| **23** | `editorial_illustration` | Editorial Illustration | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Contour Refinement, Editorial Contrast | `assets/preset_thumbnails/editorial_illustration.png` |
| **24** | `vintage_childrens_book` | Vintage Children's Book | Illustration & Comics | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Litho Aging Grain, Ink Bleed Weight | `assets/preset_thumbnails/vintage_childrens_book.png` |
| **25** | `cinematic_teal_orange` | Cinematic Teal & Orange | Film & Photography | DuoTone (Teal/Orange) $\to$ Grain | Cinematic Vignette, 35mm Film Grain | `assets/preset_thumbnails/cinematic_teal_orange.png` |
| **26** | `film_noir` | Film Noir | Film & Photography | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Shadow Contrast, Film Grain | `assets/preset_thumbnails/film_noir.png` |
| **27** | `vintage_35mm` | Vintage 35mm | Film & Photography | DuoTone (Warm Brown/Amber) $\to$ Grain | Analog Fade, Celluloid Grain | `assets/preset_thumbnails/vintage_35mm.png` |
| **28** | `faded_instant_film` | Faded Instant Film | Film & Photography | DuoTone (Milky Olive/Pale Cream) $\to$ Grain | Matte Lift Vignette, Celluloid Grit | `assets/preset_thumbnails/faded_instant_film.png` |
| **29** | `golden_hour` | Golden Hour | Film & Photography | DuoTone (Deep Sienna/Honey Gold) $\to$ Grain | Sunset Glow Falloff, Analog Texture | `assets/preset_thumbnails/golden_hour.png` |
| **30** | `cool_editorial` | Cool Editorial | Film & Photography | DuoTone (Slate/Silver) $\to$ Grain | Slate Vignette Depth, Fashion Film Grit | `assets/preset_thumbnails/cool_editorial.png` |
| **31** | `soft_portrait` | Soft Portrait | Film & Photography | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Diffusion Softness, Vignette Falloff | `assets/preset_thumbnails/soft_portrait.png` |
| **32** | `high_contrast_studio` | High-Contrast Studio | Film & Photography | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ Grain | Studio Key Gamma, Silver Gelatin Grain | `assets/preset_thumbnails/high_contrast_studio.png` |
| **33** | `halftone_pop_art` | Halftone Pop Art | Graphic & Retro | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Screen Dot Tooth, Pop Screen Contrast | `assets/preset_thumbnails/halftone_pop_art.png` |
| **34** | `duotone` | Duotone | Graphic & Retro | DuoTone (Indigo/Amber) | Vignette Falloff | `assets/preset_thumbnails/duotone.png` |
| **35** | `neon_cyberpunk` | Neon Cyberpunk | Graphic & Retro | DuoTone (Cyan/Hot Magenta) $\to$ Grain | Vignette Depth, Cyberpunk Noise Grit | `assets/preset_thumbnails/neon_cyberpunk.png` |
| **36** | `retro_poster` | Retro Poster | Graphic & Retro | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Poster Inking Weight, Vignette Depth | `assets/preset_thumbnails/retro_poster.png` |
| **37** | `screenprint` | Screenprint | Graphic & Retro | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Squeegee Pressure, Silk Mesh Grain | `assets/preset_thumbnails/screenprint.png` |
| **38** | `woodcut` | Woodcut | Graphic & Retro | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Gouge Carve Inking, Wood Fiber Grain | `assets/preset_thumbnails/woodcut.png` |
| **39** | `paper_cutout` | Paper Cutout | Graphic & Retro | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone | Cut Edge Inking, Layer Depth Falloff | `assets/preset_thumbnails/paper_cutout.png` |
| **40** | `stained_glass` | Stained Glass | Graphic & Retro | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Lead Came Outline Weight, Jewel Glow Falloff | `assets/preset_thumbnails/stained_glass.png` |
| **41** | `dreamy_bloom` | Dreamy Bloom | Experimental & Atmosphere | DuoTone (Lavender/Peach) $\to$ Grain | Halation Tooth, Ambient Glow Falloff | `assets/preset_thumbnails/dreamy_bloom.png` |
| **42** | `soft_matte_pastel` | Soft Matte Pastel | Experimental & Atmosphere | DuoTone (Muted Plum/Soft Peach) $\to$ Grain | Matte Haze Falloff, Chalk Powder Grain | `assets/preset_thumbnails/soft_matte_pastel.png` |
| **43** | `dark_academia` | Dark Academia | Experimental & Atmosphere | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Shadow Contrast Curve, Parchment Aging Tooth | `assets/preset_thumbnails/dark_academia.png` |
| **44** | `fantasy_luminance` | Fantasy Luminance | Experimental & Atmosphere | DuoTone (Mystic Violet/Starlight Gold) $\to$ Grain | Celestial Vignette Glow, Starlight Shimmer Grain | `assets/preset_thumbnails/fantasy_luminance.png` |
| **45** | `low_poly_facets` | Low-Poly Facets | Experimental & Atmosphere | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Facet Edge Contrast, Vignette Falloff | `assets/preset_thumbnails/low_poly_facets.png` |
| **46** | `clay_render` | Clay Render | Experimental & Atmosphere | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Diffuse Crease Occlusion, Matte Porosity Tooth | `assets/preset_thumbnails/clay_render.png` |
| **47** | `pixel_art` | Pixel Art | Experimental & Atmosphere | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Raster Tone Contrast, Phosphor CRT Grit | `assets/preset_thumbnails/pixel_art.png` |
| **48** | `infrared_film` | Infrared Film | Experimental & Atmosphere | Gray $\to$ Sobel $\to$ EdgeInvertSubtract $\to$ DuoTone $\to$ Grain | Aerochrome False Color, Infrared Halation Vignette | `assets/preset_thumbnails/infrared_film.png` |

---

## 3. Stylized Raster Simulation Disclosures (Invariant 7)

Per Invariant 7 (No Fake Controls or Illusory Capabilities):
- **`clay_render` (Clay Render)**: Stylized 2D raster simulation. Emulates smooth matte clay sculpture via high-radius edge occlusion, warm neutral terracotta duotone mapping, and low-amplitude surface porosity noise. It does not synthesize 3D meshes or normal maps.
- **`low_poly_facets` (Low-Poly Facets)**: Stylized 2D raster simulation. Emulates polygonal faceted lighting using quantized edge contrast, sharp contour thresholding, and cool geometric gradient remapping. It does not triangulate 3D vertex geometry.

---

## 4. Verification & Testing Evidence

All 48 presets are verified via automated CI test suites:
- `test/presets/preset_catalog_48_test.dart`:
  - Exactly 48 unique catalog IDs and canonical names.
  - Exactly 6 categories with 8 presets each.
  - Pairwise distinct SHA-256 fingerprints on identical input.
  - Parameter responsiveness verified for all 48 presets.
  - 100% deterministic execution across 4 benchmark fixture classes.
  - Source image immutability (Invariant 4) strictly proven.
  - Precomputed local thumbnail assets verified for all 48 presets.
