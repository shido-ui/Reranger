# RERANGER — PRODUCT REQUIREMENTS DOCUMENT (PRD)

## 1. Executive Summary & Architectural Mission
Reranger is an Android-first, production-grade Flutter mobile application delivering an offline-first image-transformation studio for beginners, digital artists, and AI-art users.

The core mission is empowering creators with non-destructive, high-performance image transformations without relying on remote servers, mandatory accounts, or invasive telemetry. All projects, media, transformations, and models execute 100% locally on-device.

### Core Functional Studios
1. **Recolor Studio**: Real-time palette extraction, localized color remapping, and harmonic adjustments.
2. **Style & Render Studio**: Fine-grained texture synthesis, stylistic rendering, and artistic shader transformations.
3. **Humanize Studio**: Local on-device ML/diffusion-guided refinement transforming synthetic AI art into authentic, natural aesthetics (proof-gated under Gate B).

---

## 2. Target User Personas & Value Propositions

| Persona | Core Need | Key Value Proposition | Primary Mode Used |
|---|---|---|---|
| **Beginner Creator** | Rapid, effortless visual improvement without steep digital art learning curves. | Single-tap presets, one-slider intensity control, instant live preview, zero jargon. | Beginner / Simple Mode |
| **Digital Artist** | Precise color harmony manipulation, structural control, and non-destructive experimentation. | Interactive HSL color wheels, tone curves, histogram analysis, localized mask brushes. | Fine-Tune & Pro Tools |
| **AI-Art Creator** | Mitigate plastic textures, unnatural glaze, and hyper-symmetrical synthetic artifacts from diffusion models. | Organic micro-grain injection, edge de-sharpening, anatomical balancing, film halation. | Humanize Studio |

---

## 3. Explicit Non-Goals & Scope Boundaries

- **NON-GOAL 1: No Cloud Image Processing or Remote Inference.** Zero server-side rendering or offloaded pipelines. If an operation cannot execute locally, it will not be supported.
- **NON-GOAL 2: No Compulsory Accounts, Authentication, or Sign-ups.** Zero user registration gates, cloud logins, or identity collection.
- **NON-GOAL 3: No Social Feeds or Community Platforms.** No in-app feed, user follows, comments, likes, or social sharing network integrations.
- **NON-GOAL 4: No Remote Telemetry or Tracking.** Zero analytics SDKs, crash beacons, or covert network requests.
- **NON-GOAL 5: No AI-Detection Evasion Claims.** Reranger does not claim or market "invisibility" against AI detectors; all transformations serve aesthetic and creative authenticity.
- **NON-GOAL 6: No Full Photoshop Replacement in v1.** No multi-layer vector typography, Pen-tool Bézier paths, or CMYK prepress raster image processors.

---

## 4. Progressive Disclosure Hierarchy

```text
+-------------------------------------------------------------------------+
| LEVEL 1: BEGINNER / SIMPLE MODE                                         |
| - Horizontal carousel of Preset Cards with real-time visual thumbnails |
| - Master Intensity Slider (0% - 100%)                                   |
| - Instant Before/After Split-Screen Hold Toggle                         |
+-------------------------------------------------------------------------+
                                    | (Tap "Fine-Tune")
                                    v
+-------------------------------------------------------------------------+
| LEVEL 2: FINE-TUNE MODE                                                 |
| - Curated sliders: Warmth, Saturation, Contrast, Edge Retention        |
| - Palette Extraction Pill: view dominant 5-color palette               |
| - Texture Scale & Grain Depth Controls                                  |
+-------------------------------------------------------------------------+
                                    | (Tap "Pro Tools")
                                    v
+-------------------------------------------------------------------------+
| LEVEL 3: PRO TOOLS MODE                                                 |
| - Live RGB / Luminance Real-time Histogram                              |
| - Interactive 5-point Bézier Tone Curves (RGB & Master)                 |
| - Localized Brush Masking with feathering & eraser                     |
| - Precise numeric matrix math and coordinate readouts                   |
+-------------------------------------------------------------------------+
```

---

## 5. Planned Preset Catalogue (48 Canonical Presets across 6 Categories)

> [!NOTE]
> All 48 planned presets are listed below. Each preset name appears exactly once. Initial release presets are quality-gated and released progressively based on verified performance benchmarks.

### Category 1: Color Harmonies & Palettes (Recolor Studio)
1. **Analogous Warm**
2. **Complementary Split**
3. **Triadic Pop**
4. **Monochromatic Slate**
5. **Tetradic Dynamic**
6. **Pastel Dream**
7. **Cyberpunk Neon**
8. **Earthy Terracotta**

### Category 2: Atmospheric & Lighting Shifts (Recolor Studio)
9. **Golden Hour Glow**
10. **Midnight Blue**
11. **Crimson Sunset**
12. **Emerald Forest**
13. **Nordic Frost**
14. **Desert Mirage**
15. **Dusk Twilight**
16. **Bioluminescent Depths**

### Category 3: Artistic Media & Paint (Style & Render Studio)
17. **Classical Oil Impasto**
18. **Wet Watercolor Bleed**
19. **Gouache Matte**
20. **Charcoal Sketch**
21. **Sumi-e Ink Wash**
22. **Fresco Plaster**
23. **Acrylic Palette Knife**
24. **Encaustic Wax**

### Category 4: Graphic & Printmaking (Style & Render Studio)
25. **Risograph Duotone**
26. **Halftone Newsprint**
27. **Linocut Relief**
28. **Vintage Woodblock**
29. **Screenprint CMYK**
30. **Copperplate Etching**
31. **Pop Art Litho**
32. **Cyanotype Blueprint**

### Category 5: Natural Imperfection & Film Texture (Humanize Studio - Conditional)
33. **Subtle Film Grain 35mm**
34. **Organic Micro-Texture**
35. **Medium Format Halation**
36. **Daguerreotype Patina**
37. **Vintage Polaroid Fade**
38. **Dust & Cellulose**
39. **Ambient Lens Bloom**
40. **Thermal Diffusion**

### Category 6: AI De-Synthesizing & Natural Form (Humanize Studio - Conditional)
41. **Organic Skin Softening**
42. **AI Plastic Glaze Reduction**
43. **Edge De-sharpening**
44. **Asymmetric Facial Balance**
45. **Natural Iris Refraction**
46. **Hand Anatomy Realism**
47. **Micro-Specular Balance**
48. **Atmospheric Depth Falloff**

---

## 6. Comprehensive Requirement Specifications

### 6.1 Functional Requirements (FR)

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **FR-001** | P0 | Non-destructive image import from device storage. | Read original media read-only via Android Photo Picker; create internal staging copy. Source image hash remains untouched. | `TC-FR-001` | Prompt 05 |
| **FR-002** | P0 | Real-time viewport preview for Recolor Studio presets. | GPU fragment shader pipeline rendering interactive preset adjustments at 60 FPS without modifying original buffer. | `TC-FR-002` | Prompt 06 |
| **FR-003** | P0 | Master intensity slider adjusting transformation strength. | Float uniform `uIntensity` ($0.0 \le x \le 1.0$) passed to active shader. | `TC-FR-003` | Prompt 06 |
| **FR-004** | P0 | Real-time split-screen before/after comparison. | Canvas split-wipe gesture comparing original source texture against processed shader texture. | `TC-FR-004` | Prompt 06 |
| **FR-005** | P0 | High-resolution non-destructive image export. | Background isolate rendering full-resolution output to new JPEG/PNG file with preserved metadata. | `TC-FR-005` | Prompt 07 |
| **FR-006** | P1 | Dominant color palette extraction in Recolor Studio. | K-means color clustering extracting top 5 dominant HEX colors with single-tap replacement. | `TC-FR-006` | Prompt 08 |
| **FR-007** | P1 | Style & Render artistic texture synthesis. | GPU shader convolution applying physical medium simulation (oil, watercolor, halftone). | `TC-FR-007` | Prompt 09 |
| **FR-008** | P1 | Variants and Creation history branching. | Tree-based transformation snapshot graph allowing users to branch, compare, and revert versions. | `TC-FR-008` | Prompt 10 |
| **FR-009** | P1 | Local project state persistence & recovery. | SQLite/JSON project recipe saving transformations; restores identical state on app relaunch. | `TC-FR-009` | Prompt 10 |
| **FR-010** | P2 | Fine-tune parameter control panel. | Slider controls for Warmth, Saturation, Contrast, and Grain Scale with numerical readout. | `TC-FR-010` | Prompt 11 |
| **FR-011** | P2 | Pro Tools interactive tone curves. | 5-point cubic Bézier curve editor mapping luminance transfer functions. | `TC-FR-011` | Prompt 12 |
| **FR-012** | P2 | Pro Tools real-time RGB histogram. | Real-time compute pass calculating 256-bin RGB luminance distribution. | `TC-FR-012` | Prompt 12 |
| **FR-013** | P2 | Localized brush masking for selective edits. | Touch-driven mask canvas generating single-channel alpha mask for localized transformation. | `TC-FR-013` | Prompt 13 |
| **FR-014** | P1 | Full Undo, Redo, and Reset to Original. | Stack-based command pattern supporting unlimited undos within session and single-tap reset. | `TC-FR-014` | Prompt 06 |
| **FR-015** | P2 | Custom user preset creation and export. | Serialize active slider and curve state into a shareable local JSON preset file. | `TC-FR-015` | Prompt 14 |

---

### 6.2 Non-Functional & Quality Requirements (NFR)

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **NFR-001** | P0 | Guaranteed source media immutability. | Enforce POSIX read-only flags on input media paths; SHA-256 hash verified before and after operations. | `TC-NFR-001` | Prompt 05 |
| **NFR-002** | P0 | Zero network dependencies at runtime. | Strict airplane-mode test execution; app manifests contain zero network/internet permissions. | `TC-NFR-002` | Prompt 05 |
| **NFR-003** | P0 | Strict Android memory headroom budget. | Peak heap memory usage must remain $< 300\text{ MB}$ during live preview and $< 500\text{ MB}$ during 12MP export. | `TC-NFR-003` | Prompt 07 |
| **NFR-004** | P0 | Zero memory leaks across studio transitions. | Disposing studio views and resetting project releases all native C++ pointers and GPU textures. | `TC-NFR-004` | Prompt 07 |
| **NFR-005** | P1 | Thermal protection & CPU throttling prevention. | Heavy render passes limit CPU thread pool to $N-1$ cores with duty-cycle pauses if thermal state reaches WARNING. | `TC-NFR-005` | Prompt 09 |
| **NFR-006** | P1 | Crash resilience & automatic project rehydration. | Atomic file writes for project state; dirty state journal recovers unexported edits on restart. | `TC-NFR-006` | Prompt 10 |
| **NFR-007** | P1 | Permissive license compliance across all dependencies. | Zero GPL/AGPL dependencies; all bundled libraries use MIT, Apache-2.0, or BSD-3. | `TC-NFR-007` | Prompt 04 |
| **NFR-008** | P2 | Fast application cold launch. | App launches to interactive home gallery in $< 1200\text{ ms}$ on mid-tier hardware. | `TC-NFR-008` | Prompt 05 |

---

### 6.3 User Experience & Progressive Disclosure Requirements (UX)

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **UX-001** | P0 | Beginner-first immediate feedback. | Tapping any preset card applies visual transformation in $< 100\text{ ms}$ with no configuration needed. | `TC-UX-001` | Prompt 06 |
| **UX-002** | P1 | Smooth progressive disclosure transition. | Single-tap accordion expands from Beginner cards to Fine-Tune sliders, then to Pro Tools. | `TC-UX-002` | Prompt 11 |
| **UX-003** | P0 | Interactive before/after split viewer. | Drag handle allows side-by-side or sliding curtain comparison between source and current state. | `TC-UX-003` | Prompt 06 |
| **UX-004** | P1 | Tactile haptic feedback on discrete steps. | Gentle Android haptic tick when crossing threshold points (0%, 50%, 100%) on sliders. | `TC-UX-004` | Prompt 06 |
| **UX-005** | P1 | Zoom and pan inspection on high-res canvas. | Interactive matrix viewer supporting two-finger pinch-to-zoom up to 800% with sub-pixel rendering. | `TC-UX-005` | Prompt 08 |
| **UX-006** | P2 | Visual indication of active modifications. | Dot badge on modified parameter tabs; single tap resets individual parameter to default. | `TC-UX-006` | Prompt 11 |
| **UX-007** | P2 | Orientation adaptation for tablets and foldables. | Responsive layout adjusting controls to side drawer on screens $\ge 600\text{ dp}$ width. | `TC-UX-007` | Prompt 14 |

---

### 6.4 Privacy & Local Runtime Requirements (PRIV)

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **PRIV-001** | P0 | Total data isolation & local storage. | All images, cached thumbnails, and project files reside in private app sandbox storage. | `TC-PRIV-001` | Prompt 05 |
| **PRIV-002** | P0 | Zero analytics, telemetry, or third-party tracking SDKs. | Source code and binary audit confirms absence of Firebase Analytics, Sentry, Mixpanel, or ads SDKs. | `TC-PRIV-002` | Prompt 04 |
| **PRIV-003** | P0 | No mandatory user account or authentication gates. | Immediate access to full studio suite on first app launch with zero account barriers. | `TC-PRIV-003` | Prompt 05 |
| **PRIV-004** | P1 | Transparent local storage management. | Settings view displays exact disk space occupied by project cache with single-tap cache purge. | `TC-PRIV-004` | Prompt 14 |

---

### 6.5 Machine Learning & Humanize Studio Requirements (ML — CONDITIONAL / GATE B)

> [!WARNING]
> All ML requirements are CONDITIONAL and gated under Gate B ("Proof-Gated Humanize Model Integration"). They must not be enabled in production UI until hardware memory budgets and latency benchmarks are proven on target devices.

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **ML-001** | P1 (Cond) | On-device semantic segmentation for selective recoloring. | LiteRT (`flutter_litert`) INT8 model generating subject/background/sky segmentation mask. | `TC-ML-001` | Gate B / Prompt 15 |
| **ML-002** | P1 (Cond) | AI plastic glaze reduction & texture de-smoothing. | Local neural residual filter breaking up over-smoothed synthetic skin/hair textures. | `TC-ML-002` | Gate B / Prompt 15 |
| **ML-003** | P2 (Cond) | Micro-halation & organic lens aberration synthesis. | Local CNN/shader model simulating physical analog optical halation on high-contrast edges. | `TC-ML-003` | Gate B / Prompt 16 |
| **ML-004** | P2 (Cond) | Hardware compatibility probe & graceful fallback. | Pre-flight probe checking available RAM ($\ge 6\text{ GB}$) and NNAPI/GPU delegate before activating ML studio. | `TC-ML-004` | Gate B / Prompt 15 |
| **ML-005** | P2 (Cond) | Local model asset management & verification. | Verify SHA-256 checksum and OpenRAIL / Apache-2.0 license integrity of downloaded/bundled weights. | `TC-ML-005` | Gate B / Prompt 16 |
| **ML-006** | P2 (Cond) | Memory-capped background inference execution. | Run inference in isolated process with hard limit $< 1.5\text{ GB}$ peak RAM to avoid Android OOM kills. | `TC-ML-006` | Gate B / Prompt 16 |

---

### 6.6 Performance & Frame Rate Requirements (PERF)

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **PERF-001** | P0 | Fluid 60 FPS viewport preview under user interaction. | Fragment shader uniforms update within $16.6\text{ ms}$ budget during slider manipulation. | `TC-PERF-001` | Prompt 06 |
| **PERF-002** | P1 | Full-resolution 12MP export latency under budget. | Non-destructive export of a 12MP image completes in $< 2500\text{ ms}$ on mid-tier ARM64 CPU. | `TC-PERF-002` | Prompt 07 |
| **PERF-003** | P1 | Fast preset switching time. | Switching between presets in beginner carousel reflects in viewport in $< 150\text{ ms}$. | `TC-PERF-003` | Prompt 06 |
| **PERF-004** | P1 | Background isolate concurrency for heavy compute. | CPU-intensive image decoding and encoding never blocks the main Flutter UI isolate. | `TC-PERF-004` | Prompt 05 |
| **PERF-005** | P2 | Low battery and thermal draw during idle editing. | GPU render passes pause when user stops interacting (0 FPS render loop when static). | `TC-PERF-005` | Prompt 08 |
| **PERF-006** | P2 | Efficient memory reclamation on project exit. | Closing project returns allocated memory within 50 MB of baseline application footprint. | `TC-PERF-006` | Prompt 07 |

---

### 6.7 Accessibility Requirements (A11Y)

| Requirement ID | Priority | User Value | Implementation Scope | Observable Acceptance Test | Target Milestone |
|---|---|---|---|---|---|
| **A11Y-001** | P1 | Screen reader compatibility for all controls. | All interactive buttons, sliders, and preset cards provide informative `Semantics` labels. | `TC-A11Y-001` | Prompt 14 |
| **A11Y-002** | P1 | High contrast touch target sizing. | Minimum interactive touch target size of $48 \times 48\text{ dp}$ conforming to Material accessibility guidelines. | `TC-A11Y-002` | Prompt 06 |
| **A11Y-003** | P2 | Color-blind accessible palette indicators. | Color chips provide text labels (e.g. "Warm Ochre #C68642") alongside visual colors. | `TC-A11Y-003` | Prompt 08 |
| **A11Y-004** | P2 | Dynamic text scaling support. | UI text scales gracefully up to 200% system font size without layout clipping or text overflow. | `TC-A11Y-004` | Prompt 14 |

---

## 7. Error Handling, Failure States & Edge Cases

| Error State ID | Trigger Condition | System Behavior & Mitigation | User-Facing Notification |
|---|---|---|---|
| **ERR-001** (Cancellation) | User cancels long-running export or ML inference pass. | Instantly terminate background worker isolate / cancel native job; clean up temporary buffers; leave project state intact. | Toast: "Operation cancelled." |
| **ERR-002** (Undo / Reset) | User taps Reset to Original or performs repeated undos. | Revert active parameter state to clean baseline; shader uniforms reset instantly; source image untouched. | SnackBar with "Undo Reset" action. |
| **ERR-003** (Permissions) | Android media read permission denied or restricted. | App handles denial gracefully without crashing; explains why permission is needed and offers Photo Picker fallback. | Dialog: "Media access needed to select images. You can use the private system photo picker." |
| **ERR-004** (Model Unavailable) | Device lacks compatible NPU/GPU or has insufficient RAM ($<6\text{ GB}$). | Disable Humanize Studio option with clear rationale; core Recolor and Style studios remain fully functional. | Banner: "Humanize Studio requires 6GB+ RAM. Recolor and Style Studios are fully operational." |
| **ERR-005** (Low Storage) | Target storage volume has $< 100\text{ MB}$ free space before export. | Pre-flight check detects low storage before initiating export pass; aborts before writing to avoid corrupted partial files. | Dialog: "Insufficient storage space to export image. Please free up space and try again." |
| **ERR-006** (Corrupted Input) | Selected input file has invalid headers or truncated byte stream. | Image decoder safely catches format exception in background isolate; rejects file without crashing UI. | Dialog: "Unable to read image file. The file may be damaged or in an unsupported format." |
| **ERR-007** (Unsupported Format) | User selects animated GIF, RAW, or unsupported image container. | File inspector validates MIME type and magic bytes; reports supported formats (JPEG, PNG, WebP). | Toast: "Unsupported image format. Please select a JPEG, PNG, or WebP image." |
| **ERR-008** (App Restart / Crash) | Application process is terminated by OS in background. | On next launch, dirty journal in SQLite detects unexported session; prompts user to restore unsaved project. | Banner: "Previous session recovered. Tap to resume editing." |
| **ERR-009** (Export Failure) | I/O exception or out-of-memory error during high-res rendering. | Clean up partial destination file; free intermediate memory; log error to local audit trail; preserve project recipe. | Dialog: "Export could not be completed. Your project edits are safely preserved." |

---

## 8. Definition of Done (DoD)
A requirement or vertical slice is considered DONE only when:
1. **Source Immutability Verified**: Automated test confirms source file SHA-256 is unchanged.
2. **Offline Execution Verified**: Executes without error with network completely disabled.
3. **No Fake Controls**: Every UI button or slider directly controls verified underlying math/shader/engine code.
4. **Automated Acceptance Test Passes**: The mapped test case in `docs/ACCEPTANCE_CRITERIA.md` passes with observable log evidence.
5. **Static Analysis & Formatting Clean**: `dart analyze` reports 0 errors and 0 warnings; `dart format` is clean.
6. **Bounded Change Budget**: Modified files conform to the prompt file cap ($\le 8$ files per prompt).
