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

void test_sam2_and_cielab_magic_wand() {
    std::cout << "[RUN] test_sam2_and_cielab_magic_wand..." << std::endl;

    const int w = 128, h = 128;
    std::vector<uint8_t> portrait_rgba(w * h * 4, 0);

    // Build synthetic anime/portrait scene with dark line art boundary:
    // Hair: top head region (220, 80, 120) with fine hair lines
    // Ink line: 1-pixel boundary (15, 15, 15)
    // Face: skin (255, 220, 200)
    // Background: light (255, 255, 255)
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const int off = (y * w + x) * 4;
            if (y >= 15 && y <= 45 && x >= 32 && x <= 96) {
                // Hair region: vibrant magenta anime hair
                portrait_rgba[off]     = 220;
                portrait_rgba[off + 1] = 80;
                portrait_rgba[off + 2] = 120;
                portrait_rgba[off + 3] = 255;
            } else if ((y == 46 || y == 14 || x == 31 || x == 97) && (y >= 14 && y <= 46 && x >= 31 && x <= 97)) {
                // Ink outline (line art)
                portrait_rgba[off]     = 10;
                portrait_rgba[off + 1] = 10;
                portrait_rgba[off + 2] = 10;
                portrait_rgba[off + 3] = 255;
            } else if (y >= 47 && y <= 92 && x >= 32 && x <= 96) {
                // Face skin
                portrait_rgba[off]     = 255;
                portrait_rgba[off + 1] = 220;
                portrait_rgba[off + 2] = 200;
                portrait_rgba[off + 3] = 255;
            } else {
                // Background
                portrait_rgba[off]     = 255;
                portrait_rgba[off + 1] = 255;
                portrait_rgba[off + 2] = 255;
                portrait_rgba[off + 3] = 255;
            }
        }
    }

    // 1. Test SAM 2.1 Neural Pipeline
    void* handle = native_sam2_create("assets/models/sam2_hiera_small.pte");
    assert(handle != nullptr);

    std::vector<float> embedding(SAM2_EMBEDDING_SIZE, 0.0f);
    int enc_res = native_sam2_encode(handle, portrait_rgba.data(), w, h, embedding.data(), SAM2_EMBEDDING_SIZE);
    assert(enc_res == 0);

    std::vector<uint8_t> sam2_mask(w * h, 0);
    int dec_res = native_sam2_decode(handle, embedding.data(), SAM2_EMBEDDING_SIZE, 64.0f, 30.0f, sam2_mask.data(), w, h);
    assert(dec_res == 0);
    native_sam2_destroy(handle);

    // 2. Test Math Mode: CIELAB Color Tolerance Magic Wand bounded by line art
    std::vector<uint8_t> wand_mask(w * h, 0);
    // Tap hair at x=64, y=30
    native_cielab_magic_wand(
        portrait_rgba.data(),
        w, h,
        64, 30,
        0.20f, // hue_tolerance
        0.20f, // color_tolerance
        wand_mask.data()
    );

    int hair_pixels = 0, hair_selected = 0;
    int skin_selected = 0, bg_selected = 0;

    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            uint8_t m = wand_mask[y * w + x];
            if (y >= 16 && y <= 44 && x >= 33 && x <= 95) {
                hair_pixels++;
                if (m > 0) hair_selected++;
            } else if (y >= 47 && y <= 92 && x >= 32 && x <= 96) {
                if (m > 0) skin_selected++;
            } else if (x <= 20 || x >= 110) {
                if (m > 0) bg_selected++;
            }
        }
    }

    std::cout << "   [Wand Accuracy] Hair Selected: " << hair_selected << "/" << hair_pixels << std::endl;
    std::cout << "   [Wand Accuracy] Skin Bleed: " << skin_selected << ", BG Bleed: " << bg_selected << std::endl;

    assert(hair_selected >= 1600);      // >90% hair filled, stopping at black ink walls
    assert(skin_selected == 0);          // Strictly stopped by ink outline!
    assert(bg_selected == 0);            // Strictly zero background bleed!

    std::cout << "[PASS] test_sam2_and_cielab_magic_wand passed." << std::endl;
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

    // Verify L_inf bound at strength = 1.0 (Mandate 1 & 2: L_inf <= 8/255)
    std::vector<uint8_t> dst_100(w * h * 4, 0);
    native_armor_attack(src.data(), dst_100.data(), w, h, 1.0f);
    int max_delta = 0;
    for (int i = 0; i < static_cast<int>(src.size()); ++i) {
        if ((i & 3) == 3) continue; // Skip alpha
        int d = std::abs(static_cast<int>(dst_100[i]) - static_cast<int>(src[i]));
        if (d > max_delta) max_delta = d;
    }
    std::cout << "   [L_inf] ARMOR++ Max Perturbation Delta: " << max_delta << "/255" << std::endl;
    assert(max_delta <= 8);

    // Verify Latent Sanitization on synthetic checkerboard image
    std::vector<uint8_t> checker_src(w * h * 4, 128);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int off = (y * w + x) * 4;
            int sign = ((x & 1) == (y & 1)) ? 8 : -8;
            checker_src[off] = checker_src[off + 1] = checker_src[off + 2] = static_cast<uint8_t>(128 + sign);
        }
    }
    std::vector<uint8_t> sanitized(w * h * 4, 0);
    native_latent_sanitization(checker_src.data(), sanitized.data(), w, h, 1.0f);
    // Latent checkerboard magnitude must be reduced
    int diff_before = std::abs(static_cast<int>(checker_src[0]) - static_cast<int>(checker_src[4]));
    int diff_after = std::abs(static_cast<int>(sanitized[0]) - static_cast<int>(sanitized[4]));
    std::cout << "   [Latent Sanitization] Checker diff before: " << diff_before << ", after: " << diff_after << std::endl;
    assert(diff_after < diff_before);

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

void test_skeleton_vectorization() {
    std::cout << "[RUN] test_skeleton_vectorization (Guo-Hall Thinning & Medial Axis)..." << std::endl;

    const int w = 128, h = 128;
    std::vector<uint8_t> src(w * h * 4, 255); // White canvas
    // Draw some dark ink strokes
    for (int y = 20; y < 100; ++y) {
        for (int x = 20; x < 28; ++x) { // Vertical thick bar (width 8)
            int off = (y * w + x) * 4;
            src[off] = 20;
            src[off + 1] = 20;
            src[off + 2] = 20;
            src[off + 3] = 255;
        }
    }
    for (int x = 20; x < 100; ++x) {
        for (int y = 56; y < 62; ++y) { // Horizontal cross bar (width 6)
            int off = (y * w + x) * 4;
            src[off] = 20;
            src[off + 1] = 20;
            src[off + 2] = 20;
            src[off + 3] = 255;
        }
    }

    StrokeBuffer* buffer = native_skeleton_trace(src.data(), w, h, 60);
    assert(buffer != nullptr);
    assert(buffer->stroke_count > 0);
    assert(buffer->total_points > 0);
    assert(buffer->points_x_y != nullptr);
    assert(buffer->widths != nullptr);
    assert(buffer->offsets != nullptr);

    std::cout << "   [Skeleton] Extracted Strokes: " << buffer->stroke_count
              << ", Total Points: " << buffer->total_points << std::endl;

    // Verify offsets and point coordinates
    assert(buffer->offsets[0] == 0);
    assert(buffer->offsets[buffer->stroke_count] == static_cast<uint32_t>(buffer->total_points));

    for (int p = 0; p < buffer->total_points; ++p) {
        int16_t x = buffer->points_x_y[p * 2];
        int16_t y = buffer->points_x_y[p * 2 + 1];
        uint8_t width = buffer->widths[p];
        assert(x >= 0 && x <= w);
        assert(y >= 0 && y <= h);
        assert(width >= 1);
    }

    native_stroke_buffer_free(buffer);
    std::cout << "[PASS] test_skeleton_vectorization passed." << std::endl;
}

void test_watercolor_wash() {
    std::cout << "[TEST] Running test_watercolor_wash..." << std::endl;
    const int w = 64, h = 64;
    std::vector<uint8_t> src(w * h * 4, 0);
    std::vector<uint8_t> dst(w * h * 4, 0);

    // Warm portrait colors on left half, cool background on right half
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const int off = (y * w + x) * 4;
            if (x < w / 2) {
                src[off] = 220;     // Skin tone warm peach
                src[off + 1] = 160;
                src[off + 2] = 130;
                src[off + 3] = 255;
            } else {
                src[off] = 40;      // Deep cool blue
                src[off + 1] = 80;
                src[off + 2] = 180;
                src[off + 3] = 255;
            }
        }
    }

    native_watercolor_wash(src.data(), dst.data(), w, h, 2, 0.45f, 0.05f, 4040);

    // Assert that the warm left half remains warm and cool right half remains cool
    // No "split-face" stride inversion or channel scrambling
    int left_r = 0, left_b = 0;
    int right_r = 0, right_b = 0;
    for (int y = 5; y < h - 5; ++y) {
        for (int x = 5; x < w / 2 - 5; ++x) {
            const int off = (y * w + x) * 4;
            left_r += dst[off];
            left_b += dst[off + 2];
        }
        for (int x = w / 2 + 5; x < w - 5; ++x) {
            const int off = (y * w + x) * 4;
            right_r += dst[off];
            right_b += dst[off + 2];
        }
    }

    assert(left_r > left_b * 1.3); // Warm peach preserved
    assert(right_b > right_r * 1.5); // Cool blue preserved
    std::cout << "[PASS] test_watercolor_wash passed." << std::endl;
}

void test_bilateral_filter_sanitization() {
    std::cout << "[TEST] Running test_bilateral_filter_sanitization..." << std::endl;
    const int w = 32, h = 32;
    std::vector<uint8_t> src(w * h * 4, 128);

    // Add high-frequency synthetic generative noise (VAE checkerboard/noise pattern)
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            int off = (y * w + x) * 4;
            int noise = ((x ^ y) & 1) ? 12 : -12;
            src[off] = static_cast<uint8_t>(std::clamp(128 + noise, 0, 255));
            src[off + 1] = static_cast<uint8_t>(std::clamp(128 + noise, 0, 255));
            src[off + 2] = static_cast<uint8_t>(std::clamp(128 + noise, 0, 255));
            src[off + 3] = 255;
        }
    }

    // Add a strong vertical edge at x = 16
    for (int y = 0; y < h; ++y) {
        for (int x = 16; x < w; ++x) {
            int off = (y * w + x) * 4;
            src[off] = static_cast<uint8_t>(std::clamp(src[off] + 80, 0, 255));
            src[off + 1] = static_cast<uint8_t>(std::clamp(src[off + 1] + 80, 0, 255));
            src[off + 2] = static_cast<uint8_t>(std::clamp(src[off + 2] + 80, 0, 255));
        }
    }

    std::vector<uint8_t> dst(w * h * 4, 0);
    native_bilateral_filter_sanitization(src.data(), dst.data(), w, h, 2.5f, 30.0f, 1.0f);

    // 1. Noise reduction in flat region: Check standard deviation around x in [4, 12]
    double sum = 0.0, sum_sq = 0.0;
    int count = 0;
    for (int y = 4; y < h - 4; ++y) {
        for (int x = 4; x < 12; ++x) {
            int val = dst[(y * w + x) * 4];
            sum += val;
            sum_sq += val * val;
            count++;
        }
    }
    double mean = sum / count;
    double var_after = (sum_sq / count) - (mean * mean);

    double sum_orig = 0.0, sum_sq_orig = 0.0;
    for (int y = 4; y < h - 4; ++y) {
        for (int x = 4; x < 12; ++x) {
            int val = src[(y * w + x) * 4];
            sum_orig += val;
            sum_sq_orig += val * val;
        }
    }
    double mean_orig = sum_orig / count;
    double var_before = (sum_sq_orig / count) - (mean_orig * mean_orig);

    std::cout << "   [Bilateral] Variance before: " << var_before << ", after: " << var_after << std::endl;
    assert(var_after < var_before * 0.5); // At least 50% noise reduction in flat region

    // 2. Edge preservation: Gradient across x = 15 to x = 17 must be preserved
    int edge_step_after = std::abs(static_cast<int>(dst[(16 * w + 17) * 4]) - static_cast<int>(dst[(16 * w + 14) * 4]));
    std::cout << "   [Bilateral] Edge step preserved: " << edge_step_after << std::endl;
    assert(edge_step_after > 65); // Strong edge preserved!
    assert(dst[3] == 255); // Alpha preserved

    std::cout << "[PASS] test_bilateral_filter_sanitization passed." << std::endl;
}

void test_eot_robustness_and_linf_16() {
    std::cout << "[TEST] Running test_eot_robustness_and_linf_16..." << std::endl;
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
    // Mandate 2: EOT simulation and L_inf constraint of 16/255 at strength = 1.0
    native_armor_attack_eot(src.data(), dst.data(), w, h, 1.0f, 16.0f, 1);

    // Verify not bitwise identical
    assert(memcmp(src.data(), dst.data(), src.size()) != 0);

    int max_delta = 0;
    for (int i = 0; i < w * h * 4; i += 4) {
        for (int c = 0; c < 3; ++c) {
            int d = std::abs(static_cast<int>(dst[i + c]) - static_cast<int>(src[i + c]));
            if (d > max_delta) max_delta = d;
        }
        assert(dst[i + 3] == 255); // Alpha untouched
    }

    std::cout << "   [L_inf] EOT ARMOR++ Max Delta: " << max_delta << "/255" << std::endl;
    assert(max_delta <= 16); // Bounded strictly by L_inf 16/255
    assert(max_delta > 8);  // Film grain necessary for robustness

    double ssim = compute_ssim_c(src.data(), dst.data(), w, h);
    std::cout << "   [SSIM] EOT ARMOR++ SSIM: " << ssim << std::endl;
    assert(ssim > 0.90);

    std::cout << "[PASS] test_eot_robustness_and_linf_16 passed." << std::endl;
}

void test_inject_jpeg_quantization_artifacts() {
    std::cout << "[TEST] Running test_inject_jpeg_quantization_artifacts..." << std::endl;
    const int w = 32, h = 32;
    std::vector<uint8_t> src(w * h * 4, 140);
    std::vector<uint8_t> dst(w * h * 4, 0);

    native_inject_jpeg_quantization_artifacts(src.data(), dst.data(), w, h, 85, 1.0f);

    // Verify 8x8 block boundary step
    // Boundary pixel at x=7 vs x=8 should have boundary discontinuity
    int p_boundary_left = dst[(4 * w + 7) * 4];
    int p_boundary_right = dst[(4 * w + 8) * 4];
    int step = std::abs(p_boundary_right - p_boundary_left);
    std::cout << "   [Quantization Artifacts] 8x8 Boundary Step: " << step << std::endl;
    assert(step >= 1); // Synthetic JPEG block boundary step injected!
    assert(dst[3] == 140); // Alpha preserved

    std::cout << "[PASS] test_inject_jpeg_quantization_artifacts passed." << std::endl;
}

int main() {
    std::cout << "=== Reranger Native C++ Classical Engine PoC Test Suite ===" << std::endl;
    test_grayscale();
    test_sobel_edges();
    test_grain_overlay();
    test_recipe_monochrome_ink();
    test_adaptive_vibrancy();
    test_watercolor_wash();
    test_sam2_and_cielab_magic_wand();
    test_metadata_annihilation();
    test_armor_attack_and_ssim();
    test_sensor_noise_and_ssim();
    test_skeleton_vectorization();
    test_bilateral_filter_sanitization();
    test_eot_robustness_and_linf_16();
    test_inject_jpeg_quantization_artifacts();
    std::cout << "=== ALL NATIVE C++ TESTS PASSED (100%) ===" << std::endl;
    return 0;
}
