import 'dart:convert';
import 'dart:typed_data';

/// A single resolution scale level in the image analysis pyramid.
/// Level 0: Primary preview scale (e.g. ~512 max dimension, scale 1.0)
/// Level 1: Half scale (e.g. ~256 max dimension, scale 0.5)
/// Level 2: Quarter scale (e.g. ~128 max dimension, scale 0.25)
///
/// Stores downsampled BT.601 luminance grid to prevent duplicate full-res allocations (Invariant 11).
class PyramidLevel {
  final int level;
  final int width;
  final int height;
  final double scaleFactor;
  final Uint8List luminanceData;

  const PyramidLevel({
    required this.level,
    required this.width,
    required this.height,
    required this.scaleFactor,
    required this.luminanceData,
  }) : assert(level >= 0, 'Level must be non-negative'),
       assert(width > 0 && height > 0, 'Dimensions must be positive'),
       assert(
         scaleFactor > 0.0 && scaleFactor <= 1.0,
         'Scale factor must be (0.0, 1.0]',
       ),
       assert(
         luminanceData.length == width * height,
         'Luminance buffer size (${luminanceData.length}) must equal width*height (${width * height})',
       );

  /// Retrieves the luminance byte at integer coordinate (x, y). Clamps safely at edges.
  int getLuminance(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    return luminanceData[cy * width + cx];
  }

  Map<String, dynamic> toJson() => {
    'level': level,
    'width': width,
    'height': height,
    'scaleFactor': scaleFactor,
    'luminanceBase64': base64Encode(luminanceData),
  };

  factory PyramidLevel.fromJson(Map<String, dynamic> json) {
    final w = json['width'] as int;
    final h = json['height'] as int;
    final bytes = base64Decode(json['luminanceBase64'] as String);
    return PyramidLevel(
      level: json['level'] as int,
      width: w,
      height: h,
      scaleFactor: (json['scaleFactor'] as num).toDouble(),
      luminanceData: Uint8List.fromList(bytes),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PyramidLevel &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          width == other.width &&
          height == other.height &&
          (scaleFactor - other.scaleFactor).abs() < 1e-6 &&
          _bytesEqual(luminanceData, other.luminanceData);

  @override
  int get hashCode => Object.hash(level, width, height, scaleFactor);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
