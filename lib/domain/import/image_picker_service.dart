/// Result of an image pick operation from platform photo picker.
sealed class ImagePickResult {
  const ImagePickResult();
}

/// User selected an image successfully.
class ImagePickSuccess extends ImagePickResult {
  final String path;
  const ImagePickSuccess(this.path);

  @override
  String toString() => 'ImagePickSuccess(path: $path)';
}

/// User explicitly cancelled the photo picker or backed out.
class ImagePickCancelled extends ImagePickResult {
  const ImagePickCancelled();

  @override
  String toString() => 'ImagePickCancelled()';
}

/// System or user denied photo picker / media access.
class ImagePickPermissionDenied extends ImagePickResult {
  final String? message;
  const ImagePickPermissionDenied([this.message]);

  @override
  String toString() => 'ImagePickPermissionDenied(message: $message)';
}

/// System or unexpected error occurred while picking image.
class ImagePickFailure extends ImagePickResult {
  final String error;
  const ImagePickFailure(this.error);

  @override
  String toString() => 'ImagePickFailure(error: $error)';
}

/// Clean Architecture Port for local on-device image selection.
/// Does NOT request broad storage permissions (Invariant 6).
abstract class ImagePickerService {
  Future<ImagePickResult> pickImage();
}
