# RERANGER — FLUTTER & DART MOBILE AGENT RULES & PRODUCT CONSTITUTION

## 1. Product Identity & Architectural Mission
Reranger is a production-grade, Android-first Flutter mobile application delivering an offline-first image-transformation studio for beginners, digital artists, and AI-art users. Its core functional studios are:
- **Recolor Studio**: Real-time palette extraction, localized color remapping, and harmonic color adjustments.
- **Style & Render Studio**: Fine-grained texture synthesis, stylistic rendering, and artistic shader transformations.
- **Humanize Studio**: Local on-device ML/diffusion-guided refinement transforming synthetic AI art into authentic, natural aesthetics.

The principal engineer and technical lead must maintain a product-minded, conservative posture toward existing code, report uncertainty explicitly, and protect repository integrity.

---

## 2. Non-Negotiable Invariants (Product Constitution)

1. **Target Architecture & Clean Architecture**:
   - Built with Flutter / Dart for mobile clients targeting Android first.
   - Follow clean architecture strictly: presentation (UI/blocs/notifiers), domain (pure entities, value objects, use cases), and data (repositories, data sources, platform bridges).
   - Work strictly in bounded vertical slices (default maximum cap of 8 changed source/test/config files per prompt/run).

2. **Tooling, Skills & Diagnostics**:
   - Use the official Dart MCP for analyzer diagnostics, symbol lookups, and test execution.
   - Use Google Developer Knowledge and Context7 for authoritative Flutter, Dart, and Android documentation.
   - Run code formatting and static analysis exclusively via `dart format` and `dart analyze` prior to completion.

3. **Beginner-First Progressive Disclosure**:
   - Interfaces must offer effortless, intuitive single-tap defaults and presets for beginners.
   - Granular controls (histograms, curves, color matrix math, prompt/guidance controls) are progressively disclosed for advanced artists and power users.
   - No feature should require specialized digital art expertise to produce a high-quality initial result.

4. **Source Image Immutability**:
   - Original user media and input images are strictly immutable.
   - Source files are opened read-only and never overwritten, destructively altered, or replaced in-place.
   - All transformations generate new output files or export artifacts, preserving full non-destructive project history.

5. **Offline-First Runtime Execution**:
   - Core image transformations, editing engines, model inference, and project persistence execute 100% locally on-device.
   - Zero runtime network dependency for core application workflows; airplane-mode operation is a first-class requirement.

6. **Zero Cloud Processing, Compulsory Accounts, or Analytics**:
   - No remote server-side image processing or data offloading.
   - No mandatory user accounts, registration, authentication gates, or cloud synchronization requirements.
   - Zero telemetry, analytics SDKs, advertising trackers, or covert background network calls.

7. **No Fake Controls or Illusory AI**:
   - Every exposed UI control (button, slider, toggle, progress bar) must map to an actual, verified, working implementation.
   - No placebo sliders, mock processing spinners, fake "AI" heuristics masquerading as models, or simulated transformation states.
   - If an underlying capability is not yet implemented or supported on the host device, it must not be presented as functional.

8. **Proof-Gated Native Image Processing**:
   - Performance-critical transformations utilizing platform bridges (NDK/C++, platform channels, Vulkan/OpenGL shaders) must be gated by verified benchmarks, deterministic memory checks, and automated unit/integration tests before UI exposure.

9. **Proof-Gated Humanize Model Integration**:
   - On-device ML/neural model inference (e.g., TFLite, ONNX, MediaPipe, or platform neural runtimes) must be gated by verified hardware compatibility, latency benchmarks, quantization integrity, and memory headroom proofs before feature integration.

10. **Asset, Dependency & Model Licensing Integrity**:
    - All bundled assets, model weights, open-source libraries, and fonts must possess verified, permissible open-source or commercial licenses.
    - Full provenance must be documented; zero tolerance for unlicensed intellectual property or ambiguous legal rights.

11. **Adversarial Processing, Provenance & Runtime Budgets (PO Addendum Override)**:
    - Reranger provides advanced adversarial processing and provenance tools. It does not guarantee authorship but explicitly provides users with mathematical perturbations designed to alter AI-detector confidence scores.
    - Strict runtime constraints continue to apply: peak memory consumption must respect strict headroom budgets to prevent Android Out-Of-Memory (OOM) kills on low/mid-tier hardware. Heavy compute loops must manage thermal load and release CPU/GPU memory promptly to avoid OS thermal throttling or foreground termination.

12. **Evidence-Backed Verification & Stop-the-Line Governance**:
    - Every agent turn, task completion, and bug fix must be backed by observable command outputs, raw logs, and verifiable test runs. Never fabricate or extrapolate results.
    - Any S0 (Critical) or S1 (High) defect immediately triggers a STOP-THE-LINE condition (status BLOCKED or FAIL); bypassing gates is strictly prohibited. Every defect fix requires an accompanying regression test and before/after verification evidence.
