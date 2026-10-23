import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/local_project_repository.dart';
import '../../../data/local/project_database.dart';
import '../../../data/local/project_file_storage.dart';
import 'import_controller.dart';

/// Provider for app-private sandbox directory.
final appSandboxDirectoryProvider = Provider<Directory>((ref) {
  final baseDir = Directory('${Directory.systemTemp.path}/reranger_sandbox');
  if (!baseDir.existsSync()) {
    baseDir.createSync(recursive: true);
  }
  return baseDir;
});

/// Provider for local SQLite project database.
final projectDatabaseProvider = Provider<ProjectDatabase>((ref) {
  final sandbox = ref.watch(appSandboxDirectoryProvider);
  final dbFile = File('${sandbox.path}/reranger.db');
  final db = ProjectDatabase.openFile(dbFile.path);
  ref.onDispose(() => db.dispose());
  return db;
});

/// Provider for app-private project file storage.
final projectFileStorageProvider = Provider<ProjectFileStorage>((ref) {
  final sandbox = ref.watch(appSandboxDirectoryProvider);
  return ProjectFileStorage(rootDir: sandbox);
});

/// Provider for local project repository.
final projectRepositoryProvider = Provider<LocalProjectRepository>((ref) {
  final db = ref.watch(projectDatabaseProvider);
  final storage = ref.watch(projectFileStorageProvider);
  return LocalProjectRepository(database: db, fileStorage: storage);
});

/// Provider for the import controller.
final importControllerProvider = Provider<ImportController>((ref) {
  final repo = ref.watch(projectRepositoryProvider);
  final storage = ref.watch(projectFileStorageProvider);
  final controller = ImportController(
    projectRepository: repo,
    fileStorage: storage,
  );
  ref.onDispose(() => controller.dispose());
  return controller;
});
