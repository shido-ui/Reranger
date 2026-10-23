import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/project/project_entity.dart';
import 'atomic_file_writer.dart';

/// Integrity status result for a project and its associated files.
enum ProjectIntegrityState {
  healthy,
  sourceMissing,
  sourceCorrupted,
  outputMissing,
  outputCorrupted,
}

class ProjectIntegrityReport {
  final ProjectIntegrityState state;
  final String? details;

  const ProjectIntegrityReport(this.state, [this.details]);

  bool get isHealthy => state == ProjectIntegrityState.healthy;
  bool get canReconstruct =>
      state == ProjectIntegrityState.healthy ||
      state == ProjectIntegrityState.outputMissing ||
      state == ProjectIntegrityState.outputCorrupted;
}

/// Manages private project file storage, sandbox directories, orphan cleanup, and integrity verification.
class ProjectFileStorage {
  final Directory rootDir;
  final AtomicFileWriter atomicWriter;

  ProjectFileStorage({required this.rootDir, AtomicFileWriter? writer})
    : atomicWriter = writer ?? const AtomicFileWriter();

  Directory get projectsDir => Directory(p.join(rootDir.path, 'projects'));

  /// Resolves the root directory for a specific project.
  Directory getProjectDirectory(String projectId) =>
      Directory(p.join(projectsDir.path, projectId));

  Directory getSourceDirectory(String projectId) =>
      Directory(p.join(getProjectDirectory(projectId).path, 'source'));

  Directory getMasksDirectory(String projectId) =>
      Directory(p.join(getProjectDirectory(projectId).path, 'masks'));

  Directory getOutputsDirectory(String projectId) =>
      Directory(p.join(getProjectDirectory(projectId).path, 'outputs'));

  Directory getCacheDirectory(String projectId) =>
      Directory(p.join(getProjectDirectory(projectId).path, 'cache'));

  /// Ensures project sandbox directories exist.
  void ensureProjectDirectories(String projectId) {
    getSourceDirectory(projectId).createSync(recursive: true);
    getMasksDirectory(projectId).createSync(recursive: true);
    getOutputsDirectory(projectId).createSync(recursive: true);
    getCacheDirectory(projectId).createSync(recursive: true);
  }

  /// Saves a rendered output file atomically into the project outputs directory.
  Future<AtomicWriteResult> saveOutput({
    required String projectId,
    required String fileName,
    required List<int> bytes,
    required String sourceImagePath,
  }) async {
    ensureProjectDirectories(projectId);
    final destination = p.join(getOutputsDirectory(projectId).path, fileName);
    return atomicWriter.writeBytes(
      destinationPath: destination,
      bytes: bytes,
      sourceImagePath: sourceImagePath,
    );
  }

  /// Saves a mask byte array atomically into the project masks directory.
  Future<AtomicWriteResult> saveMask({
    required String projectId,
    required String maskFileName,
    required List<int> bytes,
    required String sourceImagePath,
  }) async {
    ensureProjectDirectories(projectId);
    final destination = p.join(getMasksDirectory(projectId).path, maskFileName);
    return atomicWriter.writeBytes(
      destinationPath: destination,
      bytes: bytes,
      sourceImagePath: sourceImagePath,
    );
  }

  /// Verifies project files against recorded checksums.
  Future<ProjectIntegrityReport> verifyIntegrity(ProjectEntity project) async {
    final sourceFile = File(project.sourceImagePath);
    if (!sourceFile.existsSync()) {
      return ProjectIntegrityReport(
        ProjectIntegrityState.sourceMissing,
        'Source media file not found at ${project.sourceImagePath}',
      );
    }

    final isSourceValid = await atomicWriter.verifyChecksum(
      project.sourceImagePath,
      project.sourceImageHash,
    );
    if (!isSourceValid) {
      return ProjectIntegrityReport(
        ProjectIntegrityState.sourceCorrupted,
        'Source media SHA-256 mismatch: file may have been tampered with or corrupted on disk.',
      );
    }

    // Verify output file if an output reference is recorded
    if (project.outputReferencePath != null) {
      final outputFile = File(project.outputReferencePath!);
      if (!outputFile.existsSync()) {
        return ProjectIntegrityReport(
          ProjectIntegrityState.outputMissing,
          'Output file is missing from disk. Recipe is intact and can be re-rendered.',
        );
      }
      if (project.outputChecksum != null) {
        final isOutputValid = await atomicWriter.verifyChecksum(
          project.outputReferencePath!,
          project.outputChecksum!,
        );
        if (!isOutputValid) {
          return ProjectIntegrityReport(
            ProjectIntegrityState.outputCorrupted,
            'Output file checksum does not match recorded render checksum.',
          );
        }
      }
    }

    return const ProjectIntegrityReport(ProjectIntegrityState.healthy);
  }

  /// Purges orphaned temporary files and project directories not recorded in the database.
  Future<int> orphanCleanup(Set<String> activeProjectIds) async {
    if (!projectsDir.existsSync()) return 0;
    var cleanedCount = 0;

    // 1. Purge unreferenced project directories
    final entities = projectsDir.listSync(followLinks: false);
    for (final entity in entities) {
      if (entity is Directory) {
        final dirName = p.basename(entity.path);
        if (!activeProjectIds.contains(dirName)) {
          entity.deleteSync(recursive: true);
          cleanedCount++;
        } else {
          // 2. Clean up any stale temporary files (*.tmp.*) inside valid project directories
          cleanedCount += _cleanTempFiles(entity);
        }
      }
    }

    return cleanedCount;
  }

  int _cleanTempFiles(Directory dir) {
    var count = 0;
    try {
      final items = dir.listSync(recursive: true, followLinks: false);
      for (final item in items) {
        if (item is File && p.basename(item.path).contains('.tmp.')) {
          item.deleteSync();
          count++;
        }
      }
    } catch (_) {}
    return count;
  }

  /// Recursively deletes an entire project directory within private storage.
  void deleteProjectDirectory(String projectId) {
    final dir = getProjectDirectory(projectId);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
