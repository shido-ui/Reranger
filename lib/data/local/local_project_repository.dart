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

    // 3. Clear dirty crash journal upon successful save
    database.clearDirtyJournal();
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
  Future<RenderRecipe?> checkDirtyJournal() async {
    final journal = database.readDirtyJournal();
    if (journal == null) return null;
    return journal['recipe'] as RenderRecipe?;
  }

  @override
  Future<void> clearDirtyJournal() async {
    database.clearDirtyJournal();
  }

  @override
  Future<void> deleteProject(String projectId) async {
    // Delete database entry first
    database.deleteProject(projectId);
    // Delete private project storage files (leaves user source media intact)
    fileStorage.deleteProjectDirectory(projectId);
  }

  /// Runs orphan file cleanup against active projects in the database.
  Future<int> runOrphanCleanup() async {
    final projects = database.getRecentProjects();
    final activeIds = projects.map((p) => p.id).toSet();
    return fileStorage.orphanCleanup(activeIds);
  }
}
