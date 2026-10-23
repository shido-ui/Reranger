import '../../domain/project/project_entity.dart';
import '../../domain/project/project_repository.dart';
import 'project_database.dart';
import 'project_file_storage.dart';

/// Concrete local persistence implementation backed by SQLite and private sandboxed files.
class LocalProjectRepository implements ProjectRepository {
  final ProjectDatabase database;
  final ProjectFileStorage fileStorage;

  LocalProjectRepository({required this.database, required this.fileStorage});

  @override
  Future<void> saveProject(ProjectEntity project) async {
    // 1. Verify project integrity before committing to database
    final report = await fileStorage.verifyIntegrity(project);
    if (report.state == ProjectIntegrityState.sourceMissing ||
        report.state == ProjectIntegrityState.sourceCorrupted) {
      throw CorruptedProjectFailure(
        'Cannot save project with corrupted or missing source media: ${report.details}',
      );
    }

    // 2. Upsert in database
    database.upsertProject(project.copyWith(isDirty: false));

    // 3. Clear dirty crash journal upon successful save for this project (Prompt 1.C.3)
    database.clearDirtyJournal(project.id);
  }

  @override
  Future<ProjectEntity?> loadProject(String projectId) async {
    final project = database.getProjectById(projectId);
    if (project == null) return null;

    // Verify integrity of files
    final report = await fileStorage.verifyIntegrity(project);
    if (!report.canReconstruct) {
      // Mark corrupted if source is missing or hash mismatched
      return project.copyWith(isCorrupted: true);
    }

    if (report.state == ProjectIntegrityState.outputMissing ||
        report.state == ProjectIntegrityState.outputCorrupted) {
      // Output was deleted, lost, or corrupted, but recipe & source are 100% intact
      return project.copyWith(clearOutputReference: true);
    }

    return project;
  }

  @override
  Future<List<ProjectSummary>> getRecentProjects() async {
    return database.getRecentProjects();
  }

  @override
  Future<void> writeDirtyJournal(String projectId, RenderRecipe recipe) async {
    database.writeDirtyJournal(projectId, recipe);
  }

  @override
  Future<RenderRecipe?> checkDirtyJournal([String? projectId]) async {
    final journal = database.readDirtyJournal(projectId);
    if (journal == null) return null;
    final recipe = journal['recipe'] as RenderRecipe?;
    if (recipe == null) return null;

    // Validate integrity of journal entry if projectId was specified (Prompt 1.C.2)
    if (projectId != null) {
      if (journal['projectId'] != projectId) return null;
      final expectedRecId = journal['recipeId'] as String?;
      if (expectedRecId != null &&
          expectedRecId.isNotEmpty &&
          expectedRecId != 'unknown_rec' &&
          recipe.recipeId.isNotEmpty &&
          expectedRecId != recipe.recipeId) {
        return null;
      }
      final expectedHash = journal['sourceHash'] as String?;
      if (expectedHash != null &&
          expectedHash.isNotEmpty &&
          expectedHash != 'unknown_hash' &&
          recipe.sourceImageHash.isNotEmpty &&
          expectedHash != recipe.sourceImageHash) {
        return null;
      }
    }
    return recipe;
  }

  @override
  Future<void> clearDirtyJournal([String? projectId]) async {
    database.clearDirtyJournal(projectId);
  }

  @override
  Future<void> deleteProject(String projectId) async {
    // Delete database entry first
    database.deleteProject(projectId);
    // Delete dirty journal for this project
    database.clearDirtyJournal(projectId);
    // Delete private project storage files (leaves user source media intact)
    fileStorage.deleteProjectDirectory(projectId);
  }

  @override
  String resolveUniqueProjectName(String baseName) {
    return database.resolveUniqueProjectName(baseName);
  }

  /// Runs orphan file cleanup against active projects in the database.
  Future<int> runOrphanCleanup() async {
    final projects = database.getRecentProjects();
    final activeIds = projects.map((p) => p.id).toSet();
    return fileStorage.orphanCleanup(activeIds);
  }
}
