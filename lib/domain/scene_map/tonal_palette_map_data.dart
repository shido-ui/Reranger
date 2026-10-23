import '../project/project_entity.dart';

/// Tonal distribution and dominant palette map extracted from the image.
/// Implements verified Median Cut color quantization (OP-05) and BT.601 tonal decomposition.
class TonalPaletteMapData {
  final List<ColorVector> palette;
  final double shadowRatio; // Fraction of pixels with luminance < 0.25
  final double midtoneRatio; // Fraction of pixels with 0.25 <= luminance < 0.75
  final double highlightRatio; // Fraction of pixels with luminance >= 0.75
  final double averageLuminance; // Average image luminance in [0.0, 1.0]
  final int totalPixelSamples;

  const TonalPaletteMapData({
    required this.palette,
    required this.shadowRatio,
    required this.midtoneRatio,
    required this.highlightRatio,
    required this.averageLuminance,
    required this.totalPixelSamples,
  }) : assert(palette.length > 0, 'Palette must contain at least 1 color'),
       assert(
         shadowRatio >= 0.0 && shadowRatio <= 1.0001,
         'Shadow ratio out of [0.0, 1.0]',
       ),
       assert(
         midtoneRatio >= 0.0 && midtoneRatio <= 1.0001,
         'Midtone ratio out of [0.0, 1.0]',
       ),
       assert(
         highlightRatio >= 0.0 && highlightRatio <= 1.0001,
         'Highlight ratio out of [0.0, 1.0]',
       ),
       assert(
         averageLuminance >= 0.0 && averageLuminance <= 1.0,
         'Average luminance out of [0.0, 1.0]',
       ),
       assert(totalPixelSamples > 0, 'Total samples must be positive');

  Map<String, dynamic> toJson() => {
    'palette': palette.map((c) => c.toJson()).toList(),
    'shadowRatio': shadowRatio,
    'midtoneRatio': midtoneRatio,
    'highlightRatio': highlightRatio,
    'averageLuminance': averageLuminance,
    'totalPixelSamples': totalPixelSamples,
  };

  factory TonalPaletteMapData.fromJson(Map<String, dynamic> json) {
    final rawColors = (json['palette'] as List)
        .map((e) => ColorVector.fromJson(e as Map<String, dynamic>))
        .toList();
    return TonalPaletteMapData(
      palette: rawColors,
      shadowRatio: (json['shadowRatio'] as num).toDouble(),
      midtoneRatio: (json['midtoneRatio'] as num).toDouble(),
      highlightRatio: (json['highlightRatio'] as num).toDouble(),
      averageLuminance: (json['averageLuminance'] as num).toDouble(),
      totalPixelSamples: json['totalPixelSamples'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TonalPaletteMapData &&
          runtimeType == other.runtimeType &&
          totalPixelSamples == other.totalPixelSamples &&
          (averageLuminance - other.averageLuminance).abs() < 1e-5 &&
          (shadowRatio - other.shadowRatio).abs() < 1e-5 &&
          (midtoneRatio - other.midtoneRatio).abs() < 1e-5 &&
          (highlightRatio - other.highlightRatio).abs() < 1e-5 &&
          _paletteEqual(palette, other.palette);

  @override
  int get hashCode =>
      Object.hash(palette.length, totalPixelSamples, shadowRatio, midtoneRatio);

  static bool _paletteEqual(List<ColorVector> a, List<ColorVector> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
