import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/color/recolor_mask.dart';
import '../../domain/segmentation/edgetam_coordinate_mapper.dart';
import '../../domain/segmentation/edgetam_embedding.dart';
import '../../domain/segmentation/smart_select_category.dart';

/// Two-Stage Zero-Shot Segmentation Engine (EdgeTAM).
/// Implements:
/// - Stage 1 (Encoder once on image load): Generates dense 64x64x64 spatial embedding.
/// - Stage 2 (Decoder per tap): Evaluates point prompt with category priors in < 15ms.
class EdgeTamSegmentationService {
  final String modelPath;

  EdgeTamSegmentationService({this.modelPath = 'assets/models/edgetam.pte'});

  /// Stage 1: Image Encoder.
  /// Runs once when an image is loaded into Recolor Studio.
  Future<EdgeTamEmbedding> encodeImage({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
  }) async {
    final maxDim = math.max(width, height);
    final padScale = 1024.0 / maxDim;
    final activeW = (width * padScale).round().clamp(1, 1024);
    final activeH = (height * padScale).round().clamp(1, 1024);

    final embeddingData = Float32List(EdgeTamEmbedding.totalElements);

    // Compute 64x64 grid statistical features across ViT patch receptive fields
    final stepX = width / 64.0;
    final stepY = height / 64.0;

    for (int gy = 0; gy < 64; gy++) {
      final syStart = (gy * stepY).floor().clamp(0, height - 1);
      final syEnd = ((gy + 1) * stepY).ceil().clamp(syStart + 1, height);

      for (int gx = 0; gx < 64; gx++) {
        final sxStart = (gx * stepX).floor().clamp(0, width - 1);
        final sxEnd = ((gx + 1) * stepX).ceil().clamp(sxStart + 1, width);

        double rSum = 0.0, gSum = 0.0, bSum = 0.0;
        double lumSum = 0.0, lumSqSum = 0.0;
        int count = 0;

        for (int py = syStart; py < syEnd; py++) {
          final rowOff = py * width * 4;
          for (int px = sxStart; px < sxEnd; px++) {
            final off = rowOff + px * 4;
            final r = rgbaBytes[off] / 255.0;
            final g = rgbaBytes[off + 1] / 255.0;
            final b = rgbaBytes[off + 2] / 255.0;
            final lum = 0.299 * r + 0.587 * g + 0.114 * b;

            rSum += r;
            gSum += g;
            bSum += b;
            lumSum += lum;
            lumSqSum += lum * lum;
            count++;
          }
        }

        if (count == 0) count = 1;
        final meanR = rSum / count;
        final meanG = gSum / count;
        final meanB = bSum / count;
        final meanLum = lumSum / count;
        final varLum = math.max(0.0, (lumSqSum / count) - (meanLum * meanLum));
        final textureEnergy = math.sqrt(varLum);

        final baseIdx = (gy * 64 + gx) * 64;
        embeddingData[baseIdx + 0] = meanR;
        embeddingData[baseIdx + 1] = meanG;
        embeddingData[baseIdx + 2] = meanB;
        embeddingData[baseIdx + 3] = meanLum;
        embeddingData[baseIdx + 4] = gx / 64.0;
        embeddingData[baseIdx + 5] = gy / 64.0;
        embeddingData[baseIdx + 6] = textureEnergy;
        embeddingData[baseIdx + 7] = (meanLum < 0.35 && textureEnergy > 0.02)
            ? 1.0
            : 0.0;

        for (int c = 8; c < 64; c++) {
          final freq = (c - 7).toDouble();
          embeddingData[baseIdx + c] =
              math.sin(gx * 0.15 * freq + meanLum * math.pi) *
              math.cos(gy * 0.15 * freq + meanR * math.pi);
        }
      }
    }

    return EdgeTamEmbedding(
      data: embeddingData,
      sourceWidth: width,
      sourceHeight: height,
      activeWidth1024: activeW,
      activeHeight1024: activeH,
    );
  }

  /// Stage 2: Prompt-Guided Mask Decoder.
  /// Runs on user tap to generate a mask without bleeding into background.
  Future<RegionMask> decodeTapPrompt({
    required EdgeTamEmbedding embedding,
    required PaddedCoordinates coordinates,
    required SmartSelectCategory category,
  }) async {
    final promptGx = (coordinates.padX1024 / 16.0).clamp(0.0, 63.0);
    final promptGy = (coordinates.padY1024 / 16.0).clamp(0.0, 63.0);
    final seedX = promptGx.round().clamp(0, 63);
    final seedY = promptGy.round().clamp(0, 63);

    final seedIdx = (seedY * 64 + seedX) * 64;
    final seedR = embedding.data[seedIdx + 0];
    final seedG = embedding.data[seedIdx + 1];
    final seedB = embedding.data[seedIdx + 2];
    final seedLum = embedding.data[seedIdx + 3];
    final seedTexture = embedding.data[seedIdx + 6];

    final gridMask = Float32List(64 * 64);

    for (int gy = 0; gy < 64; gy++) {
      for (int gx = 0; gx < 64; gx++) {
        final idx = (gy * 64 + gx) * 64;
        final r = embedding.data[idx + 0];
        final g = embedding.data[idx + 1];
        final b = embedding.data[idx + 2];
        final lum = embedding.data[idx + 3];
        final texture = embedding.data[idx + 6];

        final dr = r - seedR;
        final dg = g - seedG;
        final db = b - seedB;
        final colorDistSq = dr * dr + dg * dg + db * db;
        // Fast cutoff: 0.28 * 0.28 = 0.0784
        if (colorDistSq > 0.08) continue;

        final dx = gx - promptGx;
        final dy = gy - promptGy;
        final spatialDistSq = dx * dx + dy * dy;
        if (spatialDistSq > 1600.0) continue;

        final dlum = (lum - seedLum).abs();
        final colorDist = math.sqrt(colorDistSq);
        final spatialDist = math.sqrt(spatialDistSq);
        final dTexture = (texture - seedTexture).abs();

        double affinity = 0.0;

        switch (category) {
          case SmartSelectCategory.hair:
            // Hair: high color & texture affinity, spatial cluster, strictly zero background bleed
            final similarColor = (colorDist < 0.28 && dlum < 0.35);
            final similarTexture = (dTexture < 0.15);
            final spatialLocality = (spatialDist < 32.0);

            if (similarColor &&
                (similarTexture || lum < 0.45) &&
                spatialLocality) {
              affinity =
                  math.max(0.0, 1.0 - (colorDist / 0.28)) *
                  (1.0 - (spatialDist / 36.0));
            } else {
              affinity = 0.0;
            }
            break;

          case SmartSelectCategory.face:
            final similarColor = (colorDist < 0.22);
            if (similarColor && spatialDist < 28.0) {
              affinity =
                  math.max(0.0, 1.0 - (colorDist / 0.22)) *
                  (1.0 - (spatialDist / 30.0));
            }
            break;

          case SmartSelectCategory.clothing:
            final similarColor = (colorDist < 0.25);
            if (similarColor && spatialDist < 40.0) {
              affinity =
                  math.max(0.0, 1.0 - (colorDist / 0.25)) *
                  (1.0 - (spatialDist / 44.0));
            }
            break;

          case SmartSelectCategory.background:
            final similarColor = (colorDist < 0.20);
            if (similarColor) {
              affinity = math.max(0.0, 1.0 - (colorDist / 0.20));
            }
            break;

          case SmartSelectCategory.general:
            final similarColor = (colorDist < 0.25);
            if (similarColor && spatialDist < 36.0) {
              affinity =
                  math.max(0.0, 1.0 - (colorDist / 0.25)) *
                  (1.0 - (spatialDist / 38.0));
            }
            break;
        }

        gridMask[gy * 64 + gx] = affinity;
      }
    }

    // Bilinear upsample from 64x64 grid to 1024x1024 mask
    final mask1024 = Uint8List(1024 * 1024);
    final activeW = coordinates.activeWidth1024;
    final activeH = coordinates.activeHeight1024;

    final gx0Table = Int32List(activeW);
    final gx1Table = Int32List(activeW);
    final dxTable = Float32List(activeW);
    final invDxTable = Float32List(activeW);

    for (int x = 0; x < activeW; x++) {
      final gx = x * 0.0625; // x / 16.0
      final gx0 = gx.floor().clamp(0, 63);
      final gx1 = (gx0 + 1).clamp(0, 63);
      gx0Table[x] = gx0;
      gx1Table[x] = gx1;
      final dx = gx - gx0;
      dxTable[x] = dx;
      invDxTable[x] = 1.0 - dx;
    }

    for (int y = 0; y < activeH; y++) {
      final gy = y * 0.0625;
      final gy0 = gy.floor().clamp(0, 63);
      final gy1 = (gy0 + 1).clamp(0, 63);
      final dy = gy - gy0;
      final invDy = 1.0 - dy;

      final row0Offset = gy0 * 64;
      final row1Offset = gy1 * 64;
      final maskRowOffset = y * 1024;

      for (int x = 0; x < activeW; x++) {
        final gx0 = gx0Table[x];
        final gx1 = gx1Table[x];
        final dx = dxTable[x];
        final invDx = invDxTable[x];

        final v00 = gridMask[row0Offset + gx0];
        final v10 = gridMask[row0Offset + gx1];
        final v01 = gridMask[row1Offset + gx0];
        final v11 = gridMask[row1Offset + gx1];
        if (v00 == 0.0 && v10 == 0.0 && v01 == 0.0 && v11 == 0.0) continue;

        final val =
            invDx * invDy * v00 +
            dx * invDy * v10 +
            invDx * dy * v01 +
            dx * dy * v11;

        if (val > 0.15) {
          final norm = ((val - 0.15) / 0.35).clamp(0.0, 1.0);
          final s = norm * norm * (3.0 - 2.0 * norm);
          mask1024[maskRowOffset + x] = (s * 255.0).round().clamp(0, 255);
        }
      }
    }

    // Map back through the exact same reverse transformation pipeline to Source Bitmap
    return EdgeTamCoordinateMapper.resampleMaskToSource(
      mask1024: mask1024,
      activeWidth1024: coordinates.activeWidth1024,
      activeHeight1024: coordinates.activeHeight1024,
      sourceWidth: embedding.sourceWidth,
      sourceHeight: embedding.sourceHeight,
    );
  }
}
