import '../../core/logging/app_logger.dart';
import '../../domain/scene_map/scene_map_bundle.dart';
import '../../domain/scene_map/scene_map_failure.dart';
import '../local/project_database.dart';

/// Repository managing storage, retrieval, and cache invalidation for Analysis Bundles.
/// Implements dual-layer caching (in-memory fast cache + persistent SQLite store).
/// Gracefully handles and heals corrupted cache records (Invariant 12).
class SceneMapRepository {
  final ProjectDatabase _db;
  final Map<String, SceneMapBundle> _memoryCache;
  final int maxMemoryEntries;

  SceneMapRepository(this._db, {this.maxMemoryEntries = 16})
    : _memoryCache = {};

  /// Retrieves cached bundle if present and valid.
  /// Returns null on cache miss or corrupted payload.
  Future<SceneMapBundle?> getCachedBundle(String cacheKey) async {
    // 1. In-memory cache hit
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    // 2. Persistent SQLite query
    final jsonStr = _db.getSceneMapCache(cacheKey);
    if (jsonStr == null) {
      return null; // Cache miss
    }

    try {
      final bundle = SceneMapBundle.decodeJson(jsonStr);
      _putMemory(cacheKey, bundle);
      return bundle;
    } on SceneMapCorruptCacheFailure catch (e) {
      AppLogger.warning(
        'Detected corrupt scene map cache entry: $cacheKey. Purging corrupted row: $e',
      );
      // Auto-heal by removing invalid cache entry
      _db.deleteSceneMapCache(cacheKey);
      _memoryCache.remove(cacheKey);
      return null;
    } catch (e, st) {
      AppLogger.error(
        'Unexpected error deserializing scene map: $cacheKey',
        e,
        st,
      );
      _db.deleteSceneMapCache(cacheKey);
      _memoryCache.remove(cacheKey);
      return null;
    }
  }

  /// Persists bundle into memory and SQLite cache.
  Future<void> saveBundle(SceneMapBundle bundle, String cacheKey) async {
    _putMemory(cacheKey, bundle);
    _db.saveSceneMapCache(
      cacheKey,
      bundle.metadata.sourceHash,
      bundle.encodeJson(),
    );
  }

  /// Explicitly invalidates a specific cache key.
  Future<void> invalidate(String cacheKey) async {
    _memoryCache.remove(cacheKey);
    _db.deleteSceneMapCache(cacheKey);
  }

  /// Invalidates all cached scene maps associated with a specific source image hash.
  Future<void> invalidateBySourceHash(String sourceHash) async {
    final keysToRemove = <String>[];
    for (final entry in _memoryCache.entries) {
      if (entry.value.metadata.sourceHash == sourceHash) {
        keysToRemove.add(entry.key);
      }
    }
    for (final k in keysToRemove) {
      _memoryCache.remove(k);
    }
    _db.deleteSceneMapCacheBySourceHash(sourceHash);
  }

  /// Clears all memory and persistent scene map caches.
  Future<void> clearAllCache() async {
    _memoryCache.clear();
    _db.clearSceneMapCache();
  }

  void _putMemory(String key, SceneMapBundle bundle) {
    if (_memoryCache.length >= maxMemoryEntries) {
      // Evict oldest entry
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bundle;
  }
}
