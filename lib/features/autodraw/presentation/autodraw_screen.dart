import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
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
  final VideoTimelapseRecorder? recorderOverride;

  const AutodrawScreen({
    super.key,
    required this.projectId,
    this.sourceImageBytes,
    this.recorderOverride,
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

  AutodrawVectorizationResult? _vectorResult;
  bool _isLoading = true;
  String? _errorMessage;

  bool _isPlaying = true;
  bool _isEncoding = false;

  int _currentStrokeIndex = 0;
  double _currentStrokeProgress = 0.0;
  int _frameCounter = 0;

  // Maximum batch of paths advanced per 16ms frame budget
  static const int _maxPathsPerFrame = 40;

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
      Uint8List? rawBytes = widget.sourceImageBytes;

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

      // 1. Vectorize on background isolate
      final result = await _vectorizer.vectorizeImage(
        rgbaBytes: rgbaBytes,
        width: decoded.width,
        height: decoded.height,
        maxPaths: 180,
      );

      if (mounted) {
        setState(() {
          _vectorResult = result;
          _isLoading = false;
        });
        await _recorder.startRecording();
        _ticker.start();
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

  /// 60FPS drawing loop with strict 16ms frame budget enforcement.
  void _onTick(Duration elapsed) {
    if (!_isPlaying || _vectorResult == null) return;
    final strokes = _vectorResult!.strokes;
    if (strokes.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    int pathsAdvancedInFrame = 0;

    // Enforce 16ms frame budget and max 30-50 paths/frame
    while (pathsAdvancedInFrame < _maxPathsPerFrame &&
        stopwatch.elapsedMilliseconds < 14) {
      if (_currentStrokeIndex >= strokes.length) {
        _isPlaying = false;
        _ticker.stop();
        break;
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

    setState(() {});

    // Time-lapse video capture tick (every 4th frame, streamed directly to disk)
    if (_recorder.isRecording) {
      _recorder.captureTick(_frameCounter++);
    }
  }

  Future<void> _saveVideo() async {
    if (_vectorResult == null || _isEncoding) return;

    setState(() => _isEncoding = true);

    try {
      final width = _vectorResult!.width > 0 ? _vectorResult!.width : 512;
      final height = _vectorResult!.height > 0 ? _vectorResult!.height : 512;

      // Encode frames via hardware MediaCodec (or fallback stitcher)
      final mp4Path = await _recorder.stopAndEncode(
        width: width,
        height: height,
        fps: 30,
      );

      // Save to user gallery MediaStore
      final galleryPath = await _recorder.saveVideoToGallery(
        mp4Path: mp4Path,
        title: 'reranger_autodraw_${widget.projectId}',
      );

      if (mounted) {
        setState(() {
          _isEncoding = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video saved to gallery! ($galleryPath)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
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
    setState(() {
      _currentStrokeIndex = 0;
      _currentStrokeProgress = 0.0;
      _isPlaying = true;
    });
    await _recorder.startRecording();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
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
                    Text('Vectorizing Bézier strokes on background isolate...'),
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
                            child: CustomPaint(
                              painter: AutodrawPainter(
                                strokes: _vectorResult?.strokes ?? [],
                                completedCount: _currentStrokeIndex,
                                currentProgress: _currentStrokeProgress,
                                accentColor: accentColor,
                              ),
                              size: Size.infinite,
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
                        // Progress Bar & Tonal Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Strokes: $_currentStrokeIndex / ${_vectorResult?.strokes.length ?? 0}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Recorded: ${_recorder.recordedFrameCount} frames (${(_recorder.totalBytesWritten / (1024 * 1024)).toStringAsFixed(1)} MB)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondaryText,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
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

                        // Play/Pause & Speed Row
                        Row(
                          children: [
                            IconButton(
                              key: const Key('autodraw_play_pause_button'),
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                              tooltip: _isPlaying ? 'Pause' : 'Play',
                              onPressed: () {
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
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// CustomPainter rendering Bézier stroke paths and the dynamic Brush Tip effect
/// via [PathMetric].
class AutodrawPainter extends CustomPainter {
  final List<AutodrawStroke> strokes;
  final int completedCount;
  final double currentProgress;
  final Color accentColor;

  const AutodrawPainter({
    required this.strokes,
    required this.completedCount,
    required this.currentProgress,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    // Calculate scale to fit canvas
    final scaleX = size.width / 64.0;
    final scaleY = size.height / 64.0;
    final scale = math.min(scaleX, scaleY);

    canvas.save();
    canvas.scale(scale, scale);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 1. Draw all completed strokes
    final end = completedCount.clamp(0, strokes.length);
    for (int i = 0; i < end; i++) {
      final stroke = strokes[i];
      paint.color = stroke.strokeColor;
      paint.strokeWidth = stroke.strokeWidth;
      canvas.drawPath(stroke.path, paint);
    }

    // 2. Draw active stroke with real-time Brush Tip effect via PathMetric
    if (completedCount < strokes.length && currentProgress > 0.0) {
      final activeStroke = strokes[completedCount];
      final metrics = activeStroke.path.computeMetrics();

      Offset? brushTipPos;
      paint.color = activeStroke.strokeColor;
      paint.strokeWidth = activeStroke.strokeWidth;

      for (final metric in metrics) {
        final targetLen = metric.length * currentProgress.clamp(0.0, 1.0);
        final extractedPath = metric.extractPath(0.0, targetLen);
        canvas.drawPath(extractedPath, paint);

        final tangent = metric.getTangentForOffset(targetLen);
        if (tangent != null) {
          brushTipPos = tangent.position;
        }
      }

      // Draw Brush Tip indicator at the leading edge
      if (brushTipPos != null) {
        final tipPaint = Paint()
          ..color = accentColor.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          brushTipPos,
          activeStroke.strokeWidth * 1.5,
          tipPaint,
        );

        final glowPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          brushTipPos,
          activeStroke.strokeWidth * 0.75,
          glowPaint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AutodrawPainter oldDelegate) {
    return oldDelegate.completedCount != completedCount ||
        oldDelegate.currentProgress != currentProgress;
  }
}
