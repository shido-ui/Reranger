#include "classical_engine.h"
#include <iostream>
#include <vector>
#include <chrono>

void benchmark_op(const char* name, void (*fn)(), int iterations) {
    // Warmup
    fn();

    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < iterations; ++i) {
        fn();
    }
    auto end = std::chrono::high_resolution_clock::now();

    std::chrono::duration<double, std::milli> duration = end - start;
    double avg_ms = duration.count() / iterations;
    std::cout << "  • " << name << ": " << avg_ms << " ms / op (averaged over " << iterations << " runs)" << std::endl;
}

int main() {
    std::cout << "=== RERANGER NATIVE C++ BENCHMARK SUITE ===" << std::endl;

    // 1. Medium: 400x300 = 120,000 pixels
    const int mw = 400, mh = 300;
    std::vector<uint8_t> m_src(mw * mh * 4, 180);
    std::vector<uint8_t> m_dst(mw * mh * 4, 0);

    std::cout << "\n--- [1] Medium Fixture (400 x 300 = 120,000 pixels) ---" << std::endl;

    auto m_gray = [&]() { native_to_grayscale(m_src.data(), m_dst.data(), mw, mh); };
    auto m_sobel = [&]() { native_sobel_edges(m_src.data(), m_dst.data(), mw, mh); };
    auto m_grain = [&]() { native_grain_overlay(m_src.data(), m_dst.data(), mw, mh, 42, 0.15f); };
    auto m_rec1 = [&]() { native_recipe_monochrome_ink(m_src.data(), m_dst.data(), mw, mh); };

    benchmark_op("Native Grayscale (BT.601)", +[](){
        static std::vector<uint8_t> s(400 * 300 * 4, 180), d(400 * 300 * 4, 0);
        native_to_grayscale(s.data(), d.data(), 400, 300);
    }, 50);

    benchmark_op("Native Sobel Edge Detection", +[](){
        static std::vector<uint8_t> s(400 * 300 * 4, 180), d(400 * 300 * 4, 0);
        native_sobel_edges(s.data(), d.data(), 400, 300);
    }, 50);

    benchmark_op("Native Grain Overlay", +[](){
        static std::vector<uint8_t> s(400 * 300 * 4, 180), d(400 * 300 * 4, 0);
        native_grain_overlay(s.data(), d.data(), 400, 300, 42, 0.15f);
    }, 50);

    benchmark_op("Native Recipe 1: Monochrome Ink", +[](){
        static std::vector<uint8_t> s(400 * 300 * 4, 180), d(400 * 300 * 4, 0);
        native_recipe_monochrome_ink(s.data(), d.data(), 400, 300);
    }, 50);

    // 2. Large: 12MP (4000 x 3000 = 12,000,000 pixels)
    std::cout << "\n--- [2] Large Fixture (4000 x 3000 = 12 Megapixels = 48MB) ---" << std::endl;
    static std::vector<uint8_t> l_src(4000 * 3000 * 4, 180);
    static std::vector<uint8_t> l_dst(4000 * 3000 * 4, 0);

    benchmark_op("Native 12MP Grayscale", +[](){
        native_to_grayscale(l_src.data(), l_dst.data(), 4000, 3000);
    }, 3);

    benchmark_op("Native 12MP Sobel Edge Detection", +[](){
        native_sobel_edges(l_src.data(), l_dst.data(), 4000, 3000);
    }, 1);

    benchmark_op("Native 12MP Grain Overlay", +[](){
        native_grain_overlay(l_src.data(), l_dst.data(), 4000, 3000, 42, 0.15f);
    }, 2);

    benchmark_op("Native 12MP Recipe 1: Monochrome Ink", +[](){
        native_recipe_monochrome_ink(l_src.data(), l_dst.data(), 4000, 3000);
    }, 1);

    std::cout << "\n=== NATIVE BENCHMARK COMPLETE ===" << std::endl;
    return 0;
}
