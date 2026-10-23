/// Base sealed class for all Scene Map and Analysis Bundle domain failures.
sealed class SceneMapFailure implements Exception {
  final String message;
  final String? technicalDetails;

  const SceneMapFailure(this.message, [this.technicalDetails]);

  @override
  String toString() =>
      'SceneMapFailure: $message${technicalDetails != null ? ' ($technicalDetails)' : ''}';
}

/// Thrown when the analysis operation is explicitly cancelled by the user.
class SceneMapCancellationFailure extends SceneMapFailure {
  const SceneMapCancellationFailure([
    super.message = 'Scene map analysis cancelled by user.',
  ]);
}

/// Thrown when cached analysis JSON fails validation or has missing required keys.
class SceneMapCorruptCacheFailure extends SceneMapFailure {
  final String cacheKey;
  const SceneMapCorruptCacheFailure(this.cacheKey, [String? technicalDetails])
    : super(
        'Corrupted or unreadable scene map cache entry: $cacheKey',
        technicalDetails,
      );
}

/// Thrown when coordinates or bounding boxes fall outside finite normalized [0.0, 1.0] bounds.
class SceneMapInvalidCoordinatesFailure extends SceneMapFailure {
  final double x;
  final double y;
  const SceneMapInvalidCoordinatesFailure(this.x, this.y)
    : super(
        'Invalid spatial coordinates: ($x, $y) outside normalized [0.0, 1.0]',
      );
}

/// Thrown when image buffer or byte payload is unrecognized or unsupported.
class SceneMapUnsupportedFormatFailure extends SceneMapFailure {
  const SceneMapUnsupportedFormatFailure([
    super.message = 'Unsupported image format for scene analysis',
  ]);
}

/// Thrown when allocating analysis buffers exceeds runtime memory budget (Invariant 11).
class SceneMapMemoryBudgetFailure extends SceneMapFailure {
  final int requestedBytes;
  final int maxAllowedBytes;
  const SceneMapMemoryBudgetFailure(this.requestedBytes, this.maxAllowedBytes)
    : super(
        'Scene map memory budget exceeded: requested $requestedBytes bytes, limit is $maxAllowedBytes bytes',
      );
}
