import 'project_entity.dart';

/// Abstract repository contract for project lifecycle, persistence, and crash recovery.
abstract interface class ProjectRepository {
  /// Saves or updates a project recipe and state in local SQLite storage.
  Future<void> saveProject(ProjectEntity project);

  /// Loads project by unique ID.
  Future<ProjectEntity?> loadProject(String projectId);

  /// Lists all recent projects for the Home Gallery.
  Future<List<ProjectSummary>> getRecentProjects();

  /// Records an atomic journal snapshot for crash recovery.
  Future<void> writeDirtyJournal(String projectId, RenderRecipe recipe);

  /// Checks for unsaved crash recovery state on launch (optionally scoped to [projectId]).
  Future<RenderRecipe?> checkDirtyJournal([String? projectId]);

  /// Clears the dirty journal on clean exit or save (optionally scoped to [projectId]).
  Future<void> clearDirtyJournal([String? projectId]);

  /// Deletes a project from database and cleans its private files.
  Future<void> deleteProject(String projectId);

  /// Resolves a non-colliding unique project name (DEF-022).
  String resolveUniqueProjectName(String baseName);
}
