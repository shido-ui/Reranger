import 'render_graph_node.dart';
import 'render_pipeline_failure.dart';

/// True retro arcade pixelation and palette quantization node (Invariant 7 & Prompt B).
/// Executes spatial block downsampling followed by discrete RGB color channel quantization.
class PixelateQuantizeNode extends RenderGraphNode {
  static const String nodeType = 'PixelateQuantizeNode';

  final int blockSize; // Spatial block width/height in pixels [1, 64]
  final int paletteLevels; // Quantization levels per RGB channel [2, 64]
  final bool preserveAlpha;

  PixelateQuantizeNode({
    required super.id,
    super.version = 1,
    required String inputNodeId,
    this.blockSize = 8,
    this.paletteLevels = 8,
    this.preserveAlpha = true,
  }) : super(
         type: nodeType,
         inputNodeIds: [inputNodeId],
         parameters: {
           'blockSize': blockSize,
           'paletteLevels': paletteLevels,
           'preserveAlpha': preserveAlpha,
         },
       );

  @override
  void validate() {
    if (inputNodeIds.length != 1) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'inputNodeIds',
        actualValue: inputNodeIds.length,
        expectedCriteria: 'Exactly 1 upstream input node',
      );
    }
    if (blockSize < 1 || blockSize > 64) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'blockSize',
        actualValue: blockSize,
        expectedCriteria: 'Integer pixel block size in [1, 64]',
      );
    }
    if (paletteLevels < 2 || paletteLevels > 64) {
      throw RenderInvalidParametersFailure(
        nodeId: id,
        parameterName: 'paletteLevels',
        actualValue: paletteLevels,
        expectedCriteria: 'Integer color levels in [2, 64]',
      );
    }
  }

  @override
  int estimateMemoryBytes(int width, int height) => width * height * 4;

  factory PixelateQuantizeNode.fromJson(Map<String, dynamic> json) {
    final params = json['parameters'] as Map<String, dynamic>? ?? {};
    return PixelateQuantizeNode(
      id: json['id'] as String,
      version: json['version'] as int? ?? 1,
      inputNodeId: (json['inputNodeIds'] as List<dynamic>).first as String,
      blockSize: (params['blockSize'] as num?)?.toInt() ?? 8,
      paletteLevels: (params['paletteLevels'] as num?)?.toInt() ?? 8,
      preserveAlpha: params['preserveAlpha'] as bool? ?? true,
    );
  }
}
