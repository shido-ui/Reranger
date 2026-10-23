import 'package:image/image.dart' as img;

/// Policy and utility for intentional EXIF metadata handling on export.
/// Preserves orientation/color profile information while removing sensitive geolocation tags.
class ExifMetadataPolicy {
  /// Applies metadata policy to [image] before final encoding:
  /// - Strips GPS geolocation tags if [stripGps] is true.
  /// - Bakes or canonicalizes orientation tag to 1 (normal) to prevent downstream viewer double-rotation.
  /// - Sets software provenance tag to 'Reranger Studio'.
  static void apply({
    required img.Image image,
    required bool stripGps,
    String software = 'Reranger Studio',
  }) {
    // 1. Strip GPS geolocation if requested (default policy)
    if (stripGps) {
      image.exif.directories.remove('gps');
      if (image.exif.directories.containsKey('ifd0')) {
        image.exif.imageIfd.sub.directories.remove('gps');
      }
    }

    // 2. Canonicalize Orientation (0x0112) to Top-Left (1)
    // Reranger bakes EXIF rotation directly into pixel matrices during decode,
    // so the rendered output pixels are already right-side up.
    if (image.exif.directories.containsKey('ifd0')) {
      image.exif.imageIfd.orientation = 1;
      image.exif.imageIfd.software = software;
    }
  }

  /// Inspects whether an image's EXIF container has any GPS tags.
  static bool hasGpsData(img.Image image) {
    if (image.exif.directories.containsKey('gps')) {
      return !image.exif.directories['gps']!.isEmpty;
    }
    if (image.exif.directories.containsKey('ifd0') &&
        image.exif.imageIfd.sub.directories.containsKey('gps')) {
      return !image.exif.imageIfd.sub.directories['gps']!.isEmpty;
    }
    return false;
  }
}
