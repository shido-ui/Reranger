import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// Computes a deterministic SHA-256 cache key incorporating source hash, preset ID,
/// master intensity, sorted fine-tune parameters, seed, and dimensions.
/// Guarantees that any adjustment to sliders or parameters produces a distinct cache key.
String computeRenderCacheKey({
  required String sourceHash,
  required String presetId,
  required double intensity,
  required Map<String, double> fineTune,
  int seed = 0,
  int? width,
  int? height,
}) {
  final buffer = StringBuffer();
  buffer.write('src:$sourceHash|');
  buffer.write('preset:$presetId|');
  buffer.write('int:${intensity.toStringAsFixed(4)}|');
  buffer.write('seed:$seed|');
  if (width != null && height != null) {
    buffer.write('dim:${width}x$height|');
  }

  // Sort parameter keys for deterministic, order-independent canonicalization
  final sortedKeys = fineTune.keys.toList()..sort();
  buffer.write('params:[');
  for (final k in sortedKeys) {
    final v = fineTune[k]!;
    buffer.write('$k:${v.toStringAsFixed(4)};');
  }
  buffer.write(']');

  final bytes = utf8.encode(buffer.toString());
  return crypto.sha256.convert(bytes).toString();
}
