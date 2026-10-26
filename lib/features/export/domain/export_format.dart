/// Supported export formats and configuration parameters for Reranger export studio.
enum ExportImageFormat {
  png,
  jpeg,
  webp;

  String get extension => switch (this) {
    ExportImageFormat.png => '.png',
    ExportImageFormat.jpeg => '.jpg',
    ExportImageFormat.webp => '.webp',
  };

  String get mimeType => switch (this) {
    ExportImageFormat.png => 'image/png',
    ExportImageFormat.jpeg => 'image/jpeg',
    ExportImageFormat.webp => 'image/webp',
  };

  String get displayName => switch (this) {
    ExportImageFormat.png => 'PNG (Lossless)',
    ExportImageFormat.jpeg => 'JPEG (High Compatibility)',
    ExportImageFormat.webp => 'WebP (Compact Modern)',
  };

  bool get supportsAlpha => switch (this) {
    ExportImageFormat.png => true,
    ExportImageFormat.jpeg => false,
    ExportImageFormat.webp => true,
  };

  bool get supportsQuality => switch (this) {
    ExportImageFormat.png => false,
    ExportImageFormat.jpeg => true,
    ExportImageFormat.webp => true,
  };
}

/// Immutable configuration parameters for an image export operation.
class ExportConfiguration {
  final ExportImageFormat format;
  final int quality; // 1 to 100 for lossy formats (JPEG/WebP)
  final double scale; // 0.25 to 4.0
  final bool stripGpsMetadata;
  final List<int>
  backgroundColorForOpaque; // RGB [r, g, b] default [255, 255, 255]

  final double realism; // 0.0 to 1.0 Robust Stealth Engine V2

  // Phase 5: Adversarial Robustness Pipeline (Mandates 1-3)
  final double maxLInf; // L_inf bound (Mandate 2: 16/255)
  final bool useEot; // Expectation Over Transformation (Mandate 2)
  final bool
  bilateralSanitization; // Bilateral filter denoising pass (Mandate 1)
  final bool
  injectJpegArtifacts; // Synthetic JPEG quantization on PNG (Mandate 3)

  const ExportConfiguration({
    this.format = ExportImageFormat.png,
    this.quality = 90,
    this.scale = 1.0,
    this.stripGpsMetadata = true,
    this.backgroundColorForOpaque = const [255, 255, 255],
    this.realism = 0.0,
    this.maxLInf = 16.0,
    this.useEot = true,
    this.bilateralSanitization = true,
    this.injectJpegArtifacts = true,
  }) : assert(
         quality >= 1 && quality <= 100,
         'Quality must be between 1 and 100',
       ),
       assert(scale > 0.0 && scale <= 4.0, 'Scale must be between 0.0 and 4.0'),
       assert(
         realism >= 0.0 && realism <= 1.0,
         'Realism must be between 0.0 and 1.0',
       ),
       assert(
         maxLInf >= 0.0 && maxLInf <= 32.0,
         'maxLInf must be between 0.0 and 32.0',
       );

  ExportConfiguration copyWith({
    ExportImageFormat? format,
    int? quality,
    double? scale,
    bool? stripGpsMetadata,
    List<int>? backgroundColorForOpaque,
    double? realism,
    double? maxLInf,
    bool? useEot,
    bool? bilateralSanitization,
    bool? injectJpegArtifacts,
  }) {
    return ExportConfiguration(
      format: format ?? this.format,
      quality: quality ?? this.quality,
      scale: scale ?? this.scale,
      stripGpsMetadata: stripGpsMetadata ?? this.stripGpsMetadata,
      backgroundColorForOpaque:
          backgroundColorForOpaque ?? this.backgroundColorForOpaque,
      realism: realism ?? this.realism,
      maxLInf: maxLInf ?? this.maxLInf,
      useEot: useEot ?? this.useEot,
      bilateralSanitization:
          bilateralSanitization ?? this.bilateralSanitization,
      injectJpegArtifacts: injectJpegArtifacts ?? this.injectJpegArtifacts,
    );
  }
}

/// Real mathematical file size estimator based on empirical image encoding models.
/// Does NOT fabricate random or placebo figures (Invariant 7).
class RealSizeEstimator {
  /// Estimates expected export file size in bytes.
  static int estimateSizeBytes({
    required int width,
    required int height,
    required ExportConfiguration config,
  }) {
    final targetW = (width * config.scale).round();
    final targetH = (height * config.scale).round();
    final pixelCount = targetW * targetH;

    switch (config.format) {
      case ExportImageFormat.png:
        // PNG typically compresses 32-bit natural and stylistic art buffers to ~1.4 - 1.8 bytes/pixel
        return (pixelCount * 1.5).round();
      case ExportImageFormat.jpeg:
        // JPEG compression curve: base 0.05 bytes/px plus 0.40 * (quality / 100)
        final bytesPerPixel = 0.05 + (config.quality / 100.0) * 0.40;
        return (pixelCount * bytesPerPixel).round();
      case ExportImageFormat.webp:
        // WebP achieves ~30% higher compression efficiency than standard JPEG
        final bytesPerPixel = 0.04 + (config.quality / 100.0) * 0.28;
        return (pixelCount * bytesPerPixel).round();
    }
  }

  /// Formats byte count into a human-readable string (KB or MB).
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
