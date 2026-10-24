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

/// Universal Adversarial Perturbation (ARMOR) in the frequency (DCT) domain.
/// Applies pre-computed Universal Adversarial Perturbation tensor in 8x8 DCT blocks
/// to disrupt CNN-based AI detectors without causing visible color banding.
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
// EdgeTAM Zero-Shot Semantic Segmentation (ExecuTorch / LiteRT Mobile Runtime)
// ============================================================================

enum EdgeTamCategoryHint {
    EDGETAM_CATEGORY_GENERAL = 0,
    EDGETAM_CATEGORY_HAIR = 1,
    EDGETAM_CATEGORY_FACE = 2,
    EDGETAM_CATEGORY_CLOTHING = 3,
    EDGETAM_CATEGORY_BACKGROUND = 4
};

#define EDGETAM_GRID_SIZE 64
#define EDGETAM_CHANNELS 64
#define EDGETAM_EMBEDDING_SIZE (EDGETAM_GRID_SIZE * EDGETAM_GRID_SIZE * EDGETAM_CHANNELS)
#define EDGETAM_MODEL_INPUT_DIM 1024

/// Initializes EdgeTAM session with model path. Returns opaque handle.
void* native_edgetam_create(const char* model_path);

/// Destroys EdgeTAM session and releases working tensors.
void native_edgetam_destroy(void* handle);

/// Stage 1: Image Encoder (runs on image load).
/// Preprocesses RGBA image to 1024x1024 top-left pad, extracts multi-scale vision transformer
/// embeddings into out_embedding (must be at least EDGETAM_EMBEDDING_SIZE floats).
int native_edgetam_encode(
    void* handle,
    const uint8_t* rgba,
    int width,
    int height,
    float* out_embedding,
    int embedding_dim
);

/// Stage 2: Prompt-Guided Mask Decoder (runs per tap).
/// Evaluates tap prompt coordinate in 1024x1024 padded space with category hint.
/// Writes 1024x1024 single-channel uint8 mask (1,048,576 bytes).
int native_edgetam_decode(
    void* handle,
    const float* embedding,
    int embedding_dim,
    float tap_x_1024,
    float tap_y_1024,
    int category_hint,
    uint8_t* out_mask_1024
);

/// Coordinate Mapper:
/// Maps View tap coordinate (view_x, view_y) on (view_w, view_h) with BoxFit.contain
/// to Source Bitmap space (out_src_x, out_src_y), and then into Padded 1024x1024 space (out_pad_x, out_pad_y).
/// Also returns active padded bounds (active_w_1024, active_h_1024).
void native_edgetam_map_view_to_padded(
    float view_x, float view_y,
    float view_w, float view_h,
    int src_w, int src_h,
    float* out_src_x, float* out_src_y,
    float* out_pad_x, float* out_pad_y,
    int* out_active_w_1024, int* out_active_h_1024
);

/// Reverse Coordinate Mapper:
/// Resamples 1024x1024 top-left padded mask back to Source Bitmap dimensions (src_w x src_h).
void native_edgetam_resample_mask_to_source(
    const uint8_t* in_mask_1024,
    int active_w_1024, int active_h_1024,
    uint8_t* out_mask_src,
    int src_w, int src_h
);

// ============================================================================
// Autodraw Engine (Potrace Vectorization: Background -> Midtones -> Highlights)
// ============================================================================

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
