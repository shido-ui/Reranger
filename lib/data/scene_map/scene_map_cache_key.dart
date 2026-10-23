import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// Computes a deterministic SHA-256 cache key for an Analysis Bundle / Scene Map.
/// Incorporates all relevant cache-key dimensions:
/// 1. Source image SHA-256 hash
/// 2. Schema bundle version
/// 3. Engine / algorithm version
/// 4. Target analysis dimensions (width x height)
/// 5. Sorted, normalized algorithm parameters (e.g. edge threshold, K clusters)
///
/// Guarantees:
/// - Unchanged input + settings + version -> exact identical key (Cache Hit)
/// - Any change in source, versions, dimensions, or parameters -> distinct key (Cache Miss)
String computeSceneMapCacheKey({
  required String sourceHash,
  int bundleVersion = 1,
  String engineVersion = '1.0.0',
  required int targetWidth,
  required int targetHeight,
  Map<String, dynamic> parameters = const {},
}) {
  final buffer = StringBuffer();
  buffer.write('src:$sourceHash|');
  buffer.write('bv:$bundleVersion|');
  buffer.write('ev:$engineVersion|');
  buffer.write('dim:${targetWidth}x$targetHeight|');

  // Sort parameter keys for canonical, order-independent serialization
  final sortedKeys = parameters.keys.toList()..sort();
  buffer.write('params:[');
  for (final k in sortedKeys) {
    final v = parameters[k];
    if (v is double) {
      buffer.write('$k:${v.toStringAsFixed(4)};');
    } else {
      buffer.write('$k:$v;');
    }
  }
  buffer.write(']');

  final bytes = utf8.encode(buffer.toString());
  return crypto.sha256.convert(bytes).toString();
}
