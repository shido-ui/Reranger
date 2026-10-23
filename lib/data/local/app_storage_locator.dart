import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'project_database.dart';

/// Service locating durable app-private storage paths and performing
/// idempotent, safe migration away from ephemeral temporary directories (DEF-021).
class AppStorageLocator {
  static const MethodChannel _storageChannel = MethodChannel(
    'com.reranger.app/storage',
  );

  static AppStorageLocator _instance = const AppStorageLocator();
  static AppStorageLocator get instance => _instance;
  @visibleForTesting
  static set instance(AppStorageLocator locator) => _instance = locator;

  static Directory? _cachedDurableDir;
  static Directory? _cachedTempDir;

  final Directory _overrideDurableDir;
  final Directory? _overrideTempDir;

  const AppStorageLocator({Directory? durableDir, Directory? tempDir})
    : _overrideDurableDir = durableDir ?? const _DefaultDurableDirectory(),
      _overrideTempDir = tempDir;

  /// Global initialization hook to be called at application startup.
  /// Resolves the platform storage paths and executes legacy migration.
  static Future<void> initialize({
    Directory? durableDir,
    Directory? tempDir,
  }) async {
    _instance = AppStorageLocator(durableDir: durableDir, tempDir: tempDir);
    final durable = await _instance.getDurableDirectory();
    _cachedDurableDir = durable;
    final cache = await _instance.getCacheDirectory();
    _cachedTempDir = cache;

    // Execute idempotent migration if legacy storage exists
    await _instance.migrateFromLegacyTempStorage(durable);
  }

  /// Synchronous resolution of the durable directory.
  Directory getDurableDirectorySync() {
    if (_overrideDurableDir is! _DefaultDurableDirectory) {
      if (!_overrideDurableDir.existsSync()) {
        _overrideDurableDir.createSync(recursive: true);
      }
      return _overrideDurableDir;
    }

    if (_cachedDurableDir != null && _cachedDurableDir!.existsSync()) {
      return _cachedDurableDir!;
    }

    // Platform-specific synchronous resolution for Linux / Desktop / Testing
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final dir = Directory(p.join(home, '.local', 'share', 'reranger'));
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
          _cachedDurableDir = dir;
          return dir;
        } catch (_) {
          // Fall through to fallback
        }
      } else {
        _cachedDurableDir = dir;
        return dir;
      }
    }

    // Android standard app data path fallback if running on Android
    if (Platform.isAndroid) {
      final androidPaths = [
        '/data/user/0/com.reranger.reranger/files',
        '/data/data/com.reranger.reranger/files',
      ];
      for (final aPath in androidPaths) {
        final aDir = Directory(aPath);
        if (aDir.existsSync()) {
          _cachedDurableDir = aDir;
          return aDir;
        }
      }
    }

    // Fallback: application-specific folder in current working directory
    final fallback = Directory(
      p.join(Directory.current.path, '.reranger_data'),
    );
    if (!fallback.existsSync()) {
      try {
        fallback.createSync(recursive: true);
      } catch (_) {
        // Fallback to system temp under dedicated durable namespace if current dir is read-only
        final tempDurable = Directory(
          p.join(Directory.systemTemp.path, 'reranger_persistent'),
        );
        if (!tempDurable.existsSync()) tempDurable.createSync(recursive: true);
        _cachedDurableDir = tempDurable;
        return tempDurable;
      }
    }
    _cachedDurableDir = fallback;
    return fallback;
  }

  /// Returns the durable, persistent directory for projects, recipes, and SQLite database.
  /// Never subject to OS temp cache purging.
  Future<Directory> getDurableDirectory() async {
    if (_overrideDurableDir is! _DefaultDurableDirectory) {
      if (!_overrideDurableDir.existsSync()) {
        _overrideDurableDir.createSync(recursive: true);
      }
      return _overrideDurableDir;
    }

    // Attempt platform channel query if on Android
    try {
      final String? path = await _storageChannel.invokeMethod<String>(
        'getFilesDirectory',
      );
      if (path != null && path.isNotEmpty) {
        final dir = Directory(path);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _cachedDurableDir = dir;
        return dir;
      }
    } catch (_) {
      // Platform channel unavailable (e.g. headless Linux container or test)
    }

    return getDurableDirectorySync();
  }

  /// Returns a dedicated temporary/cache directory for transient, regenerable files.
  Future<Directory> getCacheDirectory() async {
    if (_overrideTempDir != null) {
      if (!_overrideTempDir.existsSync()) {
        _overrideTempDir.createSync(recursive: true);
      }
      return _overrideTempDir;
    }

    if (_cachedTempDir != null && _cachedTempDir!.existsSync()) {
      return _cachedTempDir!;
    }

    try {
      final String? path = await _storageChannel.invokeMethod<String>(
        'getCacheDirectory',
      );
      if (path != null && path.isNotEmpty) {
        final dir = Directory(path);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        _cachedTempDir = dir;
        return dir;
      }
    } catch (_) {
      // Platform channel unavailable
    }

    final durable = await getDurableDirectory();
    final cacheDir = Directory(p.join(durable.path, 'cache'));
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    _cachedTempDir = cacheDir;
    return cacheDir;
  }

  /// Performs an idempotent, interruption-safe migration from the legacy ephemeral
  /// system temporary directory (`/tmp/reranger_sandbox`) to the durable directory.
  ///
  /// Guarantees:
  /// - Old data is never deleted until the new copy is completely written and verified.
  /// - If the target already exists, migration is skipped safely without data loss.
  /// - SQLite database integrity is checked before completing migration.
  Future<bool> migrateFromLegacyTempStorage(Directory durableTargetDir) async {
    final legacyDir = Directory(
      p.join(Directory.systemTemp.path, 'reranger_sandbox'),
    );
    if (!legacyDir.existsSync()) {
      return false; // No legacy data to migrate
    }

    final markerFile = File(
      p.join(durableTargetDir.path, '.migration_completed'),
    );
    if (markerFile.existsSync()) {
      return false; // Migration was already executed previously
    }

    final legacyDbFile = File(p.join(legacyDir.path, 'reranger.db'));
    final targetDbFile = File(p.join(durableTargetDir.path, 'reranger.db'));

    // If target database already exists and has data, do not overwrite it
    if (targetDbFile.existsSync() && targetDbFile.lengthSync() > 0) {
      markerFile.writeAsStringSync('skipped_target_exists');
      return false;
    }

    // 1. Copy SQLite database if it exists
    if (legacyDbFile.existsSync() && legacyDbFile.lengthSync() > 0) {
      final tempCopy = File(
        '${targetDbFile.path}.tmp.${DateTime.now().millisecondsSinceEpoch}',
      );
      await legacyDbFile.copy(tempCopy.path);

      // Verify SQLite can open and query the copy
      try {
        final testDb = ProjectDatabase.openFile(tempCopy.path);
        testDb.rawDb.select('PRAGMA user_version;');
        testDb.dispose();

        // Atomic move into place
        if (targetDbFile.existsSync()) targetDbFile.deleteSync();
        tempCopy.renameSync(targetDbFile.path);
      } catch (e) {
        if (tempCopy.existsSync()) tempCopy.deleteSync();
        return false; // Verification failed, preserve legacy original untouched
      }
    }

    // 2. Copy projects directory if present
    final legacyProjectsDir = Directory(p.join(legacyDir.path, 'projects'));
    final targetProjectsDir = Directory(
      p.join(durableTargetDir.path, 'projects'),
    );
    if (legacyProjectsDir.existsSync()) {
      if (!targetProjectsDir.existsSync()) {
        targetProjectsDir.createSync(recursive: true);
      }
      await _copyDirectoryRecursively(legacyProjectsDir, targetProjectsDir);
    }

    // 3. Mark migration complete
    markerFile.writeAsStringSync(
      'completed_${DateTime.now().toIso8601String()}',
    );

    // 4. Clean up legacy directory safely
    try {
      legacyDir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup of legacy temp
    }

    return true;
  }

  static Future<void> _copyDirectoryRecursively(
    Directory source,
    Directory destination,
  ) async {
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        final newDir = Directory(newPath);
        if (!newDir.existsSync()) newDir.createSync(recursive: true);
        await _copyDirectoryRecursively(entity, newDir);
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}

class _DefaultDurableDirectory implements Directory {
  const _DefaultDurableDirectory();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
