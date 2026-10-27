import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../data/local/atomic_file_writer.dart';
import '../../../data/render/render_graph_executor.dart';
import '../../../domain/recipes/adversarial_stealth_node.dart';
import '../domain/exif_metadata_policy.dart';
import '../domain/export_format.dart';

/// Result metadata from an atomic image export operation.
class ExportResult {
  final String filePath;
  final int byteLength;
  final String sha256Checksum;
  final ExportImageFormat format;
  final int width;
  final int height;
  final bool alphaStripped;
  final bool gpsStripped;

  const ExportResult({
    required this.filePath,
    required this.byteLength,
    required this.sha256Checksum,
    required this.format,
    required this.width,
    required this.height,
    required this.alphaStripped,
    required this.gpsStripped,
  });
}

/// Service providing verified, non-destructive, atomic exports across PNG, JPEG, and WebP formats.
class ImageExporter {
  final AtomicFileWriter atomicWriter;

  const ImageExporter({this.atomicWriter = const AtomicFileWriter()});

  /// Prepares and encodes [sourceImage] according to [config].
  /// Handles alpha transparency truthfully, scales if requested, and applies EXIF metadata policy.
  ({
    Uint8List bytes,
    int width,
    int height,
    bool alphaStripped,
    bool gpsStripped,
  })
  encode({
    required img.Image sourceImage,
    required ExportConfiguration config,
  }) {
    img.Image workingImage = sourceImage.clone();

    // 1. Rescale if requested (to final target resolution)
    if (config.scale != 1.0) {
      final targetWidth = (workingImage.width * config.scale).round();
      final targetHeight = (workingImage.height * config.scale).round();
      workingImage = img.copyResize(
        workingImage,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );
    }

    // 2. Resolution-Independent Stealth (Phase 5 Adversarial Robustness Pipeline):
    // Pre-processing Bilateral Filter Sanitization (Mandate 1), EOT Robustness Loop (Mandate 2),
    // and Sensor Noise directly on final target pixels after resizing to prevent noise dilution.
    if (config.realism > 0.0) {
      final workingRgba = Uint8List.fromList(
        workingImage.getBytes(order: img.ChannelOrder.rgba),
      );
      final stealthRgba = RenderGraphExecutor.applyStealthEngineV2(
        rgbaBytes: workingRgba,
        width: workingImage.width,
        height: workingImage.height,
        realism: config.realism,
        maxLInf: config.maxLInf,
        useEot: config.useEot,
        useBilateralSanitization: config.bilateralSanitization,
      );
      workingImage = img.Image.fromBytes(
        width: workingImage.width,
        height: workingImage.height,
        bytes: stealthRgba.buffer,
        numChannels: 4,
      );

      // Mandate 3: Shortcut Learning Mitigation (PNG Export)
      // Since we export as PNG (to preserve the perturbation), inject synthetic JPEG
      // quantization artifacts (8x8 DCT block boundaries) to simulate camera/social media pipeline.
      if (config.format == ExportImageFormat.png &&
          config.injectJpegArtifacts) {
        final injectedRgba =
            RenderGraphExecutor.injectSyntheticJpegQuantization(
              rgbaBytes: Uint8List.fromList(
                workingImage.getBytes(order: img.ChannelOrder.rgba),
              ),
              width: workingImage.width,
              height: workingImage.height,
              strength: config.realism,
              quality: 85,
            );
        workingImage = img.Image.fromBytes(
          width: workingImage.width,
          height: workingImage.height,
          bytes: injectedRgba.buffer,
          numChannels: 4,
        );
      }
    }

    // 2. EXIF policy application
    final hadGps = ExifMetadataPolicy.hasGpsData(workingImage);
    ExifMetadataPolicy.apply(
      image: workingImage,
      stripGps: config.stripGpsMetadata,
    );
    final gpsStripped = hadGps && config.stripGpsMetadata;

    // 3. Alpha transparency policy
    bool alphaStripped = false;
    if (config.format == ExportImageFormat.jpeg) {
      // Check if image has an active alpha channel with any non-opaque pixels
      bool hasTransparency = false;
      if (workingImage.hasAlpha) {
        for (final pixel in workingImage) {
          if (pixel.a < 255) {
            hasTransparency = true;
            break;
          }
        }
      }

      if (hasTransparency) {
        // Honest Alpha Handling: JPEG cannot store an alpha channel.
        // Composite transparent pixels over the user-selected background color (default white).
        final bgR = config.backgroundColorForOpaque[0];
        final bgG = config.backgroundColorForOpaque[1];
        final bgB = config.backgroundColorForOpaque[2];

        final opaqueImage = img.Image(
          width: workingImage.width,
          height: workingImage.height,
          numChannels: 3,
        );

        for (int y = 0; y < workingImage.height; y++) {
          for (int x = 0; x < workingImage.width; x++) {
            final p = workingImage.getPixel(x, y);
            final aNorm = p.a / 255.0;
            final invA = 1.0 - aNorm;

            final outR = (p.r * aNorm + bgR * invA).round().clamp(0, 255);
            final outG = (p.g * aNorm + bgG * invA).round().clamp(0, 255);
            final outB = (p.b * aNorm + bgB * invA).round().clamp(0, 255);

            opaqueImage.setPixelRgb(x, y, outR, outG, outB);
          }
        }
        workingImage = opaqueImage;
        alphaStripped = true;
      }
    }

    // 4. Encode to target format
    Uint8List encodedBytes;
    switch (config.format) {
      case ExportImageFormat.png:
        encodedBytes = Uint8List.fromList(img.encodePng(workingImage));
        break;
      case ExportImageFormat.jpeg:
        encodedBytes = Uint8List.fromList(
          img.encodeJpg(workingImage, quality: config.quality),
        );
        break;
      case ExportImageFormat.webp:
        encodedBytes = Uint8List.fromList(
          img.encodeWebP(workingImage, quality: config.quality),
        );
        break;
    }

    // 5. Metadata Annihilation for Stealth Export & Privacy Policy
    if (config.realism > 0.0 || config.stripGpsMetadata) {
      encodedBytes = MetadataAnnihilator.stripMetadata(encodedBytes);
    }

    return (
      bytes: encodedBytes,
      width: workingImage.width,
      height: workingImage.height,
      alphaStripped: alphaStripped,
      gpsStripped: gpsStripped,
    );
  }

  /// Exports [sourceImage] to a verified local file atomically.
  /// Throws [LowStorageFailure] if disk storage is insufficient.
  /// Guarantees Invariant 4 source image immutability.
  Future<ExportResult> exportToFile({
    required img.Image sourceImage,
    required String destinationPath,
    required ExportConfiguration config,
    String? sourceImagePath,
  }) async {
    final encoded = encode(sourceImage: sourceImage, config: config);

    final writeResult = await atomicWriter.writeBytes(
      destinationPath: destinationPath,
      bytes: encoded.bytes,
      sourceImagePath: sourceImagePath,
    );

    return ExportResult(
      filePath: writeResult.path,
      byteLength: writeResult.byteLength,
      sha256Checksum: writeResult.sha256Checksum,
      format: config.format,
      width: encoded.width,
      height: encoded.height,
      alphaStripped: encoded.alphaStripped,
      gpsStripped: encoded.gpsStripped,
    );
  }

  /// Resolves an unambiguous, non-colliding file path in [destinationDir].
  /// If `photo.png` exists, yields `photo (1).png`, `photo (2).png`, etc.
  static String resolveNonCollidingPath({
    required Directory destinationDir,
    required String baseName,
    required String extension,
  }) {
    final sanitizedBase = baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    String candidate = p.join(destinationDir.path, '$sanitizedBase$extension');
    if (!File(candidate).existsSync()) {
      return candidate;
    }

    int counter = 1;
    while (true) {
      candidate = p.join(
        destinationDir.path,
        '$sanitizedBase ($counter)$extension',
      );
      if (!File(candidate).existsSync()) {
        return candidate;
      }
      counter++;
    }
  }
}
