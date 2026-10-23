# RERANGER — ACCEPTANCE CRITERIA & TEST CATALOGUE

## 1. Overview & Verification Standard
This document defines the formal, observable acceptance criteria for Reranger. Every requirement defined in the Product Requirements Document (`docs/PRD.md`) maps 1:1 to a specific test case in this catalogue.

All tests require observable command outputs, log assertions, or automated test passes to be marked complete.

---

## 2. Functional Acceptance Tests (FR)

### TC-FR-001: Non-destructive image import (FR-001)
- **Preconditions:** A sample source image (`sample_source.png`) exists on the filesystem with known SHA-256 hash.
- **Execution Steps:**
  1. Trigger image import workflow via app repository.
  2. Compute SHA-256 hash of `sample_source.png` immediately before import.
  3. Load image into editing session.
  4. Compute SHA-256 hash of `sample_source.png` immediately after import.
- **Pass/Fail Criteria:** PASS if pre-import and post-import SHA-256 hashes are strictly identical; source file permissions remain read-only; internal working copy created in app sandbox.
- **Verification Method:** Automated unit test: `test/core/source_immutability_test.dart`.

### TC-FR-002: Real-time viewport preview for Recolor Studio (FR-002)
- **Preconditions:** An image is loaded into Recolor Studio; fragment shader program initialized.
- **Execution Steps:**
  1. Select preset "Analogous Warm".
  2. Measure time elapsed between preset tap and canvas frame render.
- **Pass/Fail Criteria:** PASS if transformed frame displays in $< 100\text{ ms}$; source image buffer in memory remains unaltered; shader renders via GPU.
- **Verification Method:** Widget & render benchmark test.

### TC-FR-003: Master intensity slider adjustment (FR-003)
- **Preconditions:** Active preset applied to viewport.
- **Execution Steps:**
  1. Set slider value to $0.0$.
  2. Set slider value to $0.5$.
  3. Set slider value to $1.0$.
- **Pass/Fail Criteria:** PASS if at $0.0$ canvas output visually and mathematically matches original image; at $1.0$ full transformation is rendered; uniform updates without UI isolate block.
- **Verification Method:** Golden image test comparing shader output at $0.0$, $0.5$, $1.0$.

### TC-FR-004: Real-time split-screen before/after comparison (FR-004)
- **Preconditions:** Transformation applied with intensity $> 0.5$.
- **Execution Steps:**
  1. Drag split-screen curtain divider across the viewport from left to right.
- **Pass/Fail Criteria:** PASS if pixels to the left of the divider show unmodified source image; pixels to the right show transformed output; divider drag maintains 60 FPS.
- **Verification Method:** Touch interaction widget test.

### TC-FR-005: High-resolution non-destructive image export (FR-005)
- **Preconditions:** Project has active transformations; destination path selected.
- **Execution Steps:**
  1. Trigger Export action (format: JPEG, quality 95).
  2. Verify export execution in background isolate.
  3. Inspect exported file on disk.
- **Pass/Fail Criteria:** PASS if new exported file exists at destination path; dimensions match original source image; source file hash unchanged; EXIF orientation preserved.
- **Verification Method:** Integration test: `test/export/export_pipeline_test.dart`.

### TC-FR-006: Dominant color palette extraction (FR-006)
- **Preconditions:** Image with distinct color zones loaded.
- **Execution Steps:**
  1. Request palette extraction.
  2. Inspect returned palette chips.
- **Pass/Fail Criteria:** PASS if exactly 5 dominant colors are extracted with valid HEX color values; tapping a color opens the replacement color picker.
- **Verification Method:** Unit test: `test/recolor/palette_extractor_test.dart`.

### TC-FR-007: Style & Render texture synthesis (FR-007)
- **Preconditions:** Image loaded into Style & Render Studio.
- **Execution Steps:**
  1. Select preset "Classical Oil Impasto".
  2. Verify canvas texture overlay and brush stroke simulation.
- **Pass/Fail Criteria:** PASS if stylistic texture renders without artifacts or seams; master intensity adjusts depth of paint strokes.
- **Verification Method:** Fragment shader integration test.

### TC-FR-008: Variants and Creation history branching (FR-008)
- **Preconditions:** Editing session with multiple sequential modifications.
- **Execution Steps:**
  1. Tap "Create Variant".
  2. Modify parameters in Variant B.
  3. Switch back to Variant A.
- **Pass/Fail Criteria:** PASS if Variant A parameter state is perfectly preserved; switching variants takes $< 50\text{ ms}$; no image re-decoding required.
- **Verification Method:** State management unit test: `test/state/project_variants_test.dart`.

### TC-FR-009: Local project state persistence & recovery (FR-009)
- **Preconditions:** Project edited with custom slider and preset values.
- **Execution Steps:**
  1. Save project state to local database.
  2. Simulate app termination.
  3. Re-open project from local storage.
- **Pass/Fail Criteria:** PASS if all sliders, active preset, curves, and variants restore to exact numerical values before termination.
- **Verification Method:** Repository persistence test: `test/data/project_repository_test.dart`.

### TC-FR-010: Fine-tune parameter control panel (FR-010)
- **Preconditions:** User in Level 2 Fine-Tune mode.
- **Execution Steps:**
  1. Adjust Warmth slider to $+25$.
  2. Adjust Saturation to $-15$.
  3. Adjust Contrast to $+10$.
- **Pass/Fail Criteria:** PASS if each slider independently alters the respective uniform in the shader; numeric badges display $+25$, $-15$, $+10$.
- **Verification Method:** Widget parameter binding test.

### TC-FR-011: Pro Tools interactive tone curves (FR-011)
- **Preconditions:** User in Level 3 Pro Tools mode.
- **Execution Steps:**
  1. Drag mid-tone curve control point upward.
  2. Verify luminance transfer function recomputes.
- **Pass/Fail Criteria:** PASS if cubic Bézier interpolation generates monotonic 256-entry lookup table; output image brightens proportionally.
- **Verification Method:** Math unit test: `test/curves/bezier_lut_test.dart`.

### TC-FR-012: Pro Tools real-time RGB histogram (FR-012)
- **Preconditions:** Pro Tools histogram panel visible.
- **Execution Steps:**
  1. Manipulate exposure / brightness slider.
- **Pass/Fail Criteria:** PASS if histogram waveform shifts dynamically in real-time ($< 33\text{ ms}$ update latency); Red, Green, Blue, and Luminance channels correctly separated.
- **Verification Method:** Widget performance test.

### TC-FR-013: Localized brush masking (FR-013)
- **Preconditions:** Image loaded; mask mode activated.
- **Execution Steps:**
  1. Paint mask over central region with brush radius $20\text{ dp}$.
  2. Apply "Pastel Dream" preset.
- **Pass/Fail Criteria:** PASS if "Pastel Dream" applies only to painted mask area; unmasked pixels remain in original state.
- **Verification Method:** Mask compositing test.

### TC-FR-014: Full Undo, Redo, and Reset to Original (FR-014)
- **Preconditions:** User applies 3 successive adjustments.
- **Execution Steps:**
  1. Tap Undo twice.
  2. Tap Redo once.
  3. Tap Reset to Original.
- **Pass/Fail Criteria:** PASS if Undo rolls back state step-by-step; Redo reapplies state; Reset returns to original image state; source file untouched.
- **Verification Method:** Command history unit test.

### TC-FR-015: Custom user preset creation and export (FR-015)
- **Preconditions:** Custom combination of fine-tune sliders and curves configured.
- **Execution Steps:**
  1. Tap "Save as Preset", name "Studio Custom 1".
  2. Export preset to local JSON file.
- **Pass/Fail Criteria:** PASS if valid JSON generated containing schema version and parameter dictionary; preset appears in "My Presets" category.
- **Verification Method:** Preset serialization test.

---

## 3. Non-Functional Acceptance Tests (NFR)

### TC-NFR-001: Source media immutability audit (NFR-001)
- **Execution Steps:**
  1. Compute SHA-256 of 5 test fixture images.
  2. Run complete suite of Recolor, Style, and Export operations across all 5 images.
  3. Re-compute SHA-256 of original fixture images.
- **Pass/Fail Criteria:** PASS if all SHA-256 hashes match bit-for-bit.
- **Verification Method:** CLI verification script: `sha256sum -c fixtures.sha256`.

### TC-NFR-002: Zero network execution audit (NFR-002)
- **Execution Steps:**
  1. Disable host/device network interfaces (airplane mode).
  2. Launch app, import image, apply 10 presets, export image.
  3. Inspect Android socket activity and app manifest.
- **Pass/Fail Criteria:** PASS if zero network errors thrown; app manifest contains no `android.permission.INTERNET`; zero sockets opened.
- **Verification Method:** Manifest audit and network proxy inspection.

### TC-NFR-003: Memory headroom budget verification (NFR-003)
- **Execution Steps:**
  1. Attach Dart VM memory profiler.
  2. Process and preview a 24MP image continuously for 60 seconds.
  3. Trigger 12MP high-resolution export.
- **Pass/Fail Criteria:** PASS if peak Dart heap $< 300\text{ MB}$; peak native memory $< 500\text{ MB}$; zero Android Out-Of-Memory events.
- **Verification Method:** Automated memory profiling test run.

### TC-NFR-004: Memory leak verification on studio exit (NFR-004)
- **Execution Steps:**
  1. Open Recolor Studio, load image, apply preset.
  2. Exit to project gallery; trigger garbage collection.
  3. Repeat cycle 10 times.
- **Pass/Fail Criteria:** PASS if final memory delta between cycle 1 and cycle 10 is $< 20\text{ MB}$; no leaked native textures or FFI allocations.
- **Verification Method:** Leak tracking test with `leak_tracker` package.

### TC-NFR-005: Thermal protection compliance (NFR-005)
- **Execution Steps:**
  1. Run 5 consecutive export operations.
  2. Monitor CPU temperature and core frequency.
- **Pass/Fail Criteria:** PASS if worker threads do not peg all CPU cores at 100%; thermal throttling does not trigger OS process kill.
- **Verification Method:** System thermals diagnostic monitor.

### TC-NFR-006: Crash resilience & recovery journal (NFR-006)
- **Execution Steps:**
  1. Create a project with 3 unexported modifications.
  2. Force-kill application process (`kill -9`).
  3. Relaunch application.
- **Pass/Fail Criteria:** PASS if app detects uncommitted dirty journal; restores session with 100% fidelity.
- **Verification Method:** Crash simulation integration test.

### TC-NFR-007: Permissive license audit (NFR-007)
- **Execution Steps:**
  1. Run license scanner across all direct and transitive dependencies.
- **Pass/Fail Criteria:** PASS if 100% of dependencies use MIT, Apache-2.0, or BSD-3; zero GPL, AGPL, or SSPL licenses detected.
- **Verification Method:** `pub_dev_search` / `dart pub deps --json` license audit.

### TC-NFR-008: Cold launch latency test (NFR-008)
- **Execution Steps:**
  1. Terminate app process.
  2. Launch app and record time to first interactive frame.
- **Pass/Fail Criteria:** PASS if first interactive frame rendered in $< 1200\text{ ms}$.
- **Verification Method:** Flutter Driver timeline trace.

---

## 4. User Experience Acceptance Tests (UX)

### TC-UX-001: Beginner-first preset latency (UX-001)
- **Pass/Fail Criteria:** PASS if single-tap on preset card updates viewport in $< 100\text{ ms}$.

### TC-UX-002: Progressive disclosure accordion (UX-002)
- **Pass/Fail Criteria:** PASS if Beginner, Fine-Tune, and Pro Tools expand/collapse smoothly without UI jump.

### TC-UX-003: Interactive split viewer responsiveness (UX-003)
- **Pass/Fail Criteria:** PASS if curtain drag tracks touch coordinates with zero lag.

### TC-UX-004: Haptic feedback verification (UX-004)
- **Pass/Fail Criteria:** PASS if Android haptic feedback triggers at 0%, 50%, and 100% slider positions.

### TC-UX-005: High-resolution zoom & pan (UX-005)
- **Pass/Fail Criteria:** PASS if pinch-to-zoom scales up to 800% smoothly without crashing memory.

### TC-UX-006: Modification indicator badges (UX-006)
- **Pass/Fail Criteria:** PASS if dot badge appears only on tabs with modified non-default values.

### TC-UX-007: Tablet & foldable responsive layout (UX-007)
- **Pass/Fail Criteria:** PASS if screens $\ge 600\text{ dp}$ display tool controls in side drawer beside canvas.

---

## 5. Privacy & Data Isolation Tests (PRIV)

### TC-PRIV-001: Private app sandbox audit (PRIV-001)
- **Pass/Fail Criteria:** PASS if all project cache files are stored within `/data/data/<package_id>/app_flutter/` or internal storage; zero files written to public external directories without explicit user export.

### TC-PRIV-002: Binary tracker scan (PRIV-002)
- **Pass/Fail Criteria:** PASS if `strings` scan on compiled APK binary reveals zero references to analytics domains.

### TC-PRIV-003: Immediate access audit (PRIV-003)
- **Pass/Fail Criteria:** PASS if app opens straight to editing workflow without showing any login or registration screen.

### TC-PRIV-004: Local cache management verification (PRIV-004)
- **Pass/Fail Criteria:** PASS if "Clear Cache" button removes temporary preview files while preserving project state.

---

## 6. Machine Learning Acceptance Tests (ML — CONDITIONAL / GATE B)

### TC-ML-001: On-device semantic segmentation (ML-001)
- **Pass/Fail Criteria:** PASS if LiteRT model produces segmentation mask for person/background in $< 150\text{ ms}$.

### TC-ML-002: Plastic glaze reduction neural filter (ML-002)
- **Pass/Fail Criteria:** PASS if filter breaks synthetic smoothness while preserving edge structure.

### TC-ML-003: Micro-halation optical simulation (ML-003)
- **Pass/Fail Criteria:** PASS if halation glow appears strictly at luminance boundaries $> 0.85$.

### TC-ML-004: Hardware capability pre-flight check (ML-004)
- **Pass/Fail Criteria:** PASS if devices with $< 6\text{ GB}$ RAM gracefully disable ML studio with clear informational dialog.

### TC-ML-005: Model checksum and license verification (ML-005)
- **Pass/Fail Criteria:** PASS if model loader rejects any model file whose SHA-256 hash does not match verified manifest.

### TC-ML-006: Memory ceiling during ML inference (ML-006)
- **Pass/Fail Criteria:** PASS if peak process RAM remains strictly $< 1.5\text{ GB}$ during full inference pass.

---

## 7. Performance Acceptance Tests (PERF)

### TC-PERF-001: 60 FPS viewport frame rate (PERF-001)
- **Pass/Fail Criteria:** PASS if 99% of slider interaction frames render within $16.6\text{ ms}$ (no jank).

### TC-PERF-002: 12MP export latency (PERF-002)
- **Pass/Fail Criteria:** PASS if full export completes in $< 2500\text{ ms}$.

### TC-PERF-003: Preset switching time (PERF-003)
- **Pass/Fail Criteria:** PASS if switching presets updates viewport in $< 150\text{ ms}$.

### TC-PERF-004: Main thread non-blocking concurrency (PERF-004)
- **Pass/Fail Criteria:** PASS if UI remains responsive at 60 FPS while background export is running.

### TC-PERF-005: Static canvas idle power draw (PERF-005)
- **Pass/Fail Criteria:** PASS if GPU frame rendering stops (0 FPS) when canvas is stationary.

### TC-PERF-006: Post-project memory reclamation (PERF-006)
- **Pass/Fail Criteria:** PASS if memory drops to baseline within 5 seconds of closing project.

---

## 8. Accessibility Acceptance Tests (A11Y)

### TC-A11Y-001: Screen reader semantics coverage (A11Y-001)
- **Pass/Fail Criteria:** PASS if 100% of interactive widgets have valid `Semantics` descriptions.

### TC-A11Y-002: Touch target size compliance (A11Y-002)
- **Pass/Fail Criteria:** PASS if all tap targets measure at least $48 \times 48\text{ dp}$.

### TC-A11Y-003: Color-blind text labels (A11Y-003)
- **Pass/Fail Criteria:** PASS if all color palette chips display textual color names and HEX values.

### TC-A11Y-004: Dynamic font scale support (A11Y-004)
- **Pass/Fail Criteria:** PASS if text displays without truncation at 200% system font scale.
