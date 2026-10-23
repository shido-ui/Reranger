# RERANGER PRIMARY-SOURCE RESEARCH REGISTER

## 1. Overview & Methodology
This register catalogs primary sources, official documentation, GitHub repositories, and package manifests consulted during technology evaluation for Reranger. Every claim is mapped directly to a verified source URL with the date accessed.

Claims are rigorously partitioned into three evidential classes:
- **[FACT]**: Verified by official documentation, package release manifests, or live command inspection.
- **[INFERENCE]**: Technically sound engineering deduction derived from verified architectural facts.
- **[UNVERIFIED / UNKNOWN]**: Claim requiring physical hardware benchmarking or runtime empirical validation before acceptance.

---

## 2. Claim-to-Source Mapping

### A. Core Flutter, Offline-First Architecture & Rendering Pipeline

| Claim ID | Evidential Class | Claim Summary | Primary Source URL | Accessed Date |
|---|---|---|---|---|
| **CLM-001** | [FACT] | `FragmentProgram` and `FragmentShader` (in `dart:ui`) compile GLSL fragment shaders into platform native formats (SPIR-V for Vulkan/Android) running directly on GPU at 60/120 FPS. | [Flutter Docs: Fragment Shaders](https://docs.flutter.dev/ui/design/graphics/fragment-shaders) | 2026-10-22 |
| **CLM-002** | [FACT] | Dart Isolates (`Isolate.run`) provide true multi-core parallel execution with zero shared memory, preventing UI thread jank during heavy CPU image processing. | [Dart Docs: Concurrency](https://dart.dev/language/concurrency) | 2026-10-22 |
| **CLM-003** | [FACT] | Flutter Native Assets (`package:ffi` with `hook/build.dart`) automates native C/C++/Rust compilation and symbol resolution without platform boilerplate. | [Flutter Docs: C Interop with FFI](https://docs.flutter.dev/perf/c-interop) | 2026-10-22 |
| **CLM-004** | [FACT] | The `image` package provides pure Dart image decoding, encoding (PNG, JPEG, WebP, TIFF), and pixel manipulation with zero native dependencies. | [pub.dev/packages/image](https://pub.dev/packages/image) / [GitHub: brendan-duncan/image](https://github.com/brendan-duncan/image) | 2026-10-22 |
| **CLM-005** | [INFERENCE] | Running `image` pixel operations on main UI thread causes frame drops; all pure Dart image processing must be dispatched to background isolates. | Derived from CLM-002 and single-threaded Dart event loop architecture | 2026-10-22 |

---

### B. Native Image Processing & Computer Vision Candidates

| Claim ID | Evidential Class | Claim Summary | Primary Source URL | Accessed Date |
|---|---|---|---|---|
| **CLM-006** | [FACT] | `opencv_dart` (v2.2.2 / `dartcv4` v2.3.1) provides OpenCV 4 C++ bindings via `dart:ffi` under Apache-2.0, supporting color conversions, filtering, and DNN modules. | [pub.dev/packages/opencv_dart](https://pub.dev/packages/opencv_dart) / [GitHub: rainyl/opencv_dart](https://github.com/rainyl/opencv_dart) | 2026-10-22 |
| **CLM-007** | [FACT] | Prebuilt `opencv_dart` binaries include large native shared libraries (`.so` per ABI), adding 15–40 MB per architecture to the APK footprint. | [GitHub: rainyl/opencv_dart Releases](https://github.com/rainyl/opencv_dart/releases) | 2026-10-22 |
| **CLM-008** | [INFERENCE] | A minimal custom C++ FFI package wrapping only needed routines (e.g., bilateral filtering, palette quantization) yields a much smaller binary footprint (<2 MB) than full OpenCV. | Engineering calculation based on stripped NDK shared library sizes | 2026-10-22 |
| **CLM-009** | [UNVERIFIED] | Exact throughput difference between `opencv_dart` FFI isolate transfers vs custom native shared memory on Adreno 6xx/7xx GPUs under Android 14. | Requires on-device benchmark harness (gated under Invariant 8) | 2026-10-22 |

---

### C. On-Device ML & Generative Diffusion Candidates (Humanize Studio)

| Claim ID | Evidential Class | Claim Summary | Primary Source URL | Accessed Date |
|---|---|---|---|---|
| **CLM-010** | [FACT] | `flutter_litert` (v3.9.4) provides LiteRT (formerly TensorFlow Lite) on-device inference for segmentation, classification, and custom `.tflite` models under Apache-2.0. | [pub.dev/packages/flutter_litert](https://pub.dev/packages/flutter_litert) / [GitHub: hugocornellier/flutter_litert](https://github.com/hugocornellier/flutter_litert) | 2026-10-22 |
| **CLM-011** | [FACT] | `stable-diffusion.cpp` (by leejet) provides native C++ GGML-based Stable Diffusion inference supporting both Text-to-Image and Image-to-Image (`--img2img`, `--strength`) under MIT license. | [GitHub: leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) | 2026-10-22 |
| **CLM-012** | [FACT] | `stable-diffusion.cpp` supports GGUF quantization (Q4_0, Q8_0) reducing model weights from ~4 GB (FP32) to ~1.2–1.8 GB, but still consumes 1.5–2.5 GB peak RAM during U-Net denoising. | [GitHub: leejet/stable-diffusion.cpp Benchmarks](https://github.com/leejet/stable-diffusion.cpp) | 2026-10-22 |
| **CLM-013** | [FACT] | Google MediaPipe Image Generator on Android primarily showcases Text-to-Image; structurally guided image conditioning requires specialized Diffusion Plugins (edge/depth/face) and 8 GB+ device RAM. | [Google AI Edge: MediaPipe Image Generator](https://ai.google.dev/edge/mediapipe/solutions/vision/image_generator) / [Google Codelab](https://developers.google.com/codelabs/mediapipe-image-generation) | 2026-10-22 |
| **CLM-014** | [FACT] | Text-to-Image (T2I) takes random noise seeded by a text prompt and generates a novel composition; it CANNOT be assumed to support non-destructive Image-to-Image (I2I) without explicit latent image blending or ControlNet/plugin conditioning. | [Stable Diffusion Pipeline Specification / High-Resolution Image Synthesis with Latent Diffusion Models](https://arxiv.org/abs/2112.10752) | 2026-10-22 |
| **CLM-015** | [INFERENCE] | Bundling 1.5 GB+ diffusion model weights inside the base APK violates mobile distribution best practices and risks immediate Android OOM termination on devices with ≤6 GB RAM. | Invariant 11 ("Strict Runtime Memory & Thermal Budgets") | 2026-10-22 |
| **CLM-016** | [UNVERIFIED] | Thermal throttling behavior and sustained FPS of Qualcomm Adreno GPU OpenCL/Vulkan drivers during 20-step local diffusion inference inside a background process. | Hardware validation required on physical device | 2026-10-22 |

---

### D. Licensing & Model Distribution Governance

| Claim ID | Evidential Class | Claim Summary | Primary Source URL | Accessed Date |
|---|---|---|---|---|
| **CLM-017** | [FACT] | SD 1.5 weights are governed by the CreativeML OpenRAIL-M license, which permits commercial use and on-device distribution but imposes specific behavioral use restrictions. | [HuggingFace: CreativeML OpenRAIL-M](https://huggingface.co/spaces/CompVis/stable-diffusion-license) | 2026-10-22 |
| **CLM-018** | [FACT] | SDXL and SD 3.5 weights are governed by Stability AI Community Licenses, which require distinct attribution and revenue-capped commercial terms. | [Stability AI Community License Agreement](https://stability.ai/license) | 2026-10-22 |
| **CLM-019** | [FACT] | Apache-2.0 (`flutter_litert`, `opencv_dart`, `MediaPipe`) and MIT (`image`, `stable-diffusion.cpp`) are fully compatible with commercial and closed/open-source mobile distribution. | [Open Source Initiative (OSI)](https://opensource.org/licenses) | 2026-10-22 |
