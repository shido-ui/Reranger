import 'dart:async';
import 'dart:isolate';
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

// -----------------------------------------------------------------------------
// WORKER ISOLATE PROTOCOL (Prompt 2.B.1: Move heavy compute off the UI isolate)
// -----------------------------------------------------------------------------

sealed class _WorkerCommand {}

class _WorkerExecuteCommand extends _WorkerCommand {
  final int requestId;
  final Map<String, dynamic> graphJson;
  final Uint8List sourceImageBytes;
  final double renderScale;
  final SendPort replyPort;

  _WorkerExecuteCommand({
    required this.requestId,
    required this.graphJson,
    required this.sourceImageBytes,
    required this.renderScale,
    required this.replyPort,
  });
}

class _WorkerCancelCommand extends _WorkerCommand {
  final int requestId;
  _WorkerCancelCommand(this.requestId);
}

class _WorkerDisposeCommand extends _WorkerCommand {}

sealed class _WorkerResponse {}

class _WorkerProgressResponse extends _WorkerResponse {
  final int requestId;
  final String nodeId;
  final int index;
  final int total;
  _WorkerProgressResponse(this.requestId, this.nodeId, this.index, this.total);
}

class _WorkerSuccessResponse extends _WorkerResponse {
  final int requestId;
  final Uint8List pixelBytes;
  final int width;
  final int height;
  final Map<String, String> nodeCacheKeys;
  final int totalNodesExecuted;
  final int cacheHits;

  _WorkerSuccessResponse({
    required this.requestId,
    required this.pixelBytes,
    required this.width,
    required this.height,
    required this.nodeCacheKeys,
    required this.totalNodesExecuted,
    required this.cacheHits,
  });
}

class _WorkerCancelledResponse extends _WorkerResponse {
  final int requestId;
  _WorkerCancelledResponse(this.requestId);
}

class _WorkerFailureResponse extends _WorkerResponse {
  final int requestId;
  final String message;
  final String errorType;
  _WorkerFailureResponse(this.requestId, this.message, this.errorType);
}

void _renderWorkerEntryPoint(SendPort mainSendPort) {
  final commandPort = ReceivePort();
  mainSendPort.send(commandPort.sendPort);

  final executor = RenderGraphExecutor(cache: RenderNodeCache());
  int? activeRequestId;
  bool isJobCancelled = false;

  commandPort.listen((message) async {
    if (message is _WorkerCancelCommand) {
      if (activeRequestId == message.requestId) {
        isJobCancelled = true;
      }
    } else if (message is _WorkerDisposeCommand) {
      commandPort.close();
    } else if (message is _WorkerExecuteCommand) {
      activeRequestId = message.requestId;
      isJobCancelled = false;
      final replyPort = message.replyPort;

      try {
        final graph = RenderGraph.fromJson(message.graphJson);
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: message.sourceImageBytes,
          renderScale: message.renderScale,
          isCancelled: () => isJobCancelled,
          onProgress: (nodeId, index, total) {
            if (!isJobCancelled) {
              replyPort.send(
                _WorkerProgressResponse(
                  message.requestId,
                  nodeId,
                  index,
                  total,
                ),
              );
            }
          },
        );

        if (isJobCancelled) {
          replyPort.send(_WorkerCancelledResponse(message.requestId));
        } else {
          replyPort.send(
            _WorkerSuccessResponse(
              requestId: message.requestId,
              pixelBytes: result.pixelBytes,
              width: result.width,
              height: result.height,
              nodeCacheKeys: result.nodeCacheKeys,
              totalNodesExecuted: result.totalNodesExecuted,
              cacheHits: result.cacheHits,
            ),
          );
        }
      } on RenderGraphCancelledFailure {
        replyPort.send(_WorkerCancelledResponse(message.requestId));
      } catch (e) {
        replyPort.send(
          _WorkerFailureResponse(
            message.requestId,
            e.toString(),
            e.runtimeType.toString(),
          ),
        );
      } finally {
        activeRequestId = null;
      }
    }
  });
}

/// Render Job Controller coordinating render requests with:
/// 1. Latest-Request-Wins: Rapid slider changes cancel or supersede prior in-flight renders.
/// 2. Stale-Result Protection: Older slow renders finishing out of order are discarded and NEVER overwrite a newer preview.
/// 3. Serialized Mutex: Ensures non-thread-safe pixel and model buffers are executed sequentially.
/// 4. Truthful Progress Reporting: Emits observable discrete node progress via [stateStream].
/// 5. Non-Blocking Isolate Execution: Optionally routes raster processing off the UI isolate.
class RenderJobController {
  final RenderGraphExecutor executor;
  final StreamController<RenderJobState> _stateController;
  final bool useWorkerIsolate;

  int _latestRequestId = 0;
  CancellationToken? _activeCancellationToken;
  Completer<void>? _mutexLock;

  // Background Isolate state
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  Completer<void>? _workerReadyCompleter;

  int _staleResultsDiscarded = 0;
  int get staleResultsDiscardedCount => _staleResultsDiscarded;
  int get latestRequestId => _latestRequestId;

  RenderJobController({
    RenderGraphExecutor? executor,
    this.useWorkerIsolate = false,
  }) : executor = executor ?? RenderGraphExecutor(cache: RenderNodeCache()),
       _stateController = StreamController<RenderJobState>.broadcast();

  Stream<RenderJobState> get stateStream => _stateController.stream;

  void _safeEmit(RenderJobState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  Future<void> _ensureWorkerStarted() async {
    if (!useWorkerIsolate) return;
    if (_workerSendPort != null) return;
    if (_workerReadyCompleter != null) {
      return _workerReadyCompleter!.future;
    }

    final completer = Completer<void>();
    _workerReadyCompleter = completer;

    final initPort = ReceivePort();
    _workerIsolate = await Isolate.spawn(
      _renderWorkerEntryPoint,
      initPort.sendPort,
    );

    initPort.listen((message) {
      if (message is SendPort) {
        _workerSendPort = message;
        initPort.close();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    return completer.future;
  }

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

    if (useWorkerIsolate && _workerSendPort != null) {
      _workerSendPort!.send(_WorkerCancelCommand(assignedRequestId - 1));
    }

    _safeEmit(
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
      _safeEmit(RenderJobCancelled(assignedRequestId));
      return null;
    }

    final localCompleter = Completer<void>();
    _mutexLock = localCompleter;

    try {
      RenderExecutionResult? result;

      if (useWorkerIsolate) {
        await _ensureWorkerStarted();
        result = await _executeOnWorker(
          assignedRequestId: assignedRequestId,
          graph: graph,
          sourceImageBytes: sourceImageBytes,
          renderScale: renderScale,
          currentToken: currentToken,
        );
      } else {
        result = await executor.execute(
          graph: graph,
          sourceImageBytes: sourceImageBytes,
          renderScale: renderScale,
          isCancelled: () =>
              currentToken.isCancelled || assignedRequestId < _latestRequestId,
          onProgress: (nodeId, index, total) {
            if (assignedRequestId == _latestRequestId &&
                !currentToken.isCancelled) {
              _safeEmit(
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
      }

      // 4. Stale-Result Guard: Strictly ensure request is still latest before committing output
      if (assignedRequestId < _latestRequestId || currentToken.isCancelled) {
        _staleResultsDiscarded++;
        AppLogger.info(
          'Render request #$assignedRequestId discarded as stale (current latest is #$_latestRequestId)',
        );
        _safeEmit(RenderJobCancelled(assignedRequestId));
        return null;
      }

      if (result != null) {
        _safeEmit(
          RenderJobCompleted(requestId: assignedRequestId, result: result),
        );
      }
      return result;
    } on RenderGraphCancelledFailure {
      _staleResultsDiscarded++;
      _safeEmit(RenderJobCancelled(assignedRequestId));
      return null;
    } catch (e, st) {
      if (assignedRequestId == _latestRequestId) {
        AppLogger.error('Render request #$assignedRequestId failed', e, st);
        _safeEmit(RenderJobFailed(assignedRequestId, e.toString()));
      }
      rethrow;
    } finally {
      if (!localCompleter.isCompleted) {
        localCompleter.complete();
      }
    }
  }

  Future<RenderExecutionResult?> _executeOnWorker({
    required int assignedRequestId,
    required RenderGraph graph,
    required Uint8List sourceImageBytes,
    required double renderScale,
    required CancellationToken currentToken,
  }) async {
    final replyPort = ReceivePort();
    final completer = Completer<RenderExecutionResult?>();

    late StreamSubscription sub;
    sub = replyPort.listen((response) {
      if (response is _WorkerProgressResponse) {
        if (assignedRequestId == _latestRequestId &&
            !currentToken.isCancelled) {
          _safeEmit(
            RenderJobExecuting(
              requestId: assignedRequestId,
              activeNodeId: response.nodeId,
              completedNodes: response.index,
              totalNodes: response.total,
              progress: (response.index / response.total).clamp(0.0, 1.0),
            ),
          );
        }
      } else if (response is _WorkerCancelledResponse) {
        sub.cancel();
        replyPort.close();
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      } else if (response is _WorkerSuccessResponse) {
        sub.cancel();
        replyPort.close();
        final execResult = RenderExecutionResult(
          pixelBytes: response.pixelBytes,
          width: response.width,
          height: response.height,
          nodeCacheKeys: response.nodeCacheKeys,
          totalNodesExecuted: response.totalNodesExecuted,
          cacheHits: response.cacheHits,
        );
        if (!completer.isCompleted) {
          completer.complete(execResult);
        }
      } else if (response is _WorkerFailureResponse) {
        sub.cancel();
        replyPort.close();
        if (!completer.isCompleted) {
          if (response.errorType == 'RenderInvalidParametersFailure' ||
              response.message.contains('Invalid parameter')) {
            completer.completeError(
              RenderInvalidParametersFailure(
                nodeId: 'worker_node',
                parameterName: 'parameter',
                actualValue: 'invalid',
                expectedCriteria: response.message,
              ),
            );
          } else if (response.errorType == 'RenderSourceIntegrityFailure' ||
              response.message.contains('Source image integrity failure')) {
            completer.completeError(
              RenderSourceIntegrityFailure(declaredHash: '', actualHash: ''),
            );
          } else if (response.errorType == 'RenderMemoryLimitFailure' ||
              response.message.contains('exceeds allocated budget')) {
            completer.completeError(RenderMemoryLimitFailure(0, 0));
          } else {
            completer.completeError(
              RenderNodeExecutionFailure('root', 'worker', response.message),
            );
          }
        }
      }
    });

    _workerSendPort!.send(
      _WorkerExecuteCommand(
        requestId: assignedRequestId,
        graphJson: graph.toJson(),
        sourceImageBytes: sourceImageBytes,
        renderScale: renderScale,
        replyPort: replyPort.sendPort,
      ),
    );

    return completer.future;
  }

  /// Visibly cancels the current running render job.
  void cancelCurrentJob() {
    _activeCancellationToken?.cancel();
    if (useWorkerIsolate && _workerSendPort != null) {
      _workerSendPort!.send(_WorkerCancelCommand(_latestRequestId));
    }
    _safeEmit(RenderJobCancelled(_latestRequestId));
  }

  /// Disposes resources cleanly.
  void dispose() {
    _activeCancellationToken?.cancel();
    if (_mutexLock != null && !_mutexLock!.isCompleted) {
      _mutexLock!.complete();
    }
    if (useWorkerIsolate) {
      _workerSendPort?.send(_WorkerDisposeCommand());
      _workerIsolate?.kill(priority: Isolate.immediate);
      _workerIsolate = null;
      _workerSendPort = null;
    }
    _stateController.close();
  }
}
