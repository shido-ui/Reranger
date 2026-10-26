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

/// Applies procedural grain overlay using 2D coherent noise and SoftLight blending.
void native_grain_overlay(const uint8_t* src, uint8_t* dst, int width, int height, uint32_t seed, float intensity);

/// Executes translucent watercolor wash diffusion with row-major memory stride and coherent paper grain.
void native_watercolor_wash(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    int wash_diffusion,
    float wet_edge_bleed,
    float paper_tooth,
    uint32_t seed
);

/// Executes Recipe 1: Dramatic Monochrome Ink in native C++.
void native_recipe_monochrome_ink(const uint8_t* src, uint8_t* dst, int width, int height);

// ============================================================================
// Robust Stealth Engine V2 (ARMOR, SensorNoise, and Metadata Annihilation)
// ============================================================================

/// Strips 100% of EXIF, XMP, and C2PA / JUMBF metadata chunks from image byte streams (JPEG, PNG, or raw byte buffers).
/// Returns the size in bytes written to dst, or 0 on error.
size_t native_strip_metadata(
    const uint8_t* src,
    size_t src_size,
    uint8_t* dst,
    size_t dst_capacity
);

/// Robust Stealth Engine V3: Strips high-frequency DALL-E 3 latent upsampling checkerboard bias.
void native_latent_sanitization(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength
);

/// ARMOR++ Multi-Domain Universal Adversarial Perturbation (2026 framework):
/// Entropy-regularized convex combination of 4 perturbation primitives:
/// 1. Spatial Perturbation (CW-style sign-gradient bounded by L_inf <= 8/255)
/// 2. Frequency-Domain Attack (JPEG Q75-hardened 8x8 DCT mid-frequency)
/// 3. Saliency Modification (JSMA gradient/variance masking)
/// 4. Block-Structured Transformations (BSR 8x8 patch modulation)
/// Constrained by an L_inf norm of 8/255 (at strength = 1.0) with SSIM > 0.90.
void native_armor_attack(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength
);

/// Simulates digital camera hardware sensor artifacts:
/// - Bayer CFA (Color Filter Array) pattern shot and read noise
/// - Subtle lateral chromatic aberration (radial wavelength refraction)
void native_sensor_noise(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float noise_intensity,
    float chromatic_aberration
);

// Academic Adversarial Robustness Research (Legacy Compatibility Shim)
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

/// Converts image from sRGB to CIELAB, applies adaptive histogram/contrast equalization
/// on the L* channel, and saliency-weighted chroma boost (a* and b*) with strict hue invariance.
void native_adaptive_vibrancy(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float vibrancy,
    float contrast
);

// ============================================================================
// SAM 2.1 (Hiera-Small) Neural Segmentation & CIELAB Math Mode Magic Wand
// ============================================================================

#define SAM2_GRID_SIZE 64
#define SAM2_CHANNELS 64
#define SAM2_EMBEDDING_SIZE (SAM2_GRID_SIZE * SAM2_GRID_SIZE * SAM2_CHANNELS)
#define SAM2_MODEL_INPUT_DIM 1024

/// Initializes SAM 2.1 Hiera-Small session with model path. Returns opaque handle.
void* native_sam2_create(const char* model_path);

/// Destroys SAM 2.1 session and releases working tensors.
void native_sam2_destroy(void* handle);

/// Stage 1: Image Encoder (runs on image load).
/// Extracts hierarchical vision transformer embeddings into out_embedding.
int native_sam2_encode(
    void* handle,
    const uint8_t* rgba,
    int width,
    int height,
    float* out_embedding,
    int embedding_dim
);

/// Stage 2: Prompt-Guided Mask Decoder (runs per tap).
/// Evaluates tap point prompt to generate high-precision object mask.
int native_sam2_decode(
    void* handle,
    const float* embedding,
    int embedding_dim,
    float tap_x,
    float tap_y,
    uint8_t* out_mask,
    int out_w,
    int out_h
);

/// Math Mode: CIELAB Color Tolerance Magic Wand for Art/Anime
/// Selects all connected pixels starting from (seed_x, seed_y) within hue/color tolerance,
/// strictly bounded by line art edges.
void native_cielab_magic_wand(
    const uint8_t* rgba,
    int width,
    int height,
    int seed_x,
    int seed_y,
    float hue_tolerance,
    float color_tolerance,
    uint8_t* out_mask
);

// ============================================================================
// Autodraw Engine (Potrace Vectorization: Background -> Midtones -> Highlights)
// ============================================================================

struct potrace_bitmap_s {
    int w, h;
    int dy;
    uint8_t* map; // Strict 1-bit per pixel representation (luminance < 128 ? 1 : 0)
};

enum PotraceTonalLayer {
    POTRACE_LAYER_BACKGROUND = 0,
    POTRACE_LAYER_MIDTONES = 1,
    POTRACE_LAYER_HIGHLIGHTS = 2
};

struct PotraceBezierSegment {
    float cp1x, cp1y;
    float cp2x, cp2y;
    float endx, endy;
};

struct PotracePath {
    int tonal_layer;      // 0=Background, 1=Midtones, 2=Highlights
    uint32_t color_rgba;  // RGBA8888
    float stroke_width;
    float start_x, start_y;
    int segment_count;
    PotraceBezierSegment* segments;
};

struct PotraceResult {
    int path_count;
    PotracePath* paths;
};

/// Vectorizes an RGBA8888 bitmap into smooth Bézier curve strokes,
/// deterministically sorted: Background -> Midtones -> Highlights.
PotraceResult* native_potrace_trace(
    const uint8_t* rgba,
    int width,
    int height,
    int max_paths
);

/// Frees all memory allocated by native_potrace_trace.
void native_potrace_free(PotraceResult* result);

#ifdef __cplusplus
}
#endif
