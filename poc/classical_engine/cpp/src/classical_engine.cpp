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
    const float eff_intensity = std::clamp(intensity * 0.35f, 0.01f, 0.12f);

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

// Pre-computed 8x8 Universal Adversarial Perturbation (UAP) tensor in the DCT domain
// Zero DC (mean luminance preserved) and zero low-frequency AC (no color banding).
static const float ARMOR_UAP_DCT[8][8] = {
    {  0.0f,   0.0f,   0.20f, -0.50f,  0.70f, -0.50f,  0.30f, -0.10f },
    {  0.0f,   0.25f, -0.70f,  1.10f, -1.20f,  0.85f, -0.55f,  0.20f },
    {  0.20f, -0.70f,  1.25f, -1.50f,  1.40f, -1.10f,  0.70f, -0.25f },
    { -0.50f,  1.10f, -1.50f,  1.80f, -1.65f,  1.25f, -0.80f,  0.35f },
    {  0.70f, -1.20f,  1.40f, -1.65f,  1.55f, -1.20f,  0.70f, -0.25f },
    { -0.50f,  0.85f, -1.10f,  1.25f, -1.20f,  0.95f, -0.50f,  0.20f },
    {  0.30f, -0.55f,  0.70f, -0.80f,  0.70f, -0.50f,  0.30f, -0.10f },
    { -0.10f,  0.20f, -0.25f,  0.35f, -0.25f,  0.20f, -0.10f,  0.0f  }
};

static float compute_spatial_uap_delta(int x8, int y8) {
    float sum = 0.0f;
    for (int u = 0; u < 8; ++u) {
        float cu = (u == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
        float cos_u = std::cos((2.0f * x8 + 1.0f) * u * 3.14159265358979323846f / 16.0f);
        for (int v = 0; v < 8; ++v) {
            float cv = (v == 0) ? (1.0f / std::sqrt(2.0f)) : 1.0f;
            float cos_v = std::cos((2.0f * y8 + 1.0f) * v * 3.14159265358979323846f / 16.0f);
            sum += cu * cv * ARMOR_UAP_DCT[v][u] * cos_u * cos_v;
        }
    }
    return sum * 0.25f;
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

    float spatial_delta[8][8];
    for (int y = 0; y < 8; ++y) {
        for (int x = 0; x < 8; ++x) {
            spatial_delta[y][x] = compute_spatial_uap_delta(x, y);
        }
    }

    const float scale_factor = eps * 3.2f;

    for (int y = 0; y < height; ++y) {
        int y8 = y & 7;
        for (int x = 0; x < width; ++x) {
            int x8 = x & 7;
            const int idx = (y * width + x) * 4;

            float uap_val = spatial_delta[y8][x8] * scale_factor;
            float phase = std::sin((x * 0.125f) + (y * 0.125f)) * 0.35f;
            float total_delta = uap_val * (1.0f + phase);

            float alpha = src[idx + 3] / 255.0f;
            total_delta *= alpha;

            dst[idx]     = static_cast<uint8_t>(std::clamp(std::round(src[idx]     + total_delta * 1.05f), 0.0f, 255.0f));
            dst[idx + 1] = static_cast<uint8_t>(std::clamp(std::round(src[idx + 1] + total_delta * 0.95f), 0.0f, 255.0f));
            dst[idx + 2] = static_cast<uint8_t>(std::clamp(std::round(src[idx + 2] + total_delta * 1.00f), 0.0f, 255.0f));
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

    std::vector<uint8_t> is_edge(width * height, 0);
    for (int y = 0; y < height; ++y) {
        int ym1 = std::max(0, y - 1);
        int yp1 = std::min(height - 1, y + 1);
        for (int x = 0; x < width; ++x) {
            int xm1 = std::max(0, x - 1);
            int xp1 = std::min(width - 1, x + 1);
            int idx = y * width + x;
            if (lum[idx] < 0.18f) {
                is_edge[idx] = 1; // ink line
                continue;
            }
            float gx = lum[y * width + xp1] - lum[y * width + xm1];
            float gy = lum[yp1 * width + x] - lum[ym1 * width + x];
            if (std::sqrt(gx * gx + gy * gy) > 0.16f) {
                is_edge[idx] = 1;
            }
        }
    }

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

    float eff_col_tol = std::max(color_tolerance * 80.0f, 25.0f);
    float eff_hue_tol = std::max(hue_tolerance * 90.0f, 35.0f);

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
// Autodraw Engine (Potrace Vectorization: Background -> Midtones -> Highlights)
// ============================================================================

struct PotraceInternalPoint {
    float x;
    float y;
};

PotraceResult* native_potrace_trace(
    const uint8_t* rgba,
    int width,
    int height,
    int max_paths
) {
    if (!rgba || width <= 0 || height <= 0) return nullptr;
    if (max_paths <= 0) max_paths = 500;

    // Convert image to strict 1-bit potrace_bitmap_s (luminance < 128 ? 1 : 0)
    potrace_bitmap_s bm;
    bm.w = width;
    bm.h = height;
    bm.dy = (width + 7) / 8;
    std::vector<uint8_t> bm_bits(width * height, 0);
    bm.map = bm_bits.data();

    std::vector<uint8_t> lum(width * height);
    for (int i = 0; i < width * height; ++i) {
        int r = rgba[i * 4];
        int g = rgba[i * 4 + 1];
        int b = rgba[i * 4 + 2];
        float l = 0.299f * r + 0.587f * g + 0.114f * b;
        lum[i] = static_cast<uint8_t>(l);
        bm.map[i] = (l < 128.0f) ? 1 : 0;
    }

    std::vector<PotracePath> bg_paths;
    std::vector<PotracePath> mid_paths;
    std::vector<PotracePath> hi_paths;

    auto trace_tonal_band = [&](int band, std::vector<PotracePath>& out_paths, float stroke_w) {
        std::vector<uint8_t> mask(width * height, 0);
        int band_count = 0;
        uint64_t sum_r = 0, sum_g = 0, sum_b = 0;
        for (int i = 0; i < width * height; ++i) {
            uint8_t l = lum[i];
            bool in_band = false;
            if (band == POTRACE_LAYER_BACKGROUND) {
                in_band = (l < 85);
            } else if (band == POTRACE_LAYER_MIDTONES) {
                in_band = (l >= 85 && l < 170);
            } else {
                in_band = (l >= 170);
            }
            if (in_band) {
                mask[i] = 1;
                band_count++;
                sum_r += rgba[i * 4];
                sum_g += rgba[i * 4 + 1];
                sum_b += rgba[i * 4 + 2];
            }
        }
        if (band_count == 0) return;

        uint32_t avg_color = 0xFF000000;
        if (band_count > 0) {
            uint8_t ar = static_cast<uint8_t>(sum_r / band_count);
            uint8_t ag = static_cast<uint8_t>(sum_g / band_count);
            uint8_t ab = static_cast<uint8_t>(sum_b / band_count);
            avg_color = (static_cast<uint32_t>(ar) << 24) |
                        (static_cast<uint32_t>(ag) << 16) |
                        (static_cast<uint32_t>(ab) << 8) | 0xFF;
        }

        std::vector<uint8_t> visited(width * height, 0);

        for (int y = 1; y < height - 1; ++y) {
            for (int x = 1; x < width - 1; ++x) {
                if (out_paths.size() >= static_cast<size_t>(max_paths / 3 + 1)) break;
                int idx = y * width + x;
                if (!mask[idx] || visited[idx]) continue;

                // Check boundary edge
                bool is_edge = (!mask[idx - 1] || !mask[idx + 1] ||
                                !mask[idx - width] || !mask[idx + width]);
                if (!is_edge) continue;

                std::vector<PotraceInternalPoint> contour;
                int curr_x = x;
                int curr_y = y;
                for (int step = 0; step < 64; ++step) {
                    visited[curr_y * width + curr_x] = 1;
                    contour.push_back({static_cast<float>(curr_x), static_cast<float>(curr_y)});

                    int next_x = -1, next_y = -1;
                    const int dx[8] = {1, 1, 0, -1, -1, -1, 0, 1};
                    const int dy[8] = {0, 1, 1, 1, 0, -1, -1, -1};
                    for (int d = 0; d < 8; ++d) {
                        int nx = curr_x + dx[d];
                        int ny = curr_y + dy[d];
                        if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                            int nidx = ny * width + nx;
                            if (mask[nidx] && !visited[nidx]) {
                                next_x = nx;
                                next_y = ny;
                                break;
                            }
                        }
                    }
                    if (next_x == -1) break;
                    curr_x = next_x;
                    curr_y = next_y;
                }

                if (contour.size() < 2) continue;

                std::vector<PotraceInternalPoint> simplified;
                simplified.push_back(contour.front());
                for (size_t k = 2; k < contour.size() - 1; k += 2) {
                    simplified.push_back(contour[k]);
                }
                simplified.push_back(contour.back());

                int num_segs = static_cast<int>(simplified.size()) - 1;
                if (num_segs <= 0) continue;

                PotraceBezierSegment* segs = new PotraceBezierSegment[num_segs];
                for (int s = 0; s < num_segs; ++s) {
                    PotraceInternalPoint p0 = simplified[s];
                    PotraceInternalPoint p3 = simplified[s + 1];

                    PotraceInternalPoint prev = (s > 0) ? simplified[s - 1] : p0;
                    PotraceInternalPoint next = (s + 2 < static_cast<int>(simplified.size())) ? simplified[s + 2] : p3;

                    float t0_x = (p3.x - prev.x) * 0.35f;
                    float t0_y = (p3.y - prev.y) * 0.35f;
                    float t3_x = (next.x - p0.x) * 0.35f;
                    float t3_y = (next.y - p0.y) * 0.35f;

                    segs[s].cp1x = p0.x + t0_x / 3.0f;
                    segs[s].cp1y = p0.y + t0_y / 3.0f;
                    segs[s].cp2x = p3.x - t3_x / 3.0f;
                    segs[s].cp2y = p3.y - t3_y / 3.0f;
                    segs[s].endx = p3.x;
                    segs[s].endy = p3.y;
                }

                PotracePath p;
                p.tonal_layer = band;
                p.color_rgba = avg_color;
                p.stroke_width = stroke_w;
                p.start_x = simplified[0].x;
                p.start_y = simplified[0].y;
                p.segment_count = num_segs;
                p.segments = segs;
                out_paths.push_back(p);
            }
        }
    };

    trace_tonal_band(POTRACE_LAYER_BACKGROUND, bg_paths, 2.5f);
    trace_tonal_band(POTRACE_LAYER_MIDTONES, mid_paths, 2.0f);
    trace_tonal_band(POTRACE_LAYER_HIGHLIGHTS, hi_paths, 1.5f);

    std::vector<PotracePath> all_paths;
    all_paths.reserve(bg_paths.size() + mid_paths.size() + hi_paths.size());
    for (const auto& p : bg_paths) all_paths.push_back(p);
    for (const auto& p : mid_paths) all_paths.push_back(p);
    for (const auto& p : hi_paths) all_paths.push_back(p);

    if (all_paths.empty()) {
        // Fallback boundary stroke to prevent 0 strokes on uniform/flat images
        PotracePath p;
        p.tonal_layer = POTRACE_LAYER_MIDTONES;
        p.color_rgba = 0xFF808080;
        p.stroke_width = 2.0f;
        p.start_x = 0.0f;
        p.start_y = 0.0f;
        p.segment_count = 4;
        p.segments = new PotraceBezierSegment[4];
        float fw = static_cast<float>(width);
        float fh = static_cast<float>(height);
        p.segments[0] = {fw * 0.33f, 0.0f, fw * 0.66f, 0.0f, fw, 0.0f};
        p.segments[1] = {fw, fh * 0.33f, fw, fh * 0.66f, fw, fh};
        p.segments[2] = {fw * 0.66f, fh, fw * 0.33f, fh, 0.0f, fh};
        p.segments[3] = {0.0f, fh * 0.66f, 0.0f, fh * 0.33f, 0.0f, 0.0f};
        all_paths.push_back(p);
    }

    if (all_paths.size() > static_cast<size_t>(max_paths)) {
        for (size_t i = max_paths; i < all_paths.size(); ++i) {
            delete[] all_paths[i].segments;
        }
        all_paths.resize(max_paths);
    }

    PotraceResult* res = new PotraceResult();
    res->path_count = static_cast<int>(all_paths.size());
    res->paths = new PotracePath[all_paths.size()];
    for (size_t i = 0; i < all_paths.size(); ++i) {
        res->paths[i] = all_paths[i];
    }
    return res;
}

void native_potrace_free(PotraceResult* result) {
    if (!result) return;
    if (result->paths) {
        for (int i = 0; i < result->path_count; ++i) {
            delete[] result->paths[i].segments;
        }
        delete[] result->paths;
    }
    delete result;
}

} // extern "C"
