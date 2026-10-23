import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/domain/recipes/adversarial_stealth_node.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() {
  group('Batch A: Adversarial Stealth Engine (FGSM) Tests', () {
    late Uint8List sourceImageBytes;
    late String sourceHash;
    const int width = 64;
    const int height = 64;

    setUp(() {
      final image = img.Image(width: width, height: height, numChannels: 4);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final r = (x * 4) % 256;
          final g = (y * 4) % 256;
          final b = ((x + y) * 2) % 256;
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      sourceImageBytes = Uint8List.fromList(img.encodePng(image));
      sourceHash = sha256.convert(sourceImageBytes).toString();
    });

    test('AdversarialStealthNode validates parameters correctly', () {
      final validNode = AdversarialStealthNode(
        id: 'stealth_1',
        inputNodeId: 'src_0',
        strength: 0.6,
      );
      expect(() => validNode.validate(), returnsNormally);
      expect(validNode.strength, equals(0.6));
      expect(validNode.applyFrequencyPerturbation, isTrue);

      final invalidNode = AdversarialStealthNode(
        id: 'stealth_bad',
        inputNodeId: 'src_0',
        strength: 1.5,
      );
      expect(() => invalidNode.validate(), throwsException);
    });

    test('FGSM perturbation alters SHA-256 hash while keeping high PSNR (> 35 dB)', () async {
      final executor = RenderGraphExecutor();

      // 1. Render baseline source node graph
      final baselineGraph = RenderGraph(
        id: 'graph_baseline',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: width,
            sourceHeight: height,
          ),
        },
        outputNodeId: 'src_0',
      );

      final baselineResult = await executor.execute(
        graph: baselineGraph,
        sourceImageBytes: sourceImageBytes,
      );
      final baselineHash = sha256.convert(baselineResult.pixelBytes).toString();

      // 2. Render stealth graph with AdversarialStealthNode
      final stealthGraph = RenderGraph(
        id: 'graph_stealth',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: width,
            sourceHeight: height,
          ),
          'stealth_0': AdversarialStealthNode(
            id: 'stealth_0',
            inputNodeId: 'src_0',
            strength: 0.5,
            applyFrequencyPerturbation: true,
          ),
        },
        outputNodeId: 'stealth_0',
      );

      final stealthResult = await executor.execute(
        graph: stealthGraph,
        sourceImageBytes: sourceImageBytes,
      );
      final stealthHash = sha256.convert(stealthResult.pixelBytes).toString();

      // Hashes MUST be distinct (pixel data altered)
      expect(stealthHash, isNot(equals(baselineHash)));

      // 3. Compute PSNR (Peak Signal-to-Noise Ratio)
      double sumSquaredError = 0.0;
      final totalPixels = width * height;
      for (int i = 0; i < baselineResult.pixelBytes.length; i += 4) {
        final dr = baselineResult.pixelBytes[i] - stealthResult.pixelBytes[i];
        final dg =
            baselineResult.pixelBytes[i + 1] - stealthResult.pixelBytes[i + 1];
        final db =
            baselineResult.pixelBytes[i + 2] - stealthResult.pixelBytes[i + 2];
        sumSquaredError += (dr * dr + dg * dg + db * db) / 3.0;
      }

      final mse = sumSquaredError / totalPixels;
      final psnr = 10.0 * (math.log(255.0 * 255.0 / mse) / math.ln10);

      // PSNR must exceed 35 dB (standard perceptual imperceptibility threshold)
      expect(psnr, greaterThan(35.0));
    });

    test('Source image immutability: source bytes are unchanged', () async {
      final originalSha = sha256.convert(sourceImageBytes).toString();
      final executor = RenderGraphExecutor();

      final stealthGraph = RenderGraph(
        id: 'graph_stealth_immutability',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: sourceHash,
            sourceWidth: width,
            sourceHeight: height,
          ),
          'stealth_0': AdversarialStealthNode(
            id: 'stealth_0',
            inputNodeId: 'src_0',
            strength: 0.8,
          ),
        },
        outputNodeId: 'stealth_0',
      );

      await executor.execute(
        graph: stealthGraph,
        sourceImageBytes: sourceImageBytes,
      );

      expect(sha256.convert(sourceImageBytes).toString(), equals(originalSha));
    });

    test('Isolation: AdversarialStealthNode is never in normal preset recipes', () {
      for (final preset in PresetCatalog.all) {
        final graph = preset.buildGraph(sourceHash, width, height, {});
        for (final node in graph.nodes.values) {
          expect(
            node,
            isNot(isA<AdversarialStealthNode>()),
            reason:
                'Preset ${preset.id} must not contain AdversarialStealthNode by default',
          );
        }
      }
    });
  });
}
