#pragma once

#include <cstdint>
#include <cstddef>

#ifdef __cplusplus
extern "C" {
#endif

/// Converts tightly packed RGBA8888 buffer to BT.601 grayscale while preserving alpha.
void native_to_grayscale(const uint8_t* src, uint8_t* dst, int width, int height);

/// Computes 3x3 Sobel gradient edge map from RGBA8888 buffer.
void native_sobel_edges(const uint8_t* src, uint8_t* dst, int width, int height);

/// Applies procedural grain overlay using a 32-bit linear congruential generator.
void native_grain_overlay(const uint8_t* src, uint8_t* dst, int width, int height, uint32_t seed, float intensity);

/// Executes Recipe 1: Dramatic Monochrome Ink in native C++.
void native_recipe_monochrome_ink(const uint8_t* src, uint8_t* dst, int width, int height);

// Academic Adversarial Robustness Research
/// Injects targeted FGSM frequency-domain perturbations to disrupt CNN-based detector confidence
/// while preserving visual fidelity (high PSNR/SSIM).
void native_adversarial_stealth(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength,
    int apply_frequency_perturbation
);

#ifdef __cplusplus
}
#endif
