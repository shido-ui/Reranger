import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../domain/recipes/render_graph.dart';
import '../data/autodraw_pipeline.dart';
import '../data/potrace_vectorizer.dart';
import '../data/video_timelapse_recorder.dart';
import '../domain/autodraw_models.dart';

/// Autodraw Studio Screen:
/// - 60FPS stroke-by-stroke rendering with strict 16ms frame budget (30-50 paths/frame).
/// - Real-time brush tip animation using [PathMetric].
/// - Stream-to-disk time-lapse video capture and hardware MediaCodec MP4 export.
class AutodrawScreen extends StatefulWidget {
  final String projectId;
  final Uint8List? sourceImageBytes;
  final Uint8List? processedImageBytes;
  final RenderGraph? renderGraph;
  final VideoTimelapseRecorder? recorderOverride;
  final int? thermalStatusOverride;

  const AutodrawScreen({
    super.key,
    required this.projectId,
    this.sourceImageBytes,
    this.processedImageBytes,
    this.renderGraph,
    this.recorderOverride,
    this.thermalStatusOverride,
  });

  @override
  State<AutodrawScreen> createState() => _AutodrawScreenState();
}

class _AutodrawScreenState extends State<AutodrawScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _canvasKey = GlobalKey();

  late final Ticker _ticker;
  late final VideoTimelapseRecorder _recorder;
  final PotraceVectorizer _vectorizer = const PotraceVectorizer();
  final AutodrawRenderCache _renderCache = AutodrawRenderCache();

  AutodrawVectorizationResult? _vectorResult;
  bool _isLoading = true;
  String? _errorMessage;

  bool _isPlaying = true;
  bool _isEncoding = false;

  bool _isThermalThrottled = false;
  bool _isProgressiveComplete = false;
  bool _isBufferingDetails = false;

  int _currentStrokeIndex = 0;
  double _currentStrokeProgress = 0.0;
  int _frameCounter = 0;

  // Maximum batch of paths advanced per 16ms frame budget
  static const int _maxPathsPerFrame = 40;

  @visibleForTesting
  Ticker get ticker => _ticker;

  @visibleForTesting
  VideoTimelapseRecorder get recorder => _recorder;

  @visibleForTesting
  int get currentStrokeIndex => _currentStrokeIndex;

  @visibleForTesting
  String? get errorMessage => _errorMessage;

  @visibleForTesting
  bool get isThermalThrottled => _isThermalThrottled;

  @visibleForTesting
  bool get isProgressiveComplete => _isProgressiveComplete;

  @visibleForTesting
  bool get isBufferingDetails => _isBufferingDetails;

  @override
  void initState() {
    super.initState();
    _recorder =
        widget.recorderOverride ??
        VideoTimelapseRecorder(
          repaintBoundaryKey: _canvasKey,
          tempRootDir: Directory.systemTemp,
          captureCadence: 4,
        );

    _ticker = createTicker(_onTick);
    _initializeAutodraw();
  }

  Future<void> _initializeAutodraw() async {
    try {
      // Mandate 3: Check Android thermal status before launching Isolate
      int thermalStatus = widget.thermalStatusOverride ?? 0;
      if (widget.thermalStatusOverride == null) {
        try {
          const channel = MethodChannel('com.reranger.app/media');
          final status = await channel
              .invokeMethod<int>('getThermalStatus')
              .timeout(const Duration(milliseconds: 200), onTimeout: () => 0);
          thermalStatus = status ?? 0;
        } catch (_) {
          thermalStatus = 0;
        }
      }

      // Severe (3) or Critical (4) thermal status triggers governor throttle
      final throttled = thermalStatus >= 3;
      if (mounted && throttled) {
        setState(() {
          _isThermalThrottled = true;
        });
      }

      Uint8List? rawBytes = widget.processedImageBytes;

      if (rawBytes == null) {
        // If renderGraph is supplied, run full shader pipeline with progressive streaming
        if (widget.renderGraph != null && widget.sourceImageBytes != null) {
          final pipeline = AutodrawPipeline();
          final stream = pipeline.processAndVectorizeProgressive(
            sourceImageBytes: widget.sourceImageBytes!,
            renderGraph: widget.renderGraph!,
            maxPaths: 2500,
            isThermalThrottled: throttled,
          );
          await for (final batch in stream) {
            if (!mounted) break;
            _handleProgressiveBatch(batch);
          }
          return;
        }

        rawBytes = widget.sourceImageBytes;
      }

      if (rawBytes == null) {
        // Fallback synthetic bitmap if no explicit bytes injected
        final fallback = img.Image(width: 64, height: 64, numChannels: 4);
        img.fill(fallback, color: img.ColorRgba8(50, 100, 180, 255));
        rawBytes = Uint8List.fromList(img.encodePng(fallback));
      }

      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        throw StateError('Could not decode source image for vectorization.');
      }

      final rgbaBytes = Uint8List.fromList(
        decoded.getBytes(order: img.ChannelOrder.rgba),
      );

      // Mandate 1: Progressive 2-phase streaming from background Isolate
      final stream = _vectorizer.vectorizeProgressive(
        rgbaBytes: rgbaBytes,
        width: decoded.width,
        height: decoded.height,
        maxPaths: 2500,
        isThermalThrottled: throttled,
      );

      await for (final batch in stream) {
        if (!mounted) break;
        _handleProgressiveBatch(batch);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Handles incoming progressive batches from the background Isolate
  void _handleProgressiveBatch(AutodrawProgressiveBatch batch) {
    if (batch.phase == 1) {
      // Phase 1 (Base Layer): Immediate playback start (< 1 second)
      setState(() {
        _vectorResult = AutodrawVectorizationResult(
          width: batch.width,
          height: batch.height,
          commands: batch.commands,
          flatStrokeBuffer: batch.flatStrokeBuffer,
        );
        _isLoading = false;
        _isProgressiveComplete = batch.isComplete;
      });
      _recorder.startRecording().then((_) {
        if (mounted && !_ticker.isActive) {
          _ticker.start();
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted && _recorder.isRecording) {
              await _recorder.captureFrame();
              if (mounted) setState(() {});
            }
          });
        }
      });
    } else if (batch.phase == 2) {
      // Phase 2 (Details): Buffer incoming detail strokes seamlessly
      setState(() {
        _vectorResult =
            _vectorResult?.copyWithAppended(newCommands: batch.commands) ??
            AutodrawVectorizationResult(
              width: batch.width,
              height: batch.height,
              commands: batch.commands,
              flatStrokeBuffer: batch.flatStrokeBuffer,
            );
        _isProgressiveComplete = true;
        _isBufferingDetails = false;
      });
      if (_isPlaying && !_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  /// 60FPS drawing loop with strict 16ms frame budget enforcement.
  void _onTick(Duration elapsed) {
    if (!_isPlaying || _vectorResult == null) return;
    final strokes = _vectorResult!.strokes;
    if (strokes.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    int pathsAdvancedInFrame = 0;

    // Mandate 3: Ensure Ticker is not skipping frames when CPU is loaded
    final allowedMaxPaths = _recorder.isRecording ? 1 : _maxPathsPerFrame;

    // Enforce 16ms frame budget
    while (pathsAdvancedInFrame < allowedMaxPaths &&
        stopwatch.elapsedMilliseconds < 14) {
      if (_currentStrokeIndex >= strokes.length) {
        if (!_isProgressiveComplete) {
          // Reached end of currently buffered strokes, wait for Phase 2 details
          if (!_isBufferingDetails) {
            setState(() {
              _isBufferingDetails = true;
            });
          }
          return;
        } else {
          _isPlaying = false;
          _ticker.stop();
          break;
        }
      }

      // Advance progress along the active Bézier stroke
      _currentStrokeProgress += 0.25; // 4 ticks per stroke
      if (_currentStrokeProgress >= 1.0) {
        _currentStrokeIndex++;
        _currentStrokeProgress = 0.0;
        pathsAdvancedInFrame++;
      } else {
        break;
      }
    }

    final frameIdx = _frameCounter++;
    debugPrint(
      '[AutodrawTicker] Advancing frame: $frameIdx, stroke: $_currentStrokeIndex / ${strokes.length}, progress: ${_currentStrokeProgress.toStringAsFixed(2)}',
    );

    setState(() {});

    // Time-lapse video capture: Ensure frame is painted before calling toImage()
    if (_recorder.isRecording && frameIdx % _recorder.captureCadence == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_recorder.isRecording) return;
        bool captured = await _recorder.captureFrame();
        if (!captured && _recorder.recordedFrameCount > 0) {
          // Mandate 3: If a frame drop occurs when CPU is loaded, repeat the last frame in video encoder
          captured = await _recorder.repeatLastFrame();
        }
        if (mounted && captured) {
          setState(() {}); // Update the Recorded: X frames UI counter
        }
      });
    }
  }

  Future<void> _saveVideo() async {
    if (_vectorResult == null || _isEncoding) return;
    HapticFeedback.mediumImpact();

    setState(() => _isEncoding = true);

    try {
      if (_recorder.recordedFrameCount == 0) {
        await _recorder.captureFrame();
      }
      // Mandate 4: 1080p resolution and 60fps frame rate for Instagram / TikTok
      final srcW = _vectorResult!.width > 0 ? _vectorResult!.width : 1080;
      final srcH = _vectorResult!.height > 0 ? _vectorResult!.height : 1080;
      int exportWidth;
      int exportHeight;
      if (srcW == srcH) {
        exportWidth = 1080;
        exportHeight = 1080;
      } else if (srcW < srcH) {
        exportWidth = 1080;
        exportHeight = ((1080 * srcH) / srcW).round();
      } else {
        exportHeight = 1080;
        exportWidth = ((1080 * srcW) / srcH).round();
      }
      // H.264 codecs require even dimensions
      if (exportWidth % 2 != 0) exportWidth -= 1;
      if (exportHeight % 2 != 0) exportHeight -= 1;

      // Encode frames directly via MediaStore MediaMuxer / FileDescriptor to Movies/Reranger
      final galleryPath = await _recorder.stopAndEncodeToGallery(
        width: exportWidth,
        height: exportHeight,
        fps: 60,
        bitRate: 8000000,
        title: 'reranger_autodraw_${widget.projectId}_1080p60',
      );
      debugPrint('[AutodrawScreen] Video saved to gallery: $galleryPath');

      if (mounted) {
        setState(() {
          _isEncoding = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video saved to Gallery!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEncoding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _restartAnimation() async {
    _ticker.stop();
    _renderCache.clear();
    setState(() {
      _currentStrokeIndex = 0;
      _currentStrokeProgress = 0.0;
      _isPlaying = true;
      _isBufferingDetails = false;
    });
    await _recorder.startRecording();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _renderCache.clear();
    _recorder.cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryText = isDark
        ? AppColorTokens.darkTextPrimary
        : AppColorTokens.lightTextPrimary;
    final secondaryText = isDark
        ? AppColorTokens.darkTextSecondary
        : AppColorTokens.lightTextSecondary;
    final accentColor = isDark
        ? AppColorTokens.darkAccentPrimary
        : AppColorTokens.lightAccentPrimary;
    final surfaceBase = isDark
        ? AppColorTokens.darkSurfaceBase
        : AppColorTokens.lightSurfaceBase;
    final surfaceElevated = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurfaceElevated;

    return Scaffold(
      backgroundColor: surfaceBase,
      appBar: AppBar(
        title: const Text('Autodraw Studio'),
        actions: [
          IconButton(
            key: const Key('autodraw_restart_button'),
            icon: const Icon(Icons.replay),
            tooltip: 'Replay Drawing',
            onPressed: _isLoading ? null : _restartAnimation,
          ),
          if (_isEncoding)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            FilledButton.icon(
              key: const Key('autodraw_save_video_button'),
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('Save Video'),
              onPressed: _isLoading || _recorder.recordedFrameCount == 0
                  ? null
                  : _saveVideo,
            ),
          const SizedBox(width: AppSpacingTokens.sm),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSpacingTokens.md),
                    Text(
                      'Preparing artist sequence...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            : Column(
                children: [
                  // Mandate 3: Thermal Governor Warning Banner
                  if (_isThermalThrottled)
                    Container(
                      key: const Key('autodraw_thermal_warning'),
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacingTokens.md,
                        vertical: AppSpacingTokens.xs,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacingTokens.sm,
                        vertical: AppSpacingTokens.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.amber.shade700,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Colors.amber.shade400,
                          ),
                          const SizedBox(width: AppSpacingTokens.xs),
                          Expanded(
                            child: Text(
                              'Device is hot. Reducing detail to protect battery.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade300,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Mandate 1: Subtle Progressive Buffering Indicator
                  if (_isBufferingDetails && !_isProgressiveComplete)
                    Container(
                      key: const Key('autodraw_preparing_details_banner'),
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacingTokens.md,
                        vertical: AppSpacingTokens.xs,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacingTokens.sm,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(accentColor),
                            ),
                          ),
                          const SizedBox(width: AppSpacingTokens.xs),
                          Text(
                            'Preparing details...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Drawing Canvas Viewport wrapped in RepaintBoundary for 60FPS stream-to-disk
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio:
                            (_vectorResult?.width ?? 1) /
                            (_vectorResult?.height ?? 1),
                        child: RepaintBoundary(
                          key: _canvasKey,
                          child: Container(
                            color: Colors.white,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: AutodrawPainter(
                                      strokes: _vectorResult?.strokes ?? [],
                                      completedCount: _currentStrokeIndex,
                                      currentProgress: _currentStrokeProgress,
                                      accentColor: accentColor,
                                      sourceWidth: _vectorResult?.width ?? 1,
                                      sourceHeight: _vectorResult?.height ?? 1,
                                      renderCache: _renderCache,
                                      flatBuffer: _vectorResult?.flatBuffer,
                                    ),
                                    size: Size.infinite,
                                  ),
                                ),
                                // Mandate 3: Tiny spinner overlay when buffering incoming details
                                if (_isBufferingDetails &&
                                    !_isProgressiveComplete)
                                  Center(
                                    child: Container(
                                      key: const Key(
                                        'autodraw_buffering_spinner',
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white24,
                                          width: 1,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                    Colors.white,
                                                  ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Preparing details...',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom Controls Dashboard
                  Container(
                    padding: const EdgeInsets.all(AppSpacingTokens.md),
                    decoration: BoxDecoration(
                      color: surfaceElevated,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? AppColorTokens.darkBorderSubtle
                              : AppColorTokens.lightBorderSubtle,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Bar & Tonal Stats (Horizontal scroll prevents overflow on narrow screens)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              Text(
                                'Strokes: $_currentStrokeIndex / ${_vectorResult?.strokes.length ?? 0}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: primaryText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: AppSpacingTokens.md),
                              Text(
                                'Recorded: ${_recorder.recordedFrameCount} frames (${(_recorder.totalBytesWritten / (1024 * 1024)).toStringAsFixed(1)} MB)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: secondaryText,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacingTokens.xs),
                        LinearProgressIndicator(
                          value: (_vectorResult?.strokes.isEmpty ?? true)
                              ? 0.0
                              : (_currentStrokeIndex /
                                        _vectorResult!.strokes.length)
                                    .clamp(0.0, 1.0),
                          backgroundColor: surfaceBase,
                          valueColor: AlwaysStoppedAnimation(accentColor),
                        ),
                        const SizedBox(height: AppSpacingTokens.sm),

                        // Play/Pause & Speed Row (Horizontal scroll with BouncingScrollPhysics prevents overflow)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: const Key('autodraw_play_pause_button'),
                                icon: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                ),
                                tooltip: _isPlaying ? 'Pause' : 'Play',
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _isPlaying = !_isPlaying;
                                    if (_isPlaying) {
                                      _ticker.start();
                                    } else {
                                      _ticker.stop();
                                    }
                                  });
                                },
                              ),
                              const SizedBox(width: AppSpacingTokens.xs),
                              Chip(
                                label: Text(
                                  'Background: ${_vectorResult?.backgroundCount ?? 0}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: surfaceBase,
                              ),
                              const SizedBox(width: AppSpacingTokens.xs),
                              Chip(
                                label: Text(
                                  'Midtones: ${_vectorResult?.midtonesCount ?? 0}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: surfaceBase,
                              ),
                              const SizedBox(width: AppSpacingTokens.xs),
                              Chip(
                                label: Text(
                                  'Highlights: ${_vectorResult?.highlightsCount ?? 0}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: surfaceBase,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Offscreen display-list cache leveraging [ui.Picture] to achieve locked 60FPS.
/// Once a stroke is drawn, it is recorded into this cached picture and never re-evaluated
/// on subsequent frames.
class AutodrawRenderCache {
  ui.Picture? _cachedPicture;
  ui.Image? _cachedImage;
  int _cachedStrokeCount = 0;
  Size _cachedSize = Size.zero;

  ui.Picture? get picture => _cachedPicture;
  ui.Image? get image => _cachedImage;
  int get cachedStrokeCount => _cachedStrokeCount;

  void update({
    required List<AutodrawStroke> strokes,
    required int targetCount,
    required Size size,
    required double scaleX,
    required double scaleY,
  }) {
    if (size != _cachedSize) {
      clear();
      _cachedSize = size;
    }

    final end = targetCount.clamp(0, strokes.length);
    if (end <= _cachedStrokeCount) {
      if (end < _cachedStrokeCount) {
        clear();
        _cachedSize = size;
      } else {
        return;
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.width, size.height),
    );

    if (_cachedImage != null) {
      canvas.drawImage(_cachedImage!, Offset.zero, Paint()..isAntiAlias = true);
    } else if (_cachedPicture != null) {
      canvas.drawPicture(_cachedPicture!);
    }

    for (int i = _cachedStrokeCount; i < end; i++) {
      AutodrawPainter.drawTaperedStroke(
        canvas: canvas,
        stroke: strokes[i],
        scaleX: scaleX,
        scaleY: scaleY,
        progress: 1.0,
      );
    }

    final newPicture = recorder.endRecording();
    _cachedPicture?.dispose();
    _cachedPicture = newPicture;
    try {
      final imgW = size.width.ceil().clamp(1, 4096);
      final imgH = size.height.ceil().clamp(1, 4096);
      final newImg = newPicture.toImageSync(imgW, imgH);
      _cachedImage?.dispose();
      _cachedImage = newImg;
    } catch (_) {
      // Graceful fallback if toImageSync is unsupported in test VM
    }
    _cachedStrokeCount = end;
  }

  void clear() {
    _cachedImage?.dispose();
    _cachedImage = null;
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedStrokeCount = 0;
    _cachedSize = Size.zero;
  }
}

/// CustomPainter rendering Bézier stroke paths with artist brush dynamics:
/// - Dynamic pressure tapering (0.5px start -> 2.2px mid -> 0.5px end) via [ui.PathMetric].
/// - Realistic ink blending with [BlendMode.multiply] for authentic watercolor/ink cross-mixing.
/// - Locked 60FPS performance via offscreen [AutodrawRenderCache] display lists.
/// - Dynamic Brush Tip effect via [PathMetric] tangents at the active leading edge.
class AutodrawPainter extends CustomPainter {
  final List<AutodrawStroke> strokes;
  final int completedCount;
  final double currentProgress;
  final Color accentColor;
  final int sourceWidth;
  final int sourceHeight;
  final AutodrawRenderCache? renderCache;
  final FlatStrokeBuffer? flatBuffer;

  const AutodrawPainter({
    required this.strokes,
    required this.completedCount,
    required this.currentProgress,
    required this.accentColor,
    required this.sourceWidth,
    required this.sourceHeight,
    this.renderCache,
    this.flatBuffer,
  });

  /// Draws an artist-grade brush stroke:
  /// - Pass 1 (Lines): Crisp contour ink sketch (strokeWidth = 1.5).
  /// - Pass 2 (Fills): Broad painterly color brush strokes and closed region fills.
  /// - Pass 3 (Highlights): Crisp gleaming highlight strokes.
  static void drawTaperedStroke({
    required Canvas canvas,
    required AutodrawCommand stroke,
    required double scaleX,
    required double scaleY,
    required double progress,
  }) {
    if (progress <= 0.0) return;

    final scaledPath = stroke.toScaledPath(scaleX, scaleY);

    // If it's a closed fill region and progress has reached completion, fill the interior
    if (stroke.actionType == AutodrawActionType.fillRegion &&
        stroke.isClosed &&
        progress >= 0.85) {
      final fillAlpha = ((progress - 0.85) / 0.15).clamp(0.0, 1.0);
      final fillPaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.srcOver
        ..color = stroke.strokeColor.withValues(
          alpha: (stroke.strokeColor.a * 0.88 * fillAlpha).clamp(0.0, 1.0),
        );
      canvas.drawPath(scaledPath, fillPaint);
    }

    final isFill = stroke.actionType == AutodrawActionType.fillRegion;
    final isLine = stroke.actionType == AutodrawActionType.drawLine;
    final baseColor = stroke.strokeColor;
    // Mandate 2: Calculate stroke width dynamically using Distance Transform (1.0px thin to wider brush)
    final dynamicWidth = stroke.strokeWidth.clamp(1.0, 20.0);

    // Mandate 2: When a line stroke is fully drawn, render continuous path with rounded joints & dynamic width
    if (isLine && progress >= 1.0) {
      final paint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.multiply
        ..color = baseColor
        ..strokeWidth = dynamicWidth;
      canvas.drawPath(scaledPath, paint);
      return;
    }

    final metrics = scaledPath.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final maxAllowedWidth = isFill
        ? stroke.strokeWidth.clamp(4.0, 24.0)
        : isLine
        ? dynamicWidth
        : stroke.strokeWidth.clamp(1.0, 3.0);

    final minWidth = isFill
        ? (maxAllowedWidth * 0.45)
        : math.max(1.0, dynamicWidth * 0.4);

    for (final metric in metrics) {
      final totalLen = metric.length;
      if (totalLen <= 0) continue;

      final targetLen = totalLen * progress.clamp(0.0, 1.0);
      if (targetLen <= 0) continue;

      // Adaptive segment subdivision (3.0 - 7.0 logical px) for smooth curvature and tapering
      final stepLen = (targetLen / 16.0).clamp(3.0, 8.0);
      final segmentCount = (targetLen / stepLen).ceil().clamp(1, 48);

      for (int i = 0; i < segmentCount; i++) {
        final startD = i * (targetLen / segmentCount);
        final endD = math.min(
          (i + 1) * (targetLen / segmentCount) + 0.5,
          targetLen,
        );
        if (endD <= startD) continue;

        final segPath = metric.extractPath(startD, endD);

        // Normalized position along the full stroke [0.0, 1.0]
        final midD = (startD + endD) * 0.5;
        final t = (midD / totalLen).clamp(0.0, 1.0);

        // Brush Dynamics: Interpolate strokeWidth based on position
        final pressure = math.sin(math.pi * t);
        final strokeWidth = minWidth + (maxAllowedWidth - minWidth) * pressure;

        // Tail opacity fade
        double opacity = 1.0;
        if (t > 0.8 && !isFill) {
          final fadeFactor = (t - 0.8) / 0.2; // 0.0 to 1.0
          opacity = 1.0 - (0.45 * fadeFactor);
        }

        final segColor = baseColor.withValues(
          alpha: (baseColor.a * opacity).clamp(0.0, 1.0),
        );

        final paint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..blendMode = isFill ? BlendMode.srcOver : BlendMode.multiply
          ..color = segColor
          ..strokeWidth = strokeWidth.clamp(1.0, 20.0);

        canvas.drawPath(segPath, paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    final srcW = sourceWidth > 0
        ? sourceWidth.toDouble()
        : (size.width > 0 ? size.width : 1.0);
    final srcH = sourceHeight > 0
        ? sourceHeight.toDouble()
        : (size.height > 0 ? size.height : 1.0);

    // Coordinate scaling: map native bitmap coordinates to logical screen pixels
    final scaleX = size.width / srcW;
    final scaleY = size.height / srcH;

    // 1. Mandate 3: 60FPS Performance - Update and draw cached picture of completed strokes
    if (renderCache != null) {
      renderCache!.update(
        strokes: strokes,
        targetCount: completedCount,
        size: size,
        scaleX: scaleX,
        scaleY: scaleY,
      );

      if (renderCache!.image != null) {
        canvas.drawImage(
          renderCache!.image!,
          Offset.zero,
          Paint()..isAntiAlias = true,
        );
      } else if (renderCache!.picture != null) {
        canvas.drawPicture(renderCache!.picture!);
      }
    } else {
      // Fallback if renderCache is omitted
      final end = completedCount.clamp(0, strokes.length);
      for (int i = 0; i < end; i++) {
        drawTaperedStroke(
          canvas: canvas,
          stroke: strokes[i],
          scaleX: scaleX,
          scaleY: scaleY,
          progress: 1.0,
        );
      }
    }

    // 2. Draw currently animating active stroke
    if (completedCount < strokes.length && currentProgress > 0.0) {
      final activeStroke = strokes[completedCount];
      drawTaperedStroke(
        canvas: canvas,
        stroke: activeStroke,
        scaleX: scaleX,
        scaleY: scaleY,
        progress: currentProgress,
      );

      // Draw Brush Tip indicator at the leading edge
      final activePath = activeStroke.toScaledPath(scaleX, scaleY);
      final metrics = activePath.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final targetLen =
            metrics.first.length * currentProgress.clamp(0.0, 1.0);
        final tangent = metrics.first.getTangentForOffset(targetLen);
        if (tangent != null) {
          final tipPaint = Paint()
            ..isAntiAlias = true
            ..color = accentColor.withValues(alpha: 0.9)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(tangent.position, 3.5, tipPaint);

          final glowPaint = Paint()
            ..isAntiAlias = true
            ..color = Colors.white.withValues(alpha: 0.85)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(tangent.position, 1.8, glowPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant AutodrawPainter oldDelegate) {
    return oldDelegate.completedCount != completedCount ||
        oldDelegate.currentProgress != currentProgress ||
        oldDelegate.sourceWidth != sourceWidth ||
        oldDelegate.sourceHeight != sourceHeight;
  }
}
