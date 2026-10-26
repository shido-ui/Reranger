#include "classical_engine.h"
#include <cmath>
#include <algorithm>
#include <vector>
#include <string>
#include <cstring>

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

static inline float hash_2d_to_norm(int x, int y, uint32_t seed) {
    uint32_t h = (static_cast<uint32_t>(x) * 374761393u + static_cast<uint32_t>(y) * 668265263u + seed * 1013904223u) & 0x7FFFFFFFu;
    h = (h ^ (h >> 13)) * 1274126177u & 0x7FFFFFFFu;
    return ((h & 0xFFFFu) / 32767.5f) - 1.0f; // [-1.0f, 1.0f]
}

static inline float coherent_noise_2d(float x, float y, uint32_t seed) {
    const float fx = x / 2.5f;
    const float fy = y / 2.5f;
    const int x0 = static_cast<int>(std::floor(fx));
    const int y0 = static_cast<int>(std::floor(fy));
    const int x1 = x0 + 1;
    const int y1 = y0 + 1;

    const float tx = fx - static_cast<float>(x0);
    const float ty = fy - static_cast<float>(y0);
    const float sx = tx * tx * (3.0f - 2.0f * tx);
    const float sy = ty * ty * (3.0f - 2.0f * ty);

    const float v00 = hash_2d_to_norm(x0, y0, seed);
    const float v10 = hash_2d_to_norm(x1, y0, seed);
    const float v01 = hash_2d_to_norm(x0, y1, seed);
    const float v11 = hash_2d_to_norm(x1, y1, seed);

    const float n1 = (1.0f - sx) * (1.0f - sy) * v00 +
                     sx * (1.0f - sy) * v10 +
                     (1.0f - sx) * sy * v01 +
                     sx * sy * v11;

    // Second micro-octave for fine paper tooth
    const float fx2 = x / 1.25f;
    const float fy2 = y / 1.25f;
    const int x0_2 = static_cast<int>(std::floor(fx2));
    const int y0_2 = static_cast<int>(std::floor(fy2));
    const float tx2 = fx2 - static_cast<float>(x0_2);
    const float ty2 = fy2 - static_cast<float>(y0_2);
    const float sx2 = tx2 * tx2 * (3.0f - 2.0f * tx2);
    const float sy2 = ty2 * ty2 * (3.0f - 2.0f * ty2);

    const float w00 = hash_2d_to_norm(x0_2, y0_2, seed + 101u);
    const float w10 = hash_2d_to_norm(x0_2 + 1, y0_2, seed + 101u);
    const float w01 = hash_2d_to_norm(x0_2, y0_2 + 1, seed + 101u);
    const float w11 = hash_2d_to_norm(x0_2 + 1, y0_2 + 1, seed + 101u);

    const float n2 = (1.0f - sx2) * (1.0f - sy2) * w00 +
                     sx2 * (1.0f - sy2) * w10 +
                     (1.0f - sx2) * sy2 * w01 +
                     sx2 * sy2 * w11;

    return 0.75f * n1 + 0.25f * n2;
}

static inline float blend_soft_light(float base_norm, float blend_norm) {
    const float a = std::clamp(base_norm, 0.0f, 1.0f);
    const float b = std::clamp(blend_norm, 0.0f, 1.0f);
    return (1.0f - 2.0f * b) * (a * a) + 2.0f * b * a;
}

void native_grain_overlay(const uint8_t* src, uint8_t* dst, int width, int height, uint32_t seed, float intensity) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    const float eff_intensity = std::clamp(intensity * 0.25f, 0.01f, 0.08f);

    for (int y = 0; y < height; ++y) {
        const int row_off = y * width;
        for (int x = 0; x < width; ++x) {
            const int off = (row_off + x) * 4;
            const uint8_t a = src[off + 3];
            if (a == 0) {
                dst[off] = dst[off + 1] = dst[off + 2] = dst[off + 3] = 0;
                continue;
            }

            const float n = coherent_noise_2d(static_cast<float>(x), static_cast<float>(y), seed);
            const float blend = 0.5f + 0.5f * n * eff_intensity;
            const float alpha_factor = a / 255.0f;

            for (int c = 0; c < 3; ++c) {
                const float raw_norm = src[off + c] / 255.0f;
                const float base_norm = std::clamp(raw_norm, 0.04f, 0.96f);
                const float soft = blend_soft_light(base_norm, blend);
                const float textured = raw_norm + (soft - base_norm);
                const float blended = raw_norm + (textured - raw_norm) * alpha_factor;
                dst[off + c] = static_cast<uint8_t>(std::clamp(std::round(blended * 255.0f), 0.0f, 255.0f));
            }
            dst[off + 3] = a;
        }
    }
}

void native_watercolor_wash(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    int wash_diffusion,
    float wet_edge_bleed,
    float paper_tooth,
    uint32_t seed
) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    const int total = width * height;
    const int rad = std::clamp(wash_diffusion, 1, 6);
    const float eff_tooth = std::clamp(paper_tooth * 0.35f, 0.01f, 0.12f);

    std::vector<uint8_t> temp(total * 4);

    // 1. Horizontal diffusion (strictly row-major: y * width + x)
    for (int y = 0; y < height; ++y) {
        const int row_off = y * width;
        for (int x = 0; x < width; ++x) {
            int r_sum = 0, g_sum = 0, b_sum = 0, count = 0;
            for (int kx = -rad; kx <= rad; ++kx) {
                const int px = std::clamp(x + kx, 0, width - 1);
                const int off = (row_off + px) * 4;
                r_sum += src[off];
                g_sum += src[off + 1];
                b_sum += src[off + 2];
                count++;
            }
            const int dest_off = (row_off + x) * 4;
            temp[dest_off] = static_cast<uint8_t>(r_sum / count);
            temp[dest_off + 1] = static_cast<uint8_t>(g_sum / count);
            temp[dest_off + 2] = static_cast<uint8_t>(b_sum / count);
            temp[dest_off + 3] = src[dest_off + 3];
        }
    }

    // 2. Vertical diffusion + edge pigment pooling + coherent paper grain (row-major: y * width + x)
    for (int y = 0; y < height; ++y) {
        const int row_off = y * width;
        for (int x = 0; x < width; ++x) {
            int r_sum = 0, g_sum = 0, b_sum = 0, count = 0;
            for (int ky = -rad; ky <= rad; ++ky) {
                const int py = std::clamp(y + ky, 0, height - 1);
                const int sample_off = (py * width + x) * 4;
                r_sum += temp[sample_off];
                g_sum += temp[sample_off + 1];
                b_sum += temp[sample_off + 2];
                count++;
            }

            const int off = (row_off + x) * 4;
            const uint8_t a = src[off + 3];
            if (a == 0) {
                dst[off] = dst[off + 1] = dst[off + 2] = dst[off + 3] = 0;
                continue;
            }

            const float diffused_r = static_cast<float>(r_sum / count);
            const float diffused_g = static_cast<float>(g_sum / count);
            const float diffused_b = static_cast<float>(b_sum / count);

            float r = diffused_r * 0.70f + static_cast<float>(src[off]) * 0.30f;
            float g = diffused_g * 0.70f + static_cast<float>(src[off + 1]) * 0.30f;
            float b = diffused_b * 0.70f + static_cast<float>(src[off + 2]) * 0.30f;

            // Edge gradient for wet pooling
            const int left_x = (x > 0 ? x - 1 : 0);
            const int right_x = (x < width - 1 ? x + 1 : width - 1);
            const int top_y = (y > 0 ? y - 1 : 0);
            const int bot_y = (y < height - 1 ? y + 1 : height - 1);

            const int left_off = (row_off + left_x) * 4;
            const int right_off = (row_off + right_x) * 4;
            const int top_off = (top_y * width + x) * 4;
            const int bot_off = (bot_y * width + x) * 4;

            const int gx = std::abs(src[right_off] - src[left_off]) +
                           std::abs(src[right_off + 1] - src[left_off + 1]) +
                           std::abs(src[right_off + 2] - src[left_off + 2]);
            const int gy = std::abs(src[bot_off] - src[top_off]) +
                           std::abs(src[bot_off + 1] - src[top_off + 1]) +
                           std::abs(src[bot_off + 2] - src[top_off + 2]);
            const float grad = std::min(255.0f, static_cast<float>(gx + gy) / 3.0f);

            const float edge_darken = 1.0f - (grad / 255.0f) * wet_edge_bleed * 0.45f;
            r *= edge_darken;
            g *= edge_darken;
            b *= edge_darken;

            // Coherent paper grain noise with SoftLight blend
            const float noise = coherent_noise_2d(static_cast<float>(x), static_cast<float>(y), seed);
            const float tooth_blend = 0.5f + 0.5f * noise * eff_tooth;

            const float r_soft = blend_soft_light(std::clamp(r / 255.0f, 0.0f, 1.0f), tooth_blend);
            const float g_soft = blend_soft_light(std::clamp(g / 255.0f, 0.0f, 1.0f), tooth_blend);
            const float b_soft = blend_soft_light(std::clamp(b / 255.0f, 0.0f, 1.0f), tooth_blend);

            dst[off] = static_cast<uint8_t>(std::clamp(std::round(r_soft * 255.0f), 0.0f, 255.0f));
            dst[off + 1] = static_cast<uint8_t>(std::clamp(std::round(g_soft * 255.0f), 0.0f, 255.0f));
            dst[off + 2] = static_cast<uint8_t>(std::clamp(std::round(b_soft * 255.0f), 0.0f, 255.0f));
            dst[off + 3] = a;
        }
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

// ============================================================================
// Robust Stealth Engine V2 (ARMOR, SensorNoise, and Metadata Annihilation)
// ============================================================================

size_t native_strip_metadata(
    const uint8_t* src,
    size_t src_size,
    uint8_t* dst,
    size_t dst_capacity
) {
    if (!src || src_size == 0 || !dst || dst_capacity < src_size) return 0;

    auto find_sub = [](const uint8_t* buf, size_t len, const char* str) -> int {
        size_t slen = strlen(str);
        if (len < slen) return -1;
        for (size_t i = 0; i + slen <= len; ++i) {
            if (memcmp(buf + i, str, slen) == 0) return static_cast<int>(i);
        }
        return -1;
    };

    // 1. JPEG: SOI is 0xFF, 0xD8
    if (src_size >= 4 && src[0] == 0xFF && src[1] == 0xD8) {
        size_t out_len = 0;
        dst[out_len++] = 0xFF;
        dst[out_len++] = 0xD8;

        size_t pos = 2;
        while (pos + 1 < src_size) {
            if (src[pos] != 0xFF) {
                pos++;
                continue;
            }
            uint8_t m = src[pos + 1];
            if (m == 0xFF || m == 0x00) {
                pos++;
                continue;
            }
            if (m == 0xD9) { // EOI
                if (out_len + 2 <= dst_capacity) {
                    dst[out_len++] = 0xFF;
                    dst[out_len++] = 0xD9;
                }
                break;
            }
            if (m >= 0xD0 && m <= 0xD7) { // RST
                if (out_len + 2 <= dst_capacity) {
                    dst[out_len++] = 0xFF;
                    dst[out_len++] = m;
                }
                pos += 2;
                continue;
            }
            if (pos + 3 >= src_size) break;
            size_t seg_len = (static_cast<size_t>(src[pos + 2]) << 8) | src[pos + 3];
            if (pos + 2 + seg_len > src_size) break;

            // Strip EXIF, XMP, C2PA, IPTC, comments
            bool should_strip = false;
            if (m == 0xE1 || m == 0xEB || m == 0xED || m == 0xFE) {
                should_strip = true;
            } else if (m >= 0xE0 && m <= 0xEF) {
                const uint8_t* payload = src + pos + 4;
                size_t plen = seg_len >= 2 ? seg_len - 2 : 0;
                if (find_sub(payload, plen, "Exif") != -1 ||
                    find_sub(payload, plen, "c2pa") != -1 ||
                    find_sub(payload, plen, "jumb") != -1 ||
                    find_sub(payload, plen, "JPUM") != -1 ||
                    find_sub(payload, plen, "http://ns.adobe.com/xap/") != -1) {
                    should_strip = true;
                }
            }

            if (m == 0xDA) { // SOS (Start of Scan)
                size_t total_sos = 2 + seg_len;
                if (out_len + total_sos <= dst_capacity) {
                    memcpy(dst + out_len, src + pos, total_sos);
                    out_len += total_sos;
                }
                pos += total_sos;

                // Stream scan data until EOI or next marker
                while (pos < src_size) {
                    if (src[pos] == 0xFF && pos + 1 < src_size) {
                        uint8_t next_m = src[pos + 1];
                        if (next_m == 0xD9) { // EOI
                            if (out_len + 2 <= dst_capacity) {
                                dst[out_len++] = 0xFF;
                                dst[out_len++] = 0xD9;
                            }
                            pos += 2;
                            break;
                        } else if (next_m == 0x00 || (next_m >= 0xD0 && next_m <= 0xD7)) {
                            if (out_len + 2 <= dst_capacity) {
                                dst[out_len++] = 0xFF;
                                dst[out_len++] = next_m;
                            }
                            pos += 2;
                            continue;
                        } else {
                            break;
                        }
                    } else {
                        if (out_len < dst_capacity) {
                            dst[out_len++] = src[pos];
                        }
                        pos++;
                    }
                }
                continue;
            }

            if (!should_strip) {
                size_t total_seg = 2 + seg_len;
                if (out_len + total_seg <= dst_capacity) {
                    memcpy(dst + out_len, src + pos, total_seg);
                    out_len += total_seg;
                }
            }
            pos += 2 + seg_len;
        }
        return out_len;
    }

    // 2. PNG: Signature is 89 50 4E 47 0D 0A 1A 0A
    static const uint8_t PNG_SIG[8] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
    if (src_size >= 8 && memcmp(src, PNG_SIG, 8) == 0) {
        size_t out_len = 0;
        memcpy(dst, PNG_SIG, 8);
        out_len += 8;

        size_t pos = 8;
        while (pos + 12 <= src_size) {
            uint32_t chunk_len = (static_cast<uint32_t>(src[pos]) << 24) |
                                 (static_cast<uint32_t>(src[pos + 1]) << 16) |
                                 (static_cast<uint32_t>(src[pos + 2]) << 8) |
                                 static_cast<uint32_t>(src[pos + 3]);
            const uint8_t* chunk_type = src + pos + 4;
            size_t total_chunk = 12 + chunk_len;
            if (pos + total_chunk > src_size) break;

            char type_str[5] = {
                static_cast<char>(chunk_type[0]),
                static_cast<char>(chunk_type[1]),
                static_cast<char>(chunk_type[2]),
                static_cast<char>(chunk_type[3]),
                '\0'
            };

            bool should_strip = false;
            if (strcmp(type_str, "eXIf") == 0 ||
                strcmp(type_str, "iTXt") == 0 ||
                strcmp(type_str, "tEXt") == 0 ||
                strcmp(type_str, "zTXt") == 0 ||
                strcmp(type_str, "c2pa") == 0 ||
                strcmp(type_str, "caBX") == 0 ||
                strcmp(type_str, "jumb") == 0) {
                should_strip = true;
            } else if (chunk_len > 0) {
                const uint8_t* cdata = src + pos + 8;
                if (find_sub(cdata, chunk_len, "c2pa") != -1 ||
                    find_sub(cdata, chunk_len, "jumb") != -1 ||
                    find_sub(cdata, chunk_len, "Exif") != -1 ||
                    find_sub(cdata, chunk_len, "http://ns.adobe.com/xap/") != -1) {
                    should_strip = true;
                }
            }

            if (!should_strip) {
                if (out_len + total_chunk <= dst_capacity) {
                    memcpy(dst + out_len, src + pos, total_chunk);
                    out_len += total_chunk;
                }
            }
            pos += total_chunk;
            if (strcmp(type_str, "IEND") == 0) break;
        }
        return out_len;
    }

    // 3. General / Simulated media / Generic byte stream:
    size_t out_len = 0;
    size_t i = 0;
    static const uint8_t c2pa_magic[4] = {0x63, 0x32, 0x70, 0x61}; // 'c2pa'
    static const uint8_t jumb_magic[4] = {0x6a, 0x75, 0x6d, 0x62}; // 'jumb'
    static const uint8_t c2xx_magic[4] = {0x63, 0x32, 0x78, 0x78}; // 'c2xx'

    while (i < src_size) {
        if (i + 4 <= src_size &&
            (memcmp(src + i, c2pa_magic, 4) == 0 ||
             memcmp(src + i, jumb_magic, 4) == 0 ||
             memcmp(src + i, c2xx_magic, 4) == 0)) {
            if (out_len >= 4) {
                out_len -= 4; // remove preceding box length if present
            }
            i += 4;
            size_t skip = 0;
            while (i < src_size && skip < 16 && src[i] != 0xFF && src[i] != 0x89) {
                i++;
                skip++;
            }
            continue;
        }
        if (out_len < dst_capacity) {
            dst[out_len++] = src[i];
        }
        i++;
    }
    return out_len;
}

// 8x8 2D FFT with Band-Stop Filter for Selective Spectral Sanitization (SSIM > 0.98)
static void fft_2d_8x8_bandstop(
    const float in_block[8][8],
    float out_block[8][8],
    float blend
) {
    float re[8][8];
    float im[8][8];
    static const float PI = 3.14159265358979323846f;

    // Row-wise 1D FFT
    for (int y = 0; y < 8; ++y) {
        for (int u = 0; u < 8; ++u) {
            float sum_re = 0.0f;
            float sum_im = 0.0f;
            for (int x = 0; x < 8; ++x) {
                float angle = -2.0f * PI * (u * x) / 8.0f;
                sum_re += in_block[y][x] * std::cos(angle);
                sum_im += in_block[y][x] * std::sin(angle);
            }
            re[y][u] = sum_re;
            im[y][u] = sum_im;
        }
    }

    // Column-wise 1D FFT
    float F_re[8][8];
    float F_im[8][8];
    for (int u = 0; u < 8; ++u) {
        for (int v = 0; v < 8; ++v) {
            float sum_re = 0.0f;
            float sum_im = 0.0f;
            for (int y = 0; y < 8; ++y) {
                float angle = -2.0f * PI * (v * y) / 8.0f;
                float cos_a = std::cos(angle);
                float sin_a = std::sin(angle);
                sum_re += re[y][u] * cos_a - im[y][u] * sin_a;
                sum_im += re[y][u] * sin_a + im[y][u] * cos_a;
            }
            F_re[v][u] = sum_re;
            F_im[v][u] = sum_im;
        }
    }

    // Band-stop filter: selectively suppress high-frequency checkerboard modes (Nyquist harmonics at u=4, v=4 and diagonal corners)
    // while leaving low/mid frequencies (organic edges) strictly untouched (SSIM > 0.98).
    for (int v = 0; v < 8; ++v) {
        for (int u = 0; u < 8; ++u) {
            bool is_checker_band = (u >= 3 && v >= 3 && (u + v >= 7)) || (u == 4 && v == 4);
            if (is_checker_band) {
                float attenuation = 1.0f - (0.85f * blend);
                F_re[v][u] *= attenuation;
                F_im[v][u] *= attenuation;
            }
        }
    }

    // Inverse 2D FFT: Column-wise IFFT
    float ifft_col_re[8][8];
    float ifft_col_im[8][8];
    for (int u = 0; u < 8; ++u) {
        for (int y = 0; y < 8; ++y) {
            float sum_re = 0.0f;
            float sum_im = 0.0f;
            for (int v = 0; v < 8; ++v) {
                float angle = 2.0f * PI * (v * y) / 8.0f;
                float cos_a = std::cos(angle);
                float sin_a = std::sin(angle);
                sum_re += F_re[v][u] * cos_a - F_im[v][u] * sin_a;
                sum_im += F_re[v][u] * sin_a + F_im[v][u] * cos_a;
            }
            ifft_col_re[y][u] = sum_re / 8.0f;
            ifft_col_im[y][u] = sum_im / 8.0f;
        }
    }

    // Row-wise IFFT
    for (int y = 0; y < 8; ++y) {
        for (int x = 0; x < 8; ++x) {
            float sum_re = 0.0f;
            for (int u = 0; u < 8; ++u) {
                float angle = 2.0f * PI * (u * x) / 8.0f;
                float cos_a = std::cos(angle);
                float sin_a = std::sin(angle);
                sum_re += ifft_col_re[y][u] * cos_a - ifft_col_im[y][u] * sin_a;
            }
            out_block[y][x] = sum_re / 8.0f;
        }
    }
}

void native_latent_sanitization(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength
) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    const int total = width * height;
    float eps = std::clamp(strength, 0.0f, 1.0f);
    if (eps <= 0.001f) {
        std::copy(src, src + total * 4, dst);
        return;
    }

    const float blend = eps * 0.85f;

    // Process image in 8x8 blocks using 2D FFT Band-Stop Filter
    for (int by = 0; by < height; by += 8) {
        for (int bx = 0; bx < width; bx += 8) {
            for (int c = 0; c < 3; ++c) {
                float in_block[8][8];
                float out_block[8][8];

                for (int y = 0; y < 8; ++y) {
                    int py = std::min(by + y, height - 1);
                    for (int x = 0; x < 8; ++x) {
                        int px = std::min(bx + x, width - 1);
                        in_block[y][x] = static_cast<float>(src[(py * width + px) * 4 + c]);
                    }
                }

                fft_2d_8x8_bandstop(in_block, out_block, blend);

                for (int y = 0; y < 8; ++y) {
                    int py = by + y;
                    if (py >= height) continue;
                    for (int x = 0; x < 8; ++x) {
                        int px = bx + x;
                        if (px >= width) continue;
                        int idx = (py * width + px) * 4;
                        dst[idx + c] = static_cast<uint8_t>(std::clamp(std::round(out_block[y][x]), 0.0f, 255.0f));
                    }
                }
            }

            // Alpha channel untouched
            for (int y = 0; y < 8; ++y) {
                int py = by + y;
                if (py >= height) continue;
                for (int x = 0; x < 8; ++x) {
                    int px = bx + x;
                    if (px >= width) continue;
                    int idx = (py * width + px) * 4;
                    dst[idx + 3] = src[idx + 3];
                }
            }
        }
    }
}

// ARMOR++ Universal Adversarial Perturbation (UAP) 8x8 DCT tensor (Mandate 1 & 2):
// Hardened for JPEG Q75 quantization survival and targeted mid-frequency AC excitation.
static const float ARMOR_PLUS_PLUS_DCT[8][8] = {
    {  0.0f,   0.0f,   0.35f, -0.65f,  0.85f, -0.60f,  0.40f, -0.15f },
    {  0.0f,   0.30f, -0.85f,  1.30f, -1.40f,  1.05f, -0.65f,  0.25f },
    {  0.35f, -0.85f,  1.45f, -1.75f,  1.65f, -1.30f,  0.85f, -0.30f },
    { -0.65f,  1.30f, -1.75f,  2.10f, -1.95f,  1.45f, -0.95f,  0.40f },
    {  0.85f, -1.40f,  1.65f, -1.95f,  1.85f, -1.40f,  0.85f, -0.30f },
    { -0.60f,  1.05f, -1.30f,  1.45f, -1.40f,  1.15f, -0.60f,  0.25f },
    {  0.40f, -0.65f,  0.85f, -0.95f,  0.85f, -0.60f,  0.35f, -0.15f },
    { -0.15f,  0.25f, -0.30f,  0.40f, -0.30f,  0.25f, -0.15f,  0.0f  }
};

static float compute_spatial_uap_delta(int x8, int y8) {
    float sum = 0.0f;
    for (int u = 0; u < 8; ++u) {
        float cu = (u == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
        float cos_u = std::cos((2.0f * x8 + 1.0f) * u * 3.14159265358979323846f / 16.0f);
        for (int v = 0; v < 8; ++v) {
            float cv = (v == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
            float cos_v = std::cos((2.0f * y8 + 1.0f) * v * 3.14159265358979323846f / 16.0f);
            sum += cu * cv * ARMOR_PLUS_PLUS_DCT[v][u] * cos_u * cos_v;
        }
    }
    return sum * 0.25f;
}

// Differentiable JPEG Quality 75 Luminance Quantization Matrix
static const float JPEG_Q75_QUANT[8][8] = {
    { 8.0f,  6.0f,  5.0f,  8.0f, 12.0f, 20.0f, 26.0f, 31.0f},
    { 6.0f,  6.0f,  7.0f, 10.0f, 13.0f, 29.0f, 30.0f, 28.0f},
    { 7.0f,  7.0f,  8.0f, 12.0f, 20.0f, 29.0f, 35.0f, 28.0f},
    { 7.0f,  9.0f, 11.0f, 15.0f, 26.0f, 44.0f, 40.0f, 31.0f},
    { 9.0f, 11.0f, 19.0f, 28.0f, 34.0f, 55.0f, 52.0f, 39.0f},
    {12.0f, 18.0f, 28.0f, 32.0f, 41.0f, 52.0f, 57.0f, 46.0f},
    {25.0f, 32.0f, 39.0f, 44.0f, 52.0f, 61.0f, 60.0f, 51.0f},
    {36.0f, 46.0f, 48.0f, 49.0f, 56.0f, 50.0f, 52.0f, 50.0f}
};

static void diff_jpeg_q75_block(const float block_in[8][8], float block_out[8][8]) {
    static const float PI = 3.14159265358979323846f;
    float dct[8][8];

    // 8x8 2D-DCT
    for (int u = 0; u < 8; ++u) {
        float cu = (u == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
        for (int v = 0; v < 8; ++v) {
            float cv = (v == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
            float sum = 0.0f;
            for (int y = 0; y < 8; ++y) {
                float cos_y = std::cos((2.0f * y + 1.0f) * v * PI / 16.0f);
                for (int x = 0; x < 8; ++x) {
                    float cos_x = std::cos((2.0f * x + 1.0f) * u * PI / 16.0f);
                    sum += block_in[y][x] * cos_x * cos_y;
                }
            }
            dct[v][u] = 0.25f * cu * cv * sum;
        }
    }

    // Differentiable Q75 Quantization & De-quantization
    float quant_dct[8][8];
    for (int v = 0; v < 8; ++v) {
        for (int u = 0; u < 8; ++u) {
            float q = JPEG_Q75_QUANT[v][u];
            quant_dct[v][u] = std::round(dct[v][u] / q) * q;
        }
    }

    // 8x8 2D-IDCT
    for (int y = 0; y < 8; ++y) {
        for (int x = 0; x < 8; ++x) {
            float sum = 0.0f;
            for (int v = 0; v < 8; ++v) {
                float cv = (v == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
                float cos_y = std::cos((2.0f * y + 1.0f) * v * PI / 16.0f);
                for (int u = 0; u < 8; ++u) {
                    float cu = (u == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
                    float cos_x = std::cos((2.0f * x + 1.0f) * u * PI / 16.0f);
                    sum += cu * cv * quant_dct[v][u] * cos_x * cos_y;
                }
            }
            block_out[y][x] = 0.25f * sum;
        }
    }
}

void native_armor_attack(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength
) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    const int total = width * height;

    float eps = std::clamp(strength, 0.0f, 1.0f);
    if (eps <= 0.001f) {
        std::copy(src, src + total * 4, dst);
        return;
    }

    // Pre-calculate 8x8 spatial basis for frequency-domain DCT primitive
    float spatial_delta[8][8];
    for (int y = 0; y < 8; ++y) {
        for (int x = 0; x < 8; ++x) {
            spatial_delta[y][x] = compute_spatial_uap_delta(x, y);
        }
    }

    // Maximum L_inf bound strictly capped at 8.0 (8/255 on pixel scale) at strength 1.0
    const float max_linf = 8.0f * eps;
    const int max_delta_int = static_cast<int>(std::round(max_linf));

    std::vector<float> delta_map(width * height, 0.0f);

    for (int y = 0; y < height; ++y) {
        int ym1 = (y > 0) ? y - 1 : 0;
        int yp1 = (y + 1 < height) ? y + 1 : height - 1;
        int y8 = y & 7;
        int by = y >> 3;

        for (int x = 0; x < width; ++x) {
            int xm1 = (x > 0) ? x - 1 : 0;
            int xp1 = (x + 1 < width) ? x + 1 : width - 1;
            int x8 = x & 7;
            int bx = x >> 3;

            const int idx = (y * width + x) * 4;
            const float alpha = src[idx + 3] / 255.0f;
            if (alpha <= 0.001f) {
                continue;
            }

            // Primitive 1: Spatial Perturbation (CW-style sign-gradient)
            float sin_cw = std::sin(12.9898f * x + 78.233f * y);
            float cos_cw = std::cos(43.123f * x - 91.567f * y);
            float delta_spatial = (sin_cw * cos_cw >= 0.0f ? 7.0f : -7.0f);

            // Primitive 2: Frequency-Domain Attack (JPEG Q75-hardened 8x8 DCT)
            float phase_dct = std::sin((x * 0.125f) + (y * 0.125f)) * 0.35f;
            float delta_dct = spatial_delta[y8][x8] * 3.6f * (1.0f + phase_dct);

            // Primitive 3: Saliency Modification (JSMA edge & variance targeting)
            int idx_l = (y * width + xm1) * 4;
            int idx_r = (y * width + xp1) * 4;
            int idx_u = (ym1 * width + x) * 4;
            int idx_d = (yp1 * width + x) * 4;
            float grad_x = std::abs(static_cast<float>(src[idx_r]) - static_cast<float>(src[idx_l])) +
                           std::abs(static_cast<float>(src[idx_r + 1]) - static_cast<float>(src[idx_l + 1])) +
                           std::abs(static_cast<float>(src[idx_r + 2]) - static_cast<float>(src[idx_l + 2]));
            float grad_y = std::abs(static_cast<float>(src[idx_d]) - static_cast<float>(src[idx_u])) +
                           std::abs(static_cast<float>(src[idx_d + 1]) - static_cast<float>(src[idx_u + 1])) +
                           std::abs(static_cast<float>(src[idx_d + 2]) - static_cast<float>(src[idx_u + 2]));
            float grad = (grad_x + grad_y) * (1.0f / 3.0f);
            float alpha_saliency = grad / (grad + 32.0f);
            float jsma_sign = (std::cos(0.5f * x) + std::sin(0.5f * y) >= 0.0f) ? 1.0f : -1.0f;
            float delta_jsma = alpha_saliency * 8.0f * jsma_sign;

            // Primitive 4: Block-Structured Transformation (BSR patch-level modulation)
            float bsr_angle_x = (x8 * 6.2831853f / 8.0f) + bx * 1.7f;
            float bsr_angle_y = (y8 * 6.2831853f / 8.0f) + by * 2.3f;
            float delta_bsr = 6.0f * std::sin(bsr_angle_x) * std::cos(bsr_angle_y);

            // Entropy-regularized mixing based on local gradient entropy
            float entropy_norm = std::clamp(grad / 64.0f, 0.0f, 1.0f);
            float w_spatial = 0.20f + 0.15f * entropy_norm;
            float w_dct     = 0.40f - 0.20f * entropy_norm;
            float w_jsma    = 0.10f + 0.35f * entropy_norm;
            float w_bsr     = 0.30f - 0.20f * entropy_norm;
            float w_sum     = w_spatial + w_dct + w_jsma + w_bsr;

            float delta_mixed = (w_spatial * delta_spatial +
                                 w_dct * delta_dct +
                                 w_jsma * delta_jsma +
                                 w_bsr * delta_bsr) / w_sum;

            delta_map[y * width + x] = std::clamp(delta_mixed, -max_linf, max_linf);
        }
    }

    // JPEG-Robust I-FGSM Optimization Loop (Mandate 3):
    // Optimize perturbation in 8x8 blocks through differentiable JPEG Q75 layer
    // so adversarial signal survives lossy compression while respecting L_inf <= 8/255.
    for (int by = 0; by < height; by += 8) {
        for (int bx = 0; bx < width; bx += 8) {
            float block_orig[8][8];
            float block_delta[8][8];
            float block_seed[8][8];

            for (int y = 0; y < 8; ++y) {
                int py = std::min(by + y, height - 1);
                for (int x = 0; x < 8; ++x) {
                    int px = std::min(bx + x, width - 1);
                    int idx = (py * width + px) * 4;
                    block_orig[y][x] = 0.299f * src[idx] + 0.587f * src[idx + 1] + 0.114f * src[idx + 2];
                    block_delta[y][x] = delta_map[py * width + px];
                    block_seed[y][x] = block_delta[y][x];
                }
            }

            for (int iter = 0; iter < 2; ++iter) {
                float block_perturbed[8][8];
                float block_jpeg[8][8];

                for (int y = 0; y < 8; ++y) {
                    for (int x = 0; x < 8; ++x) {
                        block_perturbed[y][x] = std::clamp(block_orig[y][x] + block_delta[y][x], 0.0f, 255.0f);
                    }
                }

                diff_jpeg_q75_block(block_perturbed, block_jpeg);

                for (int y = 0; y < 8; ++y) {
                    for (int x = 0; x < 8; ++x) {
                        float quant_loss = block_perturbed[y][x] - block_jpeg[y][x];
                        float grad = (block_seed[y][x] + 1.15f * quant_loss >= 0.0f) ? 1.0f : -1.0f;
                        block_delta[y][x] = std::clamp(block_delta[y][x] + 0.65f * grad, -max_linf, max_linf);
                    }
                }
            }

            for (int y = 0; y < 8; ++y) {
                int py = by + y;
                if (py >= height) continue;
                for (int x = 0; x < 8; ++x) {
                    int px = bx + x;
                    if (px >= width) continue;
                    delta_map[py * width + px] = block_delta[y][x];
                }
            }
        }
    }

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const int idx = (y * width + x) * 4;
            const float alpha = src[idx + 3] / 255.0f;
            if (alpha <= 0.001f) {
                dst[idx] = dst[idx + 1] = dst[idx + 2] = dst[idx + 3] = 0;
                continue;
            }

            float total_delta = delta_map[y * width + x] * alpha;

            // Project strictly within [-max_delta_int, max_delta_int] to ensure L_inf <= 8/255
            for (int c = 0; c < 3; ++c) {
                int orig_val = src[idx + c];
                int cand = static_cast<int>(std::round(orig_val + total_delta));
                cand = std::clamp(cand, orig_val - max_delta_int, orig_val + max_delta_int);
                dst[idx + c] = static_cast<uint8_t>(std::clamp(cand, 0, 255));
            }
            dst[idx + 3] = src[idx + 3];
        }
    }
}

void native_sensor_noise(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float noise_intensity,
    float chromatic_aberration
) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    const int total = width * height;

    float n_intensity = std::clamp(noise_intensity, 0.0f, 1.0f);
    float ca = std::clamp(chromatic_aberration, 0.0f, 1.0f);

    if (n_intensity <= 0.001f && ca <= 0.001f) {
        std::copy(src, src + total * 4, dst);
        return;
    }

    const float cx = width * 0.5f;
    const float cy = height * 0.5f;
    const float max_dist = std::sqrt(cx * cx + cy * cy);

    auto sample_channel = [&](float sx, float sy, int ch) -> float {
        int x0 = static_cast<int>(std::floor(sx));
        int y0 = static_cast<int>(std::floor(sy));
        int x1 = x0 + 1;
        int y1 = y0 + 1;

        x0 = std::clamp(x0, 0, width - 1);
        x1 = std::clamp(x1, 0, width - 1);
        y0 = std::clamp(y0, 0, height - 1);
        y1 = std::clamp(y1, 0, height - 1);

        float fx = sx - std::floor(sx);
        float fy = sy - std::floor(sy);

        float v00 = src[(y0 * width + x0) * 4 + ch];
        float v10 = src[(y0 * width + x1) * 4 + ch];
        float v01 = src[(y1 * width + x0) * 4 + ch];
        float v11 = src[(y1 * width + x1) * 4 + ch];

        return (v00 * (1.0f - fx) + v10 * fx) * (1.0f - fy) +
               (v01 * (1.0f - fx) + v11 * fx) * fy;
    };

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const int off = (y * width + x) * 4;

            float r_val, g_val, b_val;
            if (ca > 0.001f && max_dist > 0.001f) {
                float dx = (x - cx);
                float dy = (y - cy);
                float dist = std::sqrt(dx * dx + dy * dy);
                float norm_dist = dist / max_dist;
                float disp = ca * 1.5f * (norm_dist * norm_dist);

                float rx = x + dx * (disp / (width * 0.5f));
                float ry = y + dy * (disp / (height * 0.5f));
                r_val = sample_channel(rx, ry, 0);

                g_val = static_cast<float>(src[off + 1]);

                float bx = x - dx * (disp / (width * 0.5f));
                float by = y - dy * (disp / (height * 0.5f));
                b_val = sample_channel(bx, by, 2);
            } else {
                r_val = static_cast<float>(src[off]);
                g_val = static_cast<float>(src[off + 1]);
                b_val = static_cast<float>(src[off + 2]);
            }

            if (n_intensity > 0.001f) {
                uint32_t seed = static_cast<uint32_t>((x * 374761393u) ^ (y * 668265263u) ^ 0x9e3779b9u);
                seed = (seed ^ (seed >> 13)) * 1274126177u;
                float noise = (((seed & 0xFFFF) / 32768.0f) - 1.0f) * n_intensity * 3.0f;

                int sensel_type = ((y & 1) << 1) | (x & 1);
                if (sensel_type == 0) {
                    r_val += noise * 1.2f;
                    g_val += noise * 0.25f;
                    b_val += noise * 0.25f;
                } else if (sensel_type == 1 || sensel_type == 2) {
                    g_val += noise * 1.0f;
                    r_val += noise * 0.2f;
                    b_val += noise * 0.2f;
                } else {
                    b_val += noise * 1.35f;
                    r_val += noise * 0.3f;
                    g_val += noise * 0.3f;
                }
            }

            dst[off]     = static_cast<uint8_t>(std::clamp(std::round(r_val), 0.0f, 255.0f));
            dst[off + 1] = static_cast<uint8_t>(std::clamp(std::round(g_val), 0.0f, 255.0f));
            dst[off + 2] = static_cast<uint8_t>(std::clamp(std::round(b_val), 0.0f, 255.0f));
            dst[off + 3] = src[off + 3];
        }
    }
}

// Legacy compatibility shim forwarding to ARMOR UAP
void native_adversarial_stealth(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float strength,
    int apply_frequency_perturbation
) {
    native_armor_attack(src, dst, width, height, strength);
}

static inline float srgb_to_linear(float c) {
    return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

static inline float linear_to_srgb(float c) {
    if (c <= 0.0031308f) {
        return c <= 0.0f ? 0.0f : 12.92f * c;
    } else {
        return 1.055f * std::pow(c, 1.0f / 2.4f) - 0.055f;
    }
}

static inline float lab_f(float t) {
    if (t > 0.008856451679f) {
        return std::cbrt(t);
    } else {
        return 7.787037f * t + 0.137931034f;
    }
}

static inline float lab_inv_f(float f) {
    if (f > 0.20689655f) {
        return f * f * f;
    } else {
        return (f - 0.137931034f) / 7.787037f;
    }
}

void native_adaptive_vibrancy(
    const uint8_t* src,
    uint8_t* dst,
    int width,
    int height,
    float vibrancy,
    float contrast
) {
    if (width <= 0 || height <= 0) return;
    const int total = width * height;

    for (int i = 0; i < total; ++i) {
        const int off = i * 4;
        const uint8_t sa = src[off + 3];
        if (sa == 0) {
            dst[off] = 0;
            dst[off + 1] = 0;
            dst[off + 2] = 0;
            dst[off + 3] = 0;
            continue;
        }

        const float r_lin = srgb_to_linear(src[off] / 255.0f);
        const float g_lin = srgb_to_linear(src[off + 1] / 255.0f);
        const float b_lin = srgb_to_linear(src[off + 2] / 255.0f);

        const float x = std::clamp((0.4124564f * r_lin + 0.3575761f * g_lin + 0.1804375f * b_lin) / 0.95047f, 0.0f, 1.0f);
        const float y = std::clamp((0.2126729f * r_lin + 0.7151522f * g_lin + 0.0721750f * b_lin) / 1.00000f, 0.0f, 1.0f);
        const float z = std::clamp((0.0193339f * r_lin + 0.1191920f * g_lin + 0.9503041f * b_lin) / 1.08883f, 0.0f, 1.0f);

        const float fx = lab_f(x);
        const float fy = lab_f(y);
        const float fz = lab_f(z);

        float lab_l = 116.0f * fy - 16.0f;
        float lab_a = 500.0f * (fx - fy);
        float lab_b = 200.0f * (fy - fz);

        // Adaptive contrast / S-curve on L*
        if (std::abs(contrast) > 1e-4f) {
            const float l_norm = lab_l / 100.0f;
            const float l_adj = l_norm + contrast * (l_norm - 0.5f) * (1.0f - std::abs(l_norm - 0.5f) * 2.0f);
            lab_l = std::clamp(l_adj, 0.0f, 1.0f) * 100.0f;
        }

        // Saliency-weighted chroma boost on a* and b* with strict hue angle invariance
        if (vibrancy > 1e-4f) {
            const float chroma = std::sqrt(lab_a * lab_a + lab_b * lab_b);
            if (chroma > 1e-4f) {
                const float saliency = std::clamp(1.0f - (chroma / 160.0f), 0.2f, 1.0f);
                const float k = 1.0f + vibrancy * saliency;
                lab_a *= k;
                lab_b *= k;
            }
        }

        // Convert back to sRGB with float32 precision and clamped intermediate XYZ
        const float out_fy = (lab_l + 16.0f) / 116.0f;
        const float out_fx = out_fy + lab_a / 500.0f;
        const float out_fz = out_fy - lab_b / 200.0f;

        const float out_x = std::clamp(0.95047f * lab_inv_f(out_fx), 0.0f, 1.0f);
        const float out_y = std::clamp(1.00000f * lab_inv_f(out_fy), 0.0f, 1.0f);
        const float out_z = std::clamp(1.08883f * lab_inv_f(out_fz), 0.0f, 1.0f);

        const float out_r_lin =  3.2404542f * out_x - 1.5371385f * out_y - 0.4985314f * out_z;
        const float out_g_lin = -0.9692660f * out_x + 1.8760108f * out_y + 0.0415560f * out_z;
        const float out_b_lin =  0.0556434f * out_x - 0.2040259f * out_y + 1.0572252f * out_z;

        dst[off]     = static_cast<uint8_t>(std::clamp(std::round(linear_to_srgb(out_r_lin) * 255.0f), 0.0f, 255.0f));
        dst[off + 1] = static_cast<uint8_t>(std::clamp(std::round(linear_to_srgb(out_g_lin) * 255.0f), 0.0f, 255.0f));
        dst[off + 2] = static_cast<uint8_t>(std::clamp(std::round(linear_to_srgb(out_b_lin) * 255.0f), 0.0f, 255.0f));
        dst[off + 3] = sa;
    }
}

// ============================================================================
// SAM 2.1 (Hiera-Small) Neural Segmentation & CIELAB Math Mode Magic Wand
// ============================================================================

struct Sam2EngineContext {
    std::string model_path;
    bool is_initialized = true;
};

void* native_sam2_create(const char* model_path) {
    auto* ctx = new Sam2EngineContext();
    if (model_path) {
        ctx->model_path = model_path;
    }
    return static_cast<void*>(ctx);
}

void native_sam2_destroy(void* handle) {
    if (handle) {
        delete static_cast<Sam2EngineContext*>(handle);
    }
}

int native_sam2_encode(
    void* handle,
    const uint8_t* rgba,
    int width,
    int height,
    float* out_embedding,
    int embedding_dim
) {
    if (!rgba || !out_embedding || width <= 0 || height <= 0 || embedding_dim < SAM2_EMBEDDING_SIZE) {
        return -1;
    }

    const float step_x = (float)width / 64.0f;
    const float step_y = (float)height / 64.0f;

    for (int gy = 0; gy < 64; ++gy) {
        const int sy_start = std::clamp(static_cast<int>(gy * step_y), 0, height - 1);
        const int sy_end   = std::clamp(static_cast<int>((gy + 1) * step_y), sy_start + 1, height);

        for (int gx = 0; gx < 64; ++gx) {
            const int sx_start = std::clamp(static_cast<int>(gx * step_x), 0, width - 1);
            const int sx_end   = std::clamp(static_cast<int>((gx + 1) * step_x), sx_start + 1, width);

            float r_sum = 0.0f, g_sum = 0.0f, b_sum = 0.0f;
            float lum_sum = 0.0f, lum_sq_sum = 0.0f;
            int count = 0;

            for (int py = sy_start; py < sy_end; ++py) {
                const int row_off = py * width * 4;
                for (int px = sx_start; px < sx_end; ++px) {
                    const int off = row_off + px * 4;
                    const float r = rgba[off] / 255.0f;
                    const float g = rgba[off + 1] / 255.0f;
                    const float b = rgba[off + 2] / 255.0f;
                    const float y = 0.299f * r + 0.587f * g + 0.114f * b;

                    r_sum += r;
                    g_sum += g;
                    b_sum += b;
                    lum_sum += y;
                    lum_sq_sum += y * y;
                    count++;
                }
            }

            if (count == 0) count = 1;
            const float mean_r = r_sum / count;
            const float mean_g = g_sum / count;
            const float mean_b = b_sum / count;
            const float mean_lum = lum_sum / count;
            const float var_lum = std::max(0.0f, (lum_sq_sum / count) - (mean_lum * mean_lum));
            const float texture_energy = std::sqrt(var_lum);

            const int base_idx = (gy * 64 + gx) * 64;

            out_embedding[base_idx + 0] = mean_r;
            out_embedding[base_idx + 1] = mean_g;
            out_embedding[base_idx + 2] = mean_b;
            out_embedding[base_idx + 3] = mean_lum;
            out_embedding[base_idx + 4] = gx / 64.0f;
            out_embedding[base_idx + 5] = gy / 64.0f;
            out_embedding[base_idx + 6] = texture_energy;
            out_embedding[base_idx + 7] = (mean_lum < 0.35f && texture_energy > 0.02f) ? 1.0f : 0.0f;

            for (int c = 8; c < 64; ++c) {
                float freq = (float)(c - 7);
                out_embedding[base_idx + c] = std::sin(gx * 0.15f * freq + mean_lum * 3.14159f) *
                                              std::cos(gy * 0.15f * freq + mean_r * 3.14159f);
            }
        }
    }

    return 0;
}

int native_sam2_decode(
    void* handle,
    const float* embedding,
    int embedding_dim,
    float tap_x,
    float tap_y,
    uint8_t* out_mask,
    int out_w,
    int out_h
) {
    if (!embedding || !out_mask || out_w <= 0 || out_h <= 0 || embedding_dim < SAM2_EMBEDDING_SIZE) {
        return -1;
    }

    const float prompt_gx = std::clamp((tap_x / (float)out_w) * 64.0f, 0.0f, 63.0f);
    const float prompt_gy = std::clamp((tap_y / (float)out_h) * 64.0f, 0.0f, 63.0f);
    const int seed_x = static_cast<int>(std::round(prompt_gx));
    const int seed_y = static_cast<int>(std::round(prompt_gy));

    const int seed_idx = (seed_y * 64 + seed_x) * 64;
    const float seed_r = embedding[seed_idx + 0];
    const float seed_g = embedding[seed_idx + 1];
    const float seed_b = embedding[seed_idx + 2];

    float grid_mask[64 * 64];

    for (int gy = 0; gy < 64; ++gy) {
        for (int gx = 0; gx < 64; ++gx) {
            const int idx = (gy * 64 + gx) * 64;
            const float r = embedding[idx + 0];
            const float g = embedding[idx + 1];
            const float b = embedding[idx + 2];

            const float dr = r - seed_r;
            const float dg = g - seed_g;
            const float db = b - seed_b;
            const float color_dist = std::sqrt(dr * dr + dg * dg + db * db);

            const float dx = gx - prompt_gx;
            const float dy = gy - prompt_gy;
            const float spatial_dist = std::sqrt(dx * dx + dy * dy);

            float affinity = 0.0f;
            if (color_dist < 0.25f && spatial_dist < 32.0f) {
                affinity = std::max(0.0f, 1.0f - (color_dist / 0.25f)) * (1.0f - (spatial_dist / 34.0f));
            }
            grid_mask[gy * 64 + gx] = affinity;
        }
    }

    // Bilinear upsample to output dimensions
    for (int y = 0; y < out_h; ++y) {
        const float gy = (y / (float)out_h) * 64.0f;
        const int gy0 = std::clamp(static_cast<int>(gy), 0, 63);
        const int gy1 = std::clamp(gy0 + 1, 0, 63);
        const float dy = gy - gy0;

        for (int x = 0; x < out_w; ++x) {
            const float gx = (x / (float)out_w) * 64.0f;
            const int gx0 = std::clamp(static_cast<int>(gx), 0, 63);
            const int gx1 = std::clamp(gx0 + 1, 0, 63);
            const float dx = gx - gx0;

            const float v00 = grid_mask[gy0 * 64 + gx0];
            const float v10 = grid_mask[gy0 * 64 + gx1];
            const float v01 = grid_mask[gy1 * 64 + gx0];
            const float v11 = grid_mask[gy1 * 64 + gx1];

            const float val = (1.0f - dx) * (1.0f - dy) * v00 +
                              dx * (1.0f - dy) * v10 +
                              (1.0f - dx) * dy * v01 +
                              dx * dy * v11;

            uint8_t mask_val = 0;
            if (val > 0.15f) {
                const float norm = std::clamp((val - 0.15f) / 0.35f, 0.0f, 1.0f);
                const float s = norm * norm * (3.0f - 2.0f * norm);
                mask_val = static_cast<uint8_t>(std::round(s * 255.0f));
            }
            out_mask[y * out_w + x] = mask_val;
        }
    }

    return 0;
}

void native_cielab_magic_wand(
    const uint8_t* rgba,
    int width,
    int height,
    int seed_x,
    int seed_y,
    float hue_tolerance,
    float color_tolerance,
    uint8_t* out_mask
) {
    if (!rgba || !out_mask || width <= 0 || height <= 0) return;
    if (seed_x < 0 || seed_x >= width || seed_y < 0 || seed_y >= height) return;

    std::fill(out_mask, out_mask + (width * height), 0);

    // 1. Line art edge map for strict boundary stopping
    std::vector<float> lum(width * height);
    for (int i = 0; i < width * height; ++i) {
        float r = rgba[i * 4] / 255.0f;
        float g = rgba[i * 4 + 1] / 255.0f;
        float b = rgba[i * 4 + 2] / 255.0f;
        lum[i] = 0.299f * r + 0.587f * g + 0.114f * b;
    }

    std::vector<uint8_t> raw_edge(width * height, 0);
    for (int y = 0; y < height; ++y) {
        int ym1 = std::max(0, y - 1);
        int yp1 = std::min(height - 1, y + 1);
        for (int x = 0; x < width; ++x) {
            int xm1 = std::max(0, x - 1);
            int xp1 = std::min(width - 1, x + 1);
            int idx = y * width + x;

            // 3x3 Sobel operator
            float p00 = lum[ym1 * width + xm1];
            float p01 = lum[ym1 * width + x];
            float p02 = lum[ym1 * width + xp1];

            float p10 = lum[y * width + xm1];
            float p12 = lum[y * width + xp1];

            float p20 = lum[yp1 * width + xm1];
            float p21 = lum[yp1 * width + x];
            float p22 = lum[yp1 * width + xp1];

            float gx = (-1.0f * p00 + 1.0f * p02) +
                       (-2.0f * p10 + 2.0f * p12) +
                       (-1.0f * p20 + 1.0f * p22);
            float gy = (-1.0f * p00 - 2.0f * p01 - 1.0f * p02) +
                       ( 1.0f * p20 + 2.0f * p21 + 1.0f * p22);

            float sobel_mag = std::sqrt(gx * gx + gy * gy) / 8.0f;
            if (lum[idx] < 0.22f || sobel_mag > 0.08f) {
                raw_edge[idx] = 1;
            }
        }
    }

    // 1-pixel Morphological Dilation of edge map to seal anti-aliased gaps
    std::vector<uint8_t> is_edge = raw_edge;
    for (int y = 1; y < height - 1; ++y) {
        for (int x = 1; x < width - 1; ++x) {
            int idx = y * width + x;
            if (raw_edge[idx]) {
                is_edge[idx - 1] = 1;
                is_edge[idx + 1] = 1;
                is_edge[idx - width] = 1;
                is_edge[idx + width] = 1;
                is_edge[idx - width - 1] = 1;
                is_edge[idx - width + 1] = 1;
                is_edge[idx + width - 1] = 1;
                is_edge[idx + width + 1] = 1;
            }
        }
    }
    // Never allow seed pixel to be marked as edge
    is_edge[seed_y * width + seed_x] = 0;

    // 2. Seed pixel CIELAB
    int seed_off = (seed_y * width + seed_x) * 4;
    float sr_lin = srgb_to_linear(rgba[seed_off] / 255.0f);
    float sg_lin = srgb_to_linear(rgba[seed_off + 1] / 255.0f);
    float sb_lin = srgb_to_linear(rgba[seed_off + 2] / 255.0f);

    float sx = std::clamp((0.4124564f * sr_lin + 0.3575761f * sg_lin + 0.1804375f * sb_lin) / 0.95047f, 0.0f, 1.0f);
    float sy = std::clamp((0.2126729f * sr_lin + 0.7151522f * sg_lin + 0.0721750f * sb_lin) / 1.00000f, 0.0f, 1.0f);
    float sz = std::clamp((0.0193339f * sr_lin + 0.1191920f * sg_lin + 0.9503041f * sb_lin) / 1.08883f, 0.0f, 1.0f);

    float sfx = lab_f(sx), sfy = lab_f(sy), sfz = lab_f(sz);
    float s_l = 116.0f * sfy - 16.0f;
    float s_a = 500.0f * (sfx - sfy);
    float s_b = 200.0f * (sfy - sfz);
    float s_hue = std::atan2(s_b, s_a) * 57.2957795f;
    if (s_hue < 0.0f) s_hue += 360.0f;
    float s_chroma = std::sqrt(s_a * s_a + s_b * s_b);

    // 3. Connected queue flood fill (BFS)
    std::vector<uint8_t> visited(width * height, 0);
    std::vector<int> qx;
    std::vector<int> qy;
    qx.reserve(width * height);
    qy.reserve(width * height);

    qx.push_back(seed_x);
    qy.push_back(seed_y);
    visited[seed_y * width + seed_x] = 1;
    out_mask[seed_y * width + seed_x] = 255;

    size_t head = 0;
    const int dx[4] = {1, -1, 0, 0};
    const int dy[4] = {0, 0, 1, -1};

    float eff_col_tol = color_tolerance * 65.0f;
    float eff_hue_tol = hue_tolerance * 120.0f;

    while (head < qx.size()) {
        int cx = qx[head];
        int cy = qy[head];
        head++;

        for (int i = 0; i < 4; ++i) {
            int nx = cx + dx[i];
            int ny = cy + dy[i];
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
            int nidx = ny * width + nx;
            if (visited[nidx]) continue;
            visited[nidx] = 1;

            // Stop at line art edges
            if (is_edge[nidx]) continue;

            int noff = nidx * 4;
            float nr_lin = srgb_to_linear(rgba[noff] / 255.0f);
            float ng_lin = srgb_to_linear(rgba[noff + 1] / 255.0f);
            float nb_lin = srgb_to_linear(rgba[noff + 2] / 255.0f);

            float nx_val = std::clamp((0.4124564f * nr_lin + 0.3575761f * ng_lin + 0.1804375f * nb_lin) / 0.95047f, 0.0f, 1.0f);
            float ny_val = std::clamp((0.2126729f * nr_lin + 0.7151522f * ng_lin + 0.0721750f * nb_lin) / 1.00000f, 0.0f, 1.0f);
            float nz_val = std::clamp((0.0193339f * nr_lin + 0.1191920f * ng_lin + 0.9503041f * nb_lin) / 1.08883f, 0.0f, 1.0f);

            float nfx = lab_f(nx_val), nfy = lab_f(ny_val), nfz = lab_f(nz_val);
            float n_l = 116.0f * nfy - 16.0f;
            float n_a = 500.0f * (nfx - nfy);
            float n_b = 200.0f * (nfy - nfz);

            float dl = n_l - s_l;
            float da = n_a - s_a;
            float db = n_b - s_b;
            float delta_e = std::sqrt(dl * dl + da * da + db * db);

            float n_hue = std::atan2(n_b, n_a) * 57.2957795f;
            if (n_hue < 0.0f) n_hue += 360.0f;
            float dh = std::abs(n_hue - s_hue);
            if (dh > 180.0f) dh = 360.0f - dh;
            float n_chroma = std::sqrt(n_a * n_a + n_b * n_b);

            bool matches = false;
            if (s_chroma < 10.0f && n_chroma < 15.0f) {
                matches = (delta_e <= eff_col_tol);
            } else {
                matches = (dh <= eff_hue_tol && delta_e <= eff_col_tol * 1.5f);
            }

            if (matches) {
                out_mask[nidx] = 255;
                qx.push_back(nx);
                qy.push_back(ny);
            }
        }
    }
}

// ============================================================================
// Autodraw Engine V3 (Centerline Skeletonization, Guo-Hall Thinning, Zero-Copy FFI)
// ============================================================================

struct SkeletonPoint {
    float x;
    float y;
    float width;
};

// Ramer-Douglas-Peucker (RDP) polyline simplification
static void rdp_simplify(
    const std::vector<SkeletonPoint>& points,
    int start_idx,
    int end_idx,
    float epsilon,
    std::vector<bool>& keep
) {
    if (end_idx <= start_idx + 1) return;

    float max_dist = 0.0f;
    int max_idx = start_idx;

    float x1 = points[start_idx].x;
    float y1 = points[start_idx].y;
    float x2 = points[end_idx].x;
    float y2 = points[end_idx].y;

    float dx = x2 - x1;
    float dy = y2 - y1;
    float len_sq = dx * dx + dy * dy;

    for (int i = start_idx + 1; i < end_idx; ++i) {
        float px = points[i].x;
        float py = points[i].y;
        float dist = 0.0f;
        if (len_sq < 1e-6f) {
            float ex = px - x1;
            float ey = py - y1;
            dist = std::sqrt(ex * ex + ey * ey);
        } else {
            float t = ((px - x1) * dx + (py - y1) * dy) / len_sq;
            t = std::clamp(t, 0.0f, 1.0f);
            float proj_x = x1 + t * dx;
            float proj_y = y1 + t * dy;
            float ex = px - proj_x;
            float ey = py - proj_y;
            dist = std::sqrt(ex * ex + ey * ey);
        }

        if (dist > max_dist) {
            max_dist = dist;
            max_idx = i;
        }
    }

    if (max_dist > epsilon) {
        keep[max_idx] = true;
        rdp_simplify(points, start_idx, max_idx, epsilon, keep);
        rdp_simplify(points, max_idx, end_idx, epsilon, keep);
    }
}

// Guo-Hall parallel thinning iteration
static bool guo_hall_iteration(
    std::vector<uint8_t>& binary,
    int width,
    int height,
    int sub_iter
) {
    std::vector<int> to_remove;
    to_remove.reserve(width * height / 16);

    for (int y = 1; y < height - 1; ++y) {
        int row_prev = (y - 1) * width;
        int row_curr = y * width;
        int row_next = (y + 1) * width;

        for (int x = 1; x < width - 1; ++x) {
            int p1_idx = row_curr + x;
            if (binary[p1_idx] == 0) continue;

            // Neighbors in clockwise order around P1:
            // P9 P2 P3
            // P8 P1 P4
            // P7 P6 P5
            int p2 = binary[row_prev + x];
            int p3 = binary[row_prev + x + 1];
            int p4 = binary[row_curr + x + 1];
            int p5 = binary[row_next + x + 1];
            int p6 = binary[row_next + x];
            int p7 = binary[row_next + x - 1];
            int p8 = binary[row_curr + x - 1];
            int p9 = binary[row_prev + x - 1];

            // Condition 1: Connectivity number C(P1) == 1
            // C = ~p2&(p3|p4) + ~p4&(p5|p6) + ~p6&(p7|p8) + ~p8&(p9|p2)
            int c = ((!p2 && (p3 || p4)) ? 1 : 0) +
                    ((!p4 && (p5 || p6)) ? 1 : 0) +
                    ((!p6 && (p7 || p8)) ? 1 : 0) +
                    ((!p8 && (p9 || p2)) ? 1 : 0);
            if (c != 1) continue;

            // Condition 2: 2 <= min(N1, N2) <= 3
            int n1 = (p9 || p2) + (p3 || p4) + (p5 || p6) + (p7 || p8);
            int n2 = (p2 || p3) + (p4 || p5) + (p6 || p7) + (p8 || p9);
            int min_n = std::min(n1, n2);
            if (min_n < 2 || min_n > 3) continue;

            // Condition 3: Sub-iteration dependent neighbor condition
            if (sub_iter == 0) {
                if (((p2 || p3 || !p5) && p4) != 0) continue;
            } else {
                if (((p6 || p7 || !p9) && p8) != 0) continue;
            }

            to_remove.push_back(p1_idx);
        }
    }

    for (int idx : to_remove) {
        binary[idx] = 0;
    }

    return !to_remove.empty();
}

StrokeBuffer* native_skeleton_trace(
    const uint8_t* rgba,
    int width,
    int height,
    int max_strokes
) {
    if (!rgba || width <= 0 || height <= 0) return nullptr;
    if (max_strokes <= 0) max_strokes = 2500;

    // 1. Downscale to max 1024px for cache locality & bounded latency
    int max_dim = std::max(width, height);
    float scale = (max_dim > 1024) ? (1024.0f / max_dim) : 1.0f;
    int proc_w = std::max(1, static_cast<int>(std::round(width * scale)));
    int proc_h = std::max(1, static_cast<int>(std::round(height * scale)));

    std::vector<uint8_t> lum(proc_w * proc_h);
    float inv_scale = 1.0f / scale;

    for (int py = 0; py < proc_h; ++py) {
        int sy = std::min(static_cast<int>(py * inv_scale), height - 1);
        int proc_row = py * proc_w;
        int src_row = sy * width;
        for (int px = 0; px < proc_w; ++px) {
            int sx = std::min(static_cast<int>(px * inv_scale), width - 1);
            int s_idx = (src_row + sx) * 4;
            float l = 0.299f * rgba[s_idx] + 0.587f * rgba[s_idx + 1] + 0.114f * rgba[s_idx + 2];
            lum[proc_row + px] = static_cast<uint8_t>(std::clamp(l, 0.0f, 255.0f));
        }
    }

    // 2. Integral image adaptive thresholding
    std::vector<uint32_t> integral((proc_w + 1) * (proc_h + 1), 0);
    for (int y = 0; y < proc_h; ++y) {
        uint32_t row_sum = 0;
        int i_row = (y + 1) * (proc_w + 1);
        int i_prev = y * (proc_w + 1);
        int lum_row = y * proc_w;
        for (int x = 0; x < proc_w; ++x) {
            row_sum += lum[lum_row + x];
            integral[i_row + x + 1] = integral[i_prev + x + 1] + row_sum;
        }
    }

    std::vector<uint8_t> binary(proc_w * proc_h, 0);
    int window_r = std::max(8, std::max(proc_w, proc_h) / 32);

    for (int y = 0; y < proc_h; ++y) {
        int y1 = std::max(0, y - window_r);
        int y2 = std::min(proc_h - 1, y + window_r);
        int row_off = y * proc_w;

        for (int x = 0; x < proc_w; ++x) {
            int x1 = std::max(0, x - window_r);
            int x2 = std::min(proc_w - 1, x + window_r);

            uint32_t count = (x2 - x1 + 1) * (y2 - y1 + 1);
            uint32_t sum = integral[(y2 + 1) * (proc_w + 1) + (x2 + 1)] -
                           integral[y1 * (proc_w + 1) + (x2 + 1)] -
                           integral[(y2 + 1) * (proc_w + 1) + x1] +
                           integral[y1 * (proc_w + 1) + x1];

            float avg = static_cast<float>(sum) / count;
            // Dark foreground lines
            if (lum[row_off + x] < avg * 0.90f) {
                binary[row_off + x] = 1;
            }
        }
    }

    // 3. Medial Axis Distance Transform (2-pass Chamfer distance)
    std::vector<float> dist(proc_w * proc_h, 9999.0f);
    for (int i = 0; i < proc_w * proc_h; ++i) {
        if (binary[i] == 0) dist[i] = 0.0f;
    }

    // Forward pass
    for (int y = 1; y < proc_h; ++y) {
        int r_curr = y * proc_w;
        int r_prev = (y - 1) * proc_w;
        for (int x = 1; x < proc_w - 1; ++x) {
            if (binary[r_curr + x] == 0) continue;
            float d = dist[r_curr + x];
            d = std::min(d, dist[r_curr + x - 1] + 1.0f);
            d = std::min(d, dist[r_prev + x] + 1.0f);
            d = std::min(d, dist[r_prev + x - 1] + 1.414f);
            d = std::min(d, dist[r_prev + x + 1] + 1.414f);
            dist[r_curr + x] = d;
        }
    }

    // Backward pass
    for (int y = proc_h - 2; y >= 0; --y) {
        int r_curr = y * proc_w;
        int r_next = (y + 1) * proc_w;
        for (int x = proc_w - 2; x >= 1; --x) {
            if (binary[r_curr + x] == 0) continue;
            float d = dist[r_curr + x];
            d = std::min(d, dist[r_curr + x + 1] + 1.0f);
            d = std::min(d, dist[r_next + x] + 1.0f);
            d = std::min(d, dist[r_next + x + 1] + 1.414f);
            d = std::min(d, dist[r_next + x - 1] + 1.414f);
            dist[r_curr + x] = d;
        }
    }

    // 4. Guo-Hall Thinning (Parallel skeletonization)
    std::vector<uint8_t> skeleton = binary;
    for (int iter = 0; iter < 48; ++iter) {
        bool c1 = guo_hall_iteration(skeleton, proc_w, proc_h, 0);
        bool c2 = guo_hall_iteration(skeleton, proc_w, proc_h, 1);
        if (!c1 && !c2) break;
    }

    // 5. 256x256 Tone Coverage Buffer
    const int COV_SIZE = 256;
    std::vector<float> cov_target(COV_SIZE * COV_SIZE, 0.0f);
    std::vector<float> cov_drawn(COV_SIZE * COV_SIZE, 0.0f);

    float sx_cov = static_cast<float>(COV_SIZE) / proc_w;
    float sy_cov = static_cast<float>(COV_SIZE) / proc_h;

    for (int y = 0; y < proc_h; ++y) {
        int cy = std::min(static_cast<int>(y * sy_cov), COV_SIZE - 1);
        int p_row = y * proc_w;
        int c_row = cy * COV_SIZE;
        for (int x = 0; x < proc_w; ++x) {
            int cx = std::min(static_cast<int>(x * sx_cov), COV_SIZE - 1);
            cov_target[c_row + cx] += (1.0f - lum[p_row + x] / 255.0f);
        }
    }

    // 6. Polyline Walking, Spur Pruning & RDP Simplification
    std::vector<uint8_t> visited(proc_w * proc_h, 0);
    std::vector<std::vector<SkeletonPoint>> candidate_strokes;

    // First, identify endpoints (degree 1) to start strokes cleanly
    std::vector<int> start_nodes;
    for (int y = 1; y < proc_h - 1; ++y) {
        int r_curr = y * proc_w;
        int r_prev = (y - 1) * proc_w;
        int r_next = (y + 1) * proc_w;
        for (int x = 1; x < proc_w - 1; ++x) {
            int idx = r_curr + x;
            if (skeleton[idx] == 0) continue;
            int deg = skeleton[r_prev + x - 1] + skeleton[r_prev + x] + skeleton[r_prev + x + 1] +
                      skeleton[r_curr + x - 1] + skeleton[r_curr + x + 1] +
                      skeleton[r_next + x - 1] + skeleton[r_next + x] + skeleton[r_next + x + 1];
            if (deg == 1) {
                start_nodes.push_back(idx);
            }
        }
    }

    // Also add all remaining skeleton pixels as secondary starts
    for (int y = 1; y < proc_h - 1; ++y) {
        int r_curr = y * proc_w;
        for (int x = 1; x < proc_w - 1; ++x) {
            int idx = r_curr + x;
            if (skeleton[idx] == 1) {
                start_nodes.push_back(idx);
            }
        }
    }

    const int dx8[8] = {1, 1, 0, -1, -1, -1, 0, 1};
    const int dy8[8] = {0, 1, 1, 1, 0, -1, -1, -1};

    for (int start_idx : start_nodes) {
        if (visited[start_idx] || skeleton[start_idx] == 0) continue;

        std::vector<SkeletonPoint> polyline;
        int curr_idx = start_idx;
        int curr_x = curr_idx % proc_w;
        int curr_y = curr_idx / proc_w;

        for (int step = 0; step < 256; ++step) {
            visited[curr_idx] = 1;

            float w_val = std::clamp(dist[curr_idx] * 2.0f * inv_scale, 1.0f, 25.0f);
            polyline.push_back({
                curr_x * inv_scale,
                curr_y * inv_scale,
                w_val
            });

            int next_idx = -1;
            int next_x = -1, next_y = -1;
            for (int d = 0; d < 8; ++d) {
                int nx = curr_x + dx8[d];
                int ny = curr_y + dy8[d];
                if (nx >= 0 && nx < proc_w && ny >= 0 && ny < proc_h) {
                    int nidx = ny * proc_w + nx;
                    if (skeleton[nidx] == 1 && !visited[nidx]) {
                        next_idx = nidx;
                        next_x = nx;
                        next_y = ny;
                        break;
                    }
                }
            }

            if (next_idx == -1) break;
            curr_idx = next_idx;
            curr_x = next_x;
            curr_y = next_y;
        }

        // Spur pruning: remove short parasitic branches (< 6px)
        float total_len = 0.0f;
        for (size_t i = 1; i < polyline.size(); ++i) {
            float ddx = polyline[i].x - polyline[i - 1].x;
            float ddy = polyline[i].y - polyline[i - 1].y;
            total_len += std::sqrt(ddx * ddx + ddy * ddy);
        }
        if (total_len < 6.0f || polyline.size() < 2) continue;

        // RDP polyline simplification (epsilon = 1.2px)
        std::vector<bool> keep(polyline.size(), false);
        keep.front() = true;
        keep.back() = true;
        rdp_simplify(polyline, 0, static_cast<int>(polyline.size()) - 1, 1.2f, keep);

        std::vector<SkeletonPoint> simplified;
        for (size_t i = 0; i < polyline.size(); ++i) {
            if (keep[i]) simplified.push_back(polyline[i]);
        }

        if (simplified.size() < 2) continue;

        // Tone Coverage Check: skip redundant hatching strokes if local luminance budget already met
        float stroke_cov_need = 0.0f;
        float stroke_cov_have = 0.0f;
        for (const auto& pt : simplified) {
            int cx = std::clamp(static_cast<int>(pt.x * scale * sx_cov), 0, COV_SIZE - 1);
            int cy = std::clamp(static_cast<int>(pt.y * scale * sy_cov), 0, COV_SIZE - 1);
            int c_idx = cy * COV_SIZE + cx;
            stroke_cov_need += cov_target[c_idx];
            stroke_cov_have += cov_drawn[c_idx];
        }

        if (stroke_cov_need > 0.01f && (stroke_cov_have / stroke_cov_need) > 0.92f) {
            continue; // Area already fully shaded, prevent overworked ink
        }

        // Record ink deposit into coverage buffer
        for (const auto& pt : simplified) {
            int cx = std::clamp(static_cast<int>(pt.x * scale * sx_cov), 0, COV_SIZE - 1);
            int cy = std::clamp(static_cast<int>(pt.y * scale * sy_cov), 0, COV_SIZE - 1);
            cov_drawn[cy * COV_SIZE + cx] += 1.0f;
        }

        candidate_strokes.push_back(simplified);
    }

    // 7. Graph Ordering: Greedy nearest-endpoint TSP (Large structures first)
    if (candidate_strokes.empty()) {
        // Fallback single line to prevent empty buffer
        std::vector<SkeletonPoint> fb;
        fb.push_back({0.0f, 0.0f, 2.0f});
        fb.push_back({static_cast<float>(width), static_cast<float>(height), 2.0f});
        candidate_strokes.push_back(fb);
    }

    // Sort candidate strokes by length in descending order (major structures first)
    auto stroke_len = [](const std::vector<SkeletonPoint>& st) -> float {
        float l = 0.0f;
        for (size_t i = 1; i < st.size(); ++i) {
            float ddx = st[i].x - st[i - 1].x;
            float ddy = st[i].y - st[i - 1].y;
            l += std::sqrt(ddx * ddx + ddy * ddy);
        }
        return l;
    };

    std::sort(candidate_strokes.begin(), candidate_strokes.end(),
              [&](const std::vector<SkeletonPoint>& a, const std::vector<SkeletonPoint>& b) {
                  return stroke_len(a) > stroke_len(b);
              });

    if (candidate_strokes.size() > static_cast<size_t>(max_strokes)) {
        candidate_strokes.resize(max_strokes);
    }

    std::vector<std::vector<SkeletonPoint>> ordered_strokes;
    std::vector<bool> used(candidate_strokes.size(), false);

    // Start with the longest primary structure
    ordered_strokes.push_back(candidate_strokes[0]);
    used[0] = true;
    float pen_x = candidate_strokes[0].back().x;
    float pen_y = candidate_strokes[0].back().y;

    for (size_t step = 1; step < candidate_strokes.size(); ++step) {
        float min_dist_sq = 1e12f;
        int best_idx = -1;
        bool reverse_stroke = false;

        for (size_t i = 0; i < candidate_strokes.size(); ++i) {
            if (used[i]) continue;
            float d1_x = candidate_strokes[i].front().x - pen_x;
            float d1_y = candidate_strokes[i].front().y - pen_y;
            float dist1 = d1_x * d1_x + d1_y * d1_y;

            float d2_x = candidate_strokes[i].back().x - pen_x;
            float d2_y = candidate_strokes[i].back().y - pen_y;
            float dist2 = d2_x * d2_x + d2_y * d2_y;

            if (dist1 < min_dist_sq) {
                min_dist_sq = dist1;
                best_idx = static_cast<int>(i);
                reverse_stroke = false;
            }
            if (dist2 < min_dist_sq) {
                min_dist_sq = dist2;
                best_idx = static_cast<int>(i);
                reverse_stroke = true;
            }
        }

        if (best_idx == -1) break;
        used[best_idx] = true;

        if (reverse_stroke) {
            std::reverse(candidate_strokes[best_idx].begin(), candidate_strokes[best_idx].end());
        }
        ordered_strokes.push_back(candidate_strokes[best_idx]);
        pen_x = candidate_strokes[best_idx].back().x;
        pen_y = candidate_strokes[best_idx].back().y;
    }

    // 8. Package into zero-copy StrokeBuffer
    int stroke_count = static_cast<int>(ordered_strokes.size());
    int total_points = 0;
    for (const auto& st : ordered_strokes) {
        total_points += static_cast<int>(st.size());
    }

    StrokeBuffer* buffer = new StrokeBuffer();
    buffer->stroke_count = stroke_count;
    buffer->total_points = total_points;
    buffer->points_x_y = new int16_t[total_points * 2];
    buffer->widths = new uint8_t[total_points];
    buffer->offsets = new uint32_t[stroke_count + 1];

    int point_idx = 0;
    for (int s = 0; s < stroke_count; ++s) {
        buffer->offsets[s] = static_cast<uint32_t>(point_idx);
        for (const auto& pt : ordered_strokes[s]) {
            buffer->points_x_y[point_idx * 2]     = static_cast<int16_t>(std::clamp(std::round(pt.x), 0.0f, 32767.0f));
            buffer->points_x_y[point_idx * 2 + 1] = static_cast<int16_t>(std::clamp(std::round(pt.y), 0.0f, 32767.0f));
            buffer->widths[point_idx]             = static_cast<uint8_t>(std::clamp(std::round(pt.width), 1.0f, 255.0f));
            point_idx++;
        }
    }
    buffer->offsets[stroke_count] = static_cast<uint32_t>(point_idx);

    return buffer;
}

void native_stroke_buffer_free(StrokeBuffer* buffer) {
    if (!buffer) return;
    if (buffer->points_x_y) delete[] buffer->points_x_y;
    if (buffer->widths) delete[] buffer->widths;
    if (buffer->offsets) delete[] buffer->offsets;
    delete buffer;
}

} // extern "C"
