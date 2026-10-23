# RERANGER — USER JOURNEYS & UX ARCHITECTURE

## 1. Information Architecture & Progressive Disclosure Philosophy

Reranger is engineered with **beginner-friendliness as an absolute functional requirement**, not post-launch polish. Digital image editors often overwhelm beginners with technical jargon, histograms, coordinates, and floating-point parameters on first launch.

Reranger enforces a strict **Three-Tier Progressive Disclosure Model**:
1. **Level 1 (Beginner / Simple Mode):** High-level visual abstractions. One-tap preset tiles, single master Effect Strength slider, and immediate before/after preview. Technical engine internals, tensors, and raw coordinate matrices are completely hidden.
2. **Level 2 (Fine-Tune Mode):** User opt-in via a clean "Fine-Tune" trigger. Curated visual sliders (Warmth, Saturation, Contrast, Grain Scale) with intuitive visual feedback.
3. **Level 3 (Pro Tools Mode):** Dedicated to digital artists. Interactive tone curves, 256-bin RGB histograms, localized mask brushes, and numeric color matrix readouts.

---

## 2. Global Navigation & Back Behavior Map

```text
[App Launch]
     |
     v
[SCR-01: Home & Gallery] <---------------------------------------------+
     |                                                                 |
     +--- Tap "Select Image"                                           |
     |         |                                                       |
     |         v                                                       |
     |   [SCR-02: Image Import]                                        |
     |         | (Image loaded & cached)                               |
     |         v                                                       |
     |   [SCR-04: Editor Viewport] <-----------------------+           |
     |         |                                           |           |
     |         +--- [Beginner Mode: Presets + Intensity]   |           |
     |         +--- [Hold: Before/After Comparison]        |           |
     |         +--- [Tap "Fine-Tune" -> SCR-07 Sheet] -----+           |
     |         +--- [Tap "Pro Tools" -> SCR-08 Sheet] -----+           |
     |         +--- [Switch Studio: Recolor (SCR-09)] -----+           |
     |         +--- [Switch Studio: Humanize (SCR-10)] ----+           |
     |         |                                                       |
     |         +--- Tap "Export"                                       |
     |                   |                                             |
     |                   v                                             |
     |             [SCR-12: Render Progress]                           |
     |                   |                                             |
     |                   v                                             |
     |             [SCR-13: Export Complete] --------------------------+
     |
     +--- Tap "Creations / Projects" ---> [SCR-14: Project Variants] --+
     +--- Tap "Settings" -------------> [SCR-16: Settings Screen] -----+
```

### Back Button Navigation Hierarchy
- **From Sheet / Drawer (Fine-Tune / Pro Tools):** Back button or backdrop tap dismisses sheet to Editor Viewport (SCR-04); unsaved edits remain in active viewport session.
- **From Editor Viewport (SCR-04):** Back button checks project dirty state. If modified, presents non-destructive prompt ("Save to Creations", "Discard", or "Keep Editing").
- **From Home / Gallery (SCR-01):** Standard Android OS exit back to launcher.

---

## 3. Core User Journeys

### Journey 1: The Canonical Beginner 4-Decision Journey (P0)
The absolute core path for a first-time user to achieve a high-quality result in $< 30\text{ seconds}$:
1. **Decision 1 (Select Media):** User opens app $\rightarrow$ Taps prominent central button `Select Image` $\rightarrow$ System photo picker opens $\rightarrow$ User selects a photo.
2. **Decision 2 (Choose Style):** Editor opens immediately with source image. Horizontal carousel displays live visual preset cards $\rightarrow$ User taps `Golden Hour Glow`. Shader applies instant transformation in $< 100\text{ ms}$.
3. **Decision 3 (Tune Strength - Optional):** User adjusts single `Effect Strength` slider from $100\%$ to $75\%$ to soften effect.
4. **Decision 4 (Compare & Save):** User presses and holds `Compare` button to verify improvement over original $\rightarrow$ Releases $\rightarrow$ Taps primary `Save Image` button $\rightarrow$ Image renders and saves to gallery.

*Total User Decisions: Exactly 4 decisions. Zero technical setup, zero account creation, zero network prompts.*

---

### Journey 2: First-Run Onboarding & Zero-Friction Welcome (P0)
- **Step 1:** User launches Reranger for the very first time.
- **Step 2:** App opens directly to `SCR-01: Home & Gallery` in clean empty state.
- **Step 3:** Displays welcoming banner: *"100% On-Device Creative Studio. Your original photos are never overwritten."*
- **Step 4:** No sign-up wall, no email input, no tracking consent dialogs. User can immediately tap `Select Image`.

---

### Journey 3: Digital Artist Palette Recolor Journey (P1)
1. User loads a digital illustration into Editor Viewport.
2. Taps `Recolor Studio` tab on upper studio selector.
3. System extracts the dominant 5-color palette using on-device K-means clustering.
4. User taps the dominant blue color chip $\rightarrow$ Color picker opens $\rightarrow$ User selects deep indigo.
5. User opts into `Pro Tools` $\rightarrow$ Adjusts the Blue-channel Bézier tone curve to deepen contrast in the shadows.
6. Real-time histogram updates dynamically during curve manipulation.
7. User taps `Create Variant` to branch this colorway into `Variant B` without losing `Variant A`.

---

### Journey 4: AI-Art Humanize & De-Synthesizing Journey (Conditional / Gate B - P1)
1. User imports a synthetic AI-generated portrait with hyper-smooth, plastic skin textures.
2. Taps `Humanize Studio` tab.
3. **Pre-flight Probe:** App checks device RAM. If $\ge 6\text{ GB}$, unlocks studio; if $< 6\text{ GB}$, presents `SCR-11: Model Unavailable` explanation.
4. User selects `AI Plastic Glaze Reduction` preset.
5. Local LiteRT neural filter breaks up unnatural smoothness, restoring subtle micro-grain and pore texture.
6. User drags split-screen curtain to inspect the eyes and skin boundary at $300\%$ zoom.
7. Taps `Save Image` $\rightarrow$ Background isolate renders non-destructive output.

---

### Journey 5: Project Recovery & Crash Resilience Journey (P1)
1. User is actively working on a project with 12 customized adjustments.
2. Android OS terminates background process due to sudden memory pressure from another application.
3. User re-opens Reranger.
4. `SCR-01: Home` detects uncommitted project journal in local SQLite database.
5. Presents non-blocking recovery banner: *"Unsaved session found from 2 minutes ago. [Resume Editing] [Discard]"*.
6. User taps `Resume Editing` $\rightarrow$ Restores viewport with exact slider positions, active preset, and source image intact.

---

## 4. Error, Cancellation & Edge Case Journeys

### Journey 6A: User Cancellation of Long Render Pass
- During high-resolution export or heavy neural filter, a modal displays a progress ring with a prominent `Cancel` button.
- User taps `Cancel` $\rightarrow$ Worker isolate receives abort signal and cleans up temporary buffers within $50\text{ ms}$.
- Viewport returns to active editing state; project state is uncorrupted.

### Journey 6B: Corrupted / Unsupported Input File
- User selects a truncated or non-image file from external storage.
- Decoder catches byte validation error in background thread.
- User sees friendly dialog: *"Unable to open this image. Please select a valid JPEG, PNG, or WebP photo."*
- App remains on import screen without crashing.

### Journey 6C: Low Storage Warning on Export
- User initiates export, but device storage has $< 100\text{ MB}$ free space.
- Pre-flight disk check detects condition before writing bytes.
- Dialog alerts user: *"Device storage is nearly full. Please free up space before exporting."*
- Export is cleanly aborted; no 0-byte corrupted image created.

### Journey 6D: Model Unavailable / Device Incompatible State
- A user on a device with $< 6\text{ GB}$ RAM taps `Humanize Studio`.
- Screen displays clear graphic with informative message:
  *"Humanize Studio utilizes advanced on-device neural models requiring 6GB+ device RAM. Recolor Studio and Style & Render Studio are fully available on your device."*
- Includes a single CTA: `Back to Recolor Studio`.

---

## 5. Journey State Coverage Matrix

| User Journey | First-Run State | Idle / Default | Loading State | Empty State | Error State | Cancel State | Offline State | Model Unavail State |
|---|---|---|---|---|---|---|---|---|
| **J1: Beginner Core Flow** | Clean welcome banner | Viewport ready | Shader compiles $<100\text{ms}$ | Empty gallery | Format error prompt | Abort slider gesture | 100% functional | N/A |
| **J2: First Launch** | No accounts prompt | Ready to import | Fast launch $<1.2\text{s}$ | Zero projects card | Permissions denied info| Dismiss picker | 100% functional | N/A |
| **J3: Recolor Studio** | Auto-extracts palette | Palette chips active| K-means running $<150\text{ms}$ | Flat/solid color warning| Out-of-gamut indicator | Revert color chip | 100% functional | N/A |
| **J4: Humanize Studio** | Explains AI de-glaze | Preset tray active | Model inferring $<200\text{ms}$ | Mask empty | Memory headroom warn | Stop inference button | 100% functional | Informative dialog |
| **J5: Project Recovery** | N/A | Restored viewport | Journal parsing $<50\text{ms}$ | N/A | Corrupted db fallback | Discard recovered state| 100% functional | N/A |
| **J6: Export & Save** | Default to JPEG 95% | Ready to render | Export progress bar | N/A | Disk full dialog | Cancel export button | 100% functional | N/A |
