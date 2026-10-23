import 'dart:convert';

import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// Versioned Directed Acyclic Graph (DAG) describing a non-destructive render pipeline.
/// Guarantees:
/// - Acyclicity: Cycles are detected and rejected.
/// - Dependency integrity: All input nodes must exist.
/// - Deterministic execution order: Evaluates in strict topological sort.
/// - Lossless JSON serialization for recipes and project persistence.
class RenderGraph {
  final String id;
  final int version;
  final Map<String, RenderGraphNode> nodes;
  final String outputNodeId;

  const RenderGraph({
    required this.id,
    this.version = 1,
    required this.nodes,
    required this.outputNodeId,
  }) : assert(id.length > 0, 'Graph ID cannot be empty'),
       assert(nodes.length > 0, 'Graph must contain at least 1 node');

  /// Validates node parameters, dependency completeness, and DAG acyclicity.
  void validate() {
    if (!nodes.containsKey(outputNodeId)) {
      throw RenderGraphMissingInputFailure(
        'root',
        'Output node "$outputNodeId" is not registered in graph.',
      );
    }

    for (final node in nodes.values) {
      node.validate();
      for (final inputId in node.inputNodeIds) {
        if (!nodes.containsKey(inputId)) {
          throw RenderGraphMissingInputFailure(node.id, inputId);
        }
      }
    }

    // Topological sort detects cycles and verifies dependency order
    getTopologicalExecutionOrder();
  }

  /// Computes a deterministic topological order for graph evaluation using Kahn's algorithm.
  /// Throws [RenderGraphCycleFailure] if a cycle is detected.
  List<RenderGraphNode> getTopologicalExecutionOrder() {
    // 1. Calculate in-degrees and build adjacency lists
    final inDegree = <String, int>{};
    final adjacency = <String, List<String>>{};

    for (final nodeId in nodes.keys) {
      inDegree[nodeId] = 0;
      adjacency[nodeId] = [];
    }

    for (final node in nodes.values) {
      inDegree[node.id] = node.inputNodeIds.length;
      for (final inId in node.inputNodeIds) {
        adjacency[inId]?.add(node.id);
      }
    }

    // 2. Queue nodes with 0 dependencies (roots/sources)
    final queue = <String>[];
    for (final entry in inDegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    // Sort initial queue alphabetically for deterministic tie-breaking
    queue.sort();

    final result = <RenderGraphNode>[];

    while (queue.isNotEmpty) {
      final currId = queue.removeAt(0);
      result.add(nodes[currId]!);

      final neighbors = adjacency[currId] ?? [];
      for (final neighbor in neighbors) {
        inDegree[neighbor] = inDegree[neighbor]! - 1;
        if (inDegree[neighbor] == 0) {
          queue.add(neighbor);
        }
      }
      queue.sort(); // Maintain deterministic order
    }

    if (result.length != nodes.length) {
      // Cycle detected
      final unresolved = inDegree.entries
          .where((e) => e.value > 0)
          .map((e) => e.key)
          .toList();
      throw RenderGraphCycleFailure(unresolved);
    }

    return result;
  }

  /// Estimates the peak memory budget in bytes needed to execute the graph (Invariant 11).
  int estimatePeakMemoryBytes(int width, int height) {
    int maxBuffer = 0;
    for (final node in nodes.values) {
      final bytes = node.estimateMemoryBytes(width, height);
      if (bytes > maxBuffer) {
        maxBuffer = bytes;
      }
    }
    // Budget assumption: at most 2 active 32-bit pixel buffers (source + target) concurrently
    return maxBuffer * 2;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'outputNodeId': outputNodeId,
    'nodes': nodes.map((key, value) => MapEntry(key, value.toJson())),
  };

  String encodeJson() => jsonEncode(toJson());

  factory RenderGraph.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'] as Map<String, dynamic>;
    final parsedNodes = <String, RenderGraphNode>{};
    for (final entry in rawNodes.entries) {
      parsedNodes[entry.key] = RenderGraphNode.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    return RenderGraph(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      nodes: parsedNodes,
      outputNodeId: json['outputNodeId'] as String,
    );
  }

  factory RenderGraph.decodeJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return RenderGraph.fromJson(map);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderGraph &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version &&
          outputNodeId == other.outputNodeId &&
          _nodesEqual(nodes, other.nodes);

  @override
  int get hashCode => Object.hash(id, version, outputNodeId, nodes.length);

  static bool _nodesEqual(
    Map<String, RenderGraphNode> a,
    Map<String, RenderGraphNode> b,
  ) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
