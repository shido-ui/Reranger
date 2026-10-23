import 'dart:convert';
import 'dart:typed_data';

/// Edge map data representing downscaled 2D gradient magnitude landscape.
/// Generated via 3x3 Sobel operator convolution on BT.601 luminance.
class EdgeMapData {
  final int gridWidth;
  final int gridHeight;
  final int edgeThreshold;
  final double edgeDensity; // Fraction in [0.0, 1.0] exceeding edgeThreshold
  final int highGradientPixelCount;
  final Uint8List edgeMagnitudes; // 1 byte per pixel: magnitude in [0, 255]

  const EdgeMapData({
    required this.gridWidth,
    required this.gridHeight,
    required this.edgeThreshold,
    required this.edgeDensity,
    required this.highGradientPixelCount,
    required this.edgeMagnitudes,
  }) : assert(
         gridWidth > 0 && gridHeight > 0,
         'Grid dimensions must be positive',
       ),
       assert(
         edgeThreshold >= 0 && edgeThreshold <= 255,
         'Threshold must be in [0, 255]',
       ),
       assert(
         edgeDensity >= 0.0 && edgeDensity <= 1.0,
         'Edge density must be in [0.0, 1.0]',
       ),
       assert(
         highGradientPixelCount >= 0 &&
             highGradientPixelCount <= gridWidth * gridHeight,
         'Invalid high gradient pixel count',
       ),
       assert(
         edgeMagnitudes.length == gridWidth * gridHeight,
         'Buffer size must match gridWidth * gridHeight',
       );

  /// Retrieves the gradient magnitude at (x, y). Clamps safely at edges.
  int getMagnitude(int x, int y) {
    final cx = x.clamp(0, gridWidth - 1);
    final cy = y.clamp(0, gridHeight - 1);
    return edgeMagnitudes[cy * gridWidth + cx];
  }

  /// Checks if pixel at (x, y) is an edge above threshold.
  bool isEdge(int x, int y) => getMagnitude(x, y) >= edgeThreshold;

  Map<String, dynamic> toJson() => {
    'gridWidth': gridWidth,
    'gridHeight': gridHeight,
    'edgeThreshold': edgeThreshold,
    'edgeDensity': edgeDensity,
    'highGradientPixelCount': highGradientPixelCount,
    'magnitudesBase64': base64Encode(edgeMagnitudes),
  };

  factory EdgeMapData.fromJson(Map<String, dynamic> json) {
    final w = json['gridWidth'] as int;
    final h = json['gridHeight'] as int;
    final bytes = base64Decode(json['magnitudesBase64'] as String);
    return EdgeMapData(
      gridWidth: w,
      gridHeight: h,
      edgeThreshold: json['edgeThreshold'] as int,
      edgeDensity: (json['edgeDensity'] as num).toDouble(),
      highGradientPixelCount: json['highGradientPixelCount'] as int,
      edgeMagnitudes: Uint8List.fromList(bytes),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeMapData &&
          runtimeType == other.runtimeType &&
          gridWidth == other.gridWidth &&
          gridHeight == other.gridHeight &&
          edgeThreshold == other.edgeThreshold &&
          (edgeDensity - other.edgeDensity).abs() < 1e-6 &&
          highGradientPixelCount == other.highGradientPixelCount &&
          _bytesEqual(edgeMagnitudes, other.edgeMagnitudes);

  @override
  int get hashCode =>
      Object.hash(gridWidth, gridHeight, edgeThreshold, highGradientPixelCount);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
