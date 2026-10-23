import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/render/render_node_cache.dart';

void main() {
  group('DEF-027: RenderNodeCache Byte-Bounded LRU Tests', () {
    test(
      'Evicts least recently used entries when byte size limit is exceeded',
      () {
        // 100 bytes limit, up to 10 entries
        final cache = RenderNodeCache(maxEntries: 10, maxSizeBytes: 100);

        final bufA = Uint8List(40);
        final bufB = Uint8List(40);
        final bufC = Uint8List(40);

        cache.put('node_a', bufA, 10, 1);
        cache.put('node_b', bufB, 10, 1);

        expect(cache.cachedEntryCount, equals(2));
        expect(cache.currentSizeBytes, equals(80));

        // Adding node_c (40 bytes) exceeds 100 bytes (80 + 40 = 120 > 100), so oldest entry node_a must be evicted
        cache.put('node_c', bufC, 10, 1);

        expect(cache.contains('node_a'), isFalse);
        expect(cache.contains('node_b'), isTrue);
        expect(cache.contains('node_c'), isTrue);
        expect(cache.currentSizeBytes, equals(80));
      },
    );

    test('LRU access promotes accessed item preventing its eviction', () {
      final cache = RenderNodeCache(maxEntries: 10, maxSizeBytes: 100);

      final bufA = Uint8List(40);
      final bufB = Uint8List(40);
      final bufC = Uint8List(40);

      cache.put('node_a', bufA, 10, 1);
      cache.put('node_b', bufB, 10, 1);

      // Access node_a to promote it
      final retrieved = cache.get('node_a');
      expect(retrieved, isNotNull);

      // Adding node_c (40 bytes) should now evict node_b instead of node_a
      cache.put('node_c', bufC, 10, 1);

      expect(cache.contains('node_a'), isTrue);
      expect(cache.contains('node_b'), isFalse);
      expect(cache.contains('node_c'), isTrue);
    });

    test('Invalidate and clear accurately update current byte size', () {
      final cache = RenderNodeCache(maxEntries: 10, maxSizeBytes: 1000);

      cache.put('entry_1', Uint8List(150), 10, 1);
      cache.put('entry_2', Uint8List(250), 10, 1);

      expect(cache.currentSizeBytes, equals(400));

      cache.invalidate('entry_1');
      expect(cache.currentSizeBytes, equals(250));

      cache.clear();
      expect(cache.currentSizeBytes, equals(0));
      expect(cache.cachedEntryCount, equals(0));
    });
  });
}
