import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;

import '../../domain/recipes/render_graph.dart';
import '../../domain/recipes/render_graph_node.dart';
import '../../domain/recipes/render_pipeline_failure.dart';
import '../../domain/recipes/style_render_nodes.dart';
import '../../domain/recipes/recolor_render_node.dart';
import '../../domain/color/color_palette.dart';
import '../../domain/color/recolor_mask.dart';
import '../../domain/recipes/adversarial_stealth_node.dart';
import '../../domain/recipes/pixelate_quantize_node.dart';
import '../../domain/recipes/artistic_render_nodes.dart';
import '../../domain/recipes/blend_composite_node.dart';
import '../../domain/layers/editor_layer.dart';
import 'render_node_cache.dart';

/// Structured execution result of a render graph evaluation.
class RenderExecutionResult {
  final Uint8List pixelBytes; // RGBA 32-bit pixel buffer
  final int width;
  final int height;
  final Map<String, String> nodeCacheKeys; // Node ID -> computed cache key
  final int totalNodesExecuted;
  final int cacheHits;

  const RenderExecutionResult({
    required this.pixelBytes,
    required this.width,
    required this.height,
    required this.nodeCacheKeys,
    required this.totalNodesExecuted,
    required this.cacheHits,
  });
}

/// Deterministic, offline execution engine for [RenderGraph].
/// Evaluates nodes in strict topological order with intermediate buffer caching and cooperative cancellation.
class RenderGraphExecutor {
  final RenderNodeCache cache;
  final Map<String, ({Uint8List rgba, int width, int height})>
  _sourceBufferCache = {};
  static const int _maxSourceCacheEntries = 4;

  RenderGraphExecutor({RenderNodeCache? cache})
    : cache = cache ?? RenderNodeCache();

  /// Clears in-memory source buffer cache.
  void clearSourceCache() {
    _sourceBufferCache.clear();
  }

  /// Executes [graph] using [sourceImageBytes] at target scale [renderScale].
  /// [renderScale] = 1.0 for final export; [renderScale] < 1.0 for viewport preview.
  Future<RenderExecutionResult> execute({
    required RenderGraph graph,
    required Uint8List sourceImageBytes,
    double renderScale = 1.0,
    bool Function()? isCancelled,
    void Function(String nodeId, int index, int total)? onProgress,
    bool strictSourceIdentity = false,
    int maxExecutionBudgetBytes = 512 * 1024 * 1024,
  }) async {
    // 0. Pre-allocation validation: bytes, scale
    if (sourceImageBytes.isEmpty) {
      throw const RenderNodeExecutionFailure(
        'root',
        'SourceImageNode',
        'Source image byte buffer cannot be empty',
      );
    }
    if (renderScale <= 0.0 || renderScale.isNaN || renderScale.isInfinite) {
      throw RenderInvalidParametersFailure(
        nodeId: 'root',
        parameterName: 'renderScale',
        actualValue: renderScale,
        expectedCriteria: 'Positive finite scaling factor',
      );
    }

    // 1. Validate graph topology and parameters
    graph.validate();

    if (isCancelled != null && isCancelled()) {
      throw RenderGraphCancelledFailure(graph.id);
    }

    // 2. Obtain deterministic topological execution order
    final orderedNodes = graph.getTopologicalExecutionOrder();

    // Verify all nodes have supported implementations before allocating
    const supportedTypes = {
      SourceImageNode.nodeType,
      GrayscaleNode.nodeType,
      SobelEdgeNode.nodeType,
      EdgeInvertSubtractNode.nodeType,
      GrainOverlayNode.nodeType,
      DuoToneNode.nodeType,
      RecolorNode.nodeType,
      AdversarialStealthNode.nodeType,
      PixelateQuantizeNode.nodeType,
      HalftoneNode.nodeType,
      CrosshatchNode.nodeType,
      StippleNode.nodeType,
      CelShadeColorNode.nodeType,
      WatercolorWashNode.nodeType,
      PolygonalFacetNode.nodeType,
      BlendCompositeNode.nodeType,
    };
    for (final node in orderedNodes) {
      if (!supportedTypes.contains(node.type)) {
        throw RenderNodeExecutionFailure(
          node.id,
          node.type,
          'Unsupported node implementation: ${node.type}',
        );
      }
    }

    // 3. Resolve source image and verify source identity
    SourceImageNode? sourceNode;
    final sourceNodes = orderedNodes.whereType<SourceImageNode>().toList();
    if (sourceNodes.isEmpty) {
      throw const RenderNodeExecutionFailure(
        'root',
        'SourceImageNode',
        'Graph must contain at least one SourceImageNode',
      );
    }
    sourceNode = sourceNodes.first;
    for (int s = 1; s < sourceNodes.length; s++) {
      if (sourceNodes[s].sourceImageHash != sourceNode.sourceImageHash ||
          sourceNodes[s].sourceWidth != sourceNode.sourceWidth ||
          sourceNodes[s].sourceHeight != sourceNode.sourceHeight) {
        throw RenderInvalidParametersFailure(
          nodeId: sourceNodes[s].id,
          parameterName: 'sourceIdentity',
          actualValue: sourceNodes[s].sourceImageHash,
          expectedCriteria:
              'Matching source identity across all SourceImageNodes in graph',
        );
      }
    }

    final verifiedSourceHash = crypto.sha256
        .convert(sourceImageBytes)
        .toString();
    if (strictSourceIdentity &&
        sourceNode.sourceImageHash != verifiedSourceHash) {
      throw RenderSourceIntegrityFailure(
        declaredHash: sourceNode.sourceImageHash,
        actualHash: verifiedSourceHash,
      );
    }

    // Key source buffer cache strictly using verified digest and target scale to prevent stale pixel leaks (Prompt 2.A.1 & 2.A.2)
    final sourceKey = '$verifiedSourceHash@${renderScale.toStringAsFixed(4)}';

    Uint8List sourceRgba;
    int targetW;
    int targetH;

    if (_sourceBufferCache.containsKey(sourceKey)) {
      final cachedSource = _sourceBufferCache[sourceKey]!;
      sourceRgba = cachedSource.rgba;
      targetW = cachedSource.width;
      targetH = cachedSource.height;
    } else {
      final decodedSource = img.decodeImage(sourceImageBytes);
      if (decodedSource == null) {
        throw const RenderNodeExecutionFailure(
          'root',
          'SourceImageNode',
          'Failed to decode raw source image byte stream',
        );
      }
      final bakedSource = img.bakeOrientation(decodedSource);
      targetW = math.max(1, (bakedSource.width * renderScale).round());
      targetH = math.max(1, (bakedSource.height * renderScale).round());

      // Validate dimensions & impossible allocations
      if (targetW > 16384 ||
          targetH > 16384 ||
          targetW * targetH > 64 * 1024 * 1024) {
        throw RenderInvalidParametersFailure(
          nodeId: 'root',
          parameterName: 'dimensions',
          actualValue: '${targetW}x$targetH',
          expectedCriteria:
              'Dimensions must not exceed 16384x16384 or 67,108,864 pixels',
        );
      }

      int totalEstimatedMemory = 0;
      for (final n in orderedNodes) {
        totalEstimatedMemory += n.estimateMemoryBytes(targetW, targetH);
      }
      if (totalEstimatedMemory > maxExecutionBudgetBytes) {
        throw RenderMemoryLimitFailure(
          totalEstimatedMemory,
          maxExecutionBudgetBytes,
        );
      }

      // Scale source image if renderScale != 1.0
      final activeSourceImage = (renderScale < 0.999 || renderScale > 1.001)
          ? img.copyResize(
              bakedSource,
              width: targetW,
              height: targetH,
              interpolation: img.Interpolation.average,
            )
          : bakedSource;

      sourceRgba = activeSourceImage.getBytes(order: img.ChannelOrder.rgba);

      if (_sourceBufferCache.length >= _maxSourceCacheEntries) {
        _sourceBufferCache.remove(_sourceBufferCache.keys.first);
      }
      _sourceBufferCache[sourceKey] = (
        rgba: sourceRgba,
        width: targetW,
        height: targetH,
      );
    }

    // 4. Execution state: Node ID -> (Uint8List buffer, width, height)
    final nodeOutputs = <String, Uint8List>{};
    final nodeCacheKeys = <String, String>{};
    int executedCount = 0;
    final initialCacheHits = cache.cacheHits;

    for (int i = 0; i < orderedNodes.length; i++) {
      if (isCancelled != null && isCancelled()) {
        throw RenderGraphCancelledFailure(graph.id);
      }

      // Yield microtasks between nodes to process cancellation signals without creating pending FakeTimers in widget tests
      await Future<void>.value();

      if (isCancelled != null && isCancelled()) {
        throw RenderGraphCancelledFailure(graph.id);
      }

      final node = orderedNodes[i];
      onProgress?.call(node.id, i + 1, orderedNodes.length);

      // Resolve upstream cache keys for this node
      final upstreamKeys = node.inputNodeIds
          .map((inId) => nodeCacheKeys[inId]!)
          .toList();

      final nodeKey = node.computeNodeCacheKey(
        upstreamKeys,
        targetWidth: targetW,
        targetHeight: targetH,
        verifiedSourceHash: verifiedSourceHash,
      );
      nodeCacheKeys[node.id] = nodeKey;

      // Check cache for intermediate result
      final cachedBuffer = cache.get(nodeKey);
      if (cachedBuffer != null) {
        nodeOutputs[node.id] = cachedBuffer;
        continue; // Cache hit: skip computation
      }

      // Cache miss: execute node compute with cooperative cancellation
      executedCount++;
      final outputBuffer = _executeNode(
        node: node,
        sourceRgba: sourceRgba,
        width: targetW,
        height: targetH,
        nodeOutputs: nodeOutputs,
        sourceNode: sourceNode,
        isCancelled: isCancelled,
      );

      cache.put(nodeKey, outputBuffer, targetW, targetH);
      nodeOutputs[node.id] = outputBuffer;
    }

    final finalOutput = nodeOutputs[graph.outputNodeId]!;

    return RenderExecutionResult(
      pixelBytes: finalOutput,
      width: targetW,
      height: targetH,
      nodeCacheKeys: nodeCacheKeys,
      totalNodesExecuted: executedCount,
      cacheHits: cache.cacheHits - initialCacheHits,
    );
  }

  Uint8List _executeNode({
    required RenderGraphNode node,
    required Uint8List sourceRgba,
    required int width,
    required int height,
    required Map<String, Uint8List> nodeOutputs,
    SourceImageNode? sourceNode,
    bool Function()? isCancelled,
  }) {
    if (node is SourceImageNode) {
      return Uint8List.fromList(sourceRgba);
    } else if (node is GrayscaleNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeGrayscale(
        input,
        width,
        height,
        node.preserveAlpha,
        isCancelled,
      );
    } else if (node is SobelEdgeNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeSobel(
        input,
        width,
        height,
        node.edgeThreshold,
        node.invertOutput,
        isCancelled,
      );
    } else if (node is EdgeInvertSubtractNode) {
      final gray = nodeOutputs[node.inputNodeIds[0]]!;
      final edge = nodeOutputs[node.inputNodeIds[1]]!;
      return _computeEdgeInvertSubtract(
        gray,
        edge,
        width,
        height,
        node.edgeIntensity,
        node.contrastGamma,
        isCancelled,
      );
    } else if (node is GrainOverlayNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeGrainOverlay(
        input,
        width,
        height,
        node.intensity,
        node.seed,
        isCancelled,
      );
    } else if (node is DuoToneNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeDuoTone(
        input,
        width,
        height,
        node.shadowR,
        node.shadowG,
        node.shadowB,
        node.highlightR,
        node.highlightG,
        node.highlightB,
        node.vignetteFalloff,
        isCancelled,
      );
    } else if (node is RecolorNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeRecolor(
        input: input,
        width: width,
        height: height,
        sourceR: node.sourceR,
        sourceG: node.sourceG,
        sourceB: node.sourceB,
        targetR: node.targetR,
        targetG: node.targetG,
        targetB: node.targetB,
        tolerance: node.tolerance,
        feather: node.feather,
        preserveLuminance: node.preserveLuminance,
        strength: node.strength,
        maskBase64: node.maskBase64,
        sourceWidth: sourceNode?.sourceWidth,
        sourceHeight: sourceNode?.sourceHeight,
        nodeId: node.id,
        isCancelled: isCancelled,
      );
    } else if (node is AdversarialStealthNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeAdversarialStealth(
        input: input,
        width: width,
        height: height,
        strength: node.strength,
        applyFrequencyPerturbation: node.applyFrequencyPerturbation,
        isCancelled: isCancelled,
      );
    } else if (node is PixelateQuantizeNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computePixelateQuantize(
        input: input,
        width: width,
        height: height,
        blockSize: node.blockSize,
        paletteLevels: node.paletteLevels,
        preserveAlpha: node.preserveAlpha,
        isCancelled: isCancelled,
      );
    } else if (node is HalftoneNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeHalftone(
        input: input,
        width: width,
        height: height,
        dotPitch: node.dotPitch,
        angleDegrees: node.angleDegrees,
        dotIntensity: node.dotIntensity,
        preserveColor: node.preserveColor,
        isCancelled: isCancelled,
      );
    } else if (node is CrosshatchNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeCrosshatch(
        input: input,
        width: width,
        height: height,
        spacing: node.spacing,
        lineWeight: node.lineWeight,
        hatchDensity: node.hatchDensity,
        preserveColor: node.preserveColor,
        isCancelled: isCancelled,
      );
    } else if (node is StippleNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeStipple(
        input: input,
        width: width,
        height: height,
        dotDensity: node.dotDensity,
        preserveColor: node.preserveColor,
        seed: node.seed,
        isCancelled: isCancelled,
      );
    } else if (node is CelShadeColorNode) {
      final colorInput = nodeOutputs[node.inputNodeIds[0]]!;
      final edgeInput = node.inputNodeIds.length > 1
          ? nodeOutputs[node.inputNodeIds[1]]
          : null;
      return _computeCelShadeColor(
        colorInput: colorInput,
        edgeInput: edgeInput,
        width: width,
        height: height,
        shadeLevels: node.shadeLevels,
        inkStrength: node.inkStrength,
        contrastGamma: node.contrastGamma,
        isCancelled: isCancelled,
      );
    } else if (node is WatercolorWashNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeWatercolorWash(
        input: input,
        width: width,
        height: height,
        washDiffusion: node.washDiffusion,
        wetEdgeBleed: node.wetEdgeBleed,
        paperTooth: node.paperTooth,
        seed: node.seed,
        isCancelled: isCancelled,
      );
    } else if (node is PolygonalFacetNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computePolygonalFacet(
        input: input,
        width: width,
        height: height,
        facetSize: node.facetSize,
        edgeContrast: node.edgeContrast,
        isCancelled: isCancelled,
      );
    } else if (node is BlendCompositeNode) {
      final baseInput = nodeOutputs[node.inputNodeIds[0]]!;
      final topInput = nodeOutputs[node.inputNodeIds[1]]!;
      return _computeBlendComposite(
        baseInput: baseInput,
        topInput: topInput,
        width: width,
        height: height,
        blendMode: node.blendMode,
        opacity: node.opacity,
        maskBase64: node.maskBase64,
        sourceWidth: sourceNode?.sourceWidth,
        sourceHeight: sourceNode?.sourceHeight,
        nodeId: node.id,
        isCancelled: isCancelled,
      );
    } else {
      throw RenderNodeExecutionFailure(
        node.id,
        node.type,
        'Unsupported node implementation: ${node.type}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PIXEL MATHEMATICS (OP-02, OP-03, OP-07, Recipes 1, 2, 3)
  // ---------------------------------------------------------------------------

  static Uint8List _computeGrayscale(
    Uint8List src,
    int w,
    int h,
    bool preserveAlpha, [
    bool Function()? isCancelled,
  ]) {
    final total = w * h;
    final dst = Uint8List(total * 4);
    for (int i = 0; i < total; i++) {
      if ((i & 4095) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('GrayscaleNode');
      }
      final off = i * 4;
      final r = src[off];
      final g = src[off + 1];
      final b = src[off + 2];
      final a = preserveAlpha ? src[off + 3] : 255;
      final y = (299 * r + 587 * g + 114 * b) ~/ 1000;
      dst[off] = y;
      dst[off + 1] = y;
      dst[off + 2] = y;
      dst[off + 3] = a;
    }
    return dst;
  }

  static Uint8List _computeSobel(
    Uint8List src,
    int w,
    int h,
    int threshold,
    bool invert, [
    bool Function()? isCancelled,
  ]) {
    final total = w * h;
    final dst = Uint8List(total * 4);

    if (w < 2 || h < 2) {
      final outVal = invert ? 255 : 0;
      for (int i = 0; i < total; i++) {
        final off = i * 4;
        dst[off] = outVal;
        dst[off + 1] = outVal;
        dst[off + 2] = outVal;
        dst[off + 3] = src[off + 3];
      }
      return dst; // Degenerate: zero gradient, preserve alpha and invert setting
    }

    for (int y = 0; y < h; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('SobelEdgeNode');
      }
      final yPrev = (y > 0) ? (y - 1) : 0;
      final yNext = (y < h - 1) ? (y + 1) : (h - 1);

      for (int x = 0; x < w; x++) {
        final xPrev = (x > 0) ? (x - 1) : 0;
        final xNext = (x < w - 1) ? (x + 1) : (w - 1);

        int sample(int px, int py) =>
            src[(py * w + px) * 4]; // R channel of luminance

        final tl = sample(xPrev, yPrev);
        final tc = sample(x, yPrev);
        final tr = sample(xNext, yPrev);
        final ml = sample(xPrev, y);
        final mr = sample(xNext, y);
        final bl = sample(xPrev, yNext);
        final bc = sample(x, yNext);
        final br = sample(xNext, yNext);

        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bc + br) - (tl + 2 * tc + tr);

        int mag = math.sqrt(gx * gx + gy * gy).round().clamp(0, 255);
        if (mag < threshold) {
          mag = 0;
        }

        final outVal = invert ? (255 - mag) : mag;
        final off = (y * w + x) * 4;
        dst[off] = outVal;
        dst[off + 1] = outVal;
        dst[off + 2] = outVal;
        dst[off + 3] = src[off + 3]; // Preserve alpha
      }
    }
    return dst;
  }

  static Uint8List _computeEdgeInvertSubtract(
    Uint8List gray,
    Uint8List edge,
    int w,
    int h,
    double edgeIntensity,
    double gamma, [
    bool Function()? isCancelled,
  ]) {
    final total = w * h;
    final dst = Uint8List(total * 4);

    // Precompute 256-entry gamma lookup table
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final normalized = i / 255.0;
      final adjusted = math.pow(normalized, gamma);
      lut[i] = (adjusted * 255.0).round().clamp(0, 255);
    }

    for (int i = 0; i < total; i++) {
      if ((i & 4095) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('EdgeInvertSubtractNode');
      }
      final off = i * 4;
      final gVal = gray[off];
      final eVal = edge[off];

      final subtracted = (gVal - edgeIntensity * eVal).round().clamp(0, 255);
      final finalInk = lut[subtracted];

      dst[off] = finalInk;
      dst[off + 1] = finalInk;
      dst[off + 2] = finalInk;
      dst[off + 3] = gray[off + 3]; // Preserve alpha
    }
    return dst;
  }

  static Uint8List _computeGrainOverlay(
    Uint8List src,
    int w,
    int h,
    double intensity,
    int seed, [
    bool Function()? isCancelled,
  ]) {
    final total = w * h;
    final dst = Uint8List(total * 4);

    int prngState = seed & 0xFFFFFFFF;

    for (int i = 0; i < total; i++) {
      if ((i & 4095) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('GrainOverlayNode');
      }
      final off = i * 4;
      final a = src[off + 3];

      // Linear Congruential PRNG
      prngState = (prngState * 1664525 + 1013904223) & 0xFFFFFFFF;
      final noiseNorm =
          ((prngState & 0xFFFF) / 65535.0) * 2.0 - 1.0; // [-1.0, 1.0]

      // Modulate noise by pixel alpha factor (DEF-002: transparent pixels do not bleed noise)
      final alphaFactor = a / 255.0;
      final delta = (noiseNorm * intensity * 255.0 * alphaFactor).round();

      dst[off] = (src[off] + delta).clamp(0, 255);
      dst[off + 1] = (src[off + 1] + delta).clamp(0, 255);
      dst[off + 2] = (src[off + 2] + delta).clamp(0, 255);
      dst[off + 3] = a;
    }
    return dst;
  }

  static Uint8List _computeDuoTone(
    Uint8List src,
    int w,
    int h,
    int sR,
    int sG,
    int sB,
    int hR,
    int hG,
    int hB,
    double vignetteFalloff, [
    bool Function()? isCancelled,
  ]) {
    final total = w * h;
    final dst = Uint8List(total * 4);
    final centerX = w / 2.0;
    final centerY = h / 2.0;
    final maxDist = math.sqrt(centerX * centerX + centerY * centerY);

    for (int y = 0; y < h; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('DuoToneNode');
      }
      final dY = y - centerY;
      for (int x = 0; x < w; x++) {
        final dX = x - centerX;
        final off = (y * w + x) * 4;

        final r = src[off];
        final g = src[off + 1];
        final b = src[off + 2];
        final a = src[off + 3];

        // BT.601 tonal luminance in [0.0, 1.0]
        final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;

        // Quadratic vignette darkening factor
        final distNorm = (math.sqrt(dX * dX + dY * dY) / maxDist).clamp(
          0.0,
          1.0,
        );
        final vignetteFactor = 1.0 - (vignetteFalloff * distNorm * distNorm);

        // Interpolate between shadow and highlight colors
        final dtR = (sR + lum * (hR - sR)) * vignetteFactor;
        final dtG = (sG + lum * (hG - sG)) * vignetteFactor;
        final dtB = (sB + lum * (hB - sB)) * vignetteFactor;

        dst[off] = dtR.round().clamp(0, 255);
        dst[off + 1] = dtG.round().clamp(0, 255);
        dst[off + 2] = dtB.round().clamp(0, 255);
        dst[off + 3] = a;
      }
    }
    return dst;
  }

  static Uint8List _resampleMask(
    Uint8List srcMask,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final dst = Uint8List(dstW * dstH);
    for (int y = 0; y < dstH; y++) {
      final sy = ((y / dstH) * srcH).floor().clamp(0, srcH - 1);
      final srcRow = sy * srcW;
      final dstRow = y * dstW;
      for (int x = 0; x < dstW; x++) {
        final sx = ((x / dstW) * srcW).floor().clamp(0, srcW - 1);
        dst[dstRow + x] = srcMask[srcRow + sx];
      }
    }
    return dst;
  }

  static Uint8List _computeBlendComposite({
    required Uint8List baseInput,
    required Uint8List topInput,
    required int width,
    required int height,
    required String blendMode,
    required double opacity,
    String? maskBase64,
    int? sourceWidth,
    int? sourceHeight,
    String nodeId = 'blend_composite',
    bool Function()? isCancelled,
  }) {
    final totalPixels = width * height;
    final output = Uint8List(totalPixels * 4);

    final mode = BlendModeType.fromString(blendMode);

    Uint8List? maskBuffer;
    if (maskBase64 != null) {
      Uint8List maskRaw;
      try {
        maskRaw = base64Decode(maskBase64);
      } catch (e) {
        throw RenderInvalidParametersFailure(
          nodeId: nodeId,
          parameterName: 'maskBase64',
          actualValue: 'corrupt base64: $e',
          expectedCriteria: 'Valid base64-encoded binary mask string',
        );
      }
      if (maskRaw.length == totalPixels) {
        maskBuffer = maskRaw;
      } else if (sourceWidth != null &&
          sourceHeight != null &&
          maskRaw.length == sourceWidth * sourceHeight) {
        maskBuffer = _resampleMask(
          maskRaw,
          sourceWidth,
          sourceHeight,
          width,
          height,
        );
      } else {
        final dim = math.sqrt(maskRaw.length).round();
        if (dim > 0 && dim * dim == maskRaw.length) {
          maskBuffer = _resampleMask(maskRaw, dim, dim, width, height);
        }
      }
    }

    final double baseOpacity = opacity.clamp(0.0, 1.0);

    for (int p = 0; p < totalPixels; p++) {
      if ((p & 4095) == 0 && isCancelled != null && isCancelled()) {
        throw RenderGraphCancelledFailure(nodeId);
      }

      final off = p * 4;
      final bR = baseInput[off];
      final bG = baseInput[off + 1];
      final bB = baseInput[off + 2];
      final bA = baseInput[off + 3];

      final tR = topInput[off];
      final tG = topInput[off + 1];
      final tB = topInput[off + 2];

      final blendedR = mode.apply(bR, tR);
      final blendedG = mode.apply(bG, tG);
      final blendedB = mode.apply(bB, tB);

      double blendFactor = baseOpacity;
      if (maskBuffer != null) {
        blendFactor *= (maskBuffer[p] / 255.0);
      }

      if (blendFactor >= 0.999) {
        output[off] = blendedR;
        output[off + 1] = blendedG;
        output[off + 2] = blendedB;
      } else if (blendFactor <= 0.001) {
        output[off] = bR;
        output[off + 1] = bG;
        output[off + 2] = bB;
      } else {
        output[off] = (bR + (blendedR - bR) * blendFactor).round().clamp(
          0,
          255,
        );
        output[off + 1] = (bG + (blendedG - bG) * blendFactor).round().clamp(
          0,
          255,
        );
        output[off + 2] = (bB + (blendedB - bB) * blendFactor).round().clamp(
          0,
          255,
        );
      }
      output[off + 3] = bA; // Alpha strictly preserved (Invariant 4)
    }

    return output;
  }

  static Uint8List _computeRecolor({
    required Uint8List input,
    required int width,
    required int height,
    required int sourceR,
    required int sourceG,
    required int sourceB,
    required int targetR,
    required int targetG,
    required int targetB,
    required double tolerance,
    required double feather,
    required bool preserveLuminance,
    required double strength,
    String? maskBase64,
    int? sourceWidth,
    int? sourceHeight,
    String nodeId = 'recolor',
    bool Function()? isCancelled,
  }) {
    final totalPixels = width * height;
    final output = Uint8List(totalPixels * 4);

    RegionMask? explicitMask;
    if (maskBase64 != null) {
      Uint8List maskRaw;
      try {
        maskRaw = base64Decode(maskBase64);
      } catch (e) {
        throw RenderInvalidParametersFailure(
          nodeId: nodeId,
          parameterName: 'maskBase64',
          actualValue: 'corrupt base64: $e',
          expectedCriteria: 'Valid base64-encoded binary mask string',
        );
      }

      if (maskRaw.length == width * height) {
        explicitMask = RegionMask(
          width: width,
          height: height,
          buffer: maskRaw,
        );
      } else if (sourceWidth != null &&
          sourceHeight != null &&
          maskRaw.length == sourceWidth * sourceHeight) {
        final resampled = _resampleMask(
          maskRaw,
          sourceWidth,
          sourceHeight,
          width,
          height,
        );
        explicitMask = RegionMask(
          width: width,
          height: height,
          buffer: resampled,
        );
      } else {
        throw RenderInvalidParametersFailure(
          nodeId: nodeId,
          parameterName: 'maskBase64',
          actualValue: 'decoded length ${maskRaw.length}',
          expectedCriteria:
              'Mask length must match target ($width x $height = ${width * height}) or source (${sourceWidth ?? 0} x ${sourceHeight ?? 0} = ${(sourceWidth ?? 0) * (sourceHeight ?? 0)})',
        );
      }
    }

    final targetHsl = ColorRgb(targetR, targetG, targetB).toHsl();
    final sourceHsl = ColorRgb(sourceR, sourceG, sourceB).toHsl();
    const maxDist = 441.67295593; // 255 * sqrt(3)
    final tolDist = tolerance * maxDist;
    final featherDist = feather * maxDist;

    for (int i = 0; i < totalPixels; i++) {
      if ((i & 4095) == 0 && isCancelled != null && isCancelled()) {
        throw RenderGraphCancelledFailure(nodeId);
      }
      final offset = i * 4;
      final rIn = input[offset];
      final gIn = input[offset + 1];
      final bIn = input[offset + 2];
      final aIn = input[offset + 3];

      // Strictly preserve alpha
      output[offset + 3] = aIn;

      // Transparent pixel: preserve untouched
      if (aIn == 0) {
        output[offset] = rIn;
        output[offset + 1] = gIn;
        output[offset + 2] = bIn;
        continue;
      }

      double maskWeight = 0.0;
      if (explicitMask != null) {
        maskWeight = explicitMask.buffer[i] / 255.0;
      } else {
        final dr = (rIn - sourceR).toDouble();
        final dg = (gIn - sourceG).toDouble();
        final db = (bIn - sourceB).toDouble();
        final dist = math.sqrt(dr * dr + dg * dg + db * db);

        if (dist <= tolDist) {
          maskWeight = 1.0;
        } else if (featherDist > 1e-4 && dist <= tolDist + featherDist) {
          final t = (dist - tolDist) / featherDist;
          maskWeight = 1.0 - (3.0 * t * t - 2.0 * t * t * t);
        }
      }

      // Exact zero-difference guarantee for unselected pixels:
      if (maskWeight <= 1e-6 || strength <= 1e-6) {
        output[offset] = rIn;
        output[offset + 1] = gIn;
        output[offset + 2] = bIn;
        continue;
      }

      final effectiveAlphaFactor = aIn / 255.0;
      final effectiveWeight = (maskWeight * strength * effectiveAlphaFactor)
          .clamp(0.0, 1.0);

      // Input pixel BT.601 integer luminance: (299*R + 587*G + 114*B) / 1000
      final yIn = (299 * rIn + 587 * gIn + 114 * bIn) ~/ 1000;

      int rRec, gRec, bRec;

      if (preserveLuminance) {
        final inHsl = ColorRgb(rIn, gIn, bIn).toHsl();

        double satDampen = 1.0;
        if (sourceHsl.s >= 0.08 && inHsl.s < 0.08) {
          satDampen = (inHsl.s / 0.08).clamp(0.0, 1.0);
        }

        final blendSat = targetHsl.s * satDampen;
        final candidateRgb = ColorHsl(targetHsl.h, blendSat, inHsl.l).toRgb();

        final yCand =
            (299 * candidateRgb.r +
                587 * candidateRgb.g +
                114 * candidateRgb.b) ~/
            1000;

        if (yCand > 0) {
          final k = yIn / yCand;
          var rScaled = (candidateRgb.r * k).round().clamp(0, 255);
          var gScaled = (candidateRgb.g * k).round().clamp(0, 255);
          var bScaled = (candidateRgb.b * k).round().clamp(0, 255);

          final residual =
              yIn - (299 * rScaled + 587 * gScaled + 114 * bScaled) ~/ 1000;
          rRec = (rScaled + residual).clamp(0, 255);
          gRec = (gScaled + residual).clamp(0, 255);
          bRec = (bScaled + residual).clamp(0, 255);
        } else {
          rRec = yIn;
          gRec = yIn;
          bRec = yIn;
        }
      } else {
        rRec = targetR;
        gRec = targetG;
        bRec = targetB;
      }

      final rFinal = (rIn + (rRec - rIn) * effectiveWeight).round().clamp(
        0,
        255,
      );
      final gFinal = (gIn + (gRec - gIn) * effectiveWeight).round().clamp(
        0,
        255,
      );
      final bFinal = (bIn + (bRec - bIn) * effectiveWeight).round().clamp(
        0,
        255,
      );

      output[offset] = rFinal;
      output[offset + 1] = gFinal;
      output[offset + 2] = bFinal;
    }

    return output;
  }

  // Academic Adversarial Robustness Research
  static Uint8List _computeAdversarialStealth({
    required Uint8List input,
    required int width,
    required int height,
    required double strength,
    required bool applyFrequencyPerturbation,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    if (total == 0) return dst;

    final eps = (strength.clamp(0.0, 1.0) * 6.0);
    if (eps <= 0.001) {
      dst.setAll(0, input);
      return dst;
    }

    // 1. Calculate luminance channel
    final lum = Float32List(total);
    for (int i = 0; i < total; i++) {
      final off = i * 4;
      lum[i] =
          (299.0 * input[off] +
              587.0 * input[off + 1] +
              114.0 * input[off + 2]) /
          1000.0;
    }

    double getLum(int x, int y) {
      final cx = x.clamp(0, width - 1);
      final cy = y.clamp(0, height - 1);
      return lum[cy * width + cx];
    }

    // 2. FGSM + Frequency Perturbation
    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('AdversarialStealthNode');
      }
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final off = idx * 4;

        final center = getLum(x, y);
        final laplacian =
            4.0 * center -
            getLum(x + 1, y) -
            getLum(x - 1, y) -
            getLum(x, y + 1) -
            getLum(x, y - 1);

        final gx =
            (getLum(x + 1, y - 1) +
                2.0 * getLum(x + 1, y) +
                getLum(x + 1, y + 1)) -
            (getLum(x - 1, y - 1) +
                2.0 * getLum(x - 1, y) +
                getLum(x - 1, y + 1));
        final gy =
            (getLum(x - 1, y + 1) +
                2.0 * getLum(x, y + 1) +
                getLum(x + 1, y + 1)) -
            (getLum(x - 1, y - 1) +
                2.0 * getLum(x, y - 1) +
                getLum(x + 1, y - 1));

        double grad = gx + gy;
        if (applyFrequencyPerturbation) {
          final phase = math.sin(x * 0.75 + y * 0.75);
          grad += laplacian * 0.5 + phase * 2.0;
        }

        double signVal = (grad > 0.0) ? 1.0 : ((grad < 0.0) ? -1.0 : 0.0);
        if (signVal == 0.0) {
          signVal = ((idx % 2) == 0) ? 1.0 : -1.0;
        }

        double delta = signVal * eps;
        final alphaFactor = input[off + 3] / 255.0;
        delta *= alphaFactor;

        dst[off] = (input[off] + delta).round().clamp(0, 255);
        dst[off + 1] = (input[off + 1] + delta).round().clamp(0, 255);
        dst[off + 2] = (input[off + 2] + delta).round().clamp(0, 255);
        dst[off + 3] = input[off + 3];
      }
    }
    return dst;
  }

  static Uint8List _computePixelateQuantize({
    required Uint8List input,
    required int width,
    required int height,
    required int blockSize,
    required int paletteLevels,
    required bool preserveAlpha,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final minDim = math.min(width, height);
    final int block = blockSize.clamp(1, math.max(1, minDim)).toInt();
    final levels = paletteLevels.clamp(2, 256);
    final step = 255.0 / (levels - 1);

    int quantizeChannel(int val) {
      final q = (val / step).round();
      return (q * step).round().clamp(0, 255);
    }

    for (int by = 0; by < height; by += block) {
      if (isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('PixelateQuantizeNode');
      }
      final int bh = math.min(block, height - by);
      for (int bx = 0; bx < width; bx += block) {
        final int bw = math.min(block, width - bx);

        int sumR = 0, sumG = 0, sumB = 0, sumA = 0;
        final count = bw * bh;
        for (int dy = 0; dy < bh; dy++) {
          final rowOff = (by + dy) * width;
          for (int dx = 0; dx < bw; dx++) {
            final off = (rowOff + bx + dx) * 4;
            sumR += input[off];
            sumG += input[off + 1];
            sumB += input[off + 2];
            sumA += input[off + 3];
          }
        }

        final avgR = quantizeChannel(sumR ~/ count);
        final avgG = quantizeChannel(sumG ~/ count);
        final avgB = quantizeChannel(sumB ~/ count);
        final avgA = preserveAlpha ? (sumA ~/ count) : 255;

        for (int dy = 0; dy < bh; dy++) {
          final rowOff = (by + dy) * width;
          for (int dx = 0; dx < bw; dx++) {
            final off = (rowOff + bx + dx) * 4;
            dst[off] = avgR;
            dst[off + 1] = avgG;
            dst[off + 2] = avgB;
            dst[off + 3] = preserveAlpha ? input[off + 3] : avgA;
          }
        }
      }
    }
    return dst;
  }

  static Uint8List _computeHalftone({
    required Uint8List input,
    required int width,
    required int height,
    required int dotPitch,
    required double angleDegrees,
    required double dotIntensity,
    required bool preserveColor,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final pitch = dotPitch.clamp(2, 32);
    final rad = angleDegrees * (math.pi / 180.0);
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final maxR = pitch * 0.5 * 1.41421356;

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('HalftoneNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        final off = (rowOff + x) * 4;
        final a = input[off + 3];
        if (a == 0) {
          dst[off + 3] = 0;
          continue;
        }

        final r = input[off];
        final g = input[off + 1];
        final b = input[off + 2];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;

        // Halftone screen coordinate rotation
        final rotX = x * cosA - y * sinA;
        final rotY = x * sinA + y * cosA;

        final gridX = ((rotX / pitch).round()) * pitch;
        final gridY = ((rotY / pitch).round()) * pitch;
        final dx = rotX - gridX;
        final dy = rotY - gridY;
        final dist = math.sqrt(dx * dx + dy * dy);

        // Tonal modulation: shadows have large dots; highlights have fine screen tooth
        final shadowDepth = (1.0 - (lum / 255.0) * 0.85).clamp(0.05, 1.0);
        final dotR = maxR * math.sqrt(shadowDepth);

        double coverage = 0.0;
        if (dist <= dotR) {
          final edgeDist = dotR - dist;
          coverage = (edgeDist >= 0.75) ? 1.0 : ((edgeDist + 0.75) / 1.5);
          coverage = (coverage * dotIntensity).clamp(0.0, 1.0);
        }

        if (preserveColor) {
          final factor = 1.0 - coverage * 0.75;
          dst[off] = (r * factor).round().clamp(0, 255);
          dst[off + 1] = (g * factor).round().clamp(0, 255);
          dst[off + 2] = (b * factor).round().clamp(0, 255);
        } else {
          final ink = (255.0 * (1.0 - coverage)).round().clamp(0, 255);
          dst[off] = ink;
          dst[off + 1] = ink;
          dst[off + 2] = ink;
        }
        dst[off + 3] = a;
      }
    }
    return dst;
  }

  static Uint8List _computeCrosshatch({
    required Uint8List input,
    required int width,
    required int height,
    required int spacing,
    required int lineWeight,
    required double hatchDensity,
    required bool preserveColor,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final sp = spacing.clamp(3, 24);
    final lw = lineWeight.clamp(1, 4);
    final density = hatchDensity.clamp(0.1, 1.0);

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('CrosshatchNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        final off = (rowOff + x) * 4;
        final a = input[off + 3];
        if (a == 0) {
          dst[off + 3] = 0;
          continue;
        }

        final r = input[off];
        final g = input[off + 1];
        final b = input[off + 2];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;

        // Multi-tier directional hatch lines
        bool isLine = false;
        if (lum < 210 && ((x + y) % sp < lw)) {
          isLine = true;
        }
        if (!isLine && lum < 150 && (((x - y) % sp + sp) % sp < lw)) {
          isLine = true;
        }
        if (!isLine && lum < 90 && (y % sp < lw)) {
          isLine = true;
        }
        if (!isLine && lum < 40 && (x % sp < lw)) {
          isLine = true;
        }

        final darken = isLine ? density : 0.0;
        if (preserveColor) {
          final factor = 1.0 - darken;
          dst[off] = (r * factor).round().clamp(0, 255);
          dst[off + 1] = (g * factor).round().clamp(0, 255);
          dst[off + 2] = (b * factor).round().clamp(0, 255);
        } else {
          final paper = math.min(255.0, lum * 0.9 + 50.0);
          final ink = (paper * (1.0 - darken * 0.85)).round().clamp(0, 255);
          dst[off] = ink;
          dst[off + 1] = ink;
          dst[off + 2] = ink;
        }
        dst[off + 3] = a;
      }
    }
    return dst;
  }

  static Uint8List _computeStipple({
    required Uint8List input,
    required int width,
    required int height,
    required double dotDensity,
    required bool preserveColor,
    required int seed,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final density = dotDensity.clamp(0.05, 1.0);

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('StippleNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        final off = (rowOff + x) * 4;
        final a = input[off + 3];
        if (a == 0) {
          dst[off + 3] = 0;
          continue;
        }

        final r = input[off];
        final g = input[off + 1];
        final b = input[off + 2];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;

        final h =
            (((x * 374761393 + y * 668265263 + seed) ^ 0x5bf03635) *
                1274126177) &
            0x7fffffff;
        final rand = h / 2147483648.0;

        final shadow = 1.0 - (lum / 255.0);
        final threshold = (shadow * shadow * 1.25) * density;
        final isDot = rand < threshold;

        if (preserveColor) {
          final factor = isDot ? 0.25 : 1.0;
          dst[off] = (r * factor).round().clamp(0, 255);
          dst[off + 1] = (g * factor).round().clamp(0, 255);
          dst[off + 2] = (b * factor).round().clamp(0, 255);
        } else {
          final val = isDot ? 22 : 248;
          dst[off] = val;
          dst[off + 1] = val;
          dst[off + 2] = val;
        }
        dst[off + 3] = a;
      }
    }
    return dst;
  }

  static Uint8List _computeCelShadeColor({
    required Uint8List colorInput,
    Uint8List? edgeInput,
    required int width,
    required int height,
    required int shadeLevels,
    required double inkStrength,
    required double contrastGamma,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final levels = shadeLevels.clamp(2, 16);
    final invLevels = 1.0 / levels;

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('CelShadeColorNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        final off = (rowOff + x) * 4;
        final a = colorInput[off + 3];
        if (a == 0) {
          dst[off + 3] = 0;
          continue;
        }

        final r = colorInput[off];
        final g = colorInput[off + 1];
        final b = colorInput[off + 2];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;

        final normLum = (lum / 255.0).clamp(0.0, 1.0);
        final curvedLum = math.pow(normLum, contrastGamma).toDouble();
        final step = (curvedLum * levels).floor().clamp(0, levels - 1);
        final quantLum = ((step + 0.5) * invLevels).clamp(0.0, 1.0) * 255.0;

        final scale = (lum > 2.0) ? (quantLum / lum) : 1.0;
        double outR = (r * scale).clamp(0.0, 255.0);
        double outG = (g * scale).clamp(0.0, 255.0);
        double outB = (b * scale).clamp(0.0, 255.0);

        if (edgeInput != null) {
          final edgeVal = edgeInput[off];
          final edgeFactor = (edgeVal / 255.0) * inkStrength;
          outR = (outR * (1.0 - edgeFactor)).clamp(0.0, 255.0);
          outG = (outG * (1.0 - edgeFactor)).clamp(0.0, 255.0);
          outB = (outB * (1.0 - edgeFactor)).clamp(0.0, 255.0);
        }

        dst[off] = outR.round();
        dst[off + 1] = outG.round();
        dst[off + 2] = outB.round();
        dst[off + 3] = a;
      }
    }
    return dst;
  }

  static Uint8List _computeWatercolorWash({
    required Uint8List input,
    required int width,
    required int height,
    required int washDiffusion,
    required double wetEdgeBleed,
    required double paperTooth,
    required int seed,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final rad = washDiffusion.clamp(1, 6);

    // 1. Horizontal diffusion
    final temp = Uint8List(total * 4);
    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('WatercolorWashNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        int rSum = 0, gSum = 0, bSum = 0, count = 0;
        for (int kx = -rad; kx <= rad; kx++) {
          final px = (x + kx).clamp(0, width - 1);
          final off = (rowOff + px) * 4;
          rSum += input[off];
          gSum += input[off + 1];
          bSum += input[off + 2];
          count++;
        }
        final destOff = (rowOff + x) * 4;
        temp[destOff] = rSum ~/ count;
        temp[destOff + 1] = gSum ~/ count;
        temp[destOff + 2] = bSum ~/ count;
        temp[destOff + 3] = input[destOff + 3];
      }
    }

    // 2. Vertical diffusion + edge pigment pooling + paper grain
    for (int x = 0; x < width; x++) {
      if ((x & 31) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('WatercolorWashNode');
      }
      for (int y = 0; y < height; y++) {
        int rSum = 0, gSum = 0, bSum = 0, count = 0;
        for (int ky = -rad; ky <= rad; ky++) {
          final py = (y + ky).clamp(0, height - 1);
          final off = (py * width + x) * 4;
          rSum += temp[off];
          gSum += temp[off + 1];
          bSum += temp[off + 2];
          count++;
        }
        final off = (y * width + x) * 4;
        final a = input[off + 3];
        if (a == 0) {
          dst[off + 3] = 0;
          continue;
        }

        final diffusedR = rSum ~/ count;
        final diffusedG = gSum ~/ count;
        final diffusedB = bSum ~/ count;

        double r = diffusedR * 0.70 + input[off] * 0.30;
        double g = diffusedG * 0.70 + input[off + 1] * 0.30;
        double b = diffusedB * 0.70 + input[off + 2] * 0.30;

        // Edge gradient for wet pooling
        final leftOff = (y * width + (x > 0 ? x - 1 : 0)) * 4;
        final rightOff = (y * width + (x < width - 1 ? x + 1 : width - 1)) * 4;
        final topOff = ((y > 0 ? y - 1 : 0) * width + x) * 4;
        final botOff = ((y < height - 1 ? y + 1 : height - 1) * width + x) * 4;

        final gx =
            (input[rightOff] - input[leftOff]).abs() +
            (input[rightOff + 1] - input[leftOff + 1]).abs() +
            (input[rightOff + 2] - input[leftOff + 2]).abs();
        final gy =
            (input[botOff] - input[topOff]).abs() +
            (input[botOff + 1] - input[topOff + 1]).abs() +
            (input[botOff + 2] - input[topOff + 2]).abs();
        final grad = math.min(255.0, (gx + gy) / 3.0);

        final edgeDarken = 1.0 - (grad / 255.0) * wetEdgeBleed * 0.45;
        r *= edgeDarken;
        g *= edgeDarken;
        b *= edgeDarken;

        // Paper grain noise
        final h =
            (((x * 1664525 + y * 1013904223 + seed) ^ 0x4fbc83) * 22695477) &
            0x7fffffff;
        final noise = (h / 2147483648.0) * 2.0 - 1.0;
        final toothFactor = 1.0 + noise * paperTooth;

        dst[off] = (r * toothFactor).round().clamp(0, 255);
        dst[off + 1] = (g * toothFactor).round().clamp(0, 255);
        dst[off + 2] = (b * toothFactor).round().clamp(0, 255);
        dst[off + 3] = a;
      }
    }
    return dst;
  }

  static Uint8List _computePolygonalFacet({
    required Uint8List input,
    required int width,
    required int height,
    required int facetSize,
    required double edgeContrast,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    final sz = facetSize.clamp(2, 32);

    for (int gy = 0; gy < height; gy += sz) {
      if (isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('PolygonalFacetNode');
      }
      final gh = math.min(sz, height - gy);
      for (int gx = 0; gx < width; gx += sz) {
        final gw = math.min(sz, width - gx);

        int r1 = 0, g1 = 0, b1 = 0, c1 = 0;
        int r2 = 0, g2 = 0, b2 = 0, c2 = 0;

        for (int dy = 0; dy < gh; dy++) {
          final rowOff = (gy + dy) * width;
          for (int dx = 0; dx < gw; dx++) {
            final off = (rowOff + gx + dx) * 4;
            if (dx + dy < sz) {
              r1 += input[off];
              g1 += input[off + 1];
              b1 += input[off + 2];
              c1++;
            } else {
              r2 += input[off];
              g2 += input[off + 1];
              b2 += input[off + 2];
              c2++;
            }
          }
        }

        final avgR1 = c1 > 0 ? (r1 ~/ c1) : 0;
        final avgG1 = c1 > 0 ? (g1 ~/ c1) : 0;
        final avgB1 = c1 > 0 ? (b1 ~/ c1) : 0;

        final avgR2 = c2 > 0 ? (r2 ~/ c2) : avgR1;
        final avgG2 = c2 > 0 ? (g2 ~/ c2) : avgG1;
        final avgB2 = c2 > 0 ? (b2 ~/ c2) : avgB1;

        for (int dy = 0; dy < gh; dy++) {
          final rowOff = (gy + dy) * width;
          for (int dx = 0; dx < gw; dx++) {
            final off = (rowOff + gx + dx) * 4;
            final isT1 = (dx + dy < sz);
            int r = isT1 ? avgR1 : avgR2;
            int g = isT1 ? avgG1 : avgG2;
            int b = isT1 ? avgB1 : avgB2;
            final a = input[off + 3];

            final isEdge = (dx == 0 || dy == 0 || (dx + dy == sz - 1));
            if (isEdge && edgeContrast > 0.0) {
              final factor = 1.0 - edgeContrast * 0.4;
              r = (r * factor).round().clamp(0, 255);
              g = (g * factor).round().clamp(0, 255);
              b = (b * factor).round().clamp(0, 255);
            }

            dst[off] = r;
            dst[off + 1] = g;
            dst[off + 2] = b;
            dst[off + 3] = a;
          }
        }
      }
    }
    return dst;
  }
}
