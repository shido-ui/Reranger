import 'dart:typed_data';

import '../../domain/recipes/render_graph.dart';

/// In-memory cache holding intermediate raster output buffers keyed by deterministic node cache keys.
/// Enforces downstream invalidation and strict memory bounding via byte-budgeted LRU eviction (DEF-027).
class RenderNodeCache {
  final int maxEntries;
  final int maxSizeBytes;
  final Map<String, Uint8List> _buffers;
  final Map<String, ({int width, int height})> _dimensions;

  int _currentSizeBytes = 0;
  int _hits = 0;
  int _misses = 0;

  /// Default 64 MB maximum cache footprint to prevent Android OOM kills.
  static const int defaultMaxSizeBytes = 64 * 1024 * 1024;

  RenderNodeCache({
    this.maxEntries = 32,
    this.maxSizeBytes = defaultMaxSizeBytes,
  }) : _buffers = {},
       _dimensions = {};

  int get cacheHits => _hits;
  int get cacheMisses => _misses;
  int get cachedEntryCount => _buffers.length;
  int get currentSizeBytes => _currentSizeBytes;

  void resetStatistics() {
    _hits = 0;
    _misses = 0;
  }

  /// Retrieves cached raster buffer if present, updating LRU access order.
  Uint8List? get(String cacheKey) {
    final buffer = _buffers.remove(cacheKey);
    if (buffer != null) {
      _buffers[cacheKey] = buffer; // Move to end (most recently used)
      _hits++;
      return buffer;
    }
    _misses++;
    return null;
  }

  /// Returns dimensions associated with a cached buffer.
  ({int width, int height})? getDimensions(String cacheKey) =>
      _dimensions[cacheKey];

  bool contains(String cacheKey) => _buffers.containsKey(cacheKey);

  /// Caches raster buffer for [cacheKey] and evicts least recently used entries if over capacity.
  void put(String cacheKey, Uint8List buffer, int width, int height) {
    // If key already exists, subtract its prior size
    if (_buffers.containsKey(cacheKey)) {
      _currentSizeBytes -= _buffers[cacheKey]!.lengthInBytes;
      _buffers.remove(cacheKey);
      _dimensions.remove(cacheKey);
    }

    // Evict oldest entries until within entry count and byte size limits
    while (_buffers.isNotEmpty &&
        (_buffers.length >= maxEntries ||
            _currentSizeBytes + buffer.lengthInBytes > maxSizeBytes)) {
      final oldestKey = _buffers.keys.first;
      final evicted = _buffers.remove(oldestKey);
      if (evicted != null) {
        _currentSizeBytes -= evicted.lengthInBytes;
      }
      _dimensions.remove(oldestKey);
    }

    _buffers[cacheKey] = buffer;
    _dimensions[cacheKey] = (width: width, height: height);
    _currentSizeBytes += buffer.lengthInBytes;
  }

  /// Explicitly invalidates a single cache key.
  void invalidate(String cacheKey) {
    final removed = _buffers.remove(cacheKey);
    if (removed != null) {
      _currentSizeBytes -= removed.lengthInBytes;
    }
    _dimensions.remove(cacheKey);
  }

  /// Clears all entries and resets size counter.
  void clear() {
    _buffers.clear();
    _dimensions.clear();
    _currentSizeBytes = 0;
  }

  /// Identifies all downstream dependent nodes of [changedNodeId] in [graph]
  /// and invalidates their cached outputs.
  void invalidateDownstream(
    RenderGraph graph,
    String changedNodeId,
    Map<String, String> nodeCacheKeys,
  ) {
    // 1. Build adjacency list of direct dependents
    final dependents = <String, List<String>>{};
    for (final node in graph.nodes.values) {
      for (final inputId in node.inputNodeIds) {
        dependents.putIfAbsent(inputId, () => []).add(node.id);
      }
    }

    // 2. Breadth-first search for all transitive downstream nodes
    final downstreamIds = <String>{changedNodeId};
    final queue = <String>[changedNodeId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final nextNodes = dependents[current] ?? [];
      for (final next in nextNodes) {
        if (!downstreamIds.contains(next)) {
          downstreamIds.add(next);
          queue.add(next);
        }
      }
    }

    // 3. Invalidate each downstream node's key
    for (final id in downstreamIds) {
      final key = nodeCacheKeys[id];
      if (key != null) {
        invalidate(key);
      }
    }
  }
}
