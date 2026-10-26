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

/// Applies a strong Bilateral Filter denoising pass for generative image sanitization (Mandate 1):
/// Removes high-frequency generative artifacts (e.g. VAE upsampling noise) while preserving edges.
void native_bilateral_filter_sanitization(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float spatial_sigma,
    float range_sigma,
    float strength
);

/// ARMOR++ Multi-Domain Universal Adversarial Perturbation (2026 framework):
/// Entropy-regularized convex combination of 4 perturbation primitives with EOT robustness.
/// Constrained by an L_inf norm of 16/255 (at strength = 1.0) with SSIM > 0.90.
void native_armor_attack(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength
);

/// Enhanced ARMOR attack with explicit max_linf parameter and EOT simulation (Mandate 2):
void native_armor_attack_eot(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength,
    float max_linf,
    int use_eot
);

/// Injects synthetic JPEG quantization artifacts and 8x8 DCT block boundaries (Mandate 3):
/// Simulates camera/social media compression pipeline to defeat detector shortcut learning on PNG exports.
void native_inject_jpeg_quantization_artifacts(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    int quality,
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
// Autodraw Engine V3 (Centerline Skeletonization, Guo-Hall Thinning, Zero-Copy FFI)
// ============================================================================

/// C-compatible zero-copy stroke buffer for Dart FFI.
/// Points are stored as interleaved int16_t (x0, y0, x1, y1, ...).
/// Widths store the local medial axis stroke width per point.
/// Offsets stores the start point index for each stroke (length = stroke_count + 1).
struct StrokeBuffer {
    int16_t* points_x_y;
    uint8_t* widths;
    uint32_t* offsets;
    int32_t stroke_count;
    int32_t total_points;
};

/// Executes Autodraw V3 centerline skeletonization on RGBA8888 bitmap:
/// 1. Adaptive downscale to max 1024px & integral adaptive thresholding.
/// 2. Distance Transform for local medial axis stroke widths.
/// 3. Guo-Hall thinning for a clean 1-pixel centerline skeleton (no double-loops).
/// 4. Polyline walking, spur pruning (< 6px), RDP simplification & curve fitting.
/// 5. Greedy nearest-endpoint TSP stroke ordering (major structures first).
/// 6. 256px tone coverage buffer to skip overdrawn hatching regions.
/// Returns zero-copy StrokeBuffer for Dart Pointer<StrokeBuffer>.asTypedList.
StrokeBuffer* native_skeleton_trace(
    const uint8_t* rgba,
    int width,
    int height,
    int max_strokes
);

/// Frees all memory allocated by native_skeleton_trace.
void native_stroke_buffer_free(StrokeBuffer* buffer);

#ifdef __cplusplus
}
#endif
