# RERANGER TECHNOLOGY EVALUATION & FEASIBILITY REPORT

## 1. Executive Summary & Objective
This report presents an evidence-backed comparative evaluation of candidate libraries, native runtimes, and local ML engines for Reranger's three core studios:
- **Recolor Studio**: Real-time palette extraction, color remapping, and harmonic adjustment.
- **Style & Render Studio**: Fine-grained texture synthesis, stylistic rendering, and artistic shader transformations.
- **Humanize Studio**: Local on-device ML/diffusion-guided refinement transforming synthetic AI art into authentic aesthetics.

All candidate evaluations strictly adhere to the Reranger Product Constitution (`AGENTS.md`), notably:
- Source image immutability (Invariant 4)
- 100% offline-first local runtime execution (Invariant 5)
- Zero cloud processing, accounts, or analytics (Invariant 6)
- Proof-gated native processing & ML models (Invariants 8 & 9)
- Strict runtime memory & thermal budgets (Invariant 11)

---

## 2. Batch A: Flutter / Offline / Native Engine Candidates

### Candidate A1: `image` (Pure Dart)
- **Exact Version:** `4.12.0`
- **Publisher / License:** `publisher:loki3d.com` | MIT License (permissive)
- **Repository:** `https://github.com/brendan-duncan/image`
- **Supported Platforms:** All Dart/Flutter targets (100% pure Dart, zero native compilation).
- **Task Types Supported:** Format decoding (JPEG, PNG, WebP, TIFF, GIF, BMP, TGA), pixel-level color transformations, resizing, cropping, basic convolutions.
- **Pros:** Zero native build complexity, zero NDK setup, completely portable, stable API.
- **Known Limitations:** CPU-bound in Dart VM; significantly slower than SIMD-accelerated C++/NDK or GPU shaders. Iterating millions of pixels on a 12MP/24MP image takes hundreds of milliseconds or seconds.
- **Memory Footprint:** Heap-allocated pixel buffers in Dart garbage collector. Requires running inside background `Isolate.run()` to prevent UI stutter.
- **Suitability:** **HIGH for metadata, thumbnail caching, and fallback file I/O; POOR for real-time live preview rendering.**

---

### Candidate A2: `opencv_dart` (OpenCV 4 FFI Bindings)
- **Exact Version:** `2.2.2` (and `dartcv4` `2.3.1`)
- **Publisher / License:** `publisher:rainyl.dev` | Apache-2.0
- **Repository:** `https://github.com/rainyl/opencv_dart`
- **Supported Platforms:** Android (`arm64-v8a`, `armeabi-v7a`, `x86_64`), iOS, macOS, Windows, Linux.
- **Task Types Supported:** Comprehensive computer vision: bilateral filtering, edge detection, K-means color quantization, morphological transforms, CLAHE contrast equalization, DNN module inference.
- **Pros:** Highly optimized C++ algorithms, NEON/SIMD acceleration, comprehensive algorithm catalog.
- **Known Limitations:** Extremely heavy binary payload: adds 15–40 MB per ABI to APK size. Many OpenCV modules (e.g. video capture, GUI, calibration) are irrelevant to Reranger's image studio but bundled by default unless custom-compiled.
- **Memory Footprint:** Native C++ heap allocations (`cv::Mat`) require explicit lifetime management (`.dispose()`) to avoid native memory leaks outside the Dart GC.
- **Suitability:** **MEDIUM. Provides powerful CV algorithms but introduces excessive binary bloat and packaging overhead.**

---

### Candidate A3: Minimal Custom Flutter FFI Package (C++ / NDK)
- **Exact Version:** Custom project native asset (`dart:ffi` + Android NDK Clang 21)
- **License:** Project-authored permissive (MIT / Apache-2.0)
- **Supported Platforms:** Android (`arm64-v8a`, `armeabi-v7a`), Linux ARM64.
- **Task Types Supported:** Hand-tailored color matrix transformations, SIMD/NEON palette remapping, custom bilateral filter, non-destructive buffer export.
- **Pros:** Zero extraneous dependencies, stripped binary size <1.5 MB, optimal memory layout, direct memory pointers (`Pointer<Uint8>`), zero unnecessary copies.
- **Known Limitations:** Requires maintaining C++ source code and NDK build scripts; higher initial development effort than importing a pre-existing package.
- **Suitability:** **HIGH for performance-critical native routines and high-resolution export pipelines.**

---

### Complementary Viewport Technology: Flutter Fragment Shaders (`dart:ui`)
- **Exact Version:** Flutter SDK Built-in (`dart:ui` `FragmentProgram` / `FragmentShader`)
- **License:** Flutter BSD-3-Clause
- **Supported Platforms:** All Flutter platforms supporting Impeller/Skia (SPIR-V on Android Vulkan/OpenGL ES).
- **Task Types Supported:** Real-time per-pixel transformations (HSL shifts, LUT grading, dithering, film grain, vignette, halftone, color quantization).
- **Pros:** Executes at 60/120 FPS directly on the mobile GPU raster thread. Zero data transfer between isolates. Perfect interactive latency (<16ms) for sliders and controls.
- **Known Limitations:** Shader outputs exist in GPU memory for rendering; exporting high-res images to disk requires `toImage()` capture or parallel native C++ rendering.
- **Suitability:** **ESSENTIAL / FIRST-CLASS for Recolor Studio and Style & Render Studio real-time UI viewports.**

---

## 3. Batch B: Humanize / Model / Runtime Candidates

### Candidate B1: `flutter_litert` (Google LiteRT / TensorFlow Lite)
- **Exact Version:** `3.9.4`
- **Publisher / License:** `publisher:hugo.ml` | Apache-2.0
- **Repository:** `https://github.com/hugocornellier/flutter_litert`
- **Supported Platforms:** Android (`arm64-v8a`, `armeabi-v7a`), iOS, Web.
- **Task Types Supported:** Local neural network inference: semantic segmentation (subject/background separation), skin/hair segmentation, super-resolution, style transfer, edge detection.
- **Pros:** Lightweight runtime (~3–8 MB), mature hardware delegation (Android NNAPI, GPU delegate via OpenCL/Vulkan), excellent quantization support (INT8 / FP16), predictable memory usage (often <150 MB RAM for perception models).
- **Known Limitations:** Not designed for heavy multi-billion-parameter iterative diffusion pipelines. Best suited for focused discriminative or lightweight generative models.
- **Suitability:** **HIGH for localized feature refinement (segmentation masks, edge extraction, texture restoration) in Humanize Studio.**

---

### Candidate B2: `stable-diffusion.cpp` (GGML C++ Diffusion Engine)
- **Exact Version:** `master/HEAD` (Git tracking)
- **Author / License:** `leejet` | MIT License
- **Repository:** `https://github.com/leejet/stable-diffusion.cpp`
- **Supported Platforms:** Android (compiled via NDK/Termux for `aarch64`), Linux, Windows, macOS, iOS.
- **Task Types Supported:** Full iterative latent diffusion: Text-to-Image (txt2img), Image-to-Image (img2img with `--strength`), inpainting, ControlNet, LoRA.
- **Pros:** Truly local on-device generative diffusion. Supports GGUF quantization (Q4_0, Q8_0) allowing SD 1.5 to run in ~1.5–2.0 GB RAM. Pure C++ with GGML backend.
- **Known Limitations:**
  - Extremely high RAM consumption (1.5–2.5 GB peak). On devices with ≤6 GB total RAM, Android's `lowmemorykiller` will kill background processes if memory spikes.
  - High latency: 20-step inference on mobile CPU/GPU takes 30–120+ seconds per 512x512 image.
  - Thermal load: Sustained heavy GPU/NPU compute causes thermal throttling.
  - Model distribution: GGUF weights are 1.2–1.8 GB. Cannot be bundled into the initial APK.
- **Suitability:** **VIABLE ONLY FOR ADVANCED OPT-IN HARDWARE PROFILES (Devices with 8GB+ RAM, downloaded on-demand). Gated under Invariant 9.**

---

### Candidate B3: Google MediaPipe Image Generator
- **Exact Version:** MediaPipe Tasks Vision `0.10.x` (`com.google.mediapipe:tasks-vision-image-generator`)
- **Author / License:** Google AI Edge | Apache-2.0
- **Supported Platforms:** Native Android (Kotlin/Java API), iOS.
- **Task Types Supported:** On-device Stable Diffusion 1.5 generation; primarily Text-to-Image; structurally conditioned generation via Diffusion Plugins (edge, depth, face conditioning).
- **Pros:** Official Google AI Edge solution, heavily optimized for Qualcomm/MediaTek hardware.
- **Critical Caveat & Limitations:**
  - **Text-to-Image vs True Image-to-Image:** MediaPipe Image Generator does NOT provide a simple arbitrary `img2img` strength slider out-of-the-box. Instead, it relies on "Diffusion Plugins" that extract conditioning features (e.g. depth map, Canny edge map) to steer text-prompted diffusion.
  - No official Flutter plugin: Requires authoring a custom Android platform channel.
  - Strict minimum device requirements: 8 GB+ RAM and high-end SoC required.
- **Suitability:** **MEDIUM / CAUTION. Does not provide direct unconstrained image-to-image refinement without complex plugin scaffolding.**

---

## 4. Batch C: Cross-Check, Licensing & Constraints Analysis

### A. Text-to-Image (T2I) vs. Image-to-Image (I2I) Differentiation
> [!IMPORTANT]
> A critical invariant in Reranger is **Source Image Immutability** and authentic enhancement of existing user images.
> - **Text-to-Image (T2I)** generates new images from noise based purely on a prompt. It is not sufficient for Reranger's core mission.
> - **Image-to-Image (I2I)** preserves source image composition, lighting, and structure, applying controlled style or de-synthesizing artifacts according to a denoising strength parameter ($\sigma \in [0.1, 0.5]$).
> - Models that only support T2I cannot be used for Humanize Studio without structural conditioning.

### B. Mobile Memory & Thermal Budgets (Android-First Reality)
- Target devices include mid-tier Android phones with 6 GB RAM, where the OS allocates a maximum per-app heap of 512 MB and aggressively terminates processes when free system RAM drops below ~1.2 GB.
- Full diffusion models (SD 1.5 Q4_0) sit right on the edge of the Android Out-Of-Memory (OOM) threshold.
- Therefore, the default Humanize Studio pipeline must prioritize **lightweight neural filters and segmentation-guided transformations (via LiteRT)** over full diffusion passes.

### C. Dependency License Audit
| Candidate | License Type | Commercial Use Allowed | Copyleft Risk | Verified Clean |
|---|---|---|---|---|
| `image` (Dart) | MIT | YES | NONE | YES |
| `opencv_dart` | Apache-2.0 | YES | NONE | YES |
| Custom C++ FFI | MIT / Apache-2.0 | YES | NONE | YES |
| Flutter Fragment Shaders | BSD-3-Clause | YES | NONE | YES |
| `flutter_litert` | Apache-2.0 | YES | NONE | YES |
| `stable-diffusion.cpp` | MIT | YES | NONE | YES |
| `MediaPipe Tasks` | Apache-2.0 | YES | NONE | YES |
| SD 1.5 Model Weights | CreativeML OpenRAIL-M | YES (Conditional) | Use Restrictions Apply | YES |

---

## 5. Comprehensive Comparative Evidence Table

| Candidate Technology | Exact Version | Primary Source | License | Supported Task | Latency Profile | Peak Memory (RAM) | APK Size Impact | Unknowns / Verification Needed |
|---|---|---|---|---|---|---|---|---|
| **`image` (Dart)** | 4.12.0 | pub.dev/packages/image | MIT | Pixel transforms, I/O | 200–1500 ms (CPU) | ~80–200 MB (Dart GC) | <1 MB | UNKNOWN: Performance on 32MP images in background isolate |
| **`opencv_dart`** | 2.2.2 | pub.dev/packages/opencv_dart | Apache-2.0 | Computer vision, filtering | 20–80 ms (C++ SIMD) | ~100–250 MB | +15–40 MB per ABI | UNKNOWN: Build friction with Flutter Native Assets on Android 14 |
| **Custom C++ FFI** | Native | dart:ffi / Android NDK | MIT / Apache-2.0 | Selected fast kernels | 10–50 ms (C++ NEON) | ~50–120 MB | <1.5 MB | UNKNOWN: Exact NEON assembly optimization headroom |
| **Flutter Shaders** | Flutter SDK | docs.flutter.dev/ui | BSD-3 | Live viewport filters | <16 ms (60/120 FPS GPU) | <30 MB (VRAM) | <100 KB | UNKNOWN: Fragment shader limits on low-end Mali-G52 GPUs |
| **`flutter_litert`** | 3.9.4 | pub.dev/packages/flutter_litert | Apache-2.0 | Perception ML, Segmentation | 30–120 ms (NPU/GPU) | ~100–200 MB | ~4–8 MB | UNKNOWN: NNAPI delegate stability across Android vendors |
| **`stable-diffusion.cpp`** | Git HEAD | github.com/leejet/sd.cpp | MIT | Full I2I / inpainting | 30–120 s (Heavy compute)| 1.5–2.5 GB (GGUF Q4) | +5–8 MB binary (+1.5GB model)| UNKNOWN: Thermal throttling on sustained 20-step runs |
| **MediaPipe Image Gen** | 0.10.x | ai.google.dev/edge | Apache-2.0 | Conditioned diffusion | 20–60 s (GPU) | 2.0–3.0 GB | +12 MB binary (+model bundle)| UNKNOWN: Viability of arbitrary img2img without text prompt |

---

## 6. Architectural Recommendations

1. **Adopt a Three-Tiered Hybrid Engine Architecture:**
   - **Tier 1 (Interactive Viewport):** Utilize **Flutter Fragment Shaders (`dart:ui`)** for instant 60 FPS preview manipulation across Recolor Studio and Style & Render Studio.
   - **Tier 2 (High-Fidelity Export & Core CV):** Implement a **Clean Architecture Repository with a Minimal Custom FFI C++ engine** (with `image` pure-Dart isolate fallback) for deterministic, non-destructive file rendering, palette extraction, and color math.
   - **Tier 3 (Humanize Studio ML):** Use **`flutter_litert`** as the core offline on-device inference engine for segmentation and artifact-reduction neural filters. Keep full latent diffusion (`stable-diffusion.cpp`) as an optional, proof-gated advanced extension for hardware meeting strict memory requirements (8GB+ RAM).

2. **Source Image Protection & Non-Destructive Projects:**
   - Source images are mounted read-only. Edits are recorded as lightweight transformation recipe trees (JSON/project state).
   - Exports are written to new destination files with SHA-256 verification.

---

## 7. Concrete Experimentation Plan (Proof Before Implementation)
Before writing feature code in subsequent phases, the following proof benchmarks must be executed:
1. **Shader Viewport Benchmark:** Verify GLSL fragment shader rendering at 60 FPS on Android emulator and physical target.
2. **Isolate Memory Check:** Validate that a 12MP source image can be processed in a background isolate without exceeding a 200 MB memory delta.
3. **LiteRT Segmentation Benchmark:** Benchmark a lightweight INT8 segmentation model via `flutter_litert` to verify latency <100ms and peak RAM <150MB.

> [!CAUTION]
> Stop-the-line condition: Full generative diffusion must NOT be incorporated into the default user workflow until hardware detection and thermal/memory safety checks are fully proven.
