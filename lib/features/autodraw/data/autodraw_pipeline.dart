import 'dart:typed_data';

import '../../../data/render/render_graph_executor.dart';
import '../../../domain/recipes/render_graph.dart';
import '../domain/autodraw_models.dart';
import 'potrace_vectorizer.dart';

/// Autodraw Color Pipeline:
/// Source Image -> Render Graph (CIELAB, Vibrancy, Presets) -> Processed Buffer -> Potrace Vectorizer -> Sample Color from Processed Buffer -> Autodraw Canvas.
class AutodrawPipeline {
  final RenderGraphExecutor executor;
  final PotraceVectorizer vectorizer;

  AutodrawPipeline({
    RenderGraphExecutor? executor,
    this.vectorizer = const PotraceVectorizer(),
  }) : executor = executor ?? RenderGraphExecutor();

  /// Executes the full shader-to-autodraw color pipeline:
  /// 1. Executes [renderGraph] on [sourceImageBytes] to render vibrant CIELAB / shader colors.
  /// 2. Samples colors from the processed buffer and vectorizes strokes via [PotraceVectorizer].
  Future<AutodrawVectorizationResult> processAndVectorize({
    required Uint8List sourceImageBytes,
    required RenderGraph renderGraph,
    int maxPaths = 2500,
  }) async {
    // 1. Render Graph execution (CIELAB, Vibrancy, Presets)
    final renderResult = await executor.execute(
      graph: renderGraph,
      sourceImageBytes: sourceImageBytes,
    );

    // 2. Vectorize sampled shader-processed pixel buffer on background isolate
    return await vectorizer.vectorizeImage(
      rgbaBytes: renderResult.pixelBytes,
      width: renderResult.width,
      height: renderResult.height,
      maxPaths: maxPaths,
    );
  }
}
