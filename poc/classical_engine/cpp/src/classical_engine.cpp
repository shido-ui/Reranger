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

        const float x = (0.4124564f * r_lin + 0.3575761f * g_lin + 0.1804375f * b_lin) / 0.95047f;
        const float y = (0.2126729f * r_lin + 0.7151522f * g_lin + 0.0721750f * b_lin) / 1.00000f;
        const float z = (0.0193339f * r_lin + 0.1191920f * g_lin + 0.9503041f * b_lin) / 1.08883f;

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

        // Convert back to sRGB
        const float out_fy = (lab_l + 16.0f) / 116.0f;
        const float out_fx = out_fy + lab_a / 500.0f;
        const float out_fz = out_fy - lab_b / 200.0f;

        const float out_x = 0.95047f * lab_inv_f(out_fx);
        const float out_y = 1.00000f * lab_inv_f(out_fy);
        const float out_z = 1.08883f * lab_inv_f(out_fz);

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
// EdgeTAM Zero-Shot Semantic Segmentation (ExecuTorch / LiteRT Mobile Runtime)
// ============================================================================

struct EdgeTamEngineContext {
    std::string model_path;
    bool is_initialized = true;
};

void* native_edgetam_create(const char* model_path) {
    auto* ctx = new EdgeTamEngineContext();
    if (model_path) {
        ctx->model_path = model_path;
    }
    return static_cast<void*>(ctx);
}

void native_edgetam_destroy(void* handle) {
    if (handle) {
        delete static_cast<EdgeTamEngineContext*>(handle);
    }
}

void native_edgetam_map_view_to_padded(
    float view_x, float view_y,
    float view_w, float view_h,
    int src_w, int src_h,
    float* out_src_x, float* out_src_y,
    float* out_pad_x, float* out_pad_y,
    int* out_active_w_1024, int* out_active_h_1024
) {
    if (src_w <= 0 || src_h <= 0 || view_w <= 0.0f || view_h <= 0.0f) {
        if (out_src_x) *out_src_x = 0.0f;
        if (out_src_y) *out_src_y = 0.0f;
        if (out_pad_x) *out_pad_x = 0.0f;
        if (out_pad_y) *out_pad_y = 0.0f;
        if (out_active_w_1024) *out_active_w_1024 = 1024;
        if (out_active_h_1024) *out_active_h_1024 = 1024;
        return;
    }

    // 1. BoxFit.contain scale factor
    const float scale = std::min(view_w / (float)src_w, view_h / (float)src_h);
    const float rendered_w = src_w * scale;
    const float rendered_h = src_h * scale;

    // 2. Letterbox/pillarbox offset (centered)
    const float offset_x = (view_w - rendered_w) * 0.5f;
    const float offset_y = (view_h - rendered_h) * 0.5f;

    // 3. Undo letterbox -> Source bitmap coordinate
    const float src_x = std::clamp((view_x - offset_x) / scale, 0.0f, (float)(src_w - 1));
    const float src_y = std::clamp((view_y - offset_y) / scale, 0.0f, (float)(src_h - 1));
    if (out_src_x) *out_src_x = src_x;
    if (out_src_y) *out_src_y = src_y;

    // 4. Scale into 1024x1024 top-left padded square (longest edge = 1024)
    const int max_src_dim = std::max(src_w, src_h);
    const float pad_scale = 1024.0f / (float)max_src_dim;
    const int active_w = std::clamp(static_cast<int>(std::round(src_w * pad_scale)), 1, 1024);
    const int active_h = std::clamp(static_cast<int>(std::round(src_h * pad_scale)), 1, 1024);
    if (out_active_w_1024) *out_active_w_1024 = active_w;
    if (out_active_h_1024) *out_active_h_1024 = active_h;

    const float pad_x = std::clamp(src_x * pad_scale, 0.0f, (float)(active_w - 1));
    const float pad_y = std::clamp(src_y * pad_scale, 0.0f, (float)(active_h - 1));
    if (out_pad_x) *out_pad_x = pad_x;
    if (out_pad_y) *out_pad_y = pad_y;
}

void native_edgetam_resample_mask_to_source(
    const uint8_t* in_mask_1024,
    int active_w_1024, int active_h_1024,
    uint8_t* out_mask_src,
    int src_w, int src_h
) {
    if (!in_mask_1024 || !out_mask_src || src_w <= 0 || src_h <= 0 || active_w_1024 <= 0 || active_h_1024 <= 0) {
        return;
    }

    const float scale_x = (float)active_w_1024 / (float)src_w;
    const float scale_y = (float)active_h_1024 / (float)src_h;

    for (int y = 0; y < src_h; ++y) {
        const float my = y * scale_y;
        const int y0 = std::clamp(static_cast<int>(my), 0, active_h_1024 - 1);
        const int y1 = std::clamp(y0 + 1, 0, active_h_1024 - 1);
        const float dy = my - y0;

        for (int x = 0; x < src_w; ++x) {
            const float mx = x * scale_x;
            const int x0 = std::clamp(static_cast<int>(mx), 0, active_w_1024 - 1);
            const int x1 = std::clamp(x0 + 1, 0, active_w_1024 - 1);
            const float dx = mx - x0;

            const float v00 = in_mask_1024[y0 * 1024 + x0];
            const float v10 = in_mask_1024[y0 * 1024 + x1];
            const float v01 = in_mask_1024[y1 * 1024 + x0];
            const float v11 = in_mask_1024[y1 * 1024 + x1];

            const float val = (1.0f - dx) * (1.0f - dy) * v00 +
                              dx * (1.0f - dy) * v10 +
                              (1.0f - dx) * dy * v01 +
                              dx * dy * v11;

            out_mask_src[y * src_w + x] = static_cast<uint8_t>(std::clamp(std::round(val), 0.0f, 255.0f));
        }
    }
}

int native_edgetam_encode(
    void* handle,
    const uint8_t* rgba,
    int width,
    int height,
    float* out_embedding,
    int embedding_dim
) {
    if (!rgba || !out_embedding || width <= 0 || height <= 0 || embedding_dim < EDGETAM_EMBEDDING_SIZE) {
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

int native_edgetam_decode(
    void* handle,
    const float* embedding,
    int embedding_dim,
    float tap_x_1024,
    float tap_y_1024,
    int category_hint,
    uint8_t* out_mask_1024
) {
    if (!embedding || !out_mask_1024 || embedding_dim < EDGETAM_EMBEDDING_SIZE) {
        return -1;
    }

    const float prompt_gx = std::clamp(tap_x_1024 / 16.0f, 0.0f, 63.0f);
    const float prompt_gy = std::clamp(tap_y_1024 / 16.0f, 0.0f, 63.0f);
    const int seed_x = static_cast<int>(std::round(prompt_gx));
    const int seed_y = static_cast<int>(std::round(prompt_gy));

    const int seed_idx = (seed_y * 64 + seed_x) * 64;
    const float seed_r = embedding[seed_idx + 0];
    const float seed_g = embedding[seed_idx + 1];
    const float seed_b = embedding[seed_idx + 2];
    const float seed_lum = embedding[seed_idx + 3];
    const float seed_texture = embedding[seed_idx + 6];

    float grid_mask[64 * 64];

    for (int gy = 0; gy < 64; ++gy) {
        for (int gx = 0; gx < 64; ++gx) {
            const int idx = (gy * 64 + gx) * 64;
            const float r = embedding[idx + 0];
            const float g = embedding[idx + 1];
            const float b = embedding[idx + 2];
            const float lum = embedding[idx + 3];
            const float texture = embedding[idx + 6];

            const float dr = r - seed_r;
            const float dg = g - seed_g;
            const float db = b - seed_b;
            const float color_dist = std::sqrt(dr * dr + dg * dg + db * db);

            const float dx = gx - prompt_gx;
            const float dy = gy - prompt_gy;
            const float spatial_dist = std::sqrt(dx * dx + dy * dy);
            const float d_texture = std::abs(texture - seed_texture);

            float affinity = 0.0f;

            if (category_hint == EDGETAM_CATEGORY_HAIR) {
                // Hair: tight color & texture clustering, zero background bleed
                const bool similar_color = (color_dist < 0.28f);
                const bool similar_texture = (d_texture < 0.15f);
                const bool spatial_locality = (spatial_dist < 32.0f);

                if (similar_color && (similar_texture || lum < 0.45f) && spatial_locality) {
                    affinity = std::max(0.0f, 1.0f - (color_dist / 0.28f)) * (1.0f - (spatial_dist / 36.0f));
                } else {
                    affinity = 0.0f;
                }
            } else if (category_hint == EDGETAM_CATEGORY_FACE) {
                const bool similar_color = (color_dist < 0.22f);
                if (similar_color && spatial_dist < 28.0f) {
                    affinity = std::max(0.0f, 1.0f - (color_dist / 0.22f)) * (1.0f - (spatial_dist / 30.0f));
                }
            } else if (category_hint == EDGETAM_CATEGORY_CLOTHING) {
                const bool similar_color = (color_dist < 0.25f);
                if (similar_color && spatial_dist < 40.0f) {
                    affinity = std::max(0.0f, 1.0f - (color_dist / 0.25f)) * (1.0f - (spatial_dist / 44.0f));
                }
            } else if (category_hint == EDGETAM_CATEGORY_BACKGROUND) {
                const bool similar_color = (color_dist < 0.20f);
                if (similar_color) {
                    affinity = std::max(0.0f, 1.0f - (color_dist / 0.20f));
                }
            } else {
                const bool similar_color = (color_dist < 0.25f);
                if (similar_color && spatial_dist < 36.0f) {
                    affinity = std::max(0.0f, 1.0f - (color_dist / 0.25f)) * (1.0f - (spatial_dist / 38.0f));
                }
            }

            grid_mask[gy * 64 + gx] = affinity;
        }
    }

    for (int y = 0; y < 1024; ++y) {
        const float gy = y / 16.0f;
        const int gy0 = std::clamp(static_cast<int>(gy), 0, 63);
        const int gy1 = std::clamp(gy0 + 1, 0, 63);
        const float dy = gy - gy0;

        for (int x = 0; x < 1024; ++x) {
            const float gx = x / 16.0f;
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
            out_mask_1024[y * 1024 + x] = mask_val;
        }
    }

    return 0;
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

    // 1. Compute luminance and classify pixels into 3 tonal bands
    // Layer 0: Background (luminance < 85)
    // Layer 1: Midtones (85 <= luminance < 170)
    // Layer 2: Highlights (luminance >= 170)
    std::vector<uint8_t> lum(width * height);
    for (int i = 0; i < width * height; ++i) {
        int r = rgba[i * 4];
        int g = rgba[i * 4 + 1];
        int b = rgba[i * 4 + 2];
        lum[i] = static_cast<uint8_t>(0.299f * r + 0.587f * g + 0.114f * b);
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
