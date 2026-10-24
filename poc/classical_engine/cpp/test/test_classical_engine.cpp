#include "classical_engine.h"
#include <iostream>
#include <cassert>
#include <vector>
#include <cmath>
#include <algorithm>
#include <chrono>
#include <cstring>

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

static float compute_hue(uint8_t r, uint8_t g, uint8_t b) {
    float rf = r / 255.0f, gf = g / 255.0f, bf = b / 255.0f;
    float max_v = std::max({rf, gf, bf});
    float min_v = std::min({rf, gf, bf});
    float delta = max_v - min_v;
    if (delta < 1e-4f) return 0.0f;
    float h = 0.0f;
    if (max_v == rf) {
        h = 60.0f * std::fmod(((gf - bf) / delta), 6.0f);
    } else if (max_v == gf) {
        h = 60.0f * (((bf - rf) / delta) + 2.0f);
    } else {
        h = 60.0f * (((rf - gf) / delta) + 4.0f);
    }
    if (h < 0.0f) h += 360.0f;
    return h;
}

void test_adaptive_vibrancy() {
    std::cout << "[RUN] test_adaptive_vibrancy..." << std::endl;

    // 1. Pink test: RGB(255, 105, 180)
    std::vector<uint8_t> pink_src = {255, 105, 180, 255, 255, 105, 180, 255, 255, 105, 180, 255, 255, 105, 180, 255};
    std::vector<uint8_t> pink_dst(16, 0);
    native_adaptive_vibrancy(pink_src.data(), pink_dst.data(), 2, 2, 0.35f, 0.20f);
    float pink_hue = compute_hue(pink_dst[0], pink_dst[1], pink_dst[2]);
    bool is_pink = (pink_hue >= 300.0f && pink_hue <= 360.0f) || (pink_hue >= 0.0f && pink_hue <= 10.0f);
    assert(is_pink);
    assert(pink_dst[3] == 255); // Alpha preserved

    // 2. Blue test: RGB(30, 100, 255)
    std::vector<uint8_t> blue_src = {30, 100, 255, 255, 30, 100, 255, 255, 30, 100, 255, 255, 30, 100, 255, 255};
    std::vector<uint8_t> blue_dst(16, 0);
    native_adaptive_vibrancy(blue_src.data(), blue_dst.data(), 2, 2, 0.35f, 0.20f);
    float blue_hue = compute_hue(blue_dst[0], blue_dst[1], blue_dst[2]);
    bool is_blue = (blue_hue >= 190.0f && blue_hue <= 250.0f);
    assert(is_blue);
    assert(blue_dst[3] == 255); // Alpha preserved

    // 3. Gray neutrality test: RGB(128, 128, 128)
    std::vector<uint8_t> gray_src = {128, 128, 128, 255};
    std::vector<uint8_t> gray_dst(4, 0);
    native_adaptive_vibrancy(gray_src.data(), gray_dst.data(), 1, 1, 0.50f, 0.30f);
    assert(gray_dst[0] == gray_dst[1] && gray_dst[1] == gray_dst[2]);
    assert(gray_dst[3] == 255);

    std::cout << "[PASS] test_adaptive_vibrancy passed." << std::endl;
}

void test_edgetam_hair_segmentation_no_bleed() {
    std::cout << "[RUN] test_edgetam_hair_segmentation_no_bleed..." << std::endl;

    const int w = 128, h = 128;
    std::vector<uint8_t> portrait_rgba(w * h * 4, 0);

    // Build synthetic portrait scene:
    // Background: light wall (245, 250, 255)
    // Hair: top head region (35, 25, 20) with fine texture variance
    // Face: skin (230, 180, 150)
    // Clothes: blue shirt (20, 80, 200)
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const int off = (y * w + x) * 4;
            if (y >= 12 && y <= 45 && x >= 32 && x <= 96) {
                // Hair region: dark brown/black with subtle strand texture
                uint8_t noise = static_cast<uint8_t>((((x * 17 + y * 31) ^ 0x4f) % 15));
                portrait_rgba[off]     = 35 + noise;
                portrait_rgba[off + 1] = 25 + noise;
                portrait_rgba[off + 2] = 20 + noise;
                portrait_rgba[off + 3] = 255;
            } else if (y >= 46 && y <= 92 && x >= 36 && x <= 92) {
                // Face skin
                portrait_rgba[off]     = 230;
                portrait_rgba[off + 1] = 180;
                portrait_rgba[off + 2] = 150;
                portrait_rgba[off + 3] = 255;
            } else if (y >= 93 && x >= 24 && x <= 104) {
                // Clothing
                portrait_rgba[off]     = 20;
                portrait_rgba[off + 1] = 80;
                portrait_rgba[off + 2] = 200;
                portrait_rgba[off + 3] = 255;
            } else {
                // Background
                portrait_rgba[off]     = 245;
                portrait_rgba[off + 1] = 250;
                portrait_rgba[off + 2] = 255;
                portrait_rgba[off + 3] = 255;
            }
        }
    }

    // 1. Test Coordinate Mapper View -> Padded 1024x1024
    float view_w = 360.0f, view_h = 640.0f;
    // Tap on hair at x=64, y=28 in image space
    float tap_src_x = 64.0f, tap_src_y = 28.0f;
    float scale = std::min(view_w / w, view_h / h); // 360 / 128 = 2.8125
    float offset_x = (view_w - w * scale) * 0.5f; // 0.0
    float offset_y = (view_h - h * scale) * 0.5f; // (640 - 360) / 2 = 140.0
    float tap_view_x = offset_x + tap_src_x * scale;
    float tap_view_y = offset_y + tap_src_y * scale;

    float out_src_x = 0, out_src_y = 0, out_pad_x = 0, out_pad_y = 0;
    int active_w = 0, active_h = 0;
    native_edgetam_map_view_to_padded(
        tap_view_x, tap_view_y, view_w, view_h,
        w, h,
        &out_src_x, &out_src_y,
        &out_pad_x, &out_pad_y,
        &active_w, &active_h
    );

    assert(std::abs(out_src_x - tap_src_x) < 1.0f);
    assert(std::abs(out_src_y - tap_src_y) < 1.0f);
    assert(active_w == 1024 && active_h == 1024); // Square image scaled to 1024x1024

    // 2. Test EdgeTAM Create
    void* handle = native_edgetam_create("assets/models/edgetam.pte");
    assert(handle != nullptr);

    // 3. Test EdgeTAM Encoder (runs once on image load)
    std::vector<float> embedding(EDGETAM_EMBEDDING_SIZE, 0.0f);
    auto start_enc = std::chrono::high_resolution_clock::now();
    int enc_res = native_edgetam_encode(handle, portrait_rgba.data(), w, h, embedding.data(), EDGETAM_EMBEDDING_SIZE);
    auto end_enc = std::chrono::high_resolution_clock::now();
    double enc_ms = std::chrono::duration<double, std::milli>(end_enc - start_enc).count();

    assert(enc_res == 0);
    std::cout << "   [Benchmark] EdgeTAM Encoder Latency: " << enc_ms << " ms" << std::endl;
    // Encoder must run within reasonable mobile time (< 500 ms)
    assert(enc_ms < 500.0);

    // 4. Test EdgeTAM Decoder (runs per tap)
    std::vector<uint8_t> mask_1024(1024 * 1024, 0);
    auto start_dec = std::chrono::high_resolution_clock::now();
    int dec_res = native_edgetam_decode(
        handle, embedding.data(), EDGETAM_EMBEDDING_SIZE,
        out_pad_x, out_pad_y,
        EDGETAM_CATEGORY_HAIR,
        mask_1024.data()
    );
    auto end_dec = std::chrono::high_resolution_clock::now();
    double dec_ms = std::chrono::duration<double, std::milli>(end_dec - start_dec).count();

    assert(dec_res == 0);
    std::cout << "   [Benchmark] EdgeTAM Decoder Latency: " << dec_ms << " ms" << std::endl;
    // Decoder must run within reasonable interactive time (< 50 ms)
    assert(dec_ms < 50.0);

    // 5. Test Reverse Resampling back to source dimensions (128x128)
    std::vector<uint8_t> mask_src(w * h, 0);
    native_edgetam_resample_mask_to_source(mask_1024.data(), active_w, active_h, mask_src.data(), w, h);

    // 6. Verify mask precision and zero bleed into background
    int hair_pixels = 0, hair_selected = 0;
    int bg_pixels = 0, bg_selected = 0;

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint8_t m = mask_src[y * w + x];
            if (y >= 16 && y <= 40 && x >= 36 && x <= 92) {
                // Core hair region
                hair_pixels++;
                if (m > 128) hair_selected++;
            } else if (x <= 15 || x >= 112 || y <= 6) {
                // Outer background region
                bg_pixels++;
                if (m > 0) bg_selected++;
            }
        }
    }

    double hair_recall = (double)hair_selected / hair_pixels;
    double bg_bleed = (double)bg_selected / bg_pixels;

    std::cout << "   [Accuracy] Hair Recall: " << (hair_recall * 100.0) << "% (" << hair_selected << "/" << hair_pixels << ")" << std::endl;
    std::cout << "   [Accuracy] Background Bleed: " << (bg_bleed * 100.0) << "% (" << bg_selected << "/" << bg_pixels << ")" << std::endl;

    assert(hair_recall > 0.85); // High hair coverage
    assert(bg_selected == 0);   // STRICT ZERO BLEED INTO BACKGROUND
    assert(bg_bleed == 0.0);

    native_edgetam_destroy(handle);
    std::cout << "[PASS] test_edgetam_hair_segmentation_no_bleed passed." << std::endl;
}

static double compute_ssim_c(const uint8_t* img1, const uint8_t* img2, int width, int height) {
    const int total = width * height;
    if (total == 0) return 1.0;

    double sum1 = 0.0, sum2 = 0.0;
    for (int i = 0; i < total; ++i) {
        int off = i * 4;
        double l1 = (0.299 * img1[off] + 0.587 * img1[off + 1] + 0.114 * img1[off + 2]);
        double l2 = (0.299 * img2[off] + 0.587 * img2[off + 1] + 0.114 * img2[off + 2]);
        sum1 += l1;
        sum2 += l2;
    }
    double mu1 = sum1 / total;
    double mu2 = sum2 / total;

    double var1 = 0.0, var2 = 0.0, covar = 0.0;
    for (int i = 0; i < total; ++i) {
        int off = i * 4;
        double l1 = (0.299 * img1[off] + 0.587 * img1[off + 1] + 0.114 * img1[off + 2]);
        double l2 = (0.299 * img2[off] + 0.587 * img2[off + 1] + 0.114 * img2[off + 2]);
        double d1 = l1 - mu1;
        double d2 = l2 - mu2;
        var1 += d1 * d1;
        var2 += d2 * d2;
        covar += d1 * d2;
    }
    var1 /= (total - 1);
    var2 /= (total - 1);
    covar /= (total - 1);

    const double c1 = 6.5025; // (0.01 * 255)^2
    const double c2 = 58.5225; // (0.03 * 255)^2

    double ssim = ((2.0 * mu1 * mu2 + c1) * (2.0 * covar + c2)) /
                  ((mu1 * mu1 + mu2 * mu2 + c1) * (var1 + var2 + c2));
    return ssim;
}

void test_metadata_annihilation() {
    std::cout << "[RUN] test_metadata_annihilation..." << std::endl;

    // 1. JPEG with EXIF and C2PA APP markers
    std::vector<uint8_t> mock_jpeg;
    // SOI
    mock_jpeg.push_back(0xFF); mock_jpeg.push_back(0xD8);
    // APP1 (EXIF)
    mock_jpeg.push_back(0xFF); mock_jpeg.push_back(0xE1);
    mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x0A); // len 10
    mock_jpeg.push_back('E'); mock_jpeg.push_back('x'); mock_jpeg.push_back('i'); mock_jpeg.push_back('f');
    mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x01); mock_jpeg.push_back(0x02);
    // APP11 (C2PA)
    mock_jpeg.push_back(0xFF); mock_jpeg.push_back(0xEB);
    mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x0A); // len 10
    mock_jpeg.push_back('c'); mock_jpeg.push_back('2'); mock_jpeg.push_back('p'); mock_jpeg.push_back('a');
    mock_jpeg.push_back('j'); mock_jpeg.push_back('u'); mock_jpeg.push_back('m'); mock_jpeg.push_back('b');
    // DQT (Quantization table - essential)
    mock_jpeg.push_back(0xFF); mock_jpeg.push_back(0xDB);
    mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x05); // len 5
    mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x10); mock_jpeg.push_back(0x10);
    // SOS + dummy stream + EOI
    mock_jpeg.push_back(0xFF); mock_jpeg.push_back(0xDA);
    mock_jpeg.push_back(0x00); mock_jpeg.push_back(0x04);
    mock_jpeg.push_back(0x01); mock_jpeg.push_back(0x02);
    mock_jpeg.push_back(0xAA); mock_jpeg.push_back(0xBB);
    mock_jpeg.push_back(0xFF); mock_jpeg.push_back(0xD9); // EOI

    std::vector<uint8_t> clean_jpeg(mock_jpeg.size() * 2, 0);
    size_t clean_len = native_strip_metadata(mock_jpeg.data(), mock_jpeg.size(), clean_jpeg.data(), clean_jpeg.size());
    assert(clean_len > 0);

    // Verify 'Exif' and 'c2pa' are 100% gone
    auto has_sub = [](const uint8_t* b, size_t l, const char* s) -> bool {
        size_t sl = strlen(s);
        if (l < sl) return false;
        for (size_t i = 0; i + sl <= l; ++i) {
            if (memcmp(b + i, s, sl) == 0) return true;
        }
        return false;
    };
    assert(!has_sub(clean_jpeg.data(), clean_len, "Exif"));
    assert(!has_sub(clean_jpeg.data(), clean_len, "c2pa"));
    assert(!has_sub(clean_jpeg.data(), clean_len, "jumb"));
    // Verify DQT is preserved
    assert(has_sub(clean_jpeg.data(), clean_len, "\xFF\xDB"));

    // 2. PNG with eXIf, iTXt, and c2pa chunks
    std::vector<uint8_t> mock_png = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
    auto add_png_chunk = [&](const char* type, const std::vector<uint8_t>& data) {
        uint32_t len = static_cast<uint32_t>(data.size());
        mock_png.push_back((len >> 24) & 0xFF);
        mock_png.push_back((len >> 16) & 0xFF);
        mock_png.push_back((len >> 8) & 0xFF);
        mock_png.push_back(len & 0xFF);
        mock_png.push_back(type[0]); mock_png.push_back(type[1]);
        mock_png.push_back(type[2]); mock_png.push_back(type[3]);
        mock_png.insert(mock_png.end(), data.begin(), data.end());
        // Dummy CRC
        mock_png.push_back(0); mock_png.push_back(0); mock_png.push_back(0); mock_png.push_back(0);
    };

    add_png_chunk("IHDR", {0, 0, 0, 16, 0, 0, 0, 16, 8, 6, 0, 0, 0});
    add_png_chunk("eXIf", {1, 2, 3, 4, 5});
    add_png_chunk("c2pa", {'c', '2', 'p', 'a', '_', 'm', 'a', 'n'});
    add_png_chunk("IDAT", {0x78, 0x9C, 0x63, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01});
    add_png_chunk("IEND", {});

    std::vector<uint8_t> clean_png(mock_png.size() * 2, 0);
    size_t clean_png_len = native_strip_metadata(mock_png.data(), mock_png.size(), clean_png.data(), clean_png.size());
    assert(clean_png_len > 0);
    assert(!has_sub(clean_png.data(), clean_png_len, "eXIf"));
    assert(!has_sub(clean_png.data(), clean_png_len, "c2pa"));
    assert(has_sub(clean_png.data(), clean_png_len, "IHDR"));
    assert(has_sub(clean_png.data(), clean_png_len, "IDAT"));
    assert(has_sub(clean_png.data(), clean_png_len, "IEND"));

    std::cout << "[PASS] test_metadata_annihilation passed." << std::endl;
}

void test_armor_attack_and_ssim() {
    std::cout << "[RUN] test_armor_attack_and_ssim..." << std::endl;

    const int w = 64, h = 64;
    std::vector<uint8_t> src(w * h * 4);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int off = (y * w + x) * 4;
            src[off]     = static_cast<uint8_t>((x * 4) % 256);
            src[off + 1] = static_cast<uint8_t>((y * 4) % 256);
            src[off + 2] = static_cast<uint8_t>(((x + y) * 2) % 256);
            src[off + 3] = 255;
        }
    }

    std::vector<uint8_t> dst(w * h * 4, 0);
    native_armor_attack(src.data(), dst.data(), w, h, 0.75f);

    // Verify not bitwise identical
    assert(memcmp(src.data(), dst.data(), src.size()) != 0);

    // Verify alpha channel untouched
    for (int i = 3; i < static_cast<int>(src.size()); i += 4) {
        assert(dst[i] == 255);
    }

    // Verify SSIM > 0.95
    double ssim = compute_ssim_c(src.data(), dst.data(), w, h);
    std::cout << "   [SSIM] ARMOR UAP SSIM: " << ssim << std::endl;
    assert(ssim > 0.95);

    std::cout << "[PASS] test_armor_attack_and_ssim passed." << std::endl;
}

void test_sensor_noise_and_ssim() {
    std::cout << "[RUN] test_sensor_noise_and_ssim..." << std::endl;

    const int w = 64, h = 64;
    std::vector<uint8_t> src(w * h * 4);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int off = (y * w + x) * 4;
            src[off]     = static_cast<uint8_t>((x * 3 + y * 2) % 256);
            src[off + 1] = static_cast<uint8_t>((x * 2 + y * 3) % 256);
            src[off + 2] = static_cast<uint8_t>((x + y * 4) % 256);
            src[off + 3] = 255;
        }
    }

    std::vector<uint8_t> dst(w * h * 4, 0);
    native_sensor_noise(src.data(), dst.data(), w, h, 0.5f, 0.4f);

    // Verify not bitwise identical
    assert(memcmp(src.data(), dst.data(), src.size()) != 0);

    // Verify SSIM > 0.95
    double ssim = compute_ssim_c(src.data(), dst.data(), w, h);
    std::cout << "   [SSIM] Sensor Noise SSIM: " << ssim << std::endl;
    assert(ssim > 0.95);

    std::cout << "[PASS] test_sensor_noise_and_ssim passed." << std::endl;
}

void test_potrace_vectorization() {
    std::cout << "[RUN] test_potrace_vectorization..." << std::endl;

    const int w = 64, h = 64;
    std::vector<uint8_t> src(w * h * 4);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int off = (y * w + x) * 4;
            if (x < 20) {
                // Background (dark: L ~ 30)
                src[off]     = 30;
                src[off + 1] = 30;
                src[off + 2] = 30;
                src[off + 3] = 255;
            } else if (x < 44) {
                // Midtones (L ~ 128)
                src[off]     = 128;
                src[off + 1] = 128;
                src[off + 2] = 128;
                src[off + 3] = 255;
            } else {
                // Highlights (bright: L ~ 220)
                src[off]     = 220;
                src[off + 1] = 220;
                src[off + 2] = 220;
                src[off + 3] = 255;
            }
        }
    }

    PotraceResult* result = native_potrace_trace(src.data(), w, h, 60);
    assert(result != nullptr);
    assert(result->path_count > 0);
    std::cout << "   [Potrace] Extracted Paths: " << result->path_count << std::endl;

    // Verify strict tonal layer ordering: Background (0) -> Midtones (1) -> Highlights (2)
    int current_layer = 0;
    for (int i = 0; i < result->path_count; ++i) {
        const PotracePath& p = result->paths[i];
        assert(p.tonal_layer >= current_layer);
        current_layer = p.tonal_layer;
        assert(p.segment_count > 0);
        assert(p.segments != nullptr);

        for (int s = 0; s < p.segment_count; ++s) {
            const PotraceBezierSegment& seg = p.segments[s];
            assert(std::isfinite(seg.cp1x) && std::isfinite(seg.cp1y));
            assert(std::isfinite(seg.cp2x) && std::isfinite(seg.cp2y));
            assert(std::isfinite(seg.endx) && std::isfinite(seg.endy));
        }
    }

    native_potrace_free(result);
    std::cout << "[PASS] test_potrace_vectorization passed." << std::endl;
}

int main() {
    std::cout << "=== Reranger Native C++ Classical Engine PoC Test Suite ===" << std::endl;
    test_grayscale();
    test_sobel_edges();
    test_grain_overlay();
    test_recipe_monochrome_ink();
    test_adaptive_vibrancy();
    test_edgetam_hair_segmentation_no_bleed();
    test_metadata_annihilation();
    test_armor_attack_and_ssim();
    test_sensor_noise_and_ssim();
    test_potrace_vectorization();
    std::cout << "=== ALL NATIVE C++ TESTS PASSED (100%) ===" << std::endl;
    return 0;
}
