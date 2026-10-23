import 'dart:async';
import 'dart:typed_data';

import '../../core/logging/app_logger.dart';
import '../../domain/recipes/render_graph.dart';
import '../../domain/recipes/render_pipeline_failure.dart';
import 'render_graph_executor.dart';
import 'render_node_cache.dart';

/// Concrete truthful states of a render job.
/// Zero fake progress or mock percentage counters (Invariant 7).
sealed class RenderJobState {
  const RenderJobState();
}

class RenderJobIdle extends RenderJobState {
  const RenderJobIdle();
}

class RenderJobExecuting extends RenderJobState {
  final int requestId;
  final String activeNodeId;
  final int completedNodes;
  final int totalNodes;
  final double
  progress; // In [0.0, 1.0] based strictly on completed / total nodes

  const RenderJobExecuting({
    required this.requestId,
    required this.activeNodeId,
    required this.completedNodes,
    required this.totalNodes,
    required this.progress,
  });

  @override
  String toString() =>
      'RenderJobExecuting(#$requestId, node: $activeNodeId, $completedNodes/$totalNodes)';
}

class RenderJobCompleted extends RenderJobState {
  final int requestId;
  final RenderExecutionResult result;

  const RenderJobCompleted({required this.requestId, required this.result});

  @override
  String toString() =>
      'RenderJobCompleted(#$requestId, ${result.width}x${result.height})';
}

class RenderJobCancelled extends RenderJobState {
  final int requestId;
  const RenderJobCancelled(this.requestId);

  @override
  String toString() => 'RenderJobCancelled(#$requestId)';
}

class RenderJobFailed extends RenderJobState {
  final int requestId;
  final String errorMessage;
  const RenderJobFailed(this.requestId, this.errorMessage);

  @override
  String toString() => 'RenderJobFailed(#$requestId, error: $errorMessage)';
}

/// Cooperative cancellation token.
class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// Render Job Controller coordinating render requests with:
/// 1. Latest-Request-Wins: Rapid slider changes cancel or supersede prior in-flight renders.
/// 2. Stale-Result Protection: Older slow renders finishing out of order are discarded and NEVER overwrite a newer preview.
/// 3. Serialized Mutex: Ensures non-thread-safe pixel and model buffers are executed sequentially.
/// 4. Truthful Progress Reporting: Emits observable discrete node progress via [stateStream].
class RenderJobController {
  final RenderGraphExecutor executor;
  final StreamController<RenderJobState> _stateController;

  int _latestRequestId = 0;
  CancellationToken? _activeCancellationToken;
  Completer<void>? _mutexLock;

  int _staleResultsDiscarded = 0;
  int get staleResultsDiscardedCount => _staleResultsDiscarded;
  int get latestRequestId => _latestRequestId;

  RenderJobController({RenderGraphExecutor? executor})
    : executor = executor ?? RenderGraphExecutor(cache: RenderNodeCache()),
      _stateController = StreamController<RenderJobState>.broadcast();

  Stream<RenderJobState> get stateStream => _stateController.stream;

  /// Submits a render request.
  /// Automatically cancels active previous jobs and guarantees that stale out-of-order completions are dropped.
  Future<RenderExecutionResult?> submitRenderRequest({
    required RenderGraph graph,
    required Uint8List sourceImageBytes,
    double renderScale = 1.0,
  }) async {
    // 1. Monotonically increment request ID (Latest-Request-Wins)
    _latestRequestId++;
    final assignedRequestId = _latestRequestId;

    // 2. Signal cancellation to prior active job
    _activeCancellationToken?.cancel();
    final currentToken = CancellationToken();
    _activeCancellationToken = currentToken;

    _stateController.add(
      RenderJobExecuting(
        requestId: assignedRequestId,
        activeNodeId: 'init',
        completedNodes: 0,
        totalNodes: graph.nodes.length,
        progress: 0.0,
      ),
    );

    // 3. Serialized Mutex: Wait for preceding render execution to vacate shared buffers
    while (_mutexLock != null && !_mutexLock!.isCompleted) {
      try {
        await _mutexLock!.future;
      } catch (_) {
        // Preceding failure does not block subsequent renders
      }
    }

    // Check if this request was already superseded while waiting for mutex
    if (assignedRequestId < _latestRequestId || currentToken.isCancelled) {
      _staleResultsDiscarded++;
      _stateController.add(RenderJobCancelled(assignedRequestId));
      return null;
    }

    final localCompleter = Completer<void>();
    _mutexLock = localCompleter;

    try {
      final result = await executor.execute(
        graph: graph,
        sourceImageBytes: sourceImageBytes,
        renderScale: renderScale,
        isCancelled: () =>
            currentToken.isCancelled || assignedRequestId < _latestRequestId,
        onProgress: (nodeId, index, total) {
          if (assignedRequestId == _latestRequestId &&
              !currentToken.isCancelled) {
            _stateController.add(
              RenderJobExecuting(
                requestId: assignedRequestId,
                activeNodeId: nodeId,
                completedNodes: index,
                totalNodes: total,
                progress: (index / total).clamp(0.0, 1.0),
              ),
            );
          }
        },
      );

      // 4. Stale-Result Guard: Strictly ensure request is still latest before committing output
      if (assignedRequestId < _latestRequestId || currentToken.isCancelled) {
        _staleResultsDiscarded++;
        AppLogger.info(
          'Render request #$assignedRequestId discarded as stale (current latest is #$_latestRequestId)',
        );
        _stateController.add(RenderJobCancelled(assignedRequestId));
        return null;
      }

      _stateController.add(
        RenderJobCompleted(requestId: assignedRequestId, result: result),
      );
      return result;
    } on RenderGraphCancelledFailure {
      _stateController.add(RenderJobCancelled(assignedRequestId));
      return null;
    } catch (e, st) {
      if (assignedRequestId == _latestRequestId) {
        AppLogger.error('Render request #$assignedRequestId failed', e, st);
        _stateController.add(RenderJobFailed(assignedRequestId, e.toString()));
      }
      rethrow;
    } finally {
      if (!localCompleter.isCompleted) {
        localCompleter.complete();
      }
    }
  }

  /// Visibly cancels the current running render job.
  void cancelCurrentJob() {
    _activeCancellationToken?.cancel();
    _stateController.add(RenderJobCancelled(_latestRequestId));
  }

  /// Disposes resources cleanly.
  void dispose() {
    _activeCancellationToken?.cancel();
    _stateController.close();
  }
}
