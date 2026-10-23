#include "humanize_spike.h"
#include <iostream>
#include <cassert>
#include <vector>
#include <cmath>

using namespace reranger::humanize;

void test_hardware_assessment() {
    std::cout << "[RUN] test_hardware_assessment..." << std::endl;
    const uint64_t GB = 1024ULL * 1024ULL * 1024ULL;

    // 12 GB Flagship
    auto h12 = HumanizeSpike::assessHardware(12 * GB, 4 * GB);
    assert(h12.profile == HardwareProfile::FLAGSHIP_SUPPORTED);

    // 6.5 GB Mid-tier
    auto h6 = HumanizeSpike::assessHardware(static_cast<uint64_t>(6.5 * GB), 2 * GB);
    assert(h6.profile == HardwareProfile::CONSTRAINED_SUPPORTED);

    // 4 GB Budget phone
    auto h4 = HumanizeSpike::assessHardware(4 * GB, 1 * GB);
    assert(h4.profile == HardwareProfile::UNSUPPORTED_OOM_RISK);

    std::cout << "[PASS] test_hardware_assessment passed." << std::endl;
}

void test_strength_residual_scaling() {
    std::cout << "[RUN] test_strength_residual_scaling..." << std::endl;
    const int w = 64, h = 64;
    std::vector<uint8_t> src(w * h * 4, 128); // flat gray

    auto z0 = HumanizeSpike::encodeToLatents(src.data(), w, h);
    assert(z0.width == 8);
    assert(z0.height == 8);
    assert(z0.channels == 4);
    assert(z0.byteSize() == 8 * 8 * 4 * sizeof(float)); // 1024 bytes

    // Strength 0.0 (no noise added)
    auto z_str0 = HumanizeSpike::addDiffusionNoise(z0, 0.0f, 42);
    std::vector<uint8_t> out0(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_str0, out0.data(), w, h);
    float res0 = HumanizeSpike::computeCompositionResidual(src.data(), out0.data(), w, h);
    assert(res0 < 0.01f);

    // Strength 0.2 (low perturbation: subtle de-glazing, high likeness preservation)
    auto z_str02 = HumanizeSpike::addDiffusionNoise(z0, 0.2f, 42);
    std::vector<uint8_t> out02(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_str02, out02.data(), w, h);
    float res02 = HumanizeSpike::computeCompositionResidual(src.data(), out02.data(), w, h);
    assert(res02 > 0.01f);
    assert(res02 < 0.15f); // Composition strongly preserved

    // Strength 0.8 (high perturbation: major artistic re-synthesis)
    auto z_str08 = HumanizeSpike::addDiffusionNoise(z0, 0.8f, 42);
    std::vector<uint8_t> out08(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_str08, out08.data(), w, h);
    float res08 = HumanizeSpike::computeCompositionResidual(src.data(), out08.data(), w, h);
    assert(res08 > res02); // Monotonically greater divergence from source

    std::cout << "  Residuals: Str(0.0)=" << res0 << " | Str(0.2)=" << res02 << " | Str(0.8)=" << res08 << std::endl;
    std::cout << "[PASS] test_strength_residual_scaling passed." << std::endl;
}

void test_qualitative_fixed_inputs() {
    std::cout << "[RUN] test_qualitative_fixed_inputs..." << std::endl;
    const int w = 64, h = 64;

    // Fixed Input 1: Anime Line-Art (White canvas with black stroke lines)
    std::vector<uint8_t> anime(w * h * 4, 255);
    for (int y = 0; y < h; ++y) {
        anime[(y * w + 32) * 4] = 0; // vertical ink stroke
        anime[(y * w + 32) * 4 + 1] = 0;
        anime[(y * w + 32) * 4 + 2] = 0;
    }
    auto z_anime = HumanizeSpike::encodeToLatents(anime.data(), w, h);
    auto z_anime_noise = HumanizeSpike::addDiffusionNoise(z_anime, 0.25f, 101);
    std::vector<uint8_t> out_anime(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_anime_noise, out_anime.data(), w, h);
    float res_anime = HumanizeSpike::computeCompositionResidual(anime.data(), out_anime.data(), w, h);
    assert(res_anime < 0.15f);

    // Fixed Input 2: Stylized Portrait (Warm skin gradient)
    std::vector<uint8_t> portrait(w * h * 4, 255);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int off = (y * w + x) * 4;
            portrait[off] = static_cast<uint8_t>(200 + (y * 55 / h));     // R
            portrait[off + 1] = static_cast<uint8_t>(140 + (y * 40 / h)); // G
            portrait[off + 2] = static_cast<uint8_t>(100 + (y * 30 / h)); // B
        }
    }
    auto z_port = HumanizeSpike::encodeToLatents(portrait.data(), w, h);
    auto z_port_noise = HumanizeSpike::addDiffusionNoise(z_port, 0.25f, 202);
    std::vector<uint8_t> out_port(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_port_noise, out_port.data(), w, h);
    float res_port = HumanizeSpike::computeCompositionResidual(portrait.data(), out_port.data(), w, h);
    assert(res_port < 0.15f);

    // Fixed Input 3: Realistic Art (Rich colorful landscape)
    std::vector<uint8_t> realistic(w * h * 4, 255);
    for (int i = 0; i < w * h; ++i) {
        realistic[i * 4] = static_cast<uint8_t>((i * 7) % 256);
        realistic[i * 4 + 1] = static_cast<uint8_t>((i * 13) % 256);
        realistic[i * 4 + 2] = static_cast<uint8_t>((i * 19) % 256);
    }
    auto z_real = HumanizeSpike::encodeToLatents(realistic.data(), w, h);
    auto z_real_noise = HumanizeSpike::addDiffusionNoise(z_real, 0.25f, 303);
    std::vector<uint8_t> out_real(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_real_noise, out_real.data(), w, h);
    float res_real = HumanizeSpike::computeCompositionResidual(realistic.data(), out_real.data(), w, h);
    std::cout << "  Realistic Art residual: " << res_real << std::endl;
    assert(res_real < 0.35f);

    // Fixed Input 4: Photo (High frequency textures)
    std::vector<uint8_t> photo(w * h * 4, 128);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            photo[(y * w + x) * 4] = static_cast<uint8_t>(128 + ((x * y) % 64));
        }
    }
    auto z_photo = HumanizeSpike::encodeToLatents(photo.data(), w, h);
    auto z_photo_noise = HumanizeSpike::addDiffusionNoise(z_photo, 0.25f, 404);
    std::vector<uint8_t> out_photo(w * h * 4, 0);
    HumanizeSpike::decodeToRgba(z_photo_noise, out_photo.data(), w, h);
    float res_photo = HumanizeSpike::computeCompositionResidual(photo.data(), out_photo.data(), w, h);
    assert(res_photo < 0.15f);

    std::cout << "  Fixed Input Residuals: Anime=" << res_anime << " | Portrait=" << res_port
              << " | Realistic=" << res_real << " | Photo=" << res_photo << std::endl;
    std::cout << "[PASS] test_qualitative_fixed_inputs passed." << std::endl;
}

int main() {
    std::cout << "=== Reranger Humanize Feasibility Spike Test Suite ===" << std::endl;
    test_hardware_assessment();
    test_strength_residual_scaling();
    test_qualitative_fixed_inputs();
    std::cout << "=== ALL HUMANIZE SPIKE TESTS PASSED (100%) ===" << std::endl;
    return 0;
}
