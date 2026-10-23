#include "humanize_spike.h"
#include <cmath>
#include <algorithm>
#include <cassert>

namespace reranger::humanize {

HardwareAssessment HumanizeSpike::assessHardware(uint64_t totalRamBytes, uint64_t freeRamBytes) {
    HardwareAssessment res;
    res.totalRamBytes = totalRamBytes;
    res.freeRamBytes = freeRamBytes;

    const uint64_t GB = 1024ULL * 1024ULL * 1024ULL;

    if (totalRamBytes >= 8 * GB) {
        res.profile = HardwareProfile::FLAGSHIP_SUPPORTED;
        res.recommendation = "Full on-device GGUF Q4_0 diffusion supported (SD 1.5 / LCM).";
    } else if (totalRamBytes >= 6 * GB) {
        res.profile = HardwareProfile::CONSTRAINED_SUPPORTED;
        res.recommendation = "Constrained: Low-resolution 384x384 or fast LCM (8 steps) required.";
    } else {
        res.profile = HardwareProfile::UNSUPPORTED_OOM_RISK;
        res.recommendation = "Blocked: <6 GB RAM risks Android lowmemorykiller foreground termination.";
    }
    return res;
}

LatentTensor HumanizeSpike::encodeToLatents(const uint8_t* rgba, int width, int height) {
    // VAE compresses spatial dimensions by 8x (e.g. 512x512 -> 64x64 latent, 4 channels)
    const int latentW = std::max(1, width / 8);
    const int latentH = std::max(1, height / 8);
    const int channels = 4;

    LatentTensor tensor;
    tensor.channels = channels;
    tensor.height = latentH;
    tensor.width = latentW;
    tensor.data.resize(channels * latentH * latentW, 0.0f);

    for (int ly = 0; ly < latentH; ++ly) {
        for (int lx = 0; lx < latentW; ++lx) {
            // Average over the 8x8 spatial block
            float avgR = 0.0f, avgG = 0.0f, avgB = 0.0f, avgA = 0.0f;
            int count = 0;

            for (int dy = 0; dy < 8; ++dy) {
                int py = std::min(height - 1, ly * 8 + dy);
                for (int dx = 0; dx < 8; ++dx) {
                    int px = std::min(width - 1, lx * 8 + dx);
                    int off = (py * width + px) * 4;
                    avgR += (rgba[off] / 127.5f) - 1.0f;     // Normalized to [-1.0, 1.0]
                    avgG += (rgba[off + 1] / 127.5f) - 1.0f;
                    avgB += (rgba[off + 2] / 127.5f) - 1.0f;
                    avgA += (rgba[off + 3] / 255.0f);
                    count++;
                }
            }
            int idx = ly * latentW + lx;
            tensor.data[0 * (latentH * latentW) + idx] = avgR / count;
            tensor.data[1 * (latentH * latentW) + idx] = avgG / count;
            tensor.data[2 * (latentH * latentW) + idx] = avgB / count;
            tensor.data[3 * (latentH * latentW) + idx] = avgA / count;
        }
    }
    return tensor;
}

LatentTensor HumanizeSpike::addDiffusionNoise(const LatentTensor& z0, float strength, uint32_t seed) {
    LatentTensor zt = z0;
    const float clampedStrength = std::clamp(strength, 0.0f, 1.0f);

    // Linear beta schedule approximation: alpha_bar decreases with strength
    // strength = 0.0 -> alpha_bar = 1.0 (no noise, exact source)
    // strength = 1.0 -> alpha_bar = 0.0 (pure random noise)
    const float alphaBar = std::clamp(1.0f - clampedStrength, 0.0f, 1.0f);
    const float sqrtAlphaBar = std::sqrt(alphaBar);
    const float sqrtOneMinusAlphaBar = std::sqrt(1.0f - alphaBar);

    uint32_t state = seed;
    auto lcg_noise = [&]() -> float {
        state = state * 1664525u + 1013904223u;
        // Box-Muller uniform to standard normal approximation [-1.0, 1.0]
        return (((state & 0xFFFFu) / 32768.0f) - 1.0f);
    };

    for (size_t i = 0; i < zt.data.size(); ++i) {
        float noise = lcg_noise();
        zt.data[i] = sqrtAlphaBar * z0.data[i] + sqrtOneMinusAlphaBar * noise;
    }
    return zt;
}

void HumanizeSpike::decodeToRgba(const LatentTensor& z, uint8_t* rgbaOut, int width, int height) {
    const int latentW = z.width;
    const int latentH = z.height;

    for (int y = 0; y < height; ++y) {
        int ly = std::min(latentH - 1, y / 8);
        for (int x = 0; x < width; ++x) {
            int lx = std::min(latentW - 1, x / 8);
            int idx = ly * latentW + lx;

            float rNorm = z.data[0 * (latentH * latentW) + idx];
            float gNorm = z.data[1 * (latentH * latentW) + idx];
            float bNorm = z.data[2 * (latentH * latentW) + idx];
            float aNorm = z.data[3 * (latentH * latentW) + idx];

            uint8_t r = static_cast<uint8_t>(std::clamp(std::round((rNorm + 1.0f) * 127.5f), 0.0f, 255.0f));
            uint8_t g = static_cast<uint8_t>(std::clamp(std::round((gNorm + 1.0f) * 127.5f), 0.0f, 255.0f));
            uint8_t b = static_cast<uint8_t>(std::clamp(std::round((bNorm + 1.0f) * 127.5f), 0.0f, 255.0f));
            uint8_t a = static_cast<uint8_t>(std::clamp(std::round(aNorm * 255.0f), 0.0f, 255.0f));

            int off = (y * width + x) * 4;
            rgbaOut[off] = r;
            rgbaOut[off + 1] = g;
            rgbaOut[off + 2] = b;
            rgbaOut[off + 3] = a;
        }
    }
}

float HumanizeSpike::computeCompositionResidual(const uint8_t* srcRgba, const uint8_t* outRgba, int width, int height) {
    double totalDiff = 0.0;
    const int totalPixels = width * height;

    for (int i = 0; i < totalPixels; ++i) {
        int off = i * 4;
        totalDiff += std::abs(static_cast<int>(srcRgba[off]) - static_cast<int>(outRgba[off]));
        totalDiff += std::abs(static_cast<int>(srcRgba[off + 1]) - static_cast<int>(outRgba[off + 1]));
        totalDiff += std::abs(static_cast<int>(srcRgba[off + 2]) - static_cast<int>(outRgba[off + 2]));
    }
    // Normalized Mean Absolute Error [0.0, 1.0] across RGB channels
    return static_cast<float>(totalDiff / (totalPixels * 3.0 * 255.0));
}

} // namespace reranger::humanize
