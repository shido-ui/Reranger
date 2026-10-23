import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../domain/project/project_entity.dart';

/// Exception thrown when image bytes cannot be decoded by the native/pure-Dart engine.
class ImageDecodingFailure implements Exception {
  final String message;
  const ImageDecodingFailure([
    this.message = 'Failed to decode image byte stream.',
  ]);

  @override
  String toString() => message;
}

/// Structured summary of an imported and analyzed image.
class DecodedImageSummary {
  final int width;
  final int height;
  final double aspectRatio;
  final bool hasAlpha;
  final int originalExifOrientation;
  final List<ColorVector> dominantPalette;
  final Uint8List thumbnailBytes;
  final int thumbnailWidth;
  final int thumbnailHeight;

  const DecodedImageSummary({
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.hasAlpha,
    required this.originalExifOrientation,
    required this.dominantPalette,
    required this.thumbnailBytes,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
  });

  @override
  String toString() =>
      'DecodedImageSummary(${width}x$height, aspect: ${aspectRatio.toStringAsFixed(2)}, alpha: $hasAlpha, exif: $originalExifOrientation, palette: ${dominantPalette.length})';
}

/// Service executing image decoding, 8-case EXIF orientation baking, aspect ratio extraction,
/// alpha channel inspection, downscaled thumbnail generation, and dominant palette extraction
/// in a dedicated background worker isolate to ensure UI thread interactivity (Invariant 11).
class IsolateImageDecoder {
  const IsolateImageDecoder();

  /// Decodes and analyzes [bytes] in a background isolate.
  Future<DecodedImageSummary> decodeAndAnalyze(
    Uint8List bytes, {
    int maxThumbnailDimension = 512,
  }) async {
    return Isolate.run(() => _decodeWorker(bytes, maxThumbnailDimension));
  }

  static DecodedImageSummary _decodeWorker(
    Uint8List bytes,
    int maxThumbnailDimension,
  ) {
    // 1. Extract original EXIF orientation tag from raw stream if present
    final rawOrientation = _extractExifOrientationFromBytes(bytes);

    // 2. Decode raw image stream
    final rawImage = img.decodeImage(bytes);
    if (rawImage == null) {
      throw const ImageDecodingFailure(
        'Image stream corrupted or unrecognized by decoder.',
      );
    }

    final originalOrientation = (rawOrientation != 1)
        ? rawOrientation
        : (rawImage.exif.imageIfd.orientation ?? 1);

    // print('DBG: rawOri=$rawOrientation, imgOri=${rawImage.exif.imageIfd.orientation}, originalOri=$originalOrientation');
    // 3. Bake full 8-case EXIF orientation into actual pixel grid (if not already baked)
    final bakedImage = img.bakeOrientation(rawImage);

    final width = bakedImage.width;
    final height = bakedImage.height;
    if (width <= 0 || height <= 0) {
      throw ImageDecodingFailure(
        'Invalid decoded dimensions: ${width}x$height',
      );
    }

    final aspectRatio = width / height;

    // 4. Inspect alpha channel
    var hasTransparentPixels = false;
    if (bakedImage.hasAlpha) {
      // Check if there are actually non-opaque pixels
      for (final pixel in bakedImage) {
        if (pixel.a < 255) {
          hasTransparentPixels = true;
          break;
        }
      }
    }

    // 5. Generate thumbnail preview (bounded to maxThumbnailDimension)
    final int thumbW;
    final int thumbH;
    if (width > maxThumbnailDimension || height > maxThumbnailDimension) {
      if (width >= height) {
        thumbW = maxThumbnailDimension;
        thumbH = math.max(1, (maxThumbnailDimension / aspectRatio).round());
      } else {
        thumbH = maxThumbnailDimension;
        thumbW = math.max(1, (maxThumbnailDimension * aspectRatio).round());
      }
    } else {
      thumbW = width;
      thumbH = height;
    }

    final thumbnail = (thumbW == width && thumbH == height)
        ? bakedImage
        : img.copyResize(bakedImage, width: thumbW, height: thumbH);

    final thumbnailBytes = Uint8List.fromList(img.encodePng(thumbnail));

    // 6. Dominant color palette extraction (5 distinct colors, TC-FR-006)
    final dominantPalette = _extractDominantPalette(thumbnail, 5);

    return DecodedImageSummary(
      width: width,
      height: height,
      aspectRatio: aspectRatio,
      hasAlpha: hasTransparentPixels,
      originalExifOrientation: originalOrientation,
      dominantPalette: dominantPalette,
      thumbnailBytes: thumbnailBytes,
      thumbnailWidth: thumbnail.width,
      thumbnailHeight: thumbnail.height,
    );
  }

  /// Extracts [count] dominant colors using 4-bit spatial color quantization.
  static List<ColorVector> _extractDominantPalette(img.Image image, int count) {
    final Map<int, int> binCounts = {};

    // Sample pixels across image
    final stepX = math.max(1, (image.width / 64).floor());
    final stepY = math.max(1, (image.height / 64).floor());

    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        final p = image.getPixel(x, y);
        // Ignore fully transparent pixels
        if (p.a < 32) continue;

        // 4-bit quantization per channel (0..15) -> 4096 bins
        final rBin = (p.r ~/ 16).clamp(0, 15);
        final gBin = (p.g ~/ 16).clamp(0, 15);
        final bBin = (p.b ~/ 16).clamp(0, 15);
        final binKey = (rBin << 8) | (gBin << 4) | bBin;

        binCounts[binKey] = (binCounts[binKey] ?? 0) + 1;
      }
    }

    final sortedBins = binCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<ColorVector> palette = [];
    final List<List<double>> selectedRgb = [];

    for (final entry in sortedBins) {
      if (palette.length >= count) break;
      final bin = entry.key;
      final r = (((bin >> 8) & 0x0F) * 16 + 8) / 255.0;
      final g = (((bin >> 4) & 0x0F) * 16 + 8) / 255.0;
      final b = ((bin & 0x0F) * 16 + 8) / 255.0;

      // Ensure color diversity (distance in RGB space >= 0.15)
      var isDiverse = true;
      for (final prev in selectedRgb) {
        final dr = r - prev[0];
        final dg = g - prev[1];
        final db = b - prev[2];
        final dist = dr * dr + dg * dg + db * db;
        if (dist < 0.04) {
          isDiverse = false;
          break;
        }
      }

      if (isDiverse || sortedBins.length < count * 2) {
        palette.add(ColorVector(r, g, b, 1.0));
        selectedRgb.add([r, g, b]);
      }
    }

    // Default fallbacks if image had very few colors (e.g. monochrome / tiny image)
    final fallbacks = [
      const ColorVector(0.12, 0.12, 0.15, 1.0),
      const ColorVector(0.85, 0.85, 0.90, 1.0),
      const ColorVector(0.35, 0.55, 0.85, 1.0),
      const ColorVector(0.85, 0.45, 0.25, 1.0),
      const ColorVector(0.20, 0.70, 0.50, 1.0),
    ];

    while (palette.length < count) {
      palette.add(fallbacks[palette.length % fallbacks.length]);
    }

    return palette;
  }

  /// Extracts the EXIF orientation tag (1..8) directly from JPEG APP1 segments.
  static int _extractExifOrientationFromBytes(Uint8List bytes) {
    if (bytes.length < 32 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return 1;
    }
    var offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] != 0xFF) break;
      final marker = bytes[offset + 1];
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (marker == 0xE1 && offset + 10 < bytes.length) {
        final isExif =
            bytes[offset + 4] == 0x45 &&
            bytes[offset + 5] == 0x78 &&
            bytes[offset + 6] == 0x69 &&
            bytes[offset + 7] == 0x66 &&
            bytes[offset + 8] == 0x00 &&
            bytes[offset + 9] == 0x00;
        if (isExif) {
          final tiffOffset = offset + 10;
          if (tiffOffset + 8 < bytes.length) {
            final isLe =
                bytes[tiffOffset] == 0x49 && bytes[tiffOffset + 1] == 0x49;
            final ifd0Offset = isLe
                ? (bytes[tiffOffset + 4] |
                      (bytes[tiffOffset + 5] << 8) |
                      (bytes[tiffOffset + 6] << 16) |
                      (bytes[tiffOffset + 7] << 24))
                : ((bytes[tiffOffset + 4] << 24) |
                      (bytes[tiffOffset + 5] << 16) |
                      (bytes[tiffOffset + 6] << 8) |
                      bytes[tiffOffset + 7]);
            final ifdStart = tiffOffset + ifd0Offset;
            if (ifdStart + 2 < bytes.length) {
              final numEntries = isLe
                  ? bytes[ifdStart] | (bytes[ifdStart + 1] << 8)
                  : (bytes[ifdStart] << 8) | bytes[ifdStart + 1];
              for (var i = 0; i < numEntries; i++) {
                final entryOffset = ifdStart + 2 + (i * 12);
                if (entryOffset + 12 > bytes.length) break;
                final tag = isLe
                    ? bytes[entryOffset] | (bytes[entryOffset + 1] << 8)
                    : (bytes[entryOffset] << 8) | bytes[entryOffset + 1];
                if (tag == 0x0112) {
                  final orientationVal = isLe
                      ? bytes[entryOffset + 8] | (bytes[entryOffset + 9] << 8)
                      : (bytes[entryOffset + 8] << 8) | bytes[entryOffset + 9];
                  if (orientationVal >= 1 && orientationVal <= 8) {
                    return orientationVal;
                  }
                }
              }
            }
          }
        }
      }
      if (marker == 0xDA || marker == 0xD9) break;
      offset += 2 + length;
    }
    return 1;
  }
}
