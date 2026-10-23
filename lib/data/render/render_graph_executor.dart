import 'dart:math' as math;
import 'dart:typed_data';

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
  }) async {
    // 1. Validate graph topology and parameters
    graph.validate();

    if (isCancelled != null && isCancelled()) {
      throw RenderGraphCancelledFailure(graph.id);
    }

    // 2. Obtain deterministic topological execution order
    final orderedNodes = graph.getTopologicalExecutionOrder();

    // 3. Resolve source image dimensions and RGBA buffer with LRU cache
    SourceImageNode? sourceNode;
    for (final node in orderedNodes) {
      if (node is SourceImageNode) {
        sourceNode = node;
        break;
      }
    }

    final sourceKey = sourceNode != null
        ? '${sourceNode.sourceImageHash}@${renderScale.toStringAsFixed(4)}'
        : null;

    Uint8List sourceRgba;
    int targetW;
    int targetH;

    if (sourceKey != null && _sourceBufferCache.containsKey(sourceKey)) {
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

      if (sourceKey != null) {
        if (_sourceBufferCache.length >= _maxSourceCacheEntries) {
          _sourceBufferCache.remove(_sourceBufferCache.keys.first);
        }
        _sourceBufferCache[sourceKey] = (
          rgba: sourceRgba,
          width: targetW,
          height: targetH,
        );
      }
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
      );
      nodeCacheKeys[node.id] = nodeKey;

      // Check cache for intermediate result
      final cachedBuffer = cache.get(nodeKey);
      if (cachedBuffer != null) {
        nodeOutputs[node.id] = cachedBuffer;
        continue; // Cache hit: skip computation
      }

      // Cache miss: execute node compute
      executedCount++;
      final outputBuffer = _executeNode(
        node: node,
        sourceRgba: sourceRgba,
        width: targetW,
        height: targetH,
        nodeOutputs: nodeOutputs,
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
  }) {
    if (node is SourceImageNode) {
      return Uint8List.fromList(sourceRgba);
    } else if (node is GrayscaleNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeGrayscale(input, width, height, node.preserveAlpha);
    } else if (node is SobelEdgeNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeSobel(
        input,
        width,
        height,
        node.edgeThreshold,
        node.invertOutput,
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
      );
    } else if (node is GrainOverlayNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeGrainOverlay(
        input,
        width,
        height,
        node.intensity,
        node.seed,
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
      );
    } else if (node is AdversarialStealthNode) {
      final input = nodeOutputs[node.inputNodeIds[0]]!;
      return _computeAdversarialStealth(
        input: input,
        width: width,
        height: height,
        strength: node.strength,
        applyFrequencyPerturbation: node.applyFrequencyPerturbation,
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
    bool preserveAlpha,
  ) {
    final total = w * h;
    final dst = Uint8List(total * 4);
    for (int i = 0; i < total; i++) {
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
    bool invert,
  ) {
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
    double gamma,
  ) {
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
    int seed,
  ) {
    final total = w * h;
    final dst = Uint8List(total * 4);

    int prngState = seed & 0xFFFFFFFF;

    for (int i = 0; i < total; i++) {
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
    double vignetteFalloff,
  ) {
    final total = w * h;
    final dst = Uint8List(total * 4);
    final centerX = w / 2.0;
    final centerY = h / 2.0;
    final maxDist = math.sqrt(centerX * centerX + centerY * centerY);

    for (int y = 0; y < h; y++) {
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
  }) {
    final totalPixels = width * height;
    final output = Uint8List(totalPixels * 4);

    RegionMask? explicitMask;
    if (maskBase64 != null) {
      try {
        explicitMask = RegionMask.fromBase64(
          width: width,
          height: height,
          base64String: maskBase64,
        );
      } catch (_) {
        explicitMask = null;
      }
    }

    final targetHsl = ColorRgb(targetR, targetG, targetB).toHsl();
    final sourceHsl = ColorRgb(sourceR, sourceG, sourceB).toHsl();
    const maxDist = 441.67295593; // 255 * sqrt(3)
    final tolDist = tolerance * maxDist;
    final featherDist = feather * maxDist;

    for (int i = 0; i < totalPixels; i++) {
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
        // Input pixel HSL
        final inHsl = ColorRgb(rIn, gIn, bIn).toHsl();

        // Low saturation protection: if input pixel has very low saturation (< 0.08)
        // and user did NOT select an achromatic source color (sourceHsl.s >= 0.08),
        // dampen chrominance transfer to prevent noisy colors in neutrals.
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

          // Residual 1-step integer correction for exact luma matching
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

      // Interpolate with original pixel according to effectiveWeight
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
}
