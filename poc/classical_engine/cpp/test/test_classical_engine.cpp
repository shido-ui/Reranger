#include "classical_engine.h"
#include <iostream>
#include <cassert>
#include <vector>
#include <cmath>

void test_grayscale() {
    std::cout << "[RUN] test_grayscale..." << std::endl;
    // 2x2: (0,0)=Red, (1,0)=Green, (0,1)=Blue, (1,1)=White
    std::vector<uint8_t> src = {
        255, 0, 0, 255,      0, 255, 0, 255,
        0, 0, 255, 255,      255, 255, 255, 255
    };
    std::vector<uint8_t> dst(16, 0);

    native_to_grayscale(src.data(), dst.data(), 2, 2);

    // Red -> (299 * 255) / 1000 = 76
    assert(dst[0] == 76);
    assert(dst[1] == 76);
    assert(dst[2] == 76);
    assert(dst[3] == 255); // Alpha preserved

    // Green -> (587 * 255) / 1000 = 149
    assert(dst[4] == 149);

    // Blue -> (114 * 255) / 1000 = 29
    assert(dst[8] == 29);

    // White -> 254 or 255
    assert(dst[12] >= 254 && dst[12] <= 255);
    std::cout << "[PASS] test_grayscale passed." << std::endl;
}

void test_sobel_edges() {
    std::cout << "[RUN] test_sobel_edges..." << std::endl;
    const int w = 16, h = 16;
    std::vector<uint8_t> src(w * h * 4, 0);
    // Vertical step edge: left is black (0), right is white (255)
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint8_t v = (x < 8) ? 0 : 255;
            int off = (y * w + x) * 4;
            src[off] = v;
            src[off + 1] = v;
            src[off + 2] = v;
            src[off + 3] = 255;
        }
    }
    std::vector<uint8_t> dst(w * h * 4, 0);
    native_sobel_edges(src.data(), dst.data(), w, h);

    // Uniform areas have 0 gradient
    assert(dst[0] == 0); // far left (x=0, y=0)
    assert(dst[(0 * w + 15) * 4] == 0); // far right

    // Edge near x=7 and x=8 has high gradient
    int edge_val = dst[(8 * w + 7) * 4];
    assert(edge_val > 200);

    std::cout << "[PASS] test_sobel_edges passed." << std::endl;
}

void test_grain_overlay() {
    std::cout << "[RUN] test_grain_overlay..." << std::endl;
    std::vector<uint8_t> src(100 * 4, 128); // flat gray
    std::vector<uint8_t> dst1(100 * 4, 0);
    std::vector<uint8_t> dst2(100 * 4, 0);

    native_grain_overlay(src.data(), dst1.data(), 10, 10, 42, 0.15f);
    native_grain_overlay(src.data(), dst2.data(), 10, 10, 42, 0.15f);

    // Repeatability check: identical seed produces identical bytes
    for (size_t i = 0; i < dst1.size(); ++i) {
        assert(dst1[i] == dst2[i]);
    }
    // Check that some noise was actually added
    bool has_variance = false;
    for (size_t i = 0; i < dst1.size(); i += 4) {
        if (dst1[i] != 128) {
            has_variance = true;
            break;
        }
    }
    assert(has_variance);
    std::cout << "[PASS] test_grain_overlay passed." << std::endl;
}

void test_recipe_monochrome_ink() {
    std::cout << "[RUN] test_recipe_monochrome_ink..." << std::endl;
    std::vector<uint8_t> src(16 * 16 * 4, 180);
    std::vector<uint8_t> dst(16 * 16 * 4, 0);

    native_recipe_monochrome_ink(src.data(), dst.data(), 16, 16);

    for (size_t i = 0; i < dst.size(); i += 4) {
        // Pure grayscale: R == G == B
        assert(dst[i] == dst[i + 1]);
        assert(dst[i + 1] == dst[i + 2]);
        assert(dst[i + 3] == 180); // alpha preserved
    }
    std::cout << "[PASS] test_recipe_monochrome_ink passed." << std::endl;
}

int main() {
    std::cout << "=== Reranger Native C++ Classical Engine PoC Test Suite ===" << std::endl;
    test_grayscale();
    test_sobel_edges();
    test_grain_overlay();
    test_recipe_monochrome_ink();
    std::cout << "=== ALL NATIVE C++ TESTS PASSED (100%) ===" << std::endl;
    return 0;
}
