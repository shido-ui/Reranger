#include "classical_engine.h"
#include <cmath>
#include <algorithm>
#include <vector>

extern "C" {

void native_to_grayscale(const uint8_t* src, uint8_t* dst, int width, int height) {
    const int total = width * height;
    for (int i = 0; i < total; ++i) {
        const int off = i * 4;
        const uint32_t r = src[off];
        const uint32_t g = src[off + 1];
        const uint32_t b = src[off + 2];
        const uint8_t a = src[off + 3];

        const uint8_t y = static_cast<uint8_t>(std::clamp((299 * r + 587 * g + 114 * b) / 1000, 0u, 255u));

        dst[off] = y;
        dst[off + 1] = y;
        dst[off + 2] = y;
        dst[off + 3] = a;
    }
}

void native_sobel_edges(const uint8_t* src, uint8_t* dst, int width, int height) {
    if (width < 2 || height < 2) {
        std::fill(dst, dst + width * height * 4, 0);
        for (int i = 0; i < width * height; ++i) {
            dst[i * 4 + 3] = src[i * 4 + 3];
        }
        return;
    }

    std::vector<uint8_t> lum(width * height);
    for (int i = 0; i < width * height; ++i) {
        const int off = i * 4;
        lum[i] = static_cast<uint8_t>(std::clamp((299 * src[off] + 587 * src[off + 1] + 114 * src[off + 2]) / 1000, 0, 255));
    }

    auto get_lum = [&](int x, int y) -> int {
        int cx = std::clamp(x, 0, width - 1);
        int cy = std::clamp(y, 0, height - 1);
        return lum[cy * width + cx];
    };

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            int gx = (get_lum(x + 1, y - 1) + 2 * get_lum(x + 1, y) + get_lum(x + 1, y + 1)) -
                     (get_lum(x - 1, y - 1) + 2 * get_lum(x - 1, y) + get_lum(x - 1, y + 1));

            int gy = (get_lum(x - 1, y + 1) + 2 * get_lum(x, y + 1) + get_lum(x + 1, y + 1)) -
                     (get_lum(x - 1, y - 1) + 2 * get_lum(x, y - 1) + get_lum(x + 1, y - 1));

            int mag = static_cast<int>(std::clamp(std::round(std::sqrt(gx * gx + gy * gy)), 0.0, 255.0));

            const int off = (y * width + x) * 4;
            dst[off] = static_cast<uint8_t>(mag);
            dst[off + 1] = static_cast<uint8_t>(mag);
            dst[off + 2] = static_cast<uint8_t>(mag);
            dst[off + 3] = src[off + 3]; // Preserve original alpha
        }
    }
}

void native_grain_overlay(const uint8_t* src, uint8_t* dst, int width, int height, uint32_t seed, float intensity) {
    const int total = width * height;
    uint32_t state = seed;
    const float scale = intensity * 128.0f;

    for (int i = 0; i < total; ++i) {
        const int off = i * 4;
        state = state * 1664525u + 1013904223u;
        float noise = (((state & 0xFFFFu) / 32768.0f) - 1.0f) * scale;
        const float alpha_factor = src[off + 3] / 255.0f;
        const float effective_noise = noise * alpha_factor;

        dst[off] = static_cast<uint8_t>(std::clamp(std::round(src[off] + effective_noise), 0.0f, 255.0f));
        dst[off + 1] = static_cast<uint8_t>(std::clamp(std::round(src[off + 1] + effective_noise), 0.0f, 255.0f));
        dst[off + 2] = static_cast<uint8_t>(std::clamp(std::round(src[off + 2] + effective_noise), 0.0f, 255.0f));
        dst[off + 3] = src[off + 3];
    }
}

void native_recipe_monochrome_ink(const uint8_t* src, uint8_t* dst, int width, int height) {
    const int total = width * height;
    std::vector<uint8_t> gray(total * 4);
    std::vector<uint8_t> edges(total * 4);

    native_to_grayscale(src, gray.data(), width, height);
    native_sobel_edges(src, edges.data(), width, height);

    for (int i = 0; i < total; ++i) {
        const int off = i * 4;
        int g = gray[off];
        int e = edges[off];

        int ink = std::clamp(g - static_cast<int>(std::round(e * 0.85f)), 0, 255);
        float norm = ink / 255.0f;
        uint8_t final_val = static_cast<uint8_t>(std::clamp(std::round(std::pow(norm, 1.5f) * 255.0f), 0.0f, 255.0f));

        dst[off] = final_val;
        dst[off + 1] = final_val;
        dst[off + 2] = final_val;
        dst[off + 3] = gray[off + 3];
    }
}

// Academic Adversarial Robustness Research
void native_adversarial_stealth(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength,
    int apply_frequency_perturbation
) {
    const int total = width * height;
    if (total == 0) return;

    // Epsilon magnitude scaled by strength [0.0, 1.0] -> [0.0, 6.0] intensity levels
    const float eps = std::clamp(strength, 0.0f, 1.0f) * 6.0f;
    if (eps <= 0.001f) {
        std::copy(src, src + total * 4, dst);
        return;
    }

    // 1. Calculate luminance channel
    std::vector<float> lum(total);
    for (int i = 0; i < total; ++i) {
        const int off = i * 4;
        lum[i] = (299.0f * src[off] + 587.0f * src[off + 1] + 114.0f * src[off + 2]) / 1000.0f;
    }

    auto get_lum = [&](int x, int y) -> float {
        int cx = std::clamp(x, 0, width - 1);
        int cy = std::clamp(y, 0, height - 1);
        return lum[cy * width + cx];
    };

    // 2. Compute spatial gradients (Laplacian + Sobel high-pass frequency field)
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const int idx = y * width + x;
            const int off = idx * 4;

            // Spatial high-frequency Laplacian: 4 * center - sum(neighbors)
            float laplacian = 4.0f * get_lum(x, y) - get_lum(x + 1, y) - get_lum(x - 1, y) - get_lum(x, y + 1) - get_lum(x, y - 1);

            // Spatial Sobel horizontal & vertical gradients
            float gx = (get_lum(x + 1, y - 1) + 2.0f * get_lum(x + 1, y) + get_lum(x + 1, y + 1)) -
                       (get_lum(x - 1, y - 1) + 2.0f * get_lum(x - 1, y) + get_lum(x - 1, y + 1));
            float gy = (get_lum(x - 1, y + 1) + 2.0f * get_lum(x, y + 1) + get_lum(x + 1, y + 1)) -
                       (get_lum(x - 1, y - 1) + 2.0f * get_lum(x, y - 1) + get_lum(x + 1, y - 1));

            // Combined directional gradient sign (Fast Gradient Sign Method)
            float grad = gx + gy;
            if (apply_frequency_perturbation) {
                // High-frequency phase modulation
                float phase = std::sin(static_cast<float>(x * 0.75f + y * 0.75f));
                grad += laplacian * 0.5f + phase * 2.0f;
            }

            // sign(gradient)
            float sign_val = (grad > 0.0f) ? 1.0f : ((grad < 0.0f) ? -1.0f : 0.0f);
            if (sign_val == 0.0f) {
                sign_val = ((idx % 2) == 0) ? 1.0f : -1.0f;
            }

            float delta = sign_val * eps;
            const float alpha_factor = src[off + 3] / 255.0f;
            delta *= alpha_factor;

            dst[off] = static_cast<uint8_t>(std::clamp(std::round(src[off] + delta), 0.0f, 255.0f));
            dst[off + 1] = static_cast<uint8_t>(std::clamp(std::round(src[off + 1] + delta), 0.0f, 255.0f));
            dst[off + 2] = static_cast<uint8_t>(std::clamp(std::round(src[off + 2] + delta), 0.0f, 255.0f));
            dst[off + 3] = src[off + 3];
        }
    }
}

} // extern "C"
