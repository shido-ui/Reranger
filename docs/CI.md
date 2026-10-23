# RERANGER — CONTINUOUS INTEGRATION & QUALITY PIPELINE SPECIFICATION

**Document Version:** 1.0.0  
**Prompt ID:** Prompt 28 — Complete automated testing and CI  
**Status:** **OPERATIONAL & PRODUCTION-GRADE**  
**Lead Engineer:** Reranger Build & Reliability Engineering  

---

## 1. Executive Summary & Pipeline Mission

Reranger enforces a multi-tier, zero-compromise quality pipeline ensuring that every commit, pull request, and release build is 100% reproducible from a clean checkout. The pipeline covers:
1. **Code Hygiene & Static Analysis**: Strict Dart formatting (`dart format`) and zero-warning static analysis (`flutter analyze`).
2. **Security, Privacy & Licensing Isolation**: Automated static scanning guaranteeing zero runtime network calls, zero hardcoded secrets, zero path-traversal (Zip-Slip) vulnerabilities, GPS metadata stripping on export, and 100% license attribution for all 57 pub dependencies and 4 neural models.
3. **Native C/C++ Engine Verification**: CTest automated test execution of the high-performance classical C++ engine and humanize spike.
4. **Automated Flutter Test Suites**: Multi-suite segmented test execution covering Unit, Widget, Preset, Integration, Benchmark, and Fixed-Image Golden Visual QA tests.
5. **Clean Compilation & Artifact Generation**: Flutter application bundle (`flutter build bundle`) and Android Debug APK compilation (`flutter build apk --debug`).
6. **Explicit Hardware & Device Deferral Governance**: Truthful tracking of tests that require physical cloud hardware (Google Pixel 10) rather than concealing them behind illusory green badges.

---

## 2. Clean Checkout Reproduction Guide

To reproduce all verification stages from a fresh, pristine clone on any standard Linux or macOS machine with Flutter 3.47.7 and Dart 3.13.5 installed:

```bash
# 1. Clone repository
git clone <repository_url> reranger
cd reranger

# 2. Resolve clean dependencies (no machine-local undeclared state)
flutter pub get

# 3. Execute authoritative single-command verification pipeline
bash scripts/verify.sh
```

### Individual Check Commands

| Stage | Command | Target | Pass Criteria |
|---|---|---|---|
| **Formatting** | `dart format --output=none --set-exit-if-changed lib/ test/` | Dart source files | 0 unformatted files |
| **Analysis** | `flutter analyze lib/ test/` | All codebase symbols | 0 issues found |
| **Security & Licenses** | `python3 scripts/audit_security_licenses.py` | Dependencies, manifest, code | 0 UNKNOWN licenses, 0 network APIs, 0 secrets |
| **Native Classical Engine** | `(cd poc/classical_engine/cpp/build && ctest --output-on-failure)` | C++ algorithms | 100% CTest pass |
| **Native Humanize Spike** | `(cd native/humanize-poc/build && ctest --output-on-failure)` | C++ spike bindings | 100% CTest pass |
| **Widget & Visual QA** | `flutter test --concurrency=1 $(find test/widget -maxdepth 1 -name "*_test.dart" ! -name "ally_matrix_probe_test.dart")` | Widget tree, goldens, a11y | All tests pass |
| **Unit Tests** | `flutter test --concurrency=1 test/unit/` | Pure domain & data models | All tests pass |
| **Preset Catalog** | `flutter test --concurrency=1 test/presets/` | 48 artistic presets | All 48 presets pass |
| **Offline Integration** | `flutter test --concurrency=1 test/integration/` | End-to-end user journeys | 5/5 integration tests pass |
| **Performance Benchmarks** | `flutter test --concurrency=1 test/benchmarks/` | 10 required KPIs | All benchmarks within budget |
| **Application Bundle** | `flutter build bundle` | Flutter runtime assets | Exit code 0 |
| **Android APK** | `flutter build apk --debug` (requires Android SDK) | Android binary artifact | Valid APK output |

---

## 3. Requirement-to-Test Mapping

The following matrix maps all contractual domain requirements from `docs/PRD.md`, `docs/ARCHITECTURE.md`, and `docs/ACCEPTANCE_CRITERIA.md` to automated tests:

| Domain Contract / Requirement | Test Suite / Location | Verification Method |
|---|---|---|
| **Source Image Immutability (Invariant 4)** | `test/unit/project_persistence_test.dart`, `test/presets/preset_catalog_test.dart` | SHA-256 byte identity asserted before and after operations; write guards reject mutation. |
| **Offline-First Runtime (Invariant 5 & 6)** | `test/integration/first_flow_e2e_test.dart`, `test/unit/security_privacy_license_audit_test.dart` | OS-level socket block verification; static scanner asserting 0 network APIs. |
| **No Fake Controls / AI (Invariant 7)** | `test/widget/analysis_screen_test.dart`, `test/unit/humanize_adapter_test.dart` | Honest indeterminate progress; truthful unavailability on unsupported RAM (<6 GB). |
| **EXIF Orientation Matrix (Tags 1–8)** | `test/unit/isolate_image_decoder_test.dart` | All 8 orientation permutations tested with coordinate swap and reflection assertions. |
| **Alpha Channel Preservation** | `test/unit/scene_map_batch_b_test.dart`, `test/unit/recolor_engine_test.dart` | Transparent PNG fixture validation; alpha channel preserved across Sobel and blend. |
| **Scene Map & Bundle Extraction** | `test/unit/scene_map_batch_a_test.dart`, `test/unit/scene_map_batch_b_test.dart` | Histogram, saliency, Sobel edge map, and contour extraction determinism. |
| **RenderGraph DAG & Cache Keys** | `test/unit/render_graph_batch_a_test.dart`, `test/unit/render_graph_batch_b_test.dart` | Topological sorting, cycle detection, parameter-sensitive SHA-256 cache keys. |
| **In-Flight Cancellation (< 250ms)** | `test/unit/render_job_controller_test.dart`, `test/unit/performance_optimization_test.dart` | Rapid slider debouncing; cancellation acknowledgement in $\le 250\text{ms}$. |
| **Persistence, Migrations & Dirty Journal** | `test/unit/project_database_test.dart`, `test/unit/project_persistence_test.dart` | SQLite V1 $\to$ V2 migration; uncommitted dirty journal replay on simulated crash. |
| **Undo / Redo Stack & Variant Branching** | `test/unit/history_and_variants_test.dart` | 50-step undo/redo stack; non-destructive recipe variant branch creation. |
| **Export Formats & GPS Privacy** | `test/unit/export_service_test.dart`, `test/widget/export_sheet_test.dart` | JPEG/PNG generation; quality slider scaling; automatic GPS metadata stripping. |
| **Humanize Adapter Contract & Gating** | `test/unit/humanize_adapter_test.dart`, `test/widget/humanize_screen_test.dart` | RAM threshold gating; cooperative cancellation token; self-test validation. |
| **Adversarial Stealth Engine (FGSM)** | `test/unit/adversarial_stealth_test.dart`, `test/unit/detector_lab_test.dart` | Mathematical FGSM perturbation; PSNR $\ge 35\text{ dB}$; C2PA manifest parsing. |
| **Touch Targets ($\ge 48\text{dp}$) & Semantics** | `test/widget/accessibility_visual_audit_test.dart`, `test/widget/golden_visual_qa_test.dart` | Touch target dimensions measured; TalkBack `liveRegion` and slider semantics verified. |
| **Fixed-Image Golden Determinism** | `test/widget/golden_visual_qa_test.dart` | Bit-for-bit SHA-256 pixel buffer consistency across multiple runs; parameter sensitivity. |

---

## 4. Visual QA Checklist & Golden Test Policy

### Golden Test Policy
1. **Source Immutability**: All golden fixtures are stored read-only under `test/fixtures/` and must never be altered during test runs.
2. **Review-Gated Updates**: Modifying expected golden hashes or reference bitmaps requires an explicit peer-reviewed pull request documenting the mathematical or aesthetic justification.
3. **No Placebo Masking**: Golden tests calculate SHA-256 digests over raw uncompressed pixel bytes (`RGBA8888`), ensuring zero tolerance for pixel drift.

### Visual QA Checklist (Executed in `golden_visual_qa_test.dart`)
- [x] **Layout Integrity**: Verified zero `RenderFlex` overflows on standard $360\times 800\text{ dp}$ viewport across all screens (`HomeScreen`, `AnalysisScreen`, `SettingsScreen`, `CreationsScreen`).
- [x] **Touch Target Bounds**: All primary and secondary CTAs, dialog buttons, and icon buttons provide minimum hit boxes $\ge 48\times 48\text{ dp}$.
- [x] **Theme Contrast**: All text and foreground icon tokens achieve WCAG 2.1 Level AAA contrast ratios ($\ge 7.0:1$) against studio canvas backgrounds.
- [x] **Progress Transparency**: Import and inference screens display honest, named operation stages without fake percentage numbers.
- [x] **Screen Reader Semantics**: All interactive sliders declare plain-language labels with unit percentages; dynamic progress overlays declare `liveRegion: true`.

---

## 5. Explicit Device-Only Deferrals Catalog

To preserve absolute integrity and avoid illusory green CI badges, the following capabilities are explicitly documented as deferred to physical hardware execution:

| Deferred Capability | Test File / Target | Hardware Requirement | Deferral Justification & Mitigation |
|---|---|---|---|
| **Exhaustive 32-Viewport Matrix Probe** | `test/widget/ally_matrix_probe_test.dart` | Physical Google Pixel 10 (or high-spec emulator) | Excluded from PRoot Linux container to prevent compiler OOM / process hangs. Baseline viewport ($360\times 800$) tested in CI via `responsive_overflow_matrix_test.dart`. |
| **Neural Diffusion On-Device Inference** | `MOD-SD15-Q4` / `MOD-LCM-LORA` | Physical Google Pixel 10 (Tensor G5 NPU / Mali GPU, $\ge 8\text{ GB}$ RAM) | Container lacks native Vulkan/NNAPI GPU hardware acceleration and neural weight buffers. CI verifies truthful hardware gating fallback and mock/dry-run adapter contracts. |
| **Sustained Thermal Load & Battery Profiling** | Thermal throttling benchmark | Physical Google Pixel 10 hardware sensors | Thermal behavior cannot be simulated in headless virtualization or PRoot chroot. Manual execution scheduled for Stage 29 device verification. |

---

## 6. Remote CI Pipeline (`.github/workflows/ci.yml`)

The repository includes an automated GitHub Actions workflow executing on every push and pull request to `main`:
- **Job 1 (`static_analysis_and_licenses`)**: Enforces Dart code formatting, static analysis, and security/license audits.
- **Job 2 (`native_cpp_engine`)**: Compiles and tests native C++ libraries using CMake and Ninja.
- **Job 3 (`flutter_test_suite`)**: Executes all automated Flutter test suites with bounded concurrency.
- **Job 4 (`android_build`)**: Compiles the Flutter asset bundle and Android debug APK.
