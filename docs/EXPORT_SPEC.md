# RERANGER — EXPORT SPECIFICATION & INTEGRITY STANDARDS

- **Specification Status:** APPROVED & PRODUCTION READY
- **Target Platform:** Android-First (Offline Local Runtime)
- **Primary Invariants:** Invariant 4 (Source Image Immutability), Invariant 5 (100% Offline-First Runtime), Invariant 6 (Zero Cloud / Accounts), Invariant 7 (No Fake Controls or Placebo Estimates)

---

## 1. Architectural Mission & Non-Negotiable Invariants

Reranger provides dependable, mathematically verified, non-destructive export capabilities:
1. **Source Image Immutability (Invariant 4):** Original user media is opened read-only and never overwritten, altered, or truncated on export. Attempting to target source image paths throws an unrecoverable `StorageFailure`.
2. **Offline-First Runtime (Invariant 5):** All encoders execute 100% locally on-device. Zero telemetry, zero server-side rendering, and zero network dependency.
3. **Truthful Controls & Real Estimates (Invariant 7):** No fake file sizes, mock progress spinners, or placebo format options. File size estimates are computed from real dimension and format parameter models.
4. **Honest Alpha Transparency Handling:** JPEG format cannot store an alpha transparency channel. Reranger honestly discloses this limitation, composites transparent regions onto a solid user-selectable background (default: pure white), and drops the alpha channel cleanly without corruption. PNG and WebP preserve complete 32-bit RGBA transparency.
5. **Atomic Finalization:** Outputs are written to a temporary sibling file (`.tmp.$pid.$timestamp`), flushed to physical media, checksummed (SHA-256), and atomically swapped to the final destination path via POSIX filesystem rename.

---

## 2. Supported Export Format Matrix

| Format | Extension | MIME Type | Alpha Channel | Quality Control | Compression Type | Primary Use Case |
|---|---|---|---|---|---|---|
| **PNG** | `.png` | `image/png` | **Full (RGBA)** | Not applicable (Lossless) | Deflate (Lossless) | Digital art, line art, transparency, graphic design |
| **JPEG** | `.jpg` | `image/jpeg` | **None (RGB)** | Quality slider ($1..100$) | DCT Discrete Cosine (Lossy) | High-compatibility photography, social sharing |
| **WebP** | `.webp` | `image/webp` | **Full (RGBA)** | Quality slider ($1..100$) | VP8 / VP8L | Modern mobile storage optimization (~30% smaller) |

---

## 3. Metadata & Privacy Policy (EXIF & Geolocation)

### 3.1 Sensitive Geolocation Stripping (`stripGpsMetadata: true`)
- **Default Policy:** By default, all GPS IFD tags (`GPSLatitude`, `GPSLongitude`, `GPSAltitude`, `GPSTimeStamp`, `GPSProcessingMethod`) are permanently removed from exported image headers to protect artist and user privacy.
- **Opt-in Option:** Advanced users may review and opt out in the export sheet if geotag preservation is explicitly desired.

### 3.2 Canonical Orientation & Color Management
- **Orientation Baking:** Reranger bakes EXIF rotation matrices (tags 1 to 8) directly into raster memory during decoding. Exported images canonicalize EXIF Orientation to `1` (Normal / Top-Left) so downstream external viewers never apply duplicate rotations.
- **Software Provenance:** Injects standard non-deceptive metadata: `Software: Reranger Studio`.

---

## 4. File Size Estimation Modeling (`RealSizeEstimator`)

Rather than showing fake numbers or placeholder ranges, Reranger models byte footprints mathematically:
- **PNG Estimate:** $W \cdot H \cdot 1.5$ bytes (accounting for typical 32-bit line/palette entropy).
- **JPEG Estimate:** $W \cdot H \cdot \big(0.05 + 0.40 \cdot \frac{Q}{100}\big)$ bytes.
- **WebP Estimate:** $W \cdot H \cdot \big(0.04 + 0.28 \cdot \frac{Q}{100}\big)$ bytes.

---

## 5. Storage Headroom & Error Recovery

1. **Storage Guard:** Asserts available storage $\ge \text{payload} + 10\text{ MB}$. Throws `LowStorageFailure` if headroom is depleted.
2. **Failure Cleanup:** In any abort, cancellation, or exception condition, temporary files are immediately removed; destination paths remain untouched.
3. **Collision Disambiguation:** Duplicate file names auto-increment (`photo (1).png`, `photo (2).png`) rather than destructively overwriting existing work.
