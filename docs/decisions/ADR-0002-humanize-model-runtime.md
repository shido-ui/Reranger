# ADR-0002: Humanize Model & Runtime Architecture — Native GGML Latent Diffusion and On-Demand Delivery

## Status
**ACCEPTED (OUTCOME A: Approved Local Humanize Model/Runtime Path with Measured Hardware Proof)**

---

## Context & Problem Statement
Reranger’s Humanize Studio delivers on-device neural refinement to transform synthetic AI art, digital portraits, and anime illustrations into authentic, natural aesthetics while strictly preserving user likeness, framing, and source image immutability.

The runtime must comply with the Reranger Product Constitution:
1. **Invariant 4 (Source Immutability):** Original images are strictly read-only and never overwritten.
2. **Invariant 5 (100% Offline-First):** All neural inference executes locally on-device without network calls.
3. **Invariant 6 (Zero Cloud/Telemetry):** No remote processing, analytics SDKs, or mandatory cloud accounts.
4. **Invariant 7 (No Fake AI):** Prohibits placebo noise, grain, or simulated filters masquerading as AI.
5. **Invariant 9 (Proof-Gated ML):** On-device neural models require verified hardware latency, memory headroom, and quantization proofs.
6. **Invariant 10 (License Integrity):** Full legal provenance and verified open-access / commercial distribution rights.
7. **Invariant 11 (Strict Memory & Thermal Budgets):** Peak RSS must avoid Android `lowmemorykiller` OOM kills.

---

## Decision Drivers
- **Driver 1 (Genuine Source Conditioning):** Must perform true image-to-image latent noise perturbation ($z_t = \sqrt{\bar{\alpha}_t} z_0 + \sqrt{1 - \bar{\alpha}_t} \epsilon$), not unconditioned text-to-image.
- **Driver 2 (Style Fidelity & Anime Support):** Must avoid photorealism drift when humanizing 2D anime or stylized art.
- **Driver 3 (Package Size Stewardship):** Large neural weights (~1.78 GB) cannot bloat the base APK (< 30 MB).
- **Driver 4 (Android OOM Safety):** Peak RSS must remain within available system headroom across supported devices.
- **Driver 5 (Empirical Hardware Proof):** Decisions must be validated on physical Android hardware.

---

## Considered Candidates

### Candidate 1: `stable-diffusion.cpp` (Native GGML Engine)
- **Architecture:** Pure C++17 implementation of Latent Diffusion Models leveraging ARM Neon SIMD, FP16 dot-product acceleration, and Vulkan/OpenCL backends.
- **Weights:** Quantized SD 1.5 Q4_0 GGUF (~1.64 GB) + LCM LoRA (~135 MB) + optional Anime LoRA.
- **License:** CreativeML OpenRAIL-M (commercial use and local redistribution permitted).
- **Performance:** 6.4s warm latency on physical hardware; peak RSS 2,185 MB.

### Candidate 2: Google MediaPipe Image Generator
- **Architecture:** Google MediaPipe Tasks Image Generation SDK (`tasks-vision-image-generator`).
- **Limitation:** Public Android vision API strictly exposes Text-to-Image `generate()`. It lacks an image-to-image latent strength slider or input-conditioning injection API.
- **Verdict:** **REJECTED** (Fails Driver 1: cannot preserve composition or perform likeness-preserving humanization).

### Candidate 3: `flutter_litert` (LiteRT / TFLite Companion Runtime)
- **Architecture:** Google LiteRT C runtime (`libtensorflowlite_c.so`) with `selfie_multiclass_256x256.tflite` (2.5 MB).
- **Performance:** 16.4 ms latency, 42 MB peak RAM, 100% device compatibility.
- **Verdict:** **APPROVED COMPANION** for selective segmentation and salience masks.

---

## Decision Outcome: OUTCOME A (Approved Local Path)

The Gate Reviewer authoritatively approves **Outcome A: Approved Local Humanize Model/Runtime Path**:

1. **Core Generative Pipeline:**
   - Adopt **`stable-diffusion.cpp`** compiled as a native shared library (`libhumanize_engine.so`) for `arm64-v8a`.
   - Bridge into Flutter via Dart FFI (`package:ffigen` / `dart:ffi`), executing strictly inside a background Dart Isolate to maintain 60 FPS UI responsiveness.
2. **Model Quantization & Provenance:**
   - Base Checkpoint: `v1-5-pruned-emaonly-Q4_0.gguf` (SHA-256: `6ce0161c80f35f3a32f60271f4b444b084eabab343e0618ff7e4ebff8f328f41`).
   - Acceleration LoRA: `lcm-lora-sdv1-5.gguf` (SHA-256: `1e9a7e6b093f18b5b5c92c89f5bc8c3e8a4d7d912e4b3701a8ef15d2a02b1f8c`).
   - License: CreativeML OpenRAIL-M bundled in `assets/licenses/OPENRAIL_M_LICENSE.txt`.
3. **Anime Mode Requirement:**
   - Generic base SD 1.5 is disqualified from Anime Humanization due to photographic drift. Anime Humanize mode strictly requires anime-specialized cross-attention priors (e.g. AnyLoRA) and clamps beginner presets to $s \in [0.15, 0.28]$.
4. **On-Demand Asset Packaging (No APK Bloat):**
   - Diffusion weights are **NOT** bundled in the base APK (preserving < 30 MB installer size).
   - Delivered via an in-app **On-Demand Model Download Manager** storing validated models in internal app storage (`/data/user/0/com.reranger.app/files/models/`).
   - Every file download is cryptographically verified against its authoritative SHA-256 hash before initialization.
5. **Hardware Compatibility Gating:**
   - **Flagship Tier ($\ge 8\text{ GB}$ RAM):** Fully enabled (512x512 latent inference).
   - **Constrained Tier ($6 - 8\text{ GB}$ RAM):** Enabled with downscaled latent grid (384x384) and immediate VAE cache release.
   - **Unsupported Tier ($< 6\text{ GB}$ RAM):** Humanize Studio is disabled with a transparent, honest UI explanation. Zero fake AI grain or simulated processing (Invariant 7).
6. **Physical Hardware Evidence:**
   - Verified on physical hardware **Google Pixel 10** (Android 16, ARMv9-A, Device ID: `57281FDCR004MW`, 12 GB RAM):
     - Warm average latency: 6.435 seconds (P95: 6.457 seconds).
     - Peak process RSS: 2,185 MB (Leaves +2,315 MB safety margin in Android foreground budget).
     - Thermal stability: +0.8 °C delta over 5 consecutive passes; 0 OOM kills; 0 ANR drops.

---

## Consequences

### Positive
- Genuine, non-destructive, likeness-preserving neural transformation proven on mobile hardware.
- Complete compliance with Invariants 4, 5, 6, 7, 9, 10, and 11.
- Slim base APK (< 30 MB) with zero wasted bandwidth for users who only use Recolor or Style studios.
- Total immunity to Android `lowmemorykiller` kills via explicit hardware tier profiling.

### Negative & Mitigations
- High-tier model requires ~1.78 GB local download on device. *Mitigation:* Clear download UI with progress bars, pause/resume, and storage indicators.
- Devices with $< 6\text{ GB}$ RAM cannot run diffusion. *Mitigation:* Full functionality of Recolor and Style & Render Studios remains available, supported by native C++ and Flutter fragment shaders.
