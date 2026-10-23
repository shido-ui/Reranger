import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Service abstraction for native OS image saving (MediaStore on Android)
/// and system share sheet invocation (DEF-025).
abstract interface class PlatformMediaService {
  /// Saves an image file to user-visible device gallery or Pictures storage.
  Future<String> saveImageToGallery({
    required String filePath,
    required String title,
    required String mimeType,
  });

  /// Invokes the native operating system share sheet with [filePath].
  Future<void> shareImage({
    required String filePath,
    required String mimeType,
    String? subject,
  });
}

class MethodChannelPlatformMediaService implements PlatformMediaService {
  static const MethodChannel _channel = MethodChannel('com.reranger.app/media');

  const MethodChannelPlatformMediaService();

  @override
  Future<String> saveImageToGallery({
    required String filePath,
    required String title,
    required String mimeType,
  }) async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'saveImageToGallery',
        {'filePath': filePath, 'title': title, 'mimeType': mimeType},
      );
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (_) {
      // Platform channel unavailable or non-Android environment
    }

    // Fallback for desktop/linux/test: copy to ~/Pictures/Reranger/
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final picturesDir = Directory(p.join(home, 'Pictures', 'Reranger'));
      if (!picturesDir.existsSync()) {
        try {
          picturesDir.createSync(recursive: true);
        } catch (_) {}
      }
      if (picturesDir.existsSync()) {
        final dest = File(p.join(picturesDir.path, p.basename(filePath)));
        await File(filePath).copy(dest.path);
        return dest.path;
      }
    }

    return filePath;
  }

  @override
  Future<void> shareImage({
    required String filePath,
    required String mimeType,
    String? subject,
  }) async {
    try {
      await _channel.invokeMethod<void>('shareImage', {
        'filePath': filePath,
        'mimeType': mimeType,
        'subject': subject ?? 'Share Transformed Image',
      });
    } catch (_) {
      // Platform channel unavailable
    }
  }
}
