import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/project/project_entity.dart';
import '../local/atomic_file_writer.dart';
import '../local/project_file_storage.dart';
import 'project_package_models.dart';

/// Exports a complete project into a portable, versioned, checksum-verified archive (.rrproj).
class ProjectPackageExporter {
  final ProjectFileStorage fileStorage;
  final AtomicFileWriter atomicWriter;

  const ProjectPackageExporter({
    required this.fileStorage,
    this.atomicWriter = const AtomicFileWriter(),
  });

  /// Packages [project] into an archive written atomically to [destinationPackagePath].
  Future<AtomicWriteResult> exportPackage({
    required ProjectEntity project,
    required String destinationPackagePath,
  }) async {
    final sourceFile = File(project.sourceImagePath);
    if (!sourceFile.existsSync()) {
      throw StorageFailure(
        'Cannot export project package: source image does not exist at ${project.sourceImagePath}',
      );
    }

    final sourceBytes = await sourceFile.readAsBytes();
    final sourceDigest = sha256.convert(sourceBytes).toString();

    // Verify source hasn't mutated
    if (sourceDigest != project.sourceImageHash) {
      throw StorageFailure(
        'Cannot export project package: source image hash mismatch (source mutated externally)',
      );
    }

    final archive = Archive();
    final manifestFiles = <String, String>{};

    // 1. Add Source Image
    final sourceFileName = p.basename(project.sourceImagePath);
    final sourceRelativePath = 'source/$sourceFileName';
    archive.addFile(
      ArchiveFile(sourceRelativePath, sourceBytes.length, sourceBytes),
    );
    manifestFiles[sourceRelativePath] = sourceDigest;

    // 2. Add Masks (if any exist in project directory)
    final masksDir = fileStorage.getMasksDirectory(project.id);
    if (masksDir.existsSync()) {
      final maskEntries = masksDir.listSync().whereType<File>();
      for (final maskFile in maskEntries) {
        final maskBytes = await maskFile.readAsBytes();
        final maskRelativePath = 'masks/${p.basename(maskFile.path)}';
        archive.addFile(
          ArchiveFile(maskRelativePath, maskBytes.length, maskBytes),
        );
        manifestFiles[maskRelativePath] = sha256.convert(maskBytes).toString();
      }
    }

    // 3. Add Recipe JSON
    final recipeJsonBytes = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert(project.recipe.toJson()),
      ),
    );
    const recipeRelativePath = 'recipe.json';
    archive.addFile(
      ArchiveFile(recipeRelativePath, recipeJsonBytes.length, recipeJsonBytes),
    );
    manifestFiles[recipeRelativePath] = sha256
        .convert(recipeJsonBytes)
        .toString();

    // 4. Add Project Metadata JSON
    final projectMetaMap = {
      'id': project.id,
      'name': project.name,
      'sourceWidth': project.sourceWidth,
      'sourceHeight': project.sourceHeight,
      'activeStudio': project.recipe.activeStudio,
      'activePresetId': project.recipe.activePresetId,
      'masterIntensity': project.recipe.masterIntensity,
      'createdAt': project.createdAt.toIso8601String(),
      'updatedAt': project.updatedAt.toIso8601String(),
    };
    final projectMetaBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(projectMetaMap)),
    );
    const projectRelativePath = 'project.json';
    archive.addFile(
      ArchiveFile(
        projectRelativePath,
        projectMetaBytes.length,
        projectMetaBytes,
      ),
    );
    manifestFiles[projectRelativePath] = sha256
        .convert(projectMetaBytes)
        .toString();

    // 5. Add Manifest JSON
    final manifest = ProjectPackageManifest(
      createdAt: DateTime.now().toUtc(),
      originalProjectId: project.id,
      projectName: project.name,
      sourceImageHash: sourceDigest,
      files: manifestFiles,
    );
    final manifestBytes = Uint8List.fromList(
      utf8.encode(manifest.toJsonString()),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    // 6. Encode ZIP
    final zipEncoder = ZipEncoder();
    final zipData = zipEncoder.encode(archive);

    // 7. Atomic Write with Headroom Verification and Source Immutability Protection
    return atomicWriter.writeBytes(
      destinationPath: destinationPackagePath,
      bytes: zipData,
      sourceImagePath: project.sourceImagePath,
    );
  }
}
