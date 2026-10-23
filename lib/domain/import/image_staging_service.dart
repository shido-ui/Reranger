import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../data/local/atomic_file_writer.dart';
import 'image_file_validator.dart';

/// Staged metadata for an imported image file inside the app-private sandbox.
class StagedImageInfo {
  final String sourcePath;
  final String stagedPath;
  final String sha256Checksum;
  final SupportedImageFormat format;
  final int byteLength;

  const StagedImageInfo({
    required this.sourcePath,
    required this.stagedPath,
    required this.sha256Checksum,
    required this.format,
    required this.byteLength,
  });

  @override
  String toString() =>
      'StagedImageInfo(format: $format, bytes: $byteLength, hash: ${sha256Checksum.substring(0, 8)}...)';
}

/// Coordinates non-destructive image intake, header validation, and sandbox staging.
/// Strictly enforces Invariant 4 (Source Image Immutability) and Invariant 5 (100% Offline).
class ImageStagingService {
  final ImageFileValidator validator;
  final AtomicFileWriter atomicWriter;

  const ImageStagingService({
    this.validator = const ImageFileValidator(),
    this.atomicWriter = const AtomicFileWriter(),
  });

  /// Stages a source image from [sourcePath] into [destinationDir] for project [projectId].
  ///
  /// Guarantees:
  /// 1. Source image is opened read-only and never modified (Invariant 4).
  /// 2. Header magic bytes are validated before any heavy processing.
  /// 3. Pre-copy and post-copy SHA-256 hashes are verified bit-for-bit identical.
  /// 4. Atomic write into app-private sandbox prevents partial writes or corrupt states.
  Future<StagedImageInfo> stageSourceImage({
    required String sourcePath,
    required String destinationDir,
    required String projectId,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileNotFoundValidationFailure(sourcePath);
    }

    // 1. Validate header magic bytes
    final format = await validator.validateFile(sourceFile);

    // 2. Pre-copy source bytes & hash
    final preCopyBytes = await sourceFile.readAsBytes();
    final preCopyHash = sha256.convert(preCopyBytes).toString();

    final ext = switch (format) {
      SupportedImageFormat.jpeg => 'jpg',
      SupportedImageFormat.png => 'png',
      SupportedImageFormat.webp => 'webp',
    };

    final destinationPath = p.join(destinationDir, 'source.$ext');

    // 3. Atomically write copy to app-private sandbox
    final writeResult = await atomicWriter.writeBytes(
      destinationPath: destinationPath,
      bytes: preCopyBytes,
      sourceImagePath: sourcePath,
    );

    // 4. Invariant 4 Immutability Guard: Verify source file hash is unchanged
    final postCopyBytes = await sourceFile.readAsBytes();
    final postCopyHash = sha256.convert(postCopyBytes).toString();
    if (preCopyHash != postCopyHash) {
      throw StateError(
        'Critical Invariant 4 Violation: Source file hash altered during staging copy! '
        'Pre: $preCopyHash, Post: $postCopyHash',
      );
    }

    return StagedImageInfo(
      sourcePath: sourcePath,
      stagedPath: writeResult.path,
      sha256Checksum: preCopyHash,
      format: format,
      byteLength: writeResult.byteLength,
    );
  }
}
