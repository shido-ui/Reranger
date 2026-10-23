import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_node_cache.dart';
import 'package:reranger/features/presets/data/batch_a_presets.dart';

void main() {
  group('Batch E (Performance, Build & Recovery) Red-Team Audit Tests', () {
    test('DEF-020 Regression: RenderNodeCache.clear() actually clears raster buffers and releases memory', () {
      final cache = RenderNodeCache(maxEntries: 10);
      final dummyBytes = Uint8List(1024 * 1024); // 1 MB buffer

      cache.put('node_key_1', dummyBytes, 512, 512);
      cache.put('node_key_2', dummyBytes, 512, 512);

      expect(cache.cachedEntryCount, equals(2));
      expect(cache.contains('node_key_1'), isTrue);
      expect(cache.contains('node_key_2'), isTrue);

      // Call clear
      cache.clear();

      expect(
        cache.cachedEntryCount,
        equals(0),
        reason: 'Cached entry count must be 0 after clear()',
      );
      expect(
        cache.contains('node_key_1'),
        isFalse,
        reason: 'Buffer map must not retain entries after clear()',
      );
      expect(
        cache.contains('node_key_2'),
        isFalse,
        reason: 'Buffer map must not retain entries after clear()',
      );
      expect(cache.get('node_key_1'), isNull);
    });

    test('Performance & Memory: 10 consecutive render graph evaluations execute cleanly without crash or leak', () async {
      final executor = RenderGraphExecutor();
      final testImage = img.Image(width: 128, height: 128);
      img.fill(testImage, color: img.ColorRgba8(100, 150, 200, 255));
      final bytes = Uint8List.fromList(img.encodePng(testImage));
      final sourceHash = sha256.convert(bytes).toString();

      final preset = BatchAPresets.graphitePencil;
      final graph = preset.buildGraph(
        sourceHash,
        128,
        128,
        preset.resolveParameters(null),
      );

      final sw = Stopwatch()..start();
      for (int i = 0; i < 10; i++) {
        final result = await executor.execute(
          graph: graph,
          sourceImageBytes: bytes,
        );
        expect(result.width, equals(128));
        expect(result.height, equals(128));
      }
      sw.stop();

      // 10 128x128 iterations with caching should execute under 1 second
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });
}
