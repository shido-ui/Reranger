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
/// Enforces strict Zip-Slip protection, checksum verification, and duplicate-name resolution.
class ProjectPackageImporter {
  final ProjectDatabase database;
  final ProjectFileStorage fileStorage;
  final StorageCapacityChecker capacityChecker;

  const ProjectPackageImporter({
    required this.database,
    required this.fileStorage,
    this.capacityChecker = const DefaultStorageCapacityChecker(),
  });

  /// Imports and unpacks [packageFile], registering the project in local SQLite and filesystem sandbox.
  /// Throws [SecurityFailure] on any path traversal attempt.
  /// Throws [FormatFailure] or [ChecksumMismatchFailure] if package is corrupted.
  /// Throws [LowStorageFailure] if disk space is insufficient.
  Future<ProjectEntity> importPackage(File packageFile) async {
    if (!packageFile.existsSync()) {
      throw MissingFileFailure(
        packageFile.path,
        'Package file does not exist on disk',
      );
    }

    final packageBytes = await packageFile.readAsBytes();

    // 1. Verify ZIP header (magic 0x04034B50: 'PK\x03\x04')
    if (packageBytes.length < 4 ||
        packageBytes[0] != 0x50 ||
        packageBytes[1] != 0x4B ||
        packageBytes[2] != 0x03 ||
        packageBytes[3] != 0x04) {
      throw const FormatFailure(
        'Invalid package format: File is not a valid zip archive.',
      );
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(packageBytes);
    } catch (e) {
      throw FormatFailure('Corrupted zip archive: $e');
    }

    // 2. Strict Security: Zip-Slip / Path Traversal Protection
    for (final file in archive.files) {
      final name = file.name.replaceAll('\\', '/');
      if (name.contains('..') ||
          name.contains('\x00') ||
          name.startsWith('/') ||
          name.contains(':') ||
          p.isAbsolute(name)) {
        throw SecurityFailure(
          'Security violation: Potential Zip-Slip / path traversal detected in archive entry: "$name"',
        );
      }
    }

    // 3. Locate and Parse Manifest
    final manifestEntry = archive.findFile('manifest.json');
    if (manifestEntry == null) {
      throw const FormatFailure(
        'Invalid package: "manifest.json" was not found in archive.',
      );
    }

    ProjectPackageManifest manifest;
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

    // 4. Verify Checksums of All Declared Files
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

    // 5. Storage Headroom Check
    int totalUnpackedBytes = 0;
    for (final file in archive.files) {
      totalUnpackedBytes += file.size;
    }
    final availableBytes = await capacityChecker.getAvailableDiskBytes(
      fileStorage.projectsDir.path,
    );
    final requiredBytes =
        totalUnpackedBytes + AtomicFileWriter.minimumHeadroomMargin;
    if (availableBytes < requiredBytes) {
      throw LowStorageFailure(requiredBytes, availableBytes);
    }

    // 6. Resolve Duplicate Project Name to prevent SQLite unique constraint violation
    String resolvedName = manifest.projectName;
    if (database.projectNameExists(resolvedName)) {
      resolvedName = '${manifest.projectName} (Imported)';
      int counter = 1;
      while (database.projectNameExists(resolvedName)) {
        resolvedName = '${manifest.projectName} (Imported $counter)';
        counter++;
      }
    }

    // 7. Sandbox Extraction
    final newProjectId =
        'proj_imp_${DateTime.now().microsecondsSinceEpoch}_${manifest.sourceImageHash.substring(0, 6)}';
    fileStorage.ensureProjectDirectories(newProjectId);

    // Extract source media
    ArchiveFile? sourceArchiveFile;
    for (final file in archive.files) {
      if (file.name.startsWith('source/')) {
        sourceArchiveFile = file;
        break;
      }
    }
    if (sourceArchiveFile == null) {
      throw const FormatFailure(
        'Package corrupted: No source image found in source/ folder.',
      );
    }

    final sourceFileName = p.basename(sourceArchiveFile.name);
    final extractedSourceFile = File(
      p.join(fileStorage.getSourceDirectory(newProjectId).path, sourceFileName),
    );
    await extractedSourceFile.writeAsBytes(
      sourceArchiveFile.content as List<int>,
      flush: true,
    );

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

    // Update recipe to point to the newly extracted source image path
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
  }
}
