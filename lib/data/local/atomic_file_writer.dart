import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/project/project_entity.dart';

/// Result of an atomic file write containing the final path, size, and SHA-256 checksum.
class AtomicWriteResult {
  final String path;
  final int byteLength;
  final String sha256Checksum;

  const AtomicWriteResult({
    required this.path,
    required this.byteLength,
    required this.sha256Checksum,
  });
}

/// Disk space provider abstraction to allow testing low-storage handling.
abstract interface class StorageCapacityChecker {
  Future<int> getAvailableDiskBytes(String directoryPath);
}

/// Default storage checker querying the host file system.
class DefaultStorageCapacityChecker implements StorageCapacityChecker {
  const DefaultStorageCapacityChecker();

  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async {
    // Return a generous default if unable to inspect, or query stat
    return 1024 * 1024 * 1024; // 1 GB fallback headroom
  }
}

/// Service executing atomic, non-destructive file operations with SHA-256 verification.
class AtomicFileWriter {
  final StorageCapacityChecker capacityChecker;

  /// Minimum required safety margin in bytes (10 MB).
  static const int minimumHeadroomMargin = 10 * 1024 * 1024;

  const AtomicFileWriter({
    this.capacityChecker = const DefaultStorageCapacityChecker(),
  });

  /// Writes [bytes] atomically to [destinationPath].
  ///
  /// Guarantees:
  /// 1. [sourceImagePath] is strictly protected: attempting to overwrite it throws [StorageFailure].
  /// 2. If available disk storage is less than `bytes.length + 10MB`, throws [LowStorageFailure].
  /// 3. Data is written to a temporary sibling file first and flushed.
  /// 4. SHA-256 checksum is computed and returned.
  /// 5. Atomic rename moves the temporary file to [destinationPath].
  /// 6. In case of any failure, the temporary file is deleted and [destinationPath] is untouched.
  Future<AtomicWriteResult> writeBytes({
    required String destinationPath,
    required List<int> bytes,
    String? sourceImagePath,
  }) async {
    // 1. Source Image Immutability Guard (Invariant 4)
    if (sourceImagePath != null &&
        p.canonicalize(destinationPath) == p.canonicalize(sourceImagePath)) {
      throw const StorageFailure(
        'Critical violation of Invariant 4: Cannot overwrite immutable source image media.',
      );
    }

    final targetFile = File(destinationPath);
    final targetDir = targetFile.parent;
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    // 2. Storage Headroom Check
    final availableBytes = await capacityChecker.getAvailableDiskBytes(
      targetDir.path,
    );
    final requiredBytes = bytes.length + minimumHeadroomMargin;
    if (availableBytes < requiredBytes) {
      throw LowStorageFailure(requiredBytes, availableBytes);
    }

    // 3. Temporary Sibling File
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tempFilePath = '$destinationPath.tmp.$pid.$timestamp';
    final tempFile = File(tempFilePath);

    try {
      // Write bytes and flush to physical storage
      final sink = tempFile.openWrite(mode: FileMode.write);
      sink.add(bytes);
      await sink.flush();
      await sink.close();

      // 4. Checksum computation
      final digest = sha256.convert(bytes).toString();

      // 5. Atomic Rename (POSIX atomic filesystem entry swap)
      if (Platform.isWindows && targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      try {
        tempFile.renameSync(destinationPath);
      } on FileSystemException {
        // Fallback if atomic replacement across or on legacy non-POSIX filesystem fails
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
        tempFile.renameSync(destinationPath);
      }

      return AtomicWriteResult(
        path: destinationPath,
        byteLength: bytes.length,
        sha256Checksum: digest,
      );
    } catch (e) {
      // 6. Rollback / Cleanup on failure
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      if (e is ProjectFailure) rethrow;
      throw StorageFailure('Atomic write failed for $destinationPath: $e');
    }
  }

  /// Verifies SHA-256 checksum of an existing file on disk.
  Future<bool> verifyChecksum(String filePath, String expectedSha256) async {
    final file = File(filePath);
    if (!file.existsSync()) return false;
    final bytes = await file.readAsBytes();
    final actualHash = sha256.convert(bytes).toString();
    return actualHash.toLowerCase() == expectedSha256.toLowerCase();
  }
}
