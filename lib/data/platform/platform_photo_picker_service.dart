import 'package:flutter/services.dart';

import '../../domain/import/image_picker_service.dart';

/// Concrete platform implementation of [ImagePickerService] utilizing
/// Android's system photo picker through [MethodChannel].
/// Strictly offline-first with zero external cloud or storage permissions (Invariants 5 & 6).
class PlatformPhotoPickerService implements ImagePickerService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.reranger.app/photo_picker',
  );

  final MethodChannel _channel;

  const PlatformPhotoPickerService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  @override
  Future<ImagePickResult> pickImage() async {
    try {
      final String? path = await _channel.invokeMethod<String>('pickImage');
      if (path == null || path.trim().isEmpty) {
        return const ImagePickCancelled();
      }
      return ImagePickSuccess(path);
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        return ImagePickPermissionDenied(e.message);
      }
      if (e.code == 'CANCELLED') {
        return const ImagePickCancelled();
      }
      return ImagePickFailure(e.message ?? 'Unknown platform picker error');
    } on MissingPluginException {
      return const ImagePickFailure(
        'Platform photo picker channel is not registered on this device platform.',
      );
    } catch (e) {
      return ImagePickFailure(e.toString());
    }
  }
}
