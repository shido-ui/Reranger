import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/domain/recipes/adversarial_stealth_node.dart';
import 'package:reranger/domain/recipes/pixelate_quantize_node.dart';
import 'package:reranger/domain/recipes/recolor_render_node.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/domain/recipes/render_pipeline_failure.dart';
import 'package:reranger/domain/recipes/style_render_nodes.dart';

void main() {
  group('Prompt B Batch 4: Graph Serialization & Node Replay Tests', () {
    late Uint8List testImageBytes;
    late String testImageHash;
    const int testWidth = 32;
    const int testHeight = 32;

    setUp(() {
      final image = img.Image(
        width: testWidth,
        height: testHeight,
        numChannels: 4,
      );
      for (int y = 0; y < testHeight; y++) {
        for (int x = 0; x < testWidth; x++) {
          final r = (x * 8) % 256;
          final g = (y * 8) % 256;
          final b = ((x + y) * 4) % 256;
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      testImageBytes = Uint8List.fromList(img.encodePng(image));
      testImageHash = sha256.convert(testImageBytes).toString();
    });

    test('All 9 RenderGraphNode types serialize to JSON and deserialize losslessly', () {
      final nodes = <RenderGraphNode>[
        SourceImageNode(
          id: 'src_node',
          sourceImageHash: testImageHash,
          sourceWidth: testWidth,
          sourceHeight: testHeight,
        ),
        GrayscaleNode(id: 'gray_node', inputNodeId: 'src_node'),
        SobelEdgeNode(
          id: 'sobel_node',
          inputNodeId: 'gray_node',
          edgeThreshold: 30,
        ),
        EdgeInvertSubtractNode(
          id: 'edge_sub_node',
          grayInputNodeId: 'gray_node',
          edgeInputNodeId: 'sobel_node',
          edgeIntensity: 0.75,
          contrastGamma: 1.5,
        ),
        GrainOverlayNode(
          id: 'grain_node',
          inputNodeId: 'edge_sub_node',
          intensity: 0.15,
          seed: 42,
        ),
        DuoToneNode(
          id: 'duotone_node',
          inputNodeId: 'grain_node',
          shadowR: 10,
          shadowG: 20,
          shadowB: 30,
          highlightR: 240,
          highlightG: 230,
          highlightB: 220,
          vignetteFalloff: 0.25,
        ),
        RecolorNode(
          id: 'recolor_node',
          inputNodeId: 'duotone_node',
          sourceR: 100,
          sourceG: 50,
          sourceB: 20,
          targetR: 200,
          targetG: 150,
          targetB: 80,
          tolerance: 0.2,
          feather: 0.1,
          preserveLuminance: true,
          strength: 0.9,
        ),
        AdversarialStealthNode(
          id: 'stealth_node',
          inputNodeId: 'recolor_node',
          strength: 0.45,
          applyFrequencyPerturbation: true,
        ),
        PixelateQuantizeNode(
          id: 'pixelate_node',
          inputNodeId: 'stealth_node',
          blockSize: 4,
          paletteLevels: 8,
          preserveAlpha: true,
        ),
      ];

      for (final node in nodes) {
        node.validate();
        final jsonMap = node.toJson();
        final jsonString = jsonEncode(jsonMap);
        final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
        final reconstructedNode = RenderGraphNode.fromJson(decodedMap);

        expect(reconstructedNode.id, equals(node.id));
        expect(reconstructedNode.type, equals(node.type));
        expect(reconstructedNode.version, equals(node.version));
        expect(reconstructedNode.inputNodeIds, equals(node.inputNodeIds));
        expect(reconstructedNode.parameters, equals(node.parameters));
        expect(reconstructedNode, equals(node));
      }
    });

    test('PixelateQuantizeNode parameter validation and memory estimation boundaries', () {
      final validNode = PixelateQuantizeNode(
        id: 'valid_pixel',
        inputNodeId: 'src_0',
        blockSize: 8,
        paletteLevels: 16,
      );
      expect(() => validNode.validate(), returnsNormally);
      expect(validNode.estimateMemoryBytes(100, 100), equals(100 * 100 * 4));

      // Invalid block size
      final invalidBlockLow = PixelateQuantizeNode(
        id: 'bad_block_0',
        inputNodeId: 'src_0',
        blockSize: 0,
      );
      expect(
        () => invalidBlockLow.validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      final invalidBlockHigh = PixelateQuantizeNode(
        id: 'bad_block_high',
        inputNodeId: 'src_0',
        blockSize: 128,
      );
      expect(
        () => invalidBlockHigh.validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );

      // Invalid palette levels
      final invalidLevelsLow = PixelateQuantizeNode(
        id: 'bad_levels_1',
        inputNodeId: 'src_0',
        paletteLevels: 1,
      );
      expect(
        () => invalidLevelsLow.validate(),
        throwsA(isA<RenderInvalidParametersFailure>()),
      );
    });

    test('RenderGraph with PixelateQuantizeNode and AdversarialStealthNode serializes and replays deterministically', () async {
      final originalGraph = RenderGraph(
        id: 'graph_pixel_stealth',
        nodes: {
          'src_0': SourceImageNode(
            id: 'src_0',
            sourceImageHash: testImageHash,
            sourceWidth: testWidth,
            sourceHeight: testHeight,
          ),
          'pixel_1': PixelateQuantizeNode(
            id: 'pixel_1',
            inputNodeId: 'src_0',
            blockSize: 4,
            paletteLevels: 4,
            preserveAlpha: true,
          ),
          'stealth_2': AdversarialStealthNode(
            id: 'stealth_2',
            inputNodeId: 'pixel_1',
            strength: 0.3,
            applyFrequencyPerturbation: true,
          ),
        },
        outputNodeId: 'stealth_2',
      );

      originalGraph.validate();

      // Serialize graph to JSON
      final graphJson = originalGraph.toJson();
      final serializedStr = jsonEncode(graphJson);

      // Deserialize back from JSON
      final deserializedJson =
          jsonDecode(serializedStr) as Map<String, dynamic>;
      final rehydratedGraph = RenderGraph.fromJson(deserializedJson);

      expect(rehydratedGraph.id, equals(originalGraph.id));
      expect(rehydratedGraph.outputNodeId, equals(originalGraph.outputNodeId));
      expect(rehydratedGraph.nodes.length, equals(originalGraph.nodes.length));

      // Execute both graphs with RenderGraphExecutor
      final executor = RenderGraphExecutor();
      final resultOriginal = await executor.execute(
        graph: originalGraph,
        sourceImageBytes: testImageBytes,
      );
      final resultRehydrated = await executor.execute(
        graph: rehydratedGraph,
        sourceImageBytes: testImageBytes,
      );

      expect(resultOriginal.width, equals(testWidth));
      expect(resultOriginal.height, equals(testHeight));
      expect(resultRehydrated.width, equals(testWidth));
      expect(resultRehydrated.height, equals(testHeight));

      // Outputs must be bitwise identical
      expect(resultRehydrated.pixelBytes, equals(resultOriginal.pixelBytes));
    });
  });
}
