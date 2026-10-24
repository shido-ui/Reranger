import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../color/recolor_mask.dart';

/// Coordinate transformation data structure holding point positions across the transformation pipeline.
class PaddedCoordinates {
  final double viewX;
  final double viewY;
  final double sourceX;
  final double sourceY;
  final double padX1024;
  final double padY1024;
  final int activeWidth1024;
  final int activeHeight1024;
  final bool isInsideImage;

  const PaddedCoordinates({
    required this.viewX,
    required this.viewY,
    required this.sourceX,
    required this.sourceY,
    required this.padX1024,
    required this.padY1024,
    required this.activeWidth1024,
    required this.activeHeight1024,
    required this.isInsideImage,
  });
}

/// Exact bidirectional coordinate transformation pipeline:
/// View → Source Bitmap (undo letterbox) → Padded 1024x1024 Square (top-left pad),
/// and Reverse Mapping: Mask 1024x1024 active region → Source Bitmap dimensions.
class EdgeTamCoordinateMapper {
  static const int modelInputDimension = 1024;

  /// Forward Mapping:
  /// Transforms View tap coordinate [viewPosition] on canvas [viewSize]
  /// (rendered with BoxFit.contain) into source bitmap coordinates and top-left padded 1024x1024 model coordinates.
  static PaddedCoordinates mapViewToPadded({
    required Offset viewPosition,
    required Size viewSize,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        viewSize.width <= 0 ||
        viewSize.height <= 0) {
      return const PaddedCoordinates(
        viewX: 0,
        viewY: 0,
        sourceX: 0,
        sourceY: 0,
        padX1024: 0,
        padY1024: 0,
        activeWidth1024: modelInputDimension,
        activeHeight1024: modelInputDimension,
        isInsideImage: false,
      );
    }

    // 1. BoxFit.contain scale factor
    final scale = math.min(
      viewSize.width / sourceWidth,
      viewSize.height / sourceHeight,
    );
    final renderedW = sourceWidth * scale;
    final renderedH = sourceHeight * scale;

    // 2. Centered letterbox / pillarbox offsets
    final offsetX = (viewSize.width - renderedW) * 0.5;
    final offsetY = (viewSize.height - renderedH) * 0.5;

    // Check if tap fell inside rendered image area
    final rawSrcX = (viewPosition.dx - offsetX) / scale;
    final rawSrcY = (viewPosition.dy - offsetY) / scale;
    final isInside =
        (rawSrcX >= 0 &&
        rawSrcX < sourceWidth &&
        rawSrcY >= 0 &&
        rawSrcY < sourceHeight);

    // 3. Undo letterbox -> Clamped source coordinates
    final srcX = rawSrcX.clamp(0.0, (sourceWidth - 1).toDouble());
    final srcY = rawSrcY.clamp(0.0, (sourceHeight - 1).toDouble());

    // 4. Scale to 1024x1024 top-left padded square (longest edge = 1024)
    final maxSrcDim = math.max(sourceWidth, sourceHeight);
    final padScale = modelInputDimension / maxSrcDim;

    final activeW = (sourceWidth * padScale).round().clamp(
      1,
      modelInputDimension,
    );
    final activeH = (sourceHeight * padScale).round().clamp(
      1,
      modelInputDimension,
    );

    final padX = (srcX * padScale).clamp(0.0, (activeW - 1).toDouble());
    final padY = (srcY * padScale).clamp(0.0, (activeH - 1).toDouble());

    return PaddedCoordinates(
      viewX: viewPosition.dx,
      viewY: viewPosition.dy,
      sourceX: srcX,
      sourceY: srcY,
      padX1024: padX,
      padY1024: padY,
      activeWidth1024: activeW,
      activeHeight1024: activeH,
      isInsideImage: isInside,
    );
  }

  /// Reverse Mapping:
  /// Extracts the active region [0, activeWidth1024) x [0, activeHeight1024)
  /// from the 1024x1024 single-channel model output mask and resamples it
  /// back to source bitmap dimensions ([sourceWidth] x [sourceHeight]) using bilinear interpolation.
  static RegionMask resampleMaskToSource({
    required Uint8List mask1024,
    required int activeWidth1024,
    required int activeHeight1024,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    assert(mask1024.length >= modelInputDimension * modelInputDimension);
    final outBuffer = Uint8List(sourceWidth * sourceHeight);

    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        activeWidth1024 <= 0 ||
        activeHeight1024 <= 0) {
      return RegionMask(
        width: sourceWidth,
        height: sourceHeight,
        buffer: outBuffer,
      );
    }

    final scaleX = activeWidth1024 / sourceWidth;
    final scaleY = activeHeight1024 / sourceHeight;

    for (int y = 0; y < sourceHeight; y++) {
      final my = y * scaleY;
      final y0 = my.floor().clamp(0, activeHeight1024 - 1);
      final y1 = (y0 + 1).clamp(0, activeHeight1024 - 1);
      final dy = my - y0;
      final rowOffset = y * sourceWidth;

      for (int x = 0; x < sourceWidth; x++) {
        final mx = x * scaleX;
        final x0 = mx.floor().clamp(0, activeWidth1024 - 1);
        final x1 = (x0 + 1).clamp(0, activeWidth1024 - 1);
        final dx = mx - x0;

        final v00 = mask1024[y0 * modelInputDimension + x0];
        final v10 = mask1024[y0 * modelInputDimension + x1];
        final v01 = mask1024[y1 * modelInputDimension + x0];
        final v11 = mask1024[y1 * modelInputDimension + x1];

        final val =
            (1.0 - dx) * (1.0 - dy) * v00 +
            dx * (1.0 - dy) * v10 +
            (1.0 - dx) * dy * v01 +
            dx * dy * v11;

        outBuffer[rowOffset + x] = val.round().clamp(0, 255);
      }
    }

    return RegionMask(
      width: sourceWidth,
      height: sourceHeight,
      buffer: outBuffer,
    );
  }
}
