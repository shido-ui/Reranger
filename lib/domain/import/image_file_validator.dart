import 'dart:io';
import 'dart:typed_data';

/// Supported image formats for Reranger import pipeline.
enum SupportedImageFormat { jpeg, png, webp }

/// Domain failures for image format validation.
sealed class ImageValidationFailure implements Exception {
  final String message;
  const ImageValidationFailure(this.message);

  @override
  String toString() => message;
}

class FileNotFoundValidationFailure extends ImageValidationFailure {
  final String path;
  const FileNotFoundValidationFailure(this.path)
    : super('Source image file not found at: $path');
}

class EmptyFileValidationFailure extends ImageValidationFailure {
  const EmptyFileValidationFailure([
    super.message = 'Source image file is empty (0 bytes).',
  ]);
}

class CorruptHeaderValidationFailure extends ImageValidationFailure {
  const CorruptHeaderValidationFailure([
    super.message = 'Corrupt or incomplete image file header.',
  ]);
}

class UnsupportedFormatValidationFailure extends ImageValidationFailure {
  final String? detectedFormat;
  const UnsupportedFormatValidationFailure({
    this.detectedFormat,
    String? message,
  }) : super(
         message ??
             'Unsupported image format: ${detectedFormat ?? "Unknown"}. Reranger supports JPEG, PNG, and WebP.',
       );
}

/// Validates image header magic bytes for strict local offline import.
class ImageFileValidator {
  const ImageFileValidator();

  /// Maximum header bytes needed to detect format (12 bytes for RIFF/WEBP).
  static const int minHeaderBytes = 12;

  /// Magic byte signatures
  static final List<int> _pngSignature = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
  static final List<int> _jpegSignature = [0xFF, 0xD8, 0xFF];
  static final List<int> _riffSignature = [0x52, 0x49, 0x46, 0x46]; // "RIFF"
  static final List<int> _webpSignature = [0x57, 0x45, 0x42, 0x50]; // "WEBP"

  // Common unsupported signatures for explicit diagnostics
  static final List<int> _gifSignature = [0x47, 0x49, 0x46]; // "GIF"
  static final List<int> _bmpSignature = [0x42, 0x4D]; // "BM"
  static final List<int> _tiffLeSignature = [0x49, 0x49, 0x2A, 0x00];
  static final List<int> _tiffBeSignature = [0x4D, 0x4D, 0x00, 0x2A];

  /// Validates a file on disk by reading its initial header bytes.
  Future<SupportedImageFormat> validateFile(File file) async {
    if (!await file.exists()) {
      throw FileNotFoundValidationFailure(file.path);
    }

    final length = await file.length();
    if (length == 0) {
      throw const EmptyFileValidationFailure();
    }

    if (length < minHeaderBytes) {
      throw const CorruptHeaderValidationFailure(
        'File size is smaller than standard image header threshold.',
      );
    }

    // Read only the first 32 bytes to avoid memory overhead on large 12+ MP files
    final raf = await file.open(mode: FileMode.read);
    try {
      final header = await raf.read(32);
      return validateHeaderBytes(header);
    } finally {
      await raf.close();
    }
  }

  /// Validates in-memory header bytes.
  SupportedImageFormat validateHeaderBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const EmptyFileValidationFailure();
    }

    if (bytes.length < minHeaderBytes) {
      throw const CorruptHeaderValidationFailure();
    }

    // Check PNG: 8 bytes
    if (_matchesPrefix(bytes, _pngSignature)) {
      return SupportedImageFormat.png;
    }

    // Check JPEG: starts with 0xFF, 0xD8, 0xFF
    if (_matchesPrefix(bytes, _jpegSignature)) {
      return SupportedImageFormat.jpeg;
    }

    // Check WebP: bytes 0..3 == "RIFF" and bytes 8..11 == "WEBP"
    if (_matchesPrefix(bytes, _riffSignature) &&
        _matchesAt(bytes, _webpSignature, 8)) {
      return SupportedImageFormat.webp;
    }

    // Explicit detection of unsupported formats to provide helpful user guidance
    if (_matchesPrefix(bytes, _gifSignature)) {
      throw const UnsupportedFormatValidationFailure(
        detectedFormat: 'GIF',
        message: 'GIF animation/images are not supported. Please import a JPEG, PNG, or WebP.',
      );
    }

    if (_matchesPrefix(bytes, _bmpSignature)) {
      throw const UnsupportedFormatValidationFailure(
        detectedFormat: 'BMP',
        message: 'BMP format is not supported for production import. Please import a JPEG, PNG, or WebP.',
      );
    }

    if (_matchesPrefix(bytes, _tiffLeSignature) ||
        _matchesPrefix(bytes, _tiffBeSignature)) {
      throw const UnsupportedFormatValidationFailure(
        detectedFormat: 'TIFF',
        message: 'TIFF format is not supported. Please convert to PNG or JPEG before import.',
      );
    }

    throw const UnsupportedFormatValidationFailure(
      detectedFormat: 'Unknown / Binary',
      message: 'Unrecognized image file format. Only JPEG, PNG, and WebP are supported.',
    );
  }

  bool _matchesPrefix(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  bool _matchesAt(Uint8List bytes, List<int> target, int offset) {
    if (bytes.length < offset + target.length) return false;
    for (var i = 0; i < target.length; i++) {
      if (bytes[offset + i] != target[i]) return false;
    }
    return true;
  }
}
