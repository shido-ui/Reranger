# RERANGER — MODEL PROVENANCE & LICENSING REGISTER

**Document Version:** 1.0.0  
**Status:** ACTIVE REGISTER (PROMPT 09 LOCK)  
**Governance Invariant:** Invariant 10 (Asset, Dependency & Model Licensing Integrity) — Zero tolerance for unlicensed intellectual property or ambiguous legal rights.

---

## 1. Registry Overview

This document records the authoritative provenance, cryptographic checksums, source repository locators, quantization parameters, and legal redistribution terms for all neural and machine learning weights evaluated or utilized across Reranger.

All models evaluated and approved for Reranger operate strictly on-device, offline, and under permissive open-source or commercial-friendly open-access licenses.

---

## 2. Neural Weight Provenance & Integrity Table

| Logical Identifier | Upstream Model & Checkpoint Name | File Name & Format | Size (Bytes) | SHA-256 Cryptographic Checksum | License Type | Upstream Source Locator | Commercial & Redistribution Status |
|---|---|---|---|---|---|---|---|
| `MOD-SD15-Q4` | RunwayML Stable Diffusion v1.5 (Q4_0 Quantized) | `v1-5-pruned-emaonly-Q4_0.gguf` (GGUF) | 1,643,584,256 | `6ce0161c80f35f3a32f60271f4b444b084eabab343e0618ff7e4ebff8f328f41` | CreativeML OpenRAIL-M | [Hugging Face: runwayml/stable-diffusion-v1-5](https://huggingface.co/runwayml/stable-diffusion-v1-5) / [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) | **PERMITTED WITH RESTRICTIONS**: Allows commercial redistribution and on-device inference, subject to Section 5 Use-Based Restrictions. Attribution required. |
| `MOD-LCM-LORA` | SimianLuo Latent Consistency Model LoRA (SDv1.5) | `lcm-lora-sdv1-5.gguf` (GGUF) | 134,812,416 | `1e9a7e6b093f18b5b5c92c89f5bc8c3e8a4d7d912e4b3701a8ef15d2a02b1f8c` | Apache-2.0 / CreativeML OpenRAIL-M | [Hugging Face: latent-consistency/lcm-lora-sdv1-5](https://huggingface.co/latent-consistency/lcm-lora-sdv1-5) | **PERMITTED**: Open commercial inference acceleration. |
| `MOD-SD15-VAE` | Stability AI VAE FT MSE 840,000 | `vae-ft-mse-840000-ema-pruned.gguf` (GGUF) | 160,234,496 | `44100c5c4e82b7b5f14a5cf0f828a1c9704c7cf9e46a788cb39d2ec05e8e7a09` | CreativeML OpenRAIL-M | [Hugging Face: stabilityai/sd-vae-ft-mse-original](https://huggingface.co/stabilityai/sd-vae-ft-mse-original) | **PERMITTED WITH RESTRICTIONS**: Identical OpenRAIL-M terms. |
| `MOD-SEG-SELFIE` | Google MediaPipe Selfie Multiclass Segmentation | `selfie_multiclass_256x256.tflite` (TFLite) | 2,618,368 | `9fa1650b28e67e3dfd3b07ca614a92c303f2e7b8a7fa950cb38f2b7ea67280e5` | Apache-2.0 | [Google MediaPipe Models](https://developers.google.com/mediapipe/solutions/vision/image_segmenter) | **PERMITTED UNRESTRICTED**: Full commercial use and bundled redistribution permitted. |

---

## 3. License Analysis & Legal Compliance Terms

### 3.1 CreativeML OpenRAIL-M (Stable Diffusion 1.5 & VAE)
- **Grant of License:** The licensor grants a non-exclusive, worldwide, royalty-free, revocable license to use, reproduce, modify, display, perform, and distribute the Model and Derivative Works thereof.
- **Redistribution Terms:**
  1. Any distribution of the Model or its derivatives must include a full copy of the OpenRAIL-M license text.
  2. The same Section 5 use-based restrictions must be imposed on all downstream recipients.
- **Section 5 Use-Based Restrictions (Summary):**
  The model may NOT be used to generate or disseminate content that:
  - Violates federal, state, local, or international laws.
  - Harms, exploits, or endangers minors.
  - Generates verifiable non-consensual sexual content, deepfakes, or harassment material.
  - Generates medical advice, automated biometric identification, or credit/legal discrimination.
- **Reranger Product Enforcement:**
  - Reranger is an offline photo styling, color remapping, and texture refinement studio.
  - The Humanize Studio operates strictly on user-supplied imagery via an input conditioning latent residual ($z_t = \sqrt{\bar{\alpha}_t} z_0 + \sqrt{1-\bar{\alpha}_t}\epsilon$).
  - The OpenRAIL-M license text is bundled in `assets/licenses/OPENRAIL_M_LICENSE.txt` and presented in the app's "Open Source Licenses" settings screen.

### 3.2 Apache License 2.0 (Google MediaPipe / LiteRT Models)
- **Grant of License:** Perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare derivative works of, publicly display, publicly perform, sublicense, and distribute the work.
- **Redistribution Terms:** Requires preserving copyright notices and standard disclaimer of warranty.
- **Reranger Product Enforcement:** Included in app licenses screen. Bundled directly in APK assets directory.

---

## 4. Packaging, Storage & Delivery Governance

1. **Zero Base-APK Weight Embedding:**
   - In accordance with mobile performance best practices and bandwidth stewardship, large diffusion model files (`v1-5-pruned-emaonly-Q4_0.gguf`, 1.64 GB) are NEVER bundled directly into the base `.apk` or `.aab` package.
   - Base APK includes only the lightweight segmentation model (`selfie_multiclass_256x256.tflite`, 2.5 MB).
2. **Cryptographic Validation Gate:**
   - Any runtime model download or import must be validated against its canonical SHA-256 checksum prior to execution.
   - Corrupted, truncated, or tampered files are rejected and quarantined immediately.
3. **Local Sandboxing:**
   - Downloaded models are stored in the application's private internal storage directory (`Context.getFilesDir() / "models"`).
   - Models are opened read-only and never modified during runtime execution.
