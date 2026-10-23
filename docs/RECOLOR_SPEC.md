# RERANGER — RECOLOR STUDIO SPECIFICATION & ARCHITECTURAL CONTRACT

**Document Version:** 1.0.0  
**Status:** **APPROVED SPECIFICATION & CONTRACT**  
**Prompt ID:** Prompt 18 — Recolor Studio  
**Role:** Color-Science-Aware Image Editing Engineer  
**Cross-References:** [`AGENTS.md`](file:///root/reranger/AGENTS.md), [`docs/PRD.md`](file:///root/reranger/docs/PRD.md), [`docs/ENGINE_SPEC.md`](file:///root/reranger/docs/ENGINE_SPEC.md), [`docs/SCENE_MAP_SPEC.md`](file:///root/reranger/docs/SCENE_MAP_SPEC.md), [`docs/PROJECT_FORMAT.md`](file:///root/reranger/docs/PROJECT_FORMAT.md)

---

## 1. Architectural Mission & Studio Identity

Recolor Studio is Reranger's region-aware, lighting-conscious, reversible color transformation environment. Designed for beginners, digital artists, and AI-art practitioners, it provides intuitive single-tap harmonic presets alongside granular color-science controls.

### Non-Negotiable Invariants:
1. **Source Image Immutability (Invariant 4):** Source media is strictly opened read-only and never modified or replaced.
2. **Offline-First Local Execution (Invariant 5):** 100% on-device compute; zero network calls or server offloading.
3. **Zero Telemetry / Compulsory Accounts (Invariant 6):** No user tracking or analytics.
4. **No Fake Controls or Illusory AI (Invariant 7):** Every slider, toggle, and harmonic chip maps directly to deterministic color math. Semantic categories (e.g. hair, clothing, skin) are exposed *only* when backed by a verified segmentation model; otherwise, truthful manual/tolerance selection is provided.
5. **Exact Unselected Region Protection:** Pixels with mask weight $M(x, y) = 0$ remain 100% byte-identical to the source ($R_{out} = R_{in}, G_{out} = G_{in}, B_{out} = B_{in}, A_{out} = A_{in}$).
6. **Alpha Channel Preservation:** Transparency is strictly preserved ($A_{out} \equiv A_{in}$).
7. **Luminance & Lighting Conservation:** Perceptual tonal structure (shadows, midtones, specular highlights) is preserved by isolating chrominance modulation from perceptual luminance.

---

## 2. Color Science & Mathematical Formulation

### 2.1 Perceptual Luminance Definition (BT.601 / Rec.709)
The engine utilizes ITU-R BT.601 integer luminance for deterministic mobile evaluation:
$$Y = \frac{299 \cdot R + 587 \cdot G + 114 \cdot B}{1000}$$
Where $R, G, B \in [0, 255]$ and $Y \in [0, 255]$.

### 2.2 Luminance-Preserving Chrominance Transfer
To prevent color replacement from destroying shadows, folds, and highlights, chrominance is transferred while strictly preserving $Y_{in}$:
1. Compute input pixel luminance: $Y_{in} = Y(R_{in}, G_{in}, B_{in})$.
2. Convert target replacement color to HSL: $(H_{tgt}, S_{tgt}, L_{tgt})$.
3. Construct intermediate RGB candidate $(R', G', B')$ using $(H_{tgt}, S_{tgt})$ at lightness $L_{in}$.
4. Compute intermediate candidate luminance: $Y' = Y(R', G', B')$.
5. Re-scale candidate RGB to match $Y_{in}$:
   $$k = \frac{Y_{in}}{\max(Y', 1)}$$
   $$R_{scaled} = \text{clamp}(R' \cdot k, 0, 255)$$
   $$G_{scaled} = \text{clamp}(G' \cdot k, 0, 255)$$
   $$B_{scaled} = \text{clamp}(B' \cdot k, 0, 255)$$
6. Single-pass integer residual correction guarantees exact tonal matching ($\pm 1$ discrete level):
   $$\Delta = Y_{in} - Y(R_{scaled}, G_{scaled}, B_{scaled})$$
   $$R_{final} = \text{clamp}(R_{scaled} + \Delta, 0, 255)$$
   $$G_{final} = \text{clamp}(G_{scaled} + \Delta, 0, 255)$$
   $$B_{final} = \text{clamp}(B_{scaled} + \Delta, 0, 255)$$

### 2.3 Monotonic Gradient Invariant
Given an input grayscale or shaded ramp where $Y(x) \le Y(x+1)$, luminance-preserving recoloring guarantees that $Y_{out}(x) \le Y_{out}(x+1)$. Shading continuity and depth falloff are preserved without contour posterization.

### 2.4 Low-Saturation & Neutral Protection
To prevent colorful chromatic noise from infecting neutral whites, grays, and blacks, chrominance modulation is weighted by the input pixel's saturation confidence:
$$\text{conf}_{sat} = \begin{cases} 1.0, & \text{if } S_{src} < 0.08 \text{ (user explicitly selected gray)} \\ \text{clamp}\left(\frac{S_{in}}{0.08}, 0.0, 1.0\right), & \text{otherwise} \end{cases}$$

---

## 3. Color Harmonies Engine

Given a primary anchor color with hue $H \in [0^\circ, 360^\circ)$, saturation $S \in [0, 1]$, and lightness $L \in [0, 1]$, the harmonies engine generates deterministic palettes:

| Harmony Name | Formula / Offsets | Count | Description |
|---|---|:---:|---|
| **Complementary** | Base, $(H + 180^\circ) \bmod 360^\circ$ | 2 | High-contrast opposite pairs on color wheel |
| **Analogous** | $(H - 30^\circ) \bmod 360^\circ$, Base, $(H + 30^\circ) \bmod 360^\circ$ | 3 | Harmonious adjacent colors with unified temperature |
| **Split-Complementary** | Base, $(H + 150^\circ) \bmod 360^\circ$, $(H + 210^\circ) \bmod 360^\circ$ | 3 | High contrast with softer, nuanced tension |
| **Triadic** | Base, $(H + 120^\circ) \bmod 360^\circ$, $(H + 240^\circ) \bmod 360^\circ$ | 3 | Vibrant balanced equilateral triangle |
| **Tetradic (Square)** | Base, $(H + 90^\circ) \bmod 360^\circ$, $(H + 180^\circ) \bmod 360^\circ$, $(H + 270^\circ) \bmod 360^\circ$ | 4 | Rich dual-complementary harmony |
| **Monochromatic** | $L \times 0.35, L \times 0.65, \text{Base}, \min(1.0, L \times 1.3)$ | 4 | Tonal gradient at fixed hue and saturation |

---

## 4. Region Masks & Mobile Repair Tool

### 4.1 Mask Representation
A [`RegionMask`](file:///root/reranger/lib/domain/color/recolor_mask.dart) is a discrete single-channel 8-bit buffer:
$$M(x, y) \in [0, 255]$$
Where $0$ indicates completely unselected, $255$ indicates completely selected, and intermediate values represent soft antialiased edges.

### 4.2 Generation Sources
1. **Color Euclidean Tolerance:**
   $$d = \frac{\sqrt{(R - R_{src})^2 + (G - G_{src})^2 + (B - B_{src})^2}}{255 \cdot \sqrt{3}}$$
   - If $d \le \text{tolerance}$: $M(x, y) = 255$.
   - If $\text{tolerance} < d \le \text{tolerance} + \text{feather}$: Smooth cubic Hermite interpolation:
     $$t = \frac{d - \text{tolerance}}{\text{feather}}, \quad M(x, y) = \text{round}\left(255 \cdot (1 - (3t^2 - 2t^3))\right)$$
   - If $d > \text{tolerance} + \text{feather}$: $M(x, y) = 0$.
2. **Scene Map Color Regions:**
   When the Analysis Bundle contains [`ColorRegionMapData`](file:///root/reranger/lib/domain/scene_map/color_region_map_data.dart), discrete cluster indices $k \in [0, K-1]$ can be directly extracted and upscaled with bilinear interpolation.
3. **Manual Selection Fallback (Honest UI):**
   If neural semantic segmentation is not present, the UI truthfully presents color-tolerance and Scene Map region selection, never fabricating fake AI labels.

### 4.3 Mobile Mask Repair Tool
To correct edge bleeding, halos, or occlusions directly on mobile touchscreens:
- **Paint Brush:** Circular kernel with smooth quadratic falloff adding opacity:
  $$M_{new} = \text{round}\left(M_{old} + (255 - M_{old}) \cdot (1 - r^2) \cdot \text{opacity}\right)$$
- **Eraser Brush:** Circular kernel removing opacity:
  $$M_{new} = \text{round}\left(M_{old} \cdot (1 - (1 - r^2) \cdot \text{opacity})\right)$$
- **Box / Gaussian Feathering:** Filter passes smoothing mask boundaries to prevent hard edge halo artifacts.
- **Invert / Clear:** Instant one-tap mask inversions and resets.

---

## 5. Render Graph Integration ([`RecolorNode`](file:///root/reranger/lib/domain/recipes/recolor_render_node.dart))

Recoloring is implemented as a first-class DAG node in [`RenderGraph`](file:///root/reranger/lib/domain/recipes/render_graph.dart):
- **Operation Type:** `recolor`
- **Inputs:** 1 parent node (source buffer)
- **Parameters:**
  - `sourceRGB`: integer `[R, G, B]`
  - `targetRGB`: integer `[R, G, B]`
  - `tolerance`: float in `[0.0, 1.0]` (default 0.20)
  - `feather`: float in `[0.0, 1.0]` (default 0.10)
  - `preserveLuminance`: boolean (default true)
  - `strength`: float in `[0.0, 1.0]` (default 1.0)
  - `maskBase64`: optional serialized mask buffer
- **Downstream Invalidation:** Changing any parameter or mask pixel derives a new SHA-256 cache key, invalidating dependent downstream caches while reusing upstream decoded textures.

---

## 6. Documented Limitations & Edge Cases

1. **Extreme Luminance Targets:** When recoloring near-black ($Y < 15$) or near-white ($Y > 240$) pixels, perceptual chroma gamut is physically constrained. Saturated colors cannot exist at $Y=0$ (pure black) or $Y=255$ (pure white).
2. **Transparent Boundaries:** Antialiased transparent edges contain blended background colors. The engine multiplies chrominance delta by input alpha to prevent color bleeding into invisible pixels.
3. **Specular Reflections:** Specular highlights have near-zero saturation and $Y \approx 255$. Preserving luminance naturally keeps specular reflections intact without painting them opaque.
