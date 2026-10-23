/// Sealed hierarchy of typed domain failures for the Render Pipeline and Render Graph.
sealed class RenderPipelineFailure implements Exception {
  final String message;
  final String? technicalDetails;

  const RenderPipelineFailure(this.message, [this.technicalDetails]);

  @override
  String toString() =>
      'RenderPipelineFailure: $message${technicalDetails != null ? ' ($technicalDetails)' : ''}';
}

/// Thrown when a cycle is detected during DAG topological sorting.
class RenderGraphCycleFailure extends RenderPipelineFailure {
  final List<String> cycleNodeIds;
  RenderGraphCycleFailure(this.cycleNodeIds)
    : super(
        'Cyclic dependency detected in render graph: ${cycleNodeIds.join(' -> ')}',
      );
}

/// Thrown when a node requires an input node ID that does not exist in the graph.
class RenderGraphMissingInputFailure extends RenderPipelineFailure {
  final String nodeId;
  final String missingInputId;
  const RenderGraphMissingInputFailure(this.nodeId, this.missingInputId)
    : super(
        'Node "$nodeId" requires missing upstream input node "$missingInputId"',
      );
}

/// Thrown when execution is cancelled by a newer request or explicit user action.
class RenderGraphCancelledFailure extends RenderPipelineFailure {
  final String jobId;
  const RenderGraphCancelledFailure(this.jobId)
    : super('Render job "$jobId" was cancelled before completion.');
}

/// Thrown when a completed background render job has been superseded by a newer request.
class RenderStaleResultFailure extends RenderPipelineFailure {
  final int completedRequestId;
  final int currentActiveRequestId;
  const RenderStaleResultFailure(
    this.completedRequestId,
    this.currentActiveRequestId,
  ) : super(
        'Render result from request #$completedRequestId discarded as stale (current active is #$currentActiveRequestId)',
      );
}

/// Thrown when a node receives parameters outside valid mathematical bounds.
class RenderInvalidParametersFailure extends RenderPipelineFailure {
  final String nodeId;
  final String parameterName;
  final dynamic actualValue;
  final String expectedCriteria;

  const RenderInvalidParametersFailure({
    required this.nodeId,
    required this.parameterName,
    required this.actualValue,
    required this.expectedCriteria,
  }) : super(
         'Invalid parameter "$parameterName" on node "$nodeId": received $actualValue, expected $expectedCriteria',
       );
}

/// Thrown when the estimated memory required to execute the graph exceeds available headroom (Invariant 11).
class RenderMemoryLimitFailure extends RenderPipelineFailure {
  final int estimatedBytes;
  final int maxBudgetBytes;
  const RenderMemoryLimitFailure(this.estimatedBytes, this.maxBudgetBytes)
    : super(
        'Estimated render memory ($estimatedBytes bytes) exceeds allocated budget ($maxBudgetBytes bytes)',
      );
}

/// Thrown when an individual node fails during pixel processing.
class RenderNodeExecutionFailure extends RenderPipelineFailure {
  final String nodeId;
  final String nodeType;
  const RenderNodeExecutionFailure(
    this.nodeId,
    this.nodeType,
    String reason, [
    String? details,
  ]) : super('Node "$nodeId" ($nodeType) failed: $reason', details);
}
