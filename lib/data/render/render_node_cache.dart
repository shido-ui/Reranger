import 'dart:typed_data';

import '../../domain/recipes/render_graph.dart';

/// In-memory cache holding intermediate raster output buffers keyed by deterministic node cache keys.
/// Enforces downstream invalidation: when an upstream node's parameters or source hash changes,
/// all dependent downstream nodes are automatically invalidated, while independent sibling nodes remain cached.
class RenderNodeCache {
  final int maxEntries;
  final Map<String, Uint8List> _buffers;
  final Map<String, ({int width, int height})> _dimensions;

  int _hits = 0;
  int _misses = 0;

  RenderNodeCache({this.maxEntries = 32}) : _buffers = {}, _dimensions = {};

  int get cacheHits => _hits;
  int get cacheMisses => _misses;
  int get cachedEntryCount => _buffers.length;

  void resetStatistics() {
    _hits = 0;
    _misses = 0;
  }

  /// Retrieves cached raster buffer if present.
  Uint8List? get(String cacheKey) {
    final buffer = _buffers[cacheKey];
    if (buffer != null) {
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

  /// Caches raster buffer for [cacheKey].
  void put(String cacheKey, Uint8List buffer, int width, int height) {
    if (_buffers.length >= maxEntries && !_buffers.containsKey(cacheKey)) {
      // Evict oldest entry
      final oldestKey = _buffers.keys.first;
      _buffers.remove(oldestKey);
      _dimensions.remove(oldestKey);
    }
    _buffers[cacheKey] = buffer;
    _dimensions[cacheKey] = (width: width, height: height);
  }

  /// Explicitly invalidates a single cache key.
  void invalidate(String cacheKey) {
    _buffers.remove(cacheKey);
    _dimensions.remove(cacheKey);
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

  /// Clears all cached buffers.
  void clear() {
    _buffers.clear();
    _dimensions.clear();
    resetStatistics();
  }
}
