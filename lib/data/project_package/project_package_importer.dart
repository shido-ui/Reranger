import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/project/project_entity.dart';
import '../local/atomic_file_writer.dart';
import '../local/project_database.dart';
import '../local/project_file_storage.dart';
import 'project_package_models.dart';

/// Validates, unpacks, and registers portable Reranger project packages (.rrproj / .reranger).
/// Enforces safe streaming preflight, archive bomb limits, Zip-Slip protection, checksum verification,
/// duplicate-name resolution, and rollback on failure (DEF-026 & Prompt 6.A).
class ProjectPackageImporter {
  final ProjectDatabase database;
  final ProjectFileStorage fileStorage;
  final StorageCapacityChecker capacityChecker;

  /// Maximum allowed files in a project package archive.
  static const int maxArchiveEntryCount = 256;

  /// Maximum allowed uncompressed size (250 MB).
  static const int maxTotalUnpackedBytes = 250 * 1024 * 1024;

  /// Maximum allowed uncompressed size per individual entry (100 MB).
  static const int maxPerEntryBytes = 100 * 1024 * 1024;

  /// Maximum allowed compressed archive size (200 MB).
  static const int maxCompressedBytes = 200 * 1024 * 1024;

  /// Maximum allowed compression ratio to prevent zip bombs (100:1).
  static const double maxCompressionRatio = 100.0;

  const ProjectPackageImporter({
    required this.database,
    required this.fileStorage,
    this.capacityChecker = const DefaultStorageCapacityChecker(),
  });

  /// Imports and unpacks [packageFile], registering the project in local SQLite and filesystem sandbox.
  /// Enforces limits before or during decompression using a safe streaming/preflight design.
  /// Throws [SecurityFailure] on any path traversal attempt, zip bomb, or undeclared file.
  /// Throws [FormatFailure] or [ChecksumMismatchFailure] if package is corrupted.
  /// Throws [LowStorageFailure] if disk space is insufficient.
  Future<ProjectEntity> importPackage(File packageFile) async {
    if (!packageFile.existsSync()) {
      throw MissingFileFailure(
        packageFile.path,
        'Package file does not exist on disk',
      );
    }

    final compressedSize = packageFile.lengthSync();
    if (compressedSize < 22) {
      throw const FormatFailure(
        'Invalid package format: File is too small to be a valid zip archive.',
      );
    }
    if (compressedSize > maxCompressedBytes) {
      throw SecurityFailure(
        'Security violation: Package file exceeds maximum compressed size of $maxCompressedBytes bytes.',
      );
    }

    // 1. Safe Preflight: Read Central Directory structure without decompressing content bytes
    final inputStream = InputFileStream(packageFile.path);
    final zipDir = ZipDirectory();
    try {
      zipDir.read(inputStream);
    } catch (e) {
      inputStream.close();
      throw FormatFailure('Corrupted zip archive: $e');
    }

    if (zipDir.fileHeaders.isEmpty) {
      inputStream.close();
      throw const FormatFailure(
        'Invalid package: Archive contains zero entries.',
      );
    }

    // 2. Preflight Security & Limits: Bomb, Zip-Slip, Paths, and Entry Bounds
    if (zipDir.fileHeaders.length > maxArchiveEntryCount) {
      inputStream.close();
      throw SecurityFailure(
        'Security violation: Archive exceeds maximum entry count of $maxArchiveEntryCount entries.',
      );
    }

    int totalUnpackedBytes = 0;
    final seenPaths = <String>{};
    bool hasManifest = false;
    final sourceEntryNames = <String>[];

    for (final header in zipDir.fileHeaders) {
      final name = header.filename.replaceAll('\\', '/');

      // Zip-Slip / Path Traversal / Null bytes check
      if (name.contains('..') ||
          name.contains('\x00') ||
          name.startsWith('/') ||
          name.startsWith('\\') ||
          name.contains(':') ||
          p.isAbsolute(name)) {
        inputStream.close();
        throw SecurityFailure(
          'Security violation: Potential Zip-Slip / path traversal detected in archive entry: "$name"',
        );
      }

      // Symlinks / Special Entries check (mode 0xa000 symlinks, sockets, fifos)
      final mode = header.externalFileAttributes >> 16;
      final fileType = mode & 0xf000;
      if (fileType != 0 && fileType != 0x8000 && fileType != 0x4000) {
        inputStream.close();
        throw SecurityFailure(
          'Security violation: Archive contains symlink or special entry: "$name"',
        );
      }

      // Duplicate entries check
      if (seenPaths.contains(name)) {
        inputStream.close();
        throw SecurityFailure(
          'Security violation: Duplicate entry in archive: "$name"',
        );
      }
      seenPaths.add(name);

      // Per-entry uncompressed size limit
      if (header.uncompressedSize > maxPerEntryBytes) {
        inputStream.close();
        throw SecurityFailure(
          'Security violation: Entry "$name" uncompressed size (${header.uncompressedSize} bytes) exceeds limit of $maxPerEntryBytes bytes.',
        );
      }

      totalUnpackedBytes += header.uncompressedSize;

      // Allowed path structure
      if (name == 'manifest.json') {
        hasManifest = true;
      } else if (name == 'recipe.json' || name == 'project.json') {
        // Valid root metadata entries
      } else if (name.startsWith('source/')) {
        if (!name.endsWith('/')) {
          final sub = name.substring('source/'.length);
          if (sub.contains('/')) {
            inputStream.close();
            throw SecurityFailure(
              'Security violation: Nested subdirectories in source/ not permitted: "$name"',
            );
          }
          sourceEntryNames.add(name);
        }
      } else if (name.startsWith('masks/')) {
        if (!name.endsWith('/')) {
          final sub = name.substring('masks/'.length);
          if (sub.contains('/')) {
            inputStream.close();
            throw SecurityFailure(
              'Security violation: Nested subdirectories in masks/ not permitted: "$name"',
            );
          }
        }
      } else {
        inputStream.close();
        throw SecurityFailure(
          'Security violation: Disallowed or unexpected file path in package: "$name"',
        );
      }
    }

    if (totalUnpackedBytes > maxTotalUnpackedBytes) {
      inputStream.close();
      throw SecurityFailure(
        'Security violation: Archive uncompressed size ($totalUnpackedBytes bytes) exceeds maximum allowable limit of $maxTotalUnpackedBytes bytes.',
      );
    }

    if (compressedSize > 0 &&
        (totalUnpackedBytes / compressedSize) > maxCompressionRatio) {
      inputStream.close();
      throw SecurityFailure(
        'Security violation: Potential zip bomb detected. Compression ratio exceeds $maxCompressionRatio:1.',
      );
    }

    if (!hasManifest) {
      inputStream.close();
      throw const FormatFailure(
        'Invalid package: "manifest.json" was not found in archive.',
      );
    }

    // 3. Preflight Storage Headroom Check before file decompression
    final availableBytes = await capacityChecker.getAvailableDiskBytes(
      fileStorage.projectsDir.path,
    );
    if (availableBytes != null) {
      final requiredBytes =
          totalUnpackedBytes + AtomicFileWriter.minimumHeadroomMargin;
      if (availableBytes < requiredBytes) {
        inputStream.close();
        throw LowStorageFailure(requiredBytes, availableBytes);
      }
    }

    // 4. Decode Archive Stream
    inputStream.setPosition(0);
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(inputStream);
    } catch (e) {
      throw FormatFailure('Corrupted zip archive: $e');
    } finally {
      inputStream.close();
    }

    // 5. Locate, Parse, and Validate Manifest
    final manifestEntry = archive.findFile('manifest.json');
    if (manifestEntry == null) {
      throw const FormatFailure(
        'Invalid package: "manifest.json" was not found in archive.',
      );
    }

    final ProjectPackageManifest manifest;
    try {
      final manifestJson = jsonDecode(
        utf8.decode(manifestEntry.content as List<int>),
      ) as Map<String, dynamic>;
      manifest = ProjectPackageManifest.fromJson(manifestJson);
    } catch (e) {
      throw FormatFailure('Malformed manifest.json in package: $e');
    }

    if (manifest.format != kRerangerPackageFormatId) {
      throw FormatFailure(
        'Unsupported package format: expected "$kRerangerPackageFormatId" but got "${manifest.format}"',
      );
    }
    if (manifest.sourceImageHash.isEmpty) {
      throw const FormatFailure('Malformed manifest: sourceImageHash is empty');
    }
    if (manifest.projectName.isEmpty) {
      throw const FormatFailure('Malformed manifest: projectName is empty');
    }
    if (manifest.files.isEmpty) {
      throw const FormatFailure(
        'Malformed manifest: files list cannot be empty',
      );
    }

    // 6. Verify Checksums of All Declared Files & Checksum Completeness
    for (final entry in manifest.files.entries) {
      final relativePath = entry.key;
      final expectedSha = entry.value;

      final bundledFile = archive.findFile(relativePath);
      if (bundledFile == null) {
        throw MissingFileFailure(
          relativePath,
          'Manifest references "$relativePath" but it is missing from archive.',
        );
      }

      final contentBytes = bundledFile.content as List<int>;
      final actualSha = sha256.convert(contentBytes).toString();
      if (actualSha != expectedSha) {
        throw ChecksumMismatchFailure(expectedSha, actualSha);
      }
    }

    // Reject package if archive contains files not declared in manifest
    for (final file in archive.files) {
      final name = file.name.replaceAll('\\', '/');
      if (name == 'manifest.json' ||
          name == 'recipe.json' ||
          name == 'project.json' ||
          name.endsWith('/')) {
        continue;
      }
      if (!manifest.files.containsKey(name)) {
        throw SecurityFailure(
          'Security violation: Archive contains undeclared file: "$name"',
        );
      }
    }

    // 7. Source Image Verification: Checksum must match declared sourceImageHash
    final sourceRelativePath = sourceEntryNames.first;
    final sourceArchiveFile = archive.findFile(sourceRelativePath);
    if (sourceArchiveFile == null) {
      throw FormatFailure(
        'Package corrupted: Declared source image "$sourceRelativePath" not found in archive.',
      );
    }

    final sourceContent = sourceArchiveFile.content as List<int>;
    final actualSourceHash = sha256.convert(sourceContent).toString();
    if (actualSourceHash != manifest.sourceImageHash) {
      throw ChecksumMismatchFailure(manifest.sourceImageHash, actualSourceHash);
    }

    // 8. Recipe existence check before sandbox allocation
    final recipeEntry = archive.findFile('recipe.json');
    if (recipeEntry == null) {
      throw const FormatFailure('Package corrupted: missing "recipe.json"');
    }

    // 9. Resolve Duplicate Project Name to prevent SQLite unique constraint violation (DEF-022)
    String resolvedName = manifest.projectName;
    if (database.projectNameExists(resolvedName)) {
      resolvedName = '${manifest.projectName} (Imported)';
      int counter = 1;
      while (database.projectNameExists(resolvedName)) {
        resolvedName = '${manifest.projectName} (Imported $counter)';
        counter++;
      }
    }

    // 10. Atomic Sandbox Extraction with Failure Cleanup
    final hashPrefix = manifest.sourceImageHash.length >= 6
        ? manifest.sourceImageHash.substring(0, 6)
        : manifest.sourceImageHash;
    final newProjectId =
        'proj_imp_${DateTime.now().microsecondsSinceEpoch}_$hashPrefix';

    fileStorage.ensureProjectDirectories(newProjectId);

    try {
      final sourceFileName = p.basename(sourceArchiveFile.name);
      final extractedSourceFile = File(
        p.join(
          fileStorage.getSourceDirectory(newProjectId).path,
          sourceFileName,
        ),
      );
      await extractedSourceFile.writeAsBytes(sourceContent, flush: true);

      // Extract masks (if any)
      for (final file in archive.files) {
        if (file.name.startsWith('masks/') && !file.name.endsWith('/')) {
          final maskFileName = p.basename(file.name);
          final maskDest = File(
            p.join(
              fileStorage.getMasksDirectory(newProjectId).path,
              maskFileName,
            ),
          );
          await maskDest.writeAsBytes(file.content as List<int>, flush: true);
        }
      }

      // Parse and adapt Recipe
      final recipeEntry = archive.findFile('recipe.json');
      if (recipeEntry == null) {
        throw const FormatFailure('Package corrupted: missing "recipe.json"');
      }
      final recipeJson = jsonDecode(
        utf8.decode(recipeEntry.content as List<int>),
      ) as Map<String, dynamic>;
      final rawRecipe = RenderRecipe.fromJson(recipeJson);

      final adaptedRecipe = RenderRecipe(
        recipeId: 'recipe_$newProjectId',
        recipeVersion: rawRecipe.recipeVersion,
        sourceImageHash: manifest.sourceImageHash,
        sourceImagePath: extractedSourceFile.path,
        activeStudio: rawRecipe.activeStudio,
        activePresetId: rawRecipe.activePresetId,
        masterIntensity: rawRecipe.masterIntensity,
        fineTuneParameters: rawRecipe.fineTuneParameters,
        curveLut256: rawRecipe.curveLut256,
        paletteRemap: rawRecipe.paletteRemap,
        maskPath: rawRecipe.maskPath != null
            ? p.join(
                fileStorage.getMasksDirectory(newProjectId).path,
                p.basename(rawRecipe.maskPath!),
              )
            : null,
        layerStack: rawRecipe.layerStack,
        variantBoard: rawRecipe.variantBoard,
        updatedAt: DateTime.now().toUtc(),
      );

      // Parse Project Metadata
      final projectEntry = archive.findFile('project.json');
      int width = 0;
      int height = 0;
      if (projectEntry != null) {
        try {
          final projectMeta = jsonDecode(
            utf8.decode(projectEntry.content as List<int>),
          ) as Map<String, dynamic>;
          width = (projectMeta['sourceWidth'] as num?)?.toInt() ?? 0;
          height = (projectMeta['sourceHeight'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }

      final importedProject = ProjectEntity(
        id: newProjectId,
        name: resolvedName,
        sourceImagePath: extractedSourceFile.path,
        sourceImageHash: manifest.sourceImageHash,
        sourceWidth: width > 0 ? width : 100,
        sourceHeight: height > 0 ? height : 100,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe: adaptedRecipe,
        isDirty: false,
        isCorrupted: false,
      );

      database.upsertProject(importedProject);
      return importedProject;
    } catch (e) {
      // Clean up newly created project directory on extraction failure
      try {
        final dir = fileStorage.getProjectDirectory(newProjectId);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }
}
