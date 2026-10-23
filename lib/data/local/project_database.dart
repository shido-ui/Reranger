import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../domain/project/project_entity.dart';

/// Database migration step contract.
class DatabaseMigration {
  final int targetVersion;
  final String description;
  final void Function(Database db) migrate;

  const DatabaseMigration({
    required this.targetVersion,
    required this.description,
    required this.migrate,
  });
}

/// Migration-capable SQLite database engine for local project storage.
class ProjectDatabase {
  final Database _db;
  bool _isDisposed = false;

  ProjectDatabase(this._db) {
    _initPragmas();
    _runMigrations();
  }

  /// Opens an on-disk SQLite database file with WAL mode.
  factory ProjectDatabase.openFile(String path) {
    final db = sqlite3.open(path);
    return ProjectDatabase(db);
  }

  /// Opens an isolated in-memory SQLite database for testing and ephemeral workflows.
  factory ProjectDatabase.openInMemory() {
    final db = sqlite3.openInMemory();
    return ProjectDatabase(db);
  }

  Database get rawDb => _db;
  bool get isDisposed => _isDisposed;

  void _initPragmas() {
    // Configure durability and concurrency pragmas
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA busy_timeout = 5000;');
  }

  /// Current schema version stored in SQLite user_version.
  int get currentVersion {
    final result = _db.select('PRAGMA user_version;');
    return result.first.values[0] as int;
  }

  /// Ordered list of sequential migrations.
  static final List<DatabaseMigration> migrations = [
    DatabaseMigration(
      targetVersion: 1,
      description:
          'Create initial projects, dirty_journal, and scene_map_cache tables',
      migrate: (db) {
        db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            source_path TEXT NOT NULL,
            source_hash TEXT NOT NULL,
            source_width INTEGER NOT NULL,
            source_height INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            active_studio TEXT NOT NULL,
            active_preset_id TEXT NOT NULL,
            master_intensity REAL NOT NULL,
            recipe_json TEXT NOT NULL,
            scene_map_key TEXT,
            output_path TEXT,
            output_hash TEXT,
            is_dirty INTEGER NOT NULL DEFAULT 0,
            is_corrupted INTEGER NOT NULL DEFAULT 0
          );
        ''');

        db.execute('''
          CREATE TABLE dirty_journal (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            project_id TEXT NOT NULL,
            recipe_json TEXT NOT NULL,
            written_at TEXT NOT NULL
          );
        ''');

        db.execute('''
          CREATE TABLE scene_map_cache (
            cache_key TEXT PRIMARY KEY,
            source_hash TEXT NOT NULL,
            analysis_json TEXT NOT NULL,
            cached_at TEXT NOT NULL
          );
        ''');

        db.execute(
          'CREATE INDEX idx_projects_updated_at ON projects(updated_at DESC);',
        );
        db.execute(
          'CREATE INDEX idx_scene_map_source_hash ON scene_map_cache(source_hash);',
        );
      },
    ),
    DatabaseMigration(
      targetVersion: 2,
      description: 'Add favorite and tags metadata to projects',
      migrate: (db) {
        db.execute(
          'ALTER TABLE projects ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;',
        );
        db.execute('ALTER TABLE projects ADD COLUMN tags TEXT;');
      },
    ),
  ];

  void _runMigrations() {
    var version = currentVersion;
    for (final migration in migrations) {
      if (version < migration.targetVersion) {
        _db.execute('BEGIN TRANSACTION;');
        try {
          migration.migrate(_db);
          _db.execute('PRAGMA user_version = ${migration.targetVersion};');
          _db.execute('COMMIT;');
          version = migration.targetVersion;
        } catch (e) {
          _db.execute('ROLLBACK;');
          throw StorageFailure(
            'Failed migrating database to version ${migration.targetVersion}: $e',
          );
        }
      }
    }
  }

  /// Inserts or updates a project entity in the database.
  void upsertProject(ProjectEntity project) {
    try {
      _db.execute(
        '''
        INSERT INTO projects (
          id, name, source_path, source_hash, source_width, source_height,
          created_at, updated_at, active_studio, active_preset_id, master_intensity,
          recipe_json, scene_map_key, output_path, output_hash, is_dirty, is_corrupted
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          source_path = excluded.source_path,
          source_hash = excluded.source_hash,
          source_width = excluded.source_width,
          source_height = excluded.source_height,
          updated_at = excluded.updated_at,
          active_studio = excluded.active_studio,
          active_preset_id = excluded.active_preset_id,
          master_intensity = excluded.master_intensity,
          recipe_json = excluded.recipe_json,
          scene_map_key = excluded.scene_map_key,
          output_path = excluded.output_path,
          output_hash = excluded.output_hash,
          is_dirty = excluded.is_dirty,
          is_corrupted = excluded.is_corrupted;
      ''',
        [
          project.id,
          project.name,
          project.sourceImagePath,
          project.sourceImageHash,
          project.sourceWidth,
          project.sourceHeight,
          project.createdAt.toIso8601String(),
          project.updatedAt.toIso8601String(),
          project.recipe.activeStudio,
          project.recipe.activePresetId,
          project.recipe.masterIntensity,
          jsonEncode(project.recipe.toJson()),
          project.sceneMapCacheKey,
          project.outputReferencePath,
          project.outputChecksum,
          project.isDirty ? 1 : 0,
          project.isCorrupted ? 1 : 0,
        ],
      );
    } on SqliteException catch (e) {
      if (e.message.contains('UNIQUE constraint failed: projects.name')) {
        throw DuplicateProjectNameFailure(project.name);
      }
      throw StorageFailure('Database operation failed: ${e.message}');
    }
  }

  /// Fetches a project by unique ID.
  ProjectEntity? getProjectById(String id) {
    final result = _db.select('SELECT * FROM projects WHERE id = ? LIMIT 1;', [
      id,
    ]);
    if (result.isEmpty) return null;
    return _rowToProject(result.first);
  }

  /// Lists all projects sorted by update timestamp descending.
  List<ProjectSummary> getRecentProjects() {
    final result = _db.select(
      'SELECT id, name, source_path, active_studio, active_preset_id, updated_at, output_path FROM projects ORDER BY updated_at DESC;',
    );
    return result.map((row) {
      return ProjectSummary(
        id: row['id'] as String,
        name: row['name'] as String,
        sourceImagePath: row['source_path'] as String,
        activeStudio: row['active_studio'] as String,
        activePresetId: row['active_preset_id'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        outputReferencePath: row['output_path'] as String?,
      );
    }).toList();
  }

  /// Checks whether a project with [name] already exists in the database.
  bool projectNameExists(String name) {
    final stmt = _db.prepare(
      'SELECT COUNT(*) as count FROM projects WHERE name = ?;',
    );
    try {
      final result = stmt.select([name]);
      return (result.first['count'] as int) > 0;
    } finally {
      stmt.close();
    }
  }

  /// Generates a unique, non-colliding project name from [baseName] (DEF-022).
  /// If [baseName] already exists, deterministically appends " (1)", " (2)", etc.
  String resolveUniqueProjectName(String baseName) {
    var candidate = baseName.trim();
    if (candidate.isEmpty) {
      candidate = 'Untitled Project';
    }
    if (!projectNameExists(candidate)) {
      return candidate;
    }

    final regex = RegExp(r'^(.*) \((\d+)\)$');
    final match = regex.firstMatch(candidate);
    String rootName = candidate;
    int counter = 1;
    if (match != null) {
      rootName = match.group(1)!;
      counter = int.parse(match.group(2)!) + 1;
    }

    while (true) {
      final proposal = '$rootName ($counter)';
      if (!projectNameExists(proposal)) {
        return proposal;
      }
      counter++;
    }
  }

  /// Deletes a project record by ID.
  bool deleteProject(String id) {
    _db.execute('DELETE FROM projects WHERE id = ?;', [id]);
    return _db.updatedRows > 0;
  }

  /// Atomic crash recovery: records uncommitted dirty recipe to the journal.
  void writeDirtyJournal(String projectId, RenderRecipe recipe) {
    _db.execute(
      '''
      INSERT INTO dirty_journal (id, project_id, recipe_json, written_at)
      VALUES (1, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        project_id = excluded.project_id,
        recipe_json = excluded.recipe_json,
        written_at = excluded.written_at;
    ''',
      [
        projectId,
        jsonEncode(recipe.toJson()),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  /// Checks if an active dirty journal exists (indicates previous abnormal termination).
  Map<String, dynamic>? readDirtyJournal() {
    final result = _db.select(
      'SELECT * FROM dirty_journal WHERE id = 1 LIMIT 1;',
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'projectId': row['project_id'] as String,
      'recipe': RenderRecipe.fromJson(
        jsonDecode(row['recipe_json'] as String) as Map<String, dynamic>,
      ),
      'writtenAt': DateTime.parse(row['written_at'] as String),
    };
  }

  /// Clears the dirty journal on clean save or project close.
  void clearDirtyJournal() {
    _db.execute('DELETE FROM dirty_journal WHERE id = 1;');
  }

  /// Caches an analysis scene map so projects reopen instantly without re-analysis.
  void saveSceneMapCache(
    String cacheKey,
    String sourceHash,
    String analysisJson,
  ) {
    _db.execute(
      '''
      INSERT INTO scene_map_cache (cache_key, source_hash, analysis_json, cached_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(cache_key) DO UPDATE SET
        analysis_json = excluded.analysis_json,
        cached_at = excluded.cached_at;
    ''',
      [
        cacheKey,
        sourceHash,
        analysisJson,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  /// Retrieves cached scene map by cache key.
  String? getSceneMapCache(String cacheKey) {
    final result = _db.select(
      'SELECT analysis_json FROM scene_map_cache WHERE cache_key = ? LIMIT 1;',
      [cacheKey],
    );
    if (result.isEmpty) return null;
    return result.first['analysis_json'] as String;
  }

  /// Deletes a specific cached scene map.
  void deleteSceneMapCache(String cacheKey) {
    _db.execute('DELETE FROM scene_map_cache WHERE cache_key = ?;', [cacheKey]);
  }

  /// Deletes all cached scene maps for a given source hash.
  void deleteSceneMapCacheBySourceHash(String sourceHash) {
    _db.execute('DELETE FROM scene_map_cache WHERE source_hash = ?;', [
      sourceHash,
    ]);
  }

  /// Clears all scene map cache entries.
  void clearSceneMapCache() {
    _db.execute('DELETE FROM scene_map_cache;');
  }

  ProjectEntity _rowToProject(Row row) {
    final recipeJsonStr = row['recipe_json'] as String;
    final recipeMap = jsonDecode(recipeJsonStr) as Map<String, dynamic>;
    final recipe = RenderRecipe.fromJson(recipeMap);

    return ProjectEntity(
      id: row['id'] as String,
      name: row['name'] as String,
      sourceImagePath: row['source_path'] as String,
      sourceImageHash: row['source_hash'] as String,
      sourceWidth: row['source_width'] as int,
      sourceHeight: row['source_height'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      recipe: recipe,
      sceneMapCacheKey: row['scene_map_key'] as String?,
      outputReferencePath: row['output_path'] as String?,
      outputChecksum: row['output_hash'] as String?,
      isDirty: (row['is_dirty'] as int) == 1,
      isCorrupted: (row['is_corrupted'] as int) == 1,
    );
  }

  /// Closes database connection cleanly.
  void dispose() {
    if (!_isDisposed) {
      _db.close();
      _isDisposed = true;
    }
  }
}
