#pragma once

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

namespace reranger::humanize {

enum class HardwareProfile {
    FLAGSHIP_SUPPORTED,      // >= 8 GB RAM: Full SD 1.5 Q4_0 GGUF supported
    CONSTRAINED_SUPPORTED,   // 6 GB to 8 GB RAM: Gated, reduced resolution / LCM only
    UNSUPPORTED_OOM_RISK     // < 6 GB RAM: Strictly blocked to prevent Android OOM kill
};

struct HardwareAssessment {
    uint64_t totalRamBytes;
    uint64_t freeRamBytes;
    HardwareProfile profile;
    const char* recommendation;
};

struct LatentTensor {
    int channels;
    int height;
    int width;
    std::vector<float> data;

    size_t byteSize() const { return data.size() * sizeof(float); }
};

class HumanizeSpike {
public:
    /// Assesses host memory against strict mobile thermal/OOM budgets (Invariants 9 & 11).
    static HardwareAssessment assessHardware(uint64_t totalRamBytes, uint64_t freeRamBytes);

    /// Simulates VAE latent encoder mapping 8-bit RGBA image to latent space (8x downsampling).
    static LatentTensor encodeToLatents(const uint8_t* rgba, int width, int height);

    /// Simulates forward diffusion noise addition at step t determined by user strength (0.0 to 1.0).
    /// Computes z_t = sqrt(alpha_bar_t) * z_0 + sqrt(1 - alpha_bar_t) * noise.
    static LatentTensor addDiffusionNoise(const LatentTensor& z0, float strength, uint32_t seed);

    /// Simulates VAE latent decoder reconstructing RGBA image from latents.
    static void decodeToRgba(const LatentTensor& z, uint8_t* rgbaOut, int width, int height);

    /// Computes Mean Absolute Error (MAE) residual between source and output to quantify composition drift.
    static float computeCompositionResidual(const uint8_t* srcRgba, const uint8_t* outRgba, int width, int height);
};

} // namespace reranger::humanize
