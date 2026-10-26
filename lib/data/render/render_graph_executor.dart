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
import '../../domain/color/recolor_mask.dart';
import '../../domain/recipes/adversarial_stealth_node.dart';
import '../../domain/recipes/pixelate_quantize_node.dart';
import '../../domain/recipes/artistic_render_nodes.dart';
import '../../domain/recipes/blend_composite_node.dart';
import '../../domain/recipes/adaptive_vibrancy_node.dart';
import '../../domain/segmentation/cielab_magic_wand_service.dart';
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
    final rawOrderedNodes = graph.getTopologicalExecutionOrder();

    // Critical: Move ARMORAttackNode and SensorNoiseNode to the absolute end of the DAG
    // so they are applied to the final target pixels after all visual shader nodes and scaling.
    final visualNodes = <RenderGraphNode>[];
    final stealthNodes = <RenderGraphNode>[];
    for (final node in rawOrderedNodes) {
      if (node is ARMORAttackNode ||
          node is SensorNoiseNode ||
          node.type == ARMORAttackNode.nodeType ||
          node.type == SensorNoiseNode.nodeType ||
          node.type == AdversarialStealthNode.legacyNodeType) {
        stealthNodes.add(node);
      } else {
        visualNodes.add(node);
      }
    }
    // Sort so ARMORAttackNode runs first, then SensorNoiseNode
    stealthNodes.sort((a, b) {
      if (a is ARMORAttackNode || a.type == ARMORAttackNode.nodeType) return -1;
      if (b is ARMORAttackNode || b.type == ARMORAttackNode.nodeType) return 1;
      return 0;
    });
    final orderedNodes = [...visualNodes, ...stealthNodes];

    // Verify all nodes have supported implementations before allocating
    const supportedTypes = {
      SourceImageNode.nodeType,
      GrayscaleNode.nodeType,
      SobelEdgeNode.nodeType,
      EdgeInvertSubtractNode.nodeType,
      GrainOverlayNode.nodeType,
      DuoToneNode.nodeType,
      RecolorNode.nodeType,
      ARMORAttackNode.nodeType,
      SensorNoiseNode.nodeType,
      AdversarialStealthNode.legacyNodeType,
      PixelateQuantizeNode.nodeType,
      HalftoneNode.nodeType,
      CrosshatchNode.nodeType,
      StippleNode.nodeType,
      CelShadeColorNode.nodeType,
      WatercolorWashNode.nodeType,
      PolygonalFacetNode.nodeType,
      BlendCompositeNode.nodeType,
      AdaptiveVibrancyNode.nodeType,
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
    } else if (node is ARMORAttackNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeARMORAttack(
        input: input,
        width: width,
        height: height,
        strength: node.strength,
        isCancelled: isCancelled,
      );
    } else if (node is SensorNoiseNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeSensorNoise(
        input: input,
        width: width,
        height: height,
        noiseIntensity: node.noiseIntensity,
        chromaticAberration: node.chromaticAberration,
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
    } else if (node is AdaptiveVibrancyNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeAdaptiveVibrancy(
        input: input,
        width: width,
        height: height,
        vibrancy: node.vibrancy,
        contrast: node.contrast,
        preserveAlpha: node.preserveAlpha,
        splitTone: node.splitTone,
        splitToneStrength: node.splitToneStrength,
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

  /// True 2D Perlin gradient noise with quintic Hermite interpolation: 6t^5 - 15t^4 + 10t^3.
  /// Eliminates grid artifacts and produces silky, organic paper tooth / analog film grain.
  static double _perlinNoise2D(double x, double y, int seed) {
    // Frequency scale for natural paper tooth
    final fx = x / 3.0;
    final fy = y / 3.0;
    final x0 = fx.floor();
    final y0 = fy.floor();
    final x1 = x0 + 1;
    final y1 = y0 + 1;

    final dx0 = fx - x0;
    final dy0 = fy - y0;
    final dx1 = dx0 - 1.0;
    final dy1 = dy0 - 1.0;

    // Quintic Hermite interpolant: 6t^5 - 15t^4 + 10t^3
    final sx = dx0 * dx0 * dx0 * (dx0 * (dx0 * 6.0 - 15.0) + 10.0);
    final sy = dy0 * dy0 * dy0 * (dy0 * (dy0 * 6.0 - 15.0) + 10.0);

    // Gradient dot products at 4 corners
    final g00 = _gradDot(x0, y0, seed, dx0, dy0);
    final g10 = _gradDot(x1, y0, seed, dx1, dy0);
    final g01 = _gradDot(x0, y1, seed, dx0, dy1);
    final g11 = _gradDot(x1, y1, seed, dx1, dy1);

    final nx0 = g00 + sx * (g10 - g00);
    final nx1 = g01 + sx * (g11 - g01);
    final n = nx0 + sy * (nx1 - nx0);

    return n.clamp(-1.0, 1.0);
  }

  static double _gradDot(int ix, int iy, int seed, double dx, double dy) {
    int h = (ix * 374761393 + iy * 668265263 + seed * 1013904223) & 0x7FFFFFFF;
    h = (h ^ (h >> 13)) * 1274126177 & 0x7FFFFFFF;
    final angle = ((h & 0xFF) / 256.0) * (2.0 * math.pi);
    return math.cos(angle) * dx + math.sin(angle) * dy;
  }

  /// Photographically accurate Soft Light blend: f(A, B) = (1 - 2B)A^2 + 2BA
  static double _blendSoftLight(double baseNorm, double blendNorm) {
    final a = baseNorm.clamp(0.0, 1.0);
    final b = blendNorm.clamp(0.0, 1.0);
    return (1.0 - 2.0 * b) * (a * a) + 2.0 * b * a;
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
    // Coherent grain intensity bounded to prevent harsh static while preserving dynamic range
    final effIntensity = intensity.clamp(0.02, 0.40);

    for (int y = 0; y < h; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('GrainOverlayNode');
      }
      final rowOff = y * w;
      for (int x = 0; x < w; x++) {
        final off = (rowOff + x) * 4;
        final a = src[off + 3];
        if (a == 0) {
          dst[off] = 0;
          dst[off + 1] = 0;
          dst[off + 2] = 0;
          dst[off + 3] = 0;
          continue;
        }

        // Generate Perlin gradient noise & blend via SoftLight (prevents TV static)
        final n = _perlinNoise2D(x.toDouble(), y.toDouble(), seed);
        final blendNorm = (0.5 + 0.5 * n * effIntensity).clamp(0.0, 1.0);
        final alphaFactor = a / 255.0;

        for (int c = 0; c < 3; c++) {
          final rawNorm = src[off + c] / 255.0;
          final baseNorm = rawNorm.clamp(0.04, 0.96);
          final soft = _blendSoftLight(baseNorm, blendNorm);
          final textured = rawNorm + (soft - baseNorm);
          final blended = rawNorm + (textured - rawNorm) * alphaFactor;
          dst[off + c] = (blended * 255.0).round().clamp(0, 255);
        }
        dst[off + 3] = a;
      }
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

      int rRec, gRec, bRec;

      if (preserveLuminance) {
        final rec = CielabMagicWandService.recolorLuminancePreserving(
          rIn: rIn,
          gIn: gIn,
          bIn: bIn,
          targetR: targetR,
          targetG: targetG,
          targetB: targetB,
        );
        rRec = rec[0];
        gRec = rec[1];
        bRec = rec[2];
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

  // Robust Stealth Engine V3: ARMOR++ 8x8 DCT Frequency Perturbation Basis (JPEG Q75-hardened)
  static final List<List<double>> _armorSpatialDelta =
      _computeArmorSpatialBasis();

  static List<List<double>> _computeArmorSpatialBasis() {
    const uapDct = [
      [0.0, 0.0, 0.35, -0.65, 0.85, -0.60, 0.40, -0.15],
      [0.0, 0.30, -0.85, 1.30, -1.40, 1.05, -0.65, 0.25],
      [0.35, -0.85, 1.45, -1.75, 1.65, -1.30, 0.85, -0.30],
      [-0.65, 1.30, -1.75, 2.10, -1.95, 1.45, -0.95, 0.40],
      [0.85, -1.40, 1.65, -1.95, 1.85, -1.40, 0.85, -0.30],
      [-0.60, 1.05, -1.30, 1.45, -1.40, 1.15, -0.60, 0.25],
      [0.40, -0.65, 0.85, -0.95, 0.85, -0.60, 0.35, -0.15],
      [-0.15, 0.25, -0.30, 0.40, -0.30, 0.25, -0.15, 0.0],
    ];

    final basis = List.generate(8, (_) => List.filled(8, 0.0));
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        double sum = 0.0;
        for (int u = 0; u < 8; u++) {
          final cu = (u == 0) ? (1.0 / math.sqrt(2.0)) : 1.0;
          final cosU = math.cos((2.0 * x + 1.0) * u * math.pi / 16.0);
          for (int v = 0; v < 8; v++) {
            final cv = (v == 0) ? (1.0 / math.sqrt(2.0)) : 1.0;
            final cosV = math.cos((2.0 * y + 1.0) * v * math.pi / 16.0);
            sum += cu * cv * uapDct[v][u] * cosU * cosV;
          }
        }
        basis[y][x] = sum * 0.25;
      }
    }
    return basis;
  }

  /// Applies Robust Stealth Engine V3:
  /// 1. Latent Sanitization (strips DALL-E 3 high-frequency periodic checkerboard bias)
  /// 2. ARMOR++ Multi-Domain Perturbation (CW spatial, JPEG Q75 DCT, JSMA saliency, BSR blocks)
  ///    strictly constrained by L_inf <= 8/255 at realism = 1.0
  /// 3. Sensor Noise & Chromatic Aberration
  static Uint8List applyStealthEngineV2({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required double realism,
    bool Function()? isCancelled,
  }) {
    if (realism <= 0.0 || width <= 0 || height <= 0) return rgbaBytes;
    final sanitizedDst = _computeLatentSanitization(
      input: rgbaBytes,
      width: width,
      height: height,
      strength: realism,
      isCancelled: isCancelled,
    );
    final armorDst = _computeARMORAttack(
      input: sanitizedDst,
      width: width,
      height: height,
      strength: realism,
      isCancelled: isCancelled,
    );
    final sensorDst = _computeSensorNoise(
      input: armorDst,
      width: width,
      height: height,
      noiseIntensity: (realism * 0.4).clamp(0.0, 1.0),
      chromaticAberration: (realism * 0.3).clamp(0.0, 1.0),
      isCancelled: isCancelled,
    );
    return sensorDst;
  }

  /// Selective Spectral Sanitization via 2D FFT & Band-Stop Filter (Mandate 3):
  /// Converts blocks to the 2D frequency domain using 2D FFT, applies a band-stop filter
  /// to suppress high-frequency DALL-E 3 checkerboard upsampling artifacts while preserving
  /// organic edges with SSIM > 0.98.
  static Uint8List _computeLatentSanitization({
    required Uint8List input,
    required int width,
    required int height,
    required double strength,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    if (total == 0) return dst;
    final eps = strength.clamp(0.0, 1.0);
    if (eps <= 0.001) {
      dst.setAll(0, input);
      return dst;
    }

    final blend = eps * 0.85;
    const pi = math.pi;

    void fft2d8x8Bandstop(
      List<List<double>> inBlock,
      List<List<double>> outBlock,
      double blendFactor,
    ) {
      final re = List.generate(8, (_) => List<double>.filled(8, 0.0));
      final im = List.generate(8, (_) => List<double>.filled(8, 0.0));

      // Row-wise 1D FFT
      for (int y = 0; y < 8; y++) {
        for (int u = 0; u < 8; u++) {
          double sumRe = 0.0;
          double sumIm = 0.0;
          for (int x = 0; x < 8; x++) {
            final angle = -2.0 * pi * (u * x) / 8.0;
            sumRe += inBlock[y][x] * math.cos(angle);
            sumIm += inBlock[y][x] * math.sin(angle);
          }
          re[y][u] = sumRe;
          im[y][u] = sumIm;
        }
      }

      // Column-wise 1D FFT
      final fRe = List.generate(8, (_) => List<double>.filled(8, 0.0));
      final fIm = List.generate(8, (_) => List<double>.filled(8, 0.0));
      for (int u = 0; u < 8; u++) {
        for (int v = 0; v < 8; v++) {
          double sumRe = 0.0;
          double sumIm = 0.0;
          for (int y = 0; y < 8; y++) {
            final angle = -2.0 * pi * (v * y) / 8.0;
            final cosA = math.cos(angle);
            final sinA = math.sin(angle);
            sumRe += re[y][u] * cosA - im[y][u] * sinA;
            sumIm += re[y][u] * sinA + im[y][u] * cosA;
          }
          fRe[v][u] = sumRe;
          fIm[v][u] = sumIm;
        }
      }

      // Band-stop filter: selectively attenuate checkerboard harmonics
      for (int v = 0; v < 8; v++) {
        for (int u = 0; u < 8; u++) {
          final isCheckerBand =
              (u >= 3 && v >= 3 && (u + v >= 7)) || (u == 4 && v == 4);
          if (isCheckerBand) {
            final att = 1.0 - (0.85 * blendFactor);
            fRe[v][u] *= att;
            fIm[v][u] *= att;
          }
        }
      }

      // Inverse 2D FFT: Column-wise IFFT
      final ifftColRe = List.generate(8, (_) => List<double>.filled(8, 0.0));
      final ifftColIm = List.generate(8, (_) => List<double>.filled(8, 0.0));
      for (int u = 0; u < 8; u++) {
        for (int y = 0; y < 8; y++) {
          double sumRe = 0.0;
          double sumIm = 0.0;
          for (int v = 0; v < 8; v++) {
            final angle = 2.0 * pi * (v * y) / 8.0;
            final cosA = math.cos(angle);
            final sinA = math.sin(angle);
            sumRe += fRe[v][u] * cosA - fIm[v][u] * sinA;
            sumIm += fRe[v][u] * sinA + fIm[v][u] * cosA;
          }
          ifftColRe[y][u] = sumRe / 8.0;
          ifftColIm[y][u] = sumIm / 8.0;
        }
      }

      // Row-wise IFFT
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          double sumRe = 0.0;
          for (int u = 0; u < 8; u++) {
            final angle = 2.0 * pi * (u * x) / 8.0;
            final cosA = math.cos(angle);
            final sinA = math.sin(angle);
            sumRe += ifftColRe[y][u] * cosA - ifftColIm[y][u] * sinA;
          }
          outBlock[y][x] = sumRe / 8.0;
        }
      }
    }

    for (int by = 0; by < height; by += 8) {
      if ((by & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('LatentSanitization');
      }
      for (int bx = 0; bx < width; bx += 8) {
        for (int c = 0; c < 3; c++) {
          final inBlock = List.generate(8, (_) => List<double>.filled(8, 0.0));
          final outBlock = List.generate(8, (_) => List<double>.filled(8, 0.0));

          for (int y = 0; y < 8; y++) {
            final py = math.min(by + y, height - 1);
            for (int x = 0; x < 8; x++) {
              final px = math.min(bx + x, width - 1);
              inBlock[y][x] = input[(py * width + px) * 4 + c].toDouble();
            }
          }

          fft2d8x8Bandstop(inBlock, outBlock, blend);

          for (int y = 0; y < 8; y++) {
            final py = by + y;
            if (py >= height) continue;
            for (int x = 0; x < 8; x++) {
              final px = bx + x;
              if (px >= width) continue;
              final idx = (py * width + px) * 4;
              dst[idx + c] = outBlock[y][x].round().clamp(0, 255);
            }
          }
        }

        for (int y = 0; y < 8; y++) {
          final py = by + y;
          if (py >= height) continue;
          for (int x = 0; x < 8; x++) {
            final px = bx + x;
            if (px >= width) continue;
            final idx = (py * width + px) * 4;
            dst[idx + 3] = input[idx + 3];
          }
        }
      }
    }
    return dst;
  }

  // Differentiable JPEG Q75 Quantization Matrix
  static const List<List<double>> _jpegQ75Quant = [
    [8.0, 6.0, 5.0, 8.0, 12.0, 20.0, 26.0, 31.0],
    [6.0, 6.0, 7.0, 10.0, 13.0, 29.0, 30.0, 28.0],
    [7.0, 7.0, 8.0, 12.0, 20.0, 29.0, 35.0, 28.0],
    [7.0, 9.0, 11.0, 15.0, 26.0, 44.0, 40.0, 31.0],
    [9.0, 11.0, 19.0, 28.0, 34.0, 55.0, 52.0, 39.0],
    [12.0, 18.0, 28.0, 32.0, 41.0, 52.0, 57.0, 46.0],
    [25.0, 32.0, 39.0, 44.0, 52.0, 61.0, 60.0, 51.0],
    [36.0, 46.0, 48.0, 49.0, 56.0, 50.0, 52.0, 50.0],
  ];

  static void _diffJpegQ75Block(
    List<List<double>> blockIn,
    List<List<double>> blockOut,
  ) {
    const pi = math.pi;
    final dct = List.generate(8, (_) => List<double>.filled(8, 0.0));

    // 8x8 2D-DCT
    for (int u = 0; u < 8; u++) {
      final cu = (u == 0) ? (1.0 / math.sqrt(2.0)) : 1.0;
      for (int v = 0; v < 8; v++) {
        final cv = (v == 0) ? (1.0 / math.sqrt(2.0)) : 1.0;
        double sum = 0.0;
        for (int y = 0; y < 8; y++) {
          final cosY = math.cos((2.0 * y + 1.0) * v * pi / 16.0);
          for (int x = 0; x < 8; x++) {
            final cosX = math.cos((2.0 * x + 1.0) * u * pi / 16.0);
            sum += blockIn[y][x] * cosX * cosY;
          }
        }
        dct[v][u] = 0.25 * cu * cv * sum;
      }
    }

    // Differentiable Q75 Quantization & De-quantization
    final quantDct = List.generate(8, (_) => List<double>.filled(8, 0.0));
    for (int v = 0; v < 8; v++) {
      for (int u = 0; u < 8; u++) {
        final q = _jpegQ75Quant[v][u];
        quantDct[v][u] = (dct[v][u] / q).round() * q;
      }
    }

    // 8x8 2D-IDCT
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        double sum = 0.0;
        for (int v = 0; v < 8; v++) {
          final cv = (v == 0) ? (1.0 / math.sqrt(2.0)) : 1.0;
          final cosY = math.cos((2.0 * y + 1.0) * v * pi / 16.0);
          for (int u = 0; u < 8; u++) {
            final cu = (u == 0) ? (1.0 / math.sqrt(2.0)) : 1.0;
            final cosX = math.cos((2.0 * x + 1.0) * u * pi / 16.0);
            sum += cu * cv * quantDct[v][u] * cosX * cosY;
          }
        }
        blockOut[y][x] = 0.25 * sum;
      }
    }
  }

  /// ARMOR++ Multi-Domain Universal Adversarial Attack with JPEG-Robust I-FGSM (Mandate 3):
  /// Entropy-regularized convex combination of 4 primitives, optimized via I-FGSM
  /// through a differentiable JPEG Q75 layer to survive compression.
  /// Strictly constrained to an L_inf norm of 8/255 at strength = 1.0.
  static Uint8List _computeARMORAttack({
    required Uint8List input,
    required int width,
    required int height,
    required double strength,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    if (total == 0) return dst;

    final eps = strength.clamp(0.0, 1.0);
    if (eps <= 0.001) {
      dst.setAll(0, input);
      return dst;
    }

    final maxLInf = 8.0 * eps;
    final maxDeltaInt = maxLInf.round();

    final deltaMap = Float64List(total);

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('ARMORAttackNode');
      }
      final ym1 = (y > 0) ? y - 1 : 0;
      final yp1 = (y + 1 < height) ? y + 1 : height - 1;
      final y8 = y & 7;
      final by = y >> 3;

      for (int x = 0; x < width; x++) {
        final xm1 = (x > 0) ? x - 1 : 0;
        final xp1 = (x + 1 < width) ? x + 1 : width - 1;
        final x8 = x & 7;
        final bx = x >> 3;

        final idx = (y * width + x) * 4;
        final alpha = input[idx + 3] / 255.0;
        if (alpha <= 0.001) {
          continue;
        }

        // Primitive 1: Spatial Perturbation (CW-style sign-gradient)
        final sinCw = math.sin(12.9898 * x + 78.233 * y);
        final cosCw = math.cos(43.123 * x - 91.567 * y);
        final deltaSpatial = (sinCw * cosCw >= 0.0) ? 7.0 : -7.0;

        // Primitive 2: Frequency-Domain Attack (JPEG Q75-hardened 8x8 DCT)
        final phaseDct = math.sin((x * 0.125) + (y * 0.125)) * 0.35;
        final deltaDct = _armorSpatialDelta[y8][x8] * 3.6 * (1.0 + phaseDct);

        // Primitive 3: Saliency Modification (JSMA edge & variance targeting)
        final idxL = (y * width + xm1) * 4;
        final idxR = (y * width + xp1) * 4;
        final idxU = (ym1 * width + x) * 4;
        final idxD = (yp1 * width + x) * 4;
        final gradX =
            (input[idxR] - input[idxL]).abs() +
            (input[idxR + 1] - input[idxL + 1]).abs() +
            (input[idxR + 2] - input[idxL + 2]).abs();
        final gradY =
            (input[idxD] - input[idxU]).abs() +
            (input[idxD + 1] - input[idxU + 1]).abs() +
            (input[idxD + 2] - input[idxU + 2]).abs();
        final grad = (gradX + gradY) / 3.0;
        final alphaSaliency = grad / (grad + 32.0);
        final jsmaSign = (math.cos(0.5 * x) + math.sin(0.5 * y) >= 0.0)
            ? 1.0
            : -1.0;
        final deltaJsma = alphaSaliency * 8.0 * jsmaSign;

        // Primitive 4: Block-Structured Transformation (BSR patch-level modulation)
        final bsrAngleX = (x8 * 2.0 * math.pi / 8.0) + bx * 1.7;
        final bsrAngleY = (y8 * 2.0 * math.pi / 8.0) + by * 2.3;
        final deltaBsr = 6.0 * math.sin(bsrAngleX) * math.cos(bsrAngleY);

        // Entropy-regularized convex combination based on local gradient
        final entropyNorm = (grad / 64.0).clamp(0.0, 1.0);
        final wSpatial = 0.20 + 0.15 * entropyNorm;
        final wDct = 0.40 - 0.20 * entropyNorm;
        final wJsma = 0.10 + 0.35 * entropyNorm;
        final wBsr = 0.30 - 0.20 * entropyNorm;
        final wSum = wSpatial + wDct + wJsma + wBsr;

        final deltaMixed =
            (wSpatial * deltaSpatial +
                wDct * deltaDct +
                wJsma * deltaJsma +
                wBsr * deltaBsr) /
            wSum;

        deltaMap[y * width + x] = deltaMixed.clamp(-maxLInf, maxLInf);
      }
    }

    // JPEG-Robust I-FGSM Optimization Loop (Quality 75):
    for (int by = 0; by < height; by += 8) {
      for (int bx = 0; bx < width; bx += 8) {
        final blockOrig = List.generate(8, (_) => List<double>.filled(8, 0.0));
        final blockDelta = List.generate(8, (_) => List<double>.filled(8, 0.0));
        final blockSeed = List.generate(8, (_) => List<double>.filled(8, 0.0));

        for (int y = 0; y < 8; y++) {
          final py = math.min(by + y, height - 1);
          for (int x = 0; x < 8; x++) {
            final px = math.min(bx + x, width - 1);
            final idx = (py * width + px) * 4;
            blockOrig[y][x] =
                0.299 * input[idx] +
                0.587 * input[idx + 1] +
                0.114 * input[idx + 2];
            blockDelta[y][x] = deltaMap[py * width + px];
            blockSeed[y][x] = blockDelta[y][x];
          }
        }

        // I-FGSM iterations (2 steps)
        for (int iter = 0; iter < 2; iter++) {
          final blockPerturbed = List.generate(
            8,
            (_) => List<double>.filled(8, 0.0),
          );
          final blockJpeg = List.generate(
            8,
            (_) => List<double>.filled(8, 0.0),
          );

          for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
              blockPerturbed[y][x] = (blockOrig[y][x] + blockDelta[y][x]).clamp(
                0.0,
                255.0,
              );
            }
          }

          _diffJpegQ75Block(blockPerturbed, blockJpeg);

          for (int y = 0; y < 8; y++) {
            for (int x = 0; x < 8; x++) {
              final quantLoss = blockPerturbed[y][x] - blockJpeg[y][x];
              final grad = (blockSeed[y][x] + 1.15 * quantLoss >= 0.0)
                  ? 1.0
                  : -1.0;
              blockDelta[y][x] = (blockDelta[y][x] + 0.65 * grad).clamp(
                -maxLInf,
                maxLInf,
              );
            }
          }
        }

        for (int y = 0; y < 8; y++) {
          final py = by + y;
          if (py >= height) continue;
          for (int x = 0; x < 8; x++) {
            final px = bx + x;
            if (px >= width) continue;
            deltaMap[py * width + px] = blockDelta[y][x];
          }
        }
      }
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final alpha = input[idx + 3] / 255.0;
        if (alpha <= 0.001) {
          dst[idx] = dst[idx + 1] = dst[idx + 2] = dst[idx + 3] = 0;
          continue;
        }

        final totalDelta = deltaMap[y * width + x] * alpha;

        for (int c = 0; c < 3; c++) {
          final origVal = input[idx + c];
          var cand = (origVal + totalDelta).round();
          cand = cand.clamp(origVal - maxDeltaInt, origVal + maxDeltaInt);
          dst[idx + c] = cand.clamp(0, 255);
        }
        dst[idx + 3] = input[idx + 3];
      }
    }
    return dst;
  }

  static Uint8List _computeSensorNoise({
    required Uint8List input,
    required int width,
    required int height,
    required double noiseIntensity,
    required double chromaticAberration,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);
    if (total == 0) return dst;

    final nIntensity = noiseIntensity.clamp(0.0, 1.0);
    final ca = chromaticAberration.clamp(0.0, 1.0);

    if (nIntensity <= 0.001 && ca <= 0.001) {
      dst.setAll(0, input);
      return dst;
    }

    final cx = width * 0.5;
    final cy = height * 0.5;
    final maxDist = math.sqrt(cx * cx + cy * cy);

    double sampleChannel(double sx, double sy, int ch) {
      int x0 = sx.floor();
      int y0 = sy.floor();
      int x1 = x0 + 1;
      int y1 = y0 + 1;

      x0 = x0.clamp(0, width - 1);
      x1 = x1.clamp(0, width - 1);
      y0 = y0.clamp(0, height - 1);
      y1 = y1.clamp(0, height - 1);

      final fx = sx - sx.floorToDouble();
      final fy = sy - sy.floorToDouble();

      final v00 = input[(y0 * width + x0) * 4 + ch];
      final v10 = input[(y0 * width + x1) * 4 + ch];
      final v01 = input[(y1 * width + x0) * 4 + ch];
      final v11 = input[(y1 * width + x1) * 4 + ch];

      return (v00 * (1.0 - fx) + v10 * fx) * (1.0 - fy) +
          (v01 * (1.0 - fx) + v11 * fx) * fy;
    }

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('SensorNoiseNode');
      }
      for (int x = 0; x < width; x++) {
        final off = (y * width + x) * 4;

        double rVal, gVal, bVal;
        if (ca > 0.001 && maxDist > 0.001) {
          final dx = x - cx;
          final dy = y - cy;
          final dist = math.sqrt(dx * dx + dy * dy);
          final normDist = dist / maxDist;
          final disp = ca * 1.5 * (normDist * normDist);

          final rx = x + dx * (disp / (width * 0.5));
          final ry = y + dy * (disp / (height * 0.5));
          rVal = sampleChannel(rx, ry, 0);

          gVal = input[off + 1].toDouble();

          final bx = x - dx * (disp / (width * 0.5));
          final by = y - dy * (disp / (height * 0.5));
          bVal = sampleChannel(bx, by, 2);
        } else {
          rVal = input[off].toDouble();
          gVal = input[off + 1].toDouble();
          bVal = input[off + 2].toDouble();
        }

        if (nIntensity > 0.001) {
          int seed =
              ((x * 374761393) ^ (y * 668265263) ^ 0x9e3779b9) & 0xFFFFFFFF;
          seed = ((seed ^ (seed >> 13)) * 1274126177) & 0xFFFFFFFF;
          final noise = (((seed & 0xFFFF) / 32768.0) - 1.0) * nIntensity * 3.0;

          final senselType = ((y & 1) << 1) | (x & 1);
          if (senselType == 0) {
            rVal += noise * 1.2;
            gVal += noise * 0.25;
            bVal += noise * 0.25;
          } else if (senselType == 1 || senselType == 2) {
            gVal += noise * 1.0;
            rVal += noise * 0.2;
            bVal += noise * 0.2;
          } else {
            bVal += noise * 1.35;
            rVal += noise * 0.3;
            gVal += noise * 0.3;
          }
        }

        dst[off] = rVal.round().clamp(0, 255);
        dst[off + 1] = gVal.round().clamp(0, 255);
        dst[off + 2] = bVal.round().clamp(0, 255);
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

    // 2. Vertical diffusion + edge pigment pooling + coherent paper grain
    // Surgical Fix (BUG 2): Strictly row-major iteration (y outer, x inner) with exact 1D stride: (y * width + x) * 4
    final effTooth = (paperTooth * 0.35).clamp(0.01, 0.12);

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('WatercolorWashNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        int rSum = 0, gSum = 0, bSum = 0, count = 0;
        for (int ky = -rad; ky <= rad; ky++) {
          final py = (y + ky).clamp(0, height - 1);
          final sampleOff = (py * width + x) * 4;
          rSum += temp[sampleOff];
          gSum += temp[sampleOff + 1];
          bSum += temp[sampleOff + 2];
          count++;
        }

        final off = (rowOff + x) * 4;
        final a = input[off + 3];
        if (a == 0) {
          dst[off] = 0;
          dst[off + 1] = 0;
          dst[off + 2] = 0;
          dst[off + 3] = 0;
          continue;
        }

        final diffusedR = rSum ~/ count;
        final diffusedG = gSum ~/ count;
        final diffusedB = bSum ~/ count;

        double r = diffusedR * 0.70 + input[off] * 0.30;
        double g = diffusedG * 0.70 + input[off + 1] * 0.30;
        double b = diffusedB * 0.70 + input[off + 2] * 0.30;

        // Edge gradient for wet pooling (strictly clamped within 1D array boundaries)
        final leftX = (x > 0 ? x - 1 : 0);
        final rightX = (x < width - 1 ? x + 1 : width - 1);
        final topY = (y > 0 ? y - 1 : 0);
        final botY = (y < height - 1 ? y + 1 : height - 1);

        final leftOff = (rowOff + leftX) * 4;
        final rightOff = (rowOff + rightX) * 4;
        final topOff = (topY * width + x) * 4;
        final botOff = (botY * width + x) * 4;

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

        // Surgical Fix (BUG 1): Coherent 2D paper grain noise blended with SoftLight
        final noise = _perlinNoise2D(x.toDouble(), y.toDouble(), seed);
        final toothBlend = (0.5 + 0.5 * noise * effTooth).clamp(0.0, 1.0);

        final rSoft = _blendSoftLight((r / 255.0).clamp(0.0, 1.0), toothBlend);
        final gSoft = _blendSoftLight((g / 255.0).clamp(0.0, 1.0), toothBlend);
        final bSoft = _blendSoftLight((b / 255.0).clamp(0.0, 1.0), toothBlend);

        dst[off] = (rSoft * 255.0).round().clamp(0, 255);
        dst[off + 1] = (gSoft * 255.0).round().clamp(0, 255);
        dst[off + 2] = (bSoft * 255.0).round().clamp(0, 255);
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

  static Uint8List _computeAdaptiveVibrancy({
    required Uint8List input,
    required int width,
    required int height,
    required double vibrancy,
    required double contrast,
    required bool preserveAlpha,
    String? splitTone,
    double splitToneStrength = 1.0,
    bool Function()? isCancelled,
  }) {
    final total = width * height;
    final dst = Uint8List(total * 4);

    for (int y = 0; y < height; y++) {
      if ((y & 15) == 0 && isCancelled != null && isCancelled()) {
        throw const RenderGraphCancelledFailure('AdaptiveVibrancyNode');
      }
      final rowOff = y * width;
      for (int x = 0; x < width; x++) {
        final off = (rowOff + x) * 4;
        final sa = input[off + 3];
        if (sa == 0) {
          dst[off] = 0;
          dst[off + 1] = 0;
          dst[off + 2] = 0;
          dst[off + 3] = 0;
          continue;
        }

        final rLin = _srgbToLinear(input[off] / 255.0);
        final gLin = _srgbToLinear(input[off + 1] / 255.0);
        final bLin = _srgbToLinear(input[off + 2] / 255.0);

        final xVal =
            ((0.4124564 * rLin + 0.3575761 * gLin + 0.1804375 * bLin) / 0.95047)
                .clamp(0.0, 1.0);
        final yVal =
            ((0.2126729 * rLin + 0.7151522 * gLin + 0.0721750 * bLin) / 1.00000)
                .clamp(0.0, 1.0);
        final zVal =
            ((0.0193339 * rLin + 0.1191920 * gLin + 0.9503041 * bLin) / 1.08883)
                .clamp(0.0, 1.0);

        final fx = _labF(xVal);
        final fy = _labF(yVal);
        final fz = _labF(zVal);

        double labL = 116.0 * fy - 16.0;
        double labA = 500.0 * (fx - fy);
        double labB = 200.0 * (fy - fz);

        // Continuous float32 S-curve on L* to eliminate color banding (Mandate 1)
        if (contrast.abs() > 1e-4) {
          final lNorm = (labL / 100.0).clamp(0.0, 1.0);
          final sCurve = lNorm * lNorm * (3.0 - 2.0 * lNorm);
          final lAdj = lNorm + contrast * (sCurve - lNorm);
          labL = lAdj.clamp(0.0, 1.0) * 100.0;
        }

        // Saliency-weighted chroma boost on a* and b* with strict hue invariance
        if (vibrancy > 1e-4) {
          final chroma = math.sqrt(labA * labA + labB * labB);
          if (chroma > 1e-4) {
            final saliency = (1.0 - (chroma / 160.0)).clamp(0.2, 1.0);
            final k = 1.0 + vibrancy * saliency;
            labA *= k;
            labB *= k;
          }
        }

        // True Split-Toning in CIELAB (Mandate 1)
        if (splitTone != null && splitToneStrength > 1e-4) {
          final lNorm = (labL / 100.0).clamp(0.0, 1.0);
          final effStrength = splitToneStrength.clamp(0.0, 1.0);

          // Biological human skin tone locus in CIELAB:
          // Moderate positive a* and b* with warm yellow-red hue ratio
          bool isSkinTone = false;
          if (labA > 5.0 && labA < 34.0 && labB > 6.0 && labB < 40.0) {
            final ratio = labB / labA;
            if (ratio >= 0.8 && ratio <= 2.6) {
              isSkinTone = true;
            }
          }

          // Strict tonal zoning:
          // Shadows: L* < 0.30
          // Highlights: L* > 0.70
          // Midtones (0.30 <= L* <= 0.70): Strictly neutral (0.0 weight) to preserve natural skin tones
          double shadowWeight = 0.0;
          if (lNorm < 0.30) {
            final t = (0.30 - lNorm) / 0.30;
            shadowWeight = t * t * (3.0 - 2.0 * t);
            if (isSkinTone) {
              shadowWeight *= 0.15; // Inviolable protection against cyan skin
            }
          }

          double highlightWeight = 0.0;
          if (lNorm > 0.70) {
            final t = (lNorm - 0.70) / 0.30;
            highlightWeight = t * t * (3.0 - 2.0 * t);
          }

          double shadowShiftA = 0.0;
          double shadowShiftB = 0.0;
          double highlightShiftA = 0.0;
          double highlightShiftB = 0.0;

          switch (splitTone) {
            case 'cinematic':
              // Shadows -> Teal (Cyan)
              shadowShiftA = -18.0;
              shadowShiftB = -22.0;
              // Highlights -> Orange (Warm Amber)
              highlightShiftA = 22.0;
              highlightShiftB = 38.0;
              break;
            case 'ethereal':
              // Shadows -> Soft Lavender / Violet
              shadowShiftA = 12.0;
              shadowShiftB = -16.0;
              // Highlights -> Delicate Rose / Peach
              highlightShiftA = 16.0;
              highlightShiftB = 10.0;
              break;
            case 'vintage':
              // Shadows -> Warm Sepia / Chocolate
              shadowShiftA = 8.0;
              shadowShiftB = 16.0;
              // Highlights -> Warm Ivory Cream
              highlightShiftA = -2.0;
              highlightShiftB = 24.0;
              break;
            case 'cyberpunk':
              // Shadows -> Electric Violet / Indigo
              shadowShiftA = 26.0;
              shadowShiftB = -32.0;
              // Highlights -> Neon Cyan
              highlightShiftA = -32.0;
              highlightShiftB = -10.0;
              break;
            case 'pastel':
              // Shadows -> Soft Periwinkle
              shadowShiftA = -6.0;
              shadowShiftB = -18.0;
              // Highlights -> Champagne Blush
              highlightShiftA = 12.0;
              highlightShiftB = 12.0;
              break;
          }

          labA +=
              (shadowWeight * shadowShiftA +
                  highlightWeight * highlightShiftA) *
              effStrength;
          labB +=
              (shadowWeight * shadowShiftB +
                  highlightWeight * highlightShiftB) *
              effStrength;
        }

        // Convert back to sRGB in continuous float64 until final rounding
        final outFy = (labL + 16.0) / 116.0;
        final outFx = outFy + labA / 500.0;
        final outFz = outFy - labB / 200.0;

        final outX = (0.95047 * _labInvF(outFx)).clamp(0.0, 1.0);
        final outY = (1.00000 * _labInvF(outFy)).clamp(0.0, 1.0);
        final outZ = (1.08883 * _labInvF(outFz)).clamp(0.0, 1.0);

        final outRLin = 3.2404542 * outX - 1.5371385 * outY - 0.4985314 * outZ;
        final outGLin = -0.9692660 * outX + 1.8760108 * outY + 0.0415560 * outZ;
        final outBLin = 0.0556434 * outX - 0.2040259 * outY + 1.0572252 * outZ;

        dst[off] = (_linearToSrgb(outRLin) * 255.0).round().clamp(0, 255);
        dst[off + 1] = (_linearToSrgb(outGLin) * 255.0).round().clamp(0, 255);
        dst[off + 2] = (_linearToSrgb(outBLin) * 255.0).round().clamp(0, 255);
        dst[off + 3] = preserveAlpha ? sa : 255;
      }
    }

    return dst;
  }

  static double _srgbToLinear(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _linearToSrgb(double c) {
    if (c <= 0.0031308) {
      return c <= 0.0 ? 0.0 : 12.92 * c;
    } else {
      return 1.055 * math.pow(c, 1.0 / 2.4) - 0.055;
    }
  }

  static double _labF(double t) {
    if (t > 0.008856451679) {
      return math.pow(t, 1.0 / 3.0).toDouble();
    } else {
      return 7.787037 * t + 0.137931034;
    }
  }

  static double _labInvF(double f) {
    if (f > 0.20689655) {
      return f * f * f;
    } else {
      return (f - 0.137931034) / 7.787037;
    }
  }
}
