# RERANGER — SCREEN SPECIFICATIONS & INTERACTION ARCHITECTURE

## 1. Overview & UI Design Constraints
This document provides exact engineering specifications for all 16 application screens and view states in Reranger.

### Core Architectural UI Constraints
1. **Dominant Call-To-Action (CTA):** At most **one** prominent visual CTA per screen to eliminate user hesitation.
2. **Four-Decision Core Flow:** Beginners must be able to import, style, tune, and save with $\le 4$ user decisions.
3. **Progressive Disclosure:** Advanced technical controls (curves, histograms, tensors, coordinates) are strictly opt-in.
4. **Touch Targets:** All interactive elements must measure at least $48 \times 48\text{ dp}$ with explicit `Semantics` tags.
5. **Design Token Compliance:** All typography, colors, elevations, spacing, and shapes strictly reference the tokens defined in `docs/DESIGN_SYSTEM.md`.

---

## 1.1 System-Wide Design Token Mapping
- **Canvas Viewports:** `color.bg.canvas` (`#121214` Dark / `#F8F9FA` Light)
- **Chrome & Sheets:** `color.surface.base` (`#1E1E22` Dark / `#FFFFFF` Light)
- **Elevated Modals & Chips:** `color.surface.elevated` (`#2A2A30` Dark / `#F0F1F4` Light)
- **Primary Action (CTA):** `color.accent.primary` (`#8A7BFF` Dark / `#5843D8` Light) with `radius.full` ($9999\text{ dp}$) and `typography.label.large`
- **Typography Scale:** Roboto font family; Titles `typography.title.*`, Body `typography.body.*`, Labels `typography.label.*`
- **Borders & Dividers:** `color.border.subtle` (`#3E3E48` Dark / `#E2E4E8` Light)
- **Touch Target Padding:** Minimum $48 \times 48\text{ dp}$ bounding box across all controls

---

## 2. Screen Specifications

---

### SCR-01: Home & Project Gallery Screen
- **Screen Title:** Home / Gallery
- **Target Audience:** All Users (Beginners, Artists, AI Creators)
- **Primary CTA ($\le 1$):** `Select Image` (Large floating pill button at bottom center).
- **Secondary Actions:** `Settings` icon (top right app bar), `Open Project` card tap (recent projects list).
- **Layout Hierarchy:**
  - Top Bar: App Wordmark ("RERANGER") + Settings Icon.
  - Body:
    - Empty State (First-run): Clean illustration of image transformation + welcome headline *"100% On-Device Photo Transformation. Non-destructive & Private."*
    - Non-Empty State: Grid of recent project creation cards with thumbnail, date, and active studio mode badge.
  - Bottom Bar: Elevated Primary CTA button `Select Image` with icon.
- **Responsive Adaptations ($\ge 600\text{ dp}$):** Gallery switches to a 3-column responsive grid; Primary CTA remains centered with max width $320\text{ dp}$.
- **State Specifications:**
  - *Default:* Displays grid of recent local projects.
  - *Empty:* Encouraging onboarding illustration with arrow pointing to `Select Image`.
  - *Loading:* Subtle shimmer over project thumbnail cards during initial SQLite query ($< 100\text{ ms}$).
  - *Error:* SnackBar alert if recent project database fails to read, defaulting to empty state.
- **Tooltip Strategy:**
  - *Useful:* Long-press on a project card displays tooltip: *"Press and hold to rename or delete project"*.
  - *Noise:* No tooltip on the primary `Select Image` button.
- **Accessibility:** Header semantics labeled *"Home Gallery"*; project cards include accessibility label *"Project [Name], modified [Date]"*.

---

### SCR-02: Image Import & Preparation Screen
- **Screen Title:** Select Image
- **Target Audience:** All Users
- **Primary CTA ($\le 1$):** System Photo Picker launcher.
- **Secondary Actions:** Cancel / Back arrow to SCR-01.
- **Layout Hierarchy:** Invokes standard Android Photo Picker (`ActivityResultContracts.PickVisualMedia`) for privacy isolation.
- **State Specifications:**
  - *Cancellation:* User taps back button in photo picker $\rightarrow$ returns cleanly to SCR-01 without state changes.
  - *Permission Denied:* Informational dialog explaining why media access is required, offering retry or settings shortcut.

---

### SCR-03: Image Analysis & Staging Screen
- **Screen Title:** Preparing Canvas
- **Target Audience:** All Users
- **Primary CTA ($\le 1$):** None (transient loading state $< 300\text{ ms}$).
- **Secondary Actions:** `Cancel` button (if processing takes $> 1000\text{ ms}$).
- **Layout Hierarchy:** Minimalist centered spinner with status message: *"Optimizing image for real-time preview..."*.
- **State Specifications:**
  - *Loading:* Worker isolate generates preview mipmaps and computes initial EXIF orientation.
  - *Error:* If image byte stream is corrupted, displays `ERR-006` dialog with `Back to Gallery` button.

---

### SCR-04: Core Editor Viewport Screen (Beginner Simple View)
- **Screen Title:** Editor Viewport
- **Target Audience:** Beginners by default; host container for Pro sheets.
- **Primary CTA ($\le 1$):** `Save Image` (Top right prominent button).
- **Secondary Actions:**
  - `Studio Mode Selector` (Segmented pill: Recolor | Style & Render | Humanize).
  - `Undo / Redo` icons (top bar).
  - `Compare` (Hold-to-compare button overlay on canvas).
  - `Fine-Tune` expander button (bottom tray header).
- **Layout Hierarchy:**
  - Top Bar: `Back` icon | Undo | Redo | Studio Selector | `Save Image` CTA.
  - Center Viewport: Interactive image canvas rendering fragment shader with pinch-zoom.
  - Canvas Floating Action: `Compare` button (floating pill at bottom right of canvas).
  - Bottom Panel:
    - Master Slider: `Effect Strength` ($0\% \text{ to } 100\%$, default $100\%$).
    - Preset Carousel: Horizontal scrolling list of preset cards with real-time thumbnail previews.
    - Sheet Pull-Tab: "Fine-Tune Options" expander chevron.
- **Responsive Adaptations ($\ge 600\text{ dp}$):** Canvas occupies left $65\%$ of screen; Preset carousel and controls move to a fixed right-side inspector panel.
- **State Specifications:**
  - *Default:* Active image displayed with selected preset applied at $100\%$ intensity.
  - *Hold-to-Compare:* Canvas instantly reverts to raw source texture while pressed; re-renders shader on release.
  - *Cancellation:* Back button prompts user to save project if modifications exist.
- **Tooltip Strategy:**
  - *Useful:* Pulsing hint on first edit: *"Press and hold Compare to see original image"*. Dismisses on first tap.
  - *Noise:* No tooltips on Undo/Redo or slider handle.
- **Accessibility:** `Compare` button semantics: *"Hold to view original image, release to view transformed image"*.

---

### SCR-05: Style & Preset Gallery Tray (Beginner Carousel)
- **Screen Title:** Preset Tray (Embedded in SCR-04)
- **Target Audience:** Beginners
- **Primary CTA ($\le 1$):** Tap on individual Preset Card.
- **Secondary Actions:** Horizontal category filter pills (All, Paint, Graphic, Lighting, Film).
- **Layout Hierarchy:**
  - Horizontal scrolling row of $80 \times 100\text{ dp}$ cards.
  - Card layout: Aspect-fit preview thumbnail + bold preset name below + active selection ring.
- **State Specifications:**
  - *Selection:* Tapping a card immediately dispatches new shader uniform configuration ($< 50\text{ ms}$).
  - *Active State:* Selected card highlighted with primary accent border and subtle scale spring animation.

---

### SCR-06: Before / After Split-Screen Curtain View
- **Screen Title:** Split Comparison View
- **Target Audience:** All Users
- **Primary CTA ($\le 1$):** `Done` / Release Curtain.
- **Secondary Actions:** Flip vertical/horizontal split orientation.
- **Layout Hierarchy:**
  - Center canvas divided by a vertical touch-draggable splitter line.
  - Left side label: "ORIGINAL"; Right side label: "TRANSFORMED".
- **Responsive Adaptations:** Divider draggable across full width; adapts to portrait and landscape orientation.
- **State Specifications:**
  - *Drag:* Real-time clipping of two shader draw passes at 60 FPS.

---

### SCR-07: Fine-Tune Parameter Bottom Sheet (Level 2 Disclosure)
- **Screen Title:** Fine-Tune Parameters
- **Target Audience:** Intermediate Users & Digital Artists
- **Primary CTA ($\le 1$):** Auto-applies changes in real-time to preview mipmap.
- **Secondary Actions:** `Reset per-control` (individual parameter reset button), `Reset All` (header action), `Open Pro Tools` text button in footer.
- **Layout Hierarchy:**
  - Draggable modal bottom sheet expanding to $75\%$ max screen height.
  - Header: "Fine-Tune Adjustments" + active recipe subtitle + "Reset All" action button + close button.
  - Parametric Sliders list:
    - Dynamically populated strictly with parameters relevant to the active recipe (e.g. `Pencil Hardness`, `Paper Tooth` for Graphite Pencil).
    - Plain-language labels and explanatory subtitles (e.g. *"Controls stroke intensity and edge line sharpness"*).
    - Dedicated refresh/reset icon per slider row returning the individual parameter to its default.
  - Footer: Prominent link *"Need layers, masks & history? Open Pro Tools $\rightarrow$"*.
- **State Specifications:**
  - *Real-Time Update:* Dragging any slider directly dispatches updated recipe graph to worker isolate.
  - *Reset-Per-Control:* Tapping the reset icon next to an altered control restores only that parameter to baseline.
  - *Reset-All:* Restores all recipe parameters to preset defaults.
  - *Zero Technical Jargon:* Internal variables, tensor shapes, and matrix labels are strictly hidden.

---

### SCR-08: Pro Tools Modal Sheet (Level 3 Disclosure)
- **Screen Title:** Pro Tools Studio
- **Target Audience:** Digital Artists & Advanced Power Users
- **Primary CTA ($\le 1$):** `Done` (top right, closes sheet returning cleanly to Simple viewport).
- **Secondary Actions:** 4-tab studio navigation bar (`Layers & Masks`, `History`, `Curtain & Variants`, `Output`).
- **Layout Hierarchy:**
  - Modal studio sheet expanding to $85\%$ screen height with `Material` backing.
  - Header: "Pro Tools Studio" + active recipe badge + prominent `Done` button.
  - Tab 1 (`Layers & Masks`):
    - Visual layer stack with `LOCKED BASE` immutable source layer (Invariant 4).
    - Adjustment layers with opacity slider, blend mode selector (`NORMAL`, `MULTIPLY`, `SCREEN`, `OVERLAY`, `SOFTLIGHT`), visibility toggle, and delete action.
    - `Add Tint Layer` action button.
  - Tab 2 (`History & Timeline`):
    - Bounded-memory command delta stack with live undo/redo counters.
    - Quick actions: `Undo`, `Redo`, `Undo All`, `Redo All`.
  - Tab 3 (`Curtain & Variants`):
    - `Show Split Curtain` toggle with draggable split position control (SCR-06).
    - `Variant Board` (SCR-14) listing all branched variants with `Branch Variant` action button.
  - Tab 4 (`Output & Render`):
    - Render scale selector (`50% Fast Preview`, `100% Full Master`).
    - Export format choice (`PNG Lossless`, `JPEG High Quality`).
- **State Specifications:**
  - *Non-Destructive Operations:* Source media is never mutated (Invariant 4).
  - *Bounded Memory:* Command history bounded at 100 entries (< 100 KB RAM) (Invariant 11).
  - *Effortless Exit:* Tapping `Done` or outside the sheet instantly returns to the primary simple editor viewport.

---

### SCR-09: Recolor Studio (Palette Extraction & Color Remapping View)
- **Screen Title:** Recolor Studio
- **Target Audience:** Digital Artists
- **Primary CTA ($\le 1$):** `Extract New Palette` / `Apply Palette`.
- **Secondary Actions:** Individual color chip tap, HSL color wheel adjustment, Harmonies dropdown.
- **Layout Hierarchy:**
  - Upper Viewport: Canvas preview.
  - Lower Panel:
    - Dominant Palette Bar: Row of 5 circular color chips extracted via K-means clustering.
    - Color Remap Wheel: Tapping any chip opens an interactive HSL color wheel to remap that specific color range.
    - Harmonic Presets: Complementary, Analogous, Triadic, Monochromatic pills.
- **State Specifications:**
  - *Extraction:* During image load, K-means runs in background isolate ($< 150\text{ ms}$).
  - *Remapping:* Shader shifts hue and chroma of targeted cluster with smooth falloff.

---

### SCR-10: Humanize Studio (Conditional / Gate B View)
- **Screen Title:** Humanize Studio
- **Target Audience:** AI-Art Users & Photographers
- **Primary CTA ($\le 1$):** `De-Synthesize & Enhance` button.
- **Secondary Actions:** Mode selector (Organic Skin, Micro-Grain, Halation, Edge Balance).
- **Layout Hierarchy:**
  - Pre-flight check verifies device hardware meets requirements ($\ge 6\text{ GB}$ RAM).
  - Viewport: Zoomable split comparison canvas.
  - Bottom Panel: Specialized de-glazing sliders:
    - Plastic Glaze Reduction ($0\% \text{ to } 100\%$)
    - Analog Film Halation ($0\% \text{ to } 100\%$)
    - Anatomical Asymmetry ($0\% \text{ to } 100\%$)
- **State Specifications:**
  - *Inference Running:* Displays non-blocking progress ring over canvas; cancel button active.
  - *Model Loading:* Progress message *"Preparing on-device neural model (100% offline)..."*.

---

### SCR-11: Model Unavailable / Device Incompatible State View
- **Screen Title:** Studio Compatibility Notice
- **Target Audience:** Users on devices with $< 6\text{ GB}$ RAM or missing neural delegates.
- **Primary CTA ($\le 1$):** `Back to Recolor Studio`.
- **Secondary Actions:** `View Hardware Specifications` (expands device RAM and OS details).
- **Layout Hierarchy:**
  - Centered informational card with clean, non-alarming graphic.
  - Headline: *"Humanize Studio Unavailable on this Device"*.
  - Body: *"Humanize Studio requires at least 6GB of device RAM to run local neural inference safely without crashing. Recolor Studio and Style & Render Studio are fully supported and operational."*
  - Primary CTA button: `Back to Recolor Studio`.
- **State Specifications:** Zero error codes or stack traces displayed; clear and friendly explanation.

---

### SCR-12: High-Resolution Render Queue & Progress Modal
- **Screen Title:** Rendering Image
- **Target Audience:** All Users
- **Primary CTA ($\le 1$):** `Cancel Render` (Outlined secondary button).
- **Secondary Actions:** None (modal prevents background interaction).
- **Layout Hierarchy:**
  - Dialog modal with linear progress bar + percentage text ($0\% \rightarrow 100\%$).
  - Current pass label: *"Applying transformations..."* $\rightarrow$ *"Encoding JPEG..."*.
- **State Specifications:**
  - *Cancellation:* Tapping `Cancel Render` sends interrupt signal to worker isolate; closes modal in $< 50\text{ ms}$.
  - *Success:* Closes automatically and transitions to SCR-13.

---

### SCR-13: Export & Share Options Screen
- **Screen Title:** Image Saved
- **Target Audience:** All Users
- **Primary CTA ($\le 1$):** `Done / Back to Home`.
- **Secondary Actions:** `Share Image` (invokes Android system share sheet), `View in Device Gallery`.
- **Layout Hierarchy:**
  - Top: Large success checkmark badge + headline *"Saved to Photos"*.
  - Center: Preview card of exported image with resolution and file size badge (e.g. "4032 x 3024 • 3.4 MB JPEG").
  - Bottom: `Share Image` outlined button + Primary `Done` filled button.
- **State Specifications:**
  - *File Verification:* Computes exported file SHA-256 and verifies file exists on storage before showing success.

---

### SCR-14: Project History & Variants Management View
- **Screen Title:** Project Variants
- **Target Audience:** Digital Artists & Power Users
- **Primary CTA ($\le 1$):** `Create New Variant`.
- **Secondary Actions:** Select active variant, duplicate variant, delete variant.
- **Layout Hierarchy:**
  - Grid of variant cards (Variant A: Original Style, Variant B: Warm Tone, Variant C: High Contrast).
  - Tapping a variant loads that recipe tree into the active viewport without re-decoding image bytes.

---

### SCR-15: Crash Recovery Prompt Dialog
- **Screen Title:** Recover Unsaved Session
- **Target Audience:** Users after unexpected OS process kill.
- **Primary CTA ($\le 1$):** `Resume Editing` (Filled button).
- **Secondary Actions:** `Discard Unsaved Edits` (Text button).
- **Layout Hierarchy:**
  - System alert dialog displayed over SCR-01 on launch if uncommitted dirty journal exists.
  - Text: *"We found an unsaved editing session from [Time/Date]. Would you like to resume where you left off?"*.
- **State Specifications:**
  - *Resume:* Rehydrates project state and opens SCR-04 directly.
  - *Discard:* Purges dirty journal and displays standard home gallery.

---

### SCR-16: Settings & Storage Management Screen
- **Screen Title:** Settings & Device Diagnostics
- **Target Audience:** All Users
- **Primary CTA ($\le 1$):** `Clear Temporary Cache` (Outlined button).
- **Secondary Actions:** Dark/Light theme toggle, About Reranger, License Attribution link.
- **Layout Hierarchy:**
  - Section 1 (Privacy & Storage): Private Sandbox Storage used ($XX\text{ MB}$), Clear Cache button.
  - Section 2 (Rendering Performance): Hardware acceleration status (GPU Vulkan / Impeller active).
  - Section 3 (About): Version 1.0.0, 100% Offline Notice, Open-Source Licenses.
- **State Specifications:**
  - *Clear Cache:* Removes preview thumbnails and temporary files; shows toast *"14.2 MB cache cleared"*. Original source images and saved project recipes remain untouched.
