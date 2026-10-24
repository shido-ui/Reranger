import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../../core/routing/route_names.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../domain/color/color_palette.dart';
import '../../../domain/layers/editor_layer.dart';
import '../../../domain/layers/history_command.dart';
import '../../../domain/segmentation/smart_select_category.dart';
import '../../editor/presentation/editor_providers.dart';
import 'recolor_controller.dart';

/// SCR-07: Recolor Studio Screen (Level 1 Single-Tap Palette Remapping with Level 2 Tolerance Math).
class RecolorScreen extends ConsumerStatefulWidget {
  final String projectId;
  final RecolorController? controller;

  const RecolorScreen({super.key, required this.projectId, this.controller});

  @override
  ConsumerState<RecolorScreen> createState() => _RecolorScreenState();
}

class _RecolorScreenState extends ConsumerState<RecolorScreen> {
  RecolorController? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _previewPng;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller;
      _controller!.addListener(_onControllerUpdated);
      _isLoading = false;
      _updatePreview();
    } else {
      _loadFromProject();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdated);
    super.dispose();
  }

  void _onControllerUpdated() {
    _updatePreview();
    if (mounted) setState(() {});
  }

  Future<void> _loadFromProject() async {
    try {
      final editorCtrl = ref.read(editorControllerProvider(widget.projectId));
      await editorCtrl.loadProject(widget.projectId);

      final project = editorCtrl.project;
      final sourceBytes = editorCtrl.sourceImageBytes;

      if (project == null || sourceBytes == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Project media could not be loaded.';
            _isLoading = false;
          });
        }
        return;
      }

      // Extract raw RGBA bytes for RecolorController
      Uint8List rawRgba;
      if (sourceBytes.length ==
          project.sourceWidth * project.sourceHeight * 4) {
        rawRgba = sourceBytes;
      } else {
        final decoded = img.decodeImage(sourceBytes);
        if (decoded != null) {
          rawRgba = decoded.getBytes(order: img.ChannelOrder.rgba);
        } else {
          rawRgba = sourceBytes;
        }
      }

      final palette = ColorPalette.extractDominant(
        id: 'palette_${project.id}',
        name: 'Extracted Palette',
        rgbaBytes: rawRgba,
        width: project.sourceWidth,
        height: project.sourceHeight,
        k: 6,
      );

      final ctrl = RecolorController(
        sourceRgba: rawRgba,
        imageWidth: project.sourceWidth,
        imageHeight: project.sourceHeight,
        sourceImageHash: project.sourceImageHash,
        initialPalette: palette,
      );

      // Restore prior recolor edits if an adjustment layer already exists
      final existingRecolor = editorCtrl
          .layerHistoryController
          ?.state
          .layerStack
          .layers
          .whereType<AdjustmentLayer>()
          .where((l) => l.effectType == 'recolor')
          .lastOrNull;

      if (existingRecolor != null) {
        final params = existingRecolor.parameters;
        final srcR = params['sourceR'] as int?;
        final srcG = params['sourceG'] as int?;
        final srcB = params['sourceB'] as int?;
        final tgtR = params['targetR'] as int?;
        final tgtG = params['targetG'] as int?;
        final tgtB = params['targetB'] as int?;
        final tol = (params['tolerance'] as num?)?.toDouble() ?? 0.20;
        final fth = (params['feather'] as num?)?.toDouble() ?? 0.10;

        if (srcR != null && srcG != null && srcB != null) {
          final colorIdx = palette.colors.indexWhere(
            (c) =>
                (c.r - srcR).abs() + (c.g - srcG).abs() + (c.b - srcB).abs() <
                15,
          );
          if (colorIdx != -1) {
            ctrl.selectPaletteColor(colorIdx);
          }
        }

        if (tgtR != null && tgtG != null && tgtB != null) {
          ctrl.setTargetColor(ColorRgb(tgtR, tgtG, tgtB));
        }

        ctrl.setStrength(existingRecolor.opacity);
        ctrl.setTolerance(tol);
        ctrl.setFeather(fth);
      }

      if (mounted) {
        setState(() {
          _controller = ctrl;
          _controller!.addListener(_onControllerUpdated);
          _isLoading = false;
        });
        _updatePreview();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize Recolor Studio: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _updatePreview() {
    final ctrl = _controller;
    if (ctrl == null) return;

    final state = ctrl.state;
    final w = ctrl.imageWidth;
    final h = ctrl.imageHeight;

    // Fast preview generation
    final outBytes = Uint8List(w * h * 4);
    final src = ctrl.sourceRgba;

    if (state.isComparing) {
      outBytes.setAll(0, src);
    } else {
      final target = state.targetColor;
      final mask = state.activeMask;

      for (int i = 0; i < w * h; i++) {
        final off = i * 4;
        final r = src[off];
        final g = src[off + 1];
        final b = src[off + 2];
        final a = src[off + 3];

        if (state.isMaskPreviewActive) {
          final maskWeight = (mask != null && i < mask.buffer.length)
              ? mask.buffer[i]
              : 0;
          if (maskWeight > 32) {
            // Ruby red overlay
            outBytes[off] = ((r * 0.4) + 150).round().clamp(0, 255);
            outBytes[off + 1] = (g * 0.4).round().clamp(0, 255);
            outBytes[off + 2] = (b * 0.4).round().clamp(0, 255);
            outBytes[off + 3] = a;
            continue;
          }
        }

        if (target != null) {
          final maskWeight =
              ((mask != null && i < mask.buffer.length)
                  ? mask.buffer[i]
                  : 255) /
              255.0;
          final effectiveWeight = maskWeight * state.strength;

          if (effectiveWeight > 1e-3) {
            final blendedR =
                (r * (1.0 - effectiveWeight) + target.r * effectiveWeight)
                    .round()
                    .clamp(0, 255);
            final blendedG =
                (g * (1.0 - effectiveWeight) + target.g * effectiveWeight)
                    .round()
                    .clamp(0, 255);
            final blendedB =
                (b * (1.0 - effectiveWeight) + target.b * effectiveWeight)
                    .round()
                    .clamp(0, 255);

            outBytes[off] = blendedR;
            outBytes[off + 1] = blendedG;
            outBytes[off + 2] = blendedB;
            outBytes[off + 3] = a;
          } else {
            outBytes[off] = r;
            outBytes[off + 1] = g;
            outBytes[off + 2] = b;
            outBytes[off + 3] = a;
          }
        } else {
          outBytes[off] = r;
          outBytes[off + 1] = g;
          outBytes[off + 2] = b;
          outBytes[off + 3] = a;
        }
      }
    }

    final image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: outBytes.buffer,
      order: img.ChannelOrder.rgba,
    );
    _previewPng = Uint8List.fromList(img.encodePng(image, level: 0));
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
    final surfaceElevated = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurfaceElevated;
    final surfaceBase = isDark
        ? AppColorTokens.darkSurfaceBase
        : AppColorTokens.lightSurfaceBase;
    final borderSubtle = isDark
        ? AppColorTokens.darkBorderSubtle
        : AppColorTokens.lightBorderSubtle;

    final ctrl = _controller;

    return Scaffold(
      backgroundColor: surfaceBase,
      appBar: AppBar(
        title: const Text('Recolor Studio'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Editor',
          onPressed: () {
            if (GoRouter.maybeOf(context) != null &&
                GoRouter.of(context).canPop()) {
              GoRouter.of(context).pop();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(
                AppRouteNames.editor.replaceAll(':id', widget.projectId),
              );
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: ctrl?.state.canUndo == true ? () => ctrl?.undo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: ctrl?.state.canRedo == true ? () => ctrl?.redo() : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Colors',
            onPressed: () => ctrl?.reset(),
          ),
          TextButton(
            onPressed: () {
              final activeCtrl = _controller;
              if (activeCtrl != null) {
                final srcColor = activeCtrl.state.activeSourceColor;
                final tgtColor = activeCtrl.state.targetColor;

                if (srcColor != null && tgtColor != null) {
                  final editorCtrl = ref.read(
                    editorControllerProvider(widget.projectId),
                  );
                  final historyCtrl = editorCtrl.layerHistoryController;

                  final existingRecolor = historyCtrl?.state.layerStack.layers
                      .whereType<AdjustmentLayer>()
                      .where((l) => l.effectType == 'recolor')
                      .lastOrNull;

                  final maskBase64 = activeCtrl.state.activeMask?.toBase64();
                  final params = <String, dynamic>{
                    'sourceR': srcColor.r,
                    'sourceG': srcColor.g,
                    'sourceB': srcColor.b,
                    'targetR': tgtColor.r,
                    'targetG': tgtColor.g,
                    'targetB': tgtColor.b,
                    'tolerance': activeCtrl.state.tolerance,
                    'feather': activeCtrl.state.feather,
                    'preserveLuminance': activeCtrl.state.preserveLuminance,
                    'maskBase64': ?maskBase64,
                  };

                  if (existingRecolor != null && historyCtrl != null) {
                    historyCtrl.executeCommand(
                      UpdateAdjustmentParametersCommand(
                        layerId: existingRecolor.id,
                        oldParameters: existingRecolor.parameters,
                        newParameters: params,
                      ),
                    );
                    historyCtrl.setLayerOpacity(
                      existingRecolor.id,
                      activeCtrl.state.strength,
                    );
                  } else if (historyCtrl != null) {
                    final newLayer = AdjustmentLayer(
                      id: 'recolor_${DateTime.now().millisecondsSinceEpoch}',
                      name:
                          'Recolor (${srcColor.toHex()} -> ${tgtColor.toHex()})',
                      opacity: activeCtrl.state.strength,
                      effectType: 'recolor',
                      parameters: params,
                    );
                    historyCtrl.addAdjustmentLayer(newLayer);
                  }
                  editorCtrl.setActiveStudio('recolor');
                }
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Recolor applied non-destructively to project!',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
              Navigator.of(context).maybePop();
            },
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacingTokens.lg),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            )
          : Column(
              children: [
                // Viewport with hold-to-compare and Tap-to-Recolor (EdgeTAM)
                Expanded(
                  flex: 5,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onLongPressStart: (_) => ctrl?.setComparing(true),
                        onLongPressEnd: (_) => ctrl?.setComparing(false),
                        onTapUp: (details) {
                          if (ctrl == null) return;
                          ctrl.handleCanvasTap(
                            viewX: details.localPosition.dx,
                            viewY: details.localPosition.dy,
                            viewSize: Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            ),
                          );
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              color: Colors.black,
                              width: double.infinity,
                              height: double.infinity,
                              child: _previewPng != null
                                  ? Image.memory(
                                      _previewPng!,
                                      fit: BoxFit.contain,
                                    )
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                            ),
                            if (ctrl?.state.isSegmenting == true)
                              Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        color: Colors.white,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Segmenting with EdgeTAM...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (ctrl?.state.isComparing == true)
                              Positioned(
                                top: AppSpacingTokens.md,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: const Text(
                                    'ORIGINAL PHOTO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            // Floating Smart Select pills over canvas
                            Positioned(
                              bottom: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.70),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.touch_app,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    ...[
                                      SmartSelectCategory.hair,
                                      SmartSelectCategory.face,
                                      SmartSelectCategory.clothing,
                                      SmartSelectCategory.background,
                                    ].map((cat) {
                                      final isSelected =
                                          ctrl?.state.activeSmartCategory ==
                                          cat;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 3,
                                        ),
                                        child: Listener(
                                          behavior: HitTestBehavior.opaque,
                                          onPointerUp: (_) {
                                            ctrl?.setSmartSelectCategory(cat);
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? accentColor
                                                  : Colors.white.withValues(
                                                      alpha: 0.15,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              cat.label,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.white70,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    if (ctrl?.state.activeMask != null) ...[
                                      const SizedBox(width: 4),
                                      Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerUp: (_) =>
                                            ctrl?.clearActiveMask(),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(
                                              alpha: 0.4,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Text(
                                            'Clear',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Controls Panel
                Expanded(
                  flex: 4,
                  child: Material(
                    color: surfaceElevated,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacingTokens.md),
                      children: [
                        // 1. Source Palette
                        Text(
                          'Select Color to Remap',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: primaryText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacingTokens.xs),
                        if (ctrl?.state.extractedPalette != null)
                          SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount:
                                  ctrl!.state.extractedPalette!.colors.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: AppSpacingTokens.sm),
                              itemBuilder: (context, idx) {
                                final color =
                                    ctrl.state.extractedPalette!.colors[idx];
                                final isSelected =
                                    ctrl.state.selectedColorIndex == idx;
                                return GestureDetector(
                                  onTap: () => ctrl.selectPaletteColor(idx),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Color.fromARGB(
                                        color.a,
                                        color.r,
                                        color.g,
                                        color.b,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? accentColor
                                            : borderSubtle,
                                        width: isSelected ? 3.5 : 1.5,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Icon(
                                            Icons.check,
                                            size: 20,
                                            color: color.luminance > 128
                                                ? Colors.black
                                                : Colors.white,
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),

                        const SizedBox(height: AppSpacingTokens.md),

                        // 2. Harmonic Suggestions & Target Color
                        Text(
                          'Target Replacement Color',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: primaryText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacingTokens.xs),
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              // Standard Vibrant Targets
                              ..._standardTargetColors.map((c) {
                                final isSelected = ctrl?.state.targetColor == c;
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacingTokens.sm,
                                  ),
                                  child: GestureDetector(
                                    onTap: () => ctrl?.setTargetColor(c),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Color.fromARGB(
                                          c.a,
                                          c.r,
                                          c.g,
                                          c.b,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? accentColor
                                              : borderSubtle,
                                          width: isSelected ? 3.5 : 1.5,
                                        ),
                                      ),
                                      child: isSelected
                                          ? Icon(
                                              Icons.check,
                                              size: 20,
                                              color: c.luminance > 128
                                                  ? Colors.black
                                                  : Colors.white,
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppSpacingTokens.md),

                        // Level 2 Progressive Disclosure: Tolerance & Feather
                        ExpansionTile(
                          title: const Text('Precision & Mask Controls'),
                          subtitle: Text(
                            'Tolerance: ${((ctrl?.state.tolerance ?? 0.2) * 100).round()}% | Feather: ${((ctrl?.state.feather ?? 0.1) * 100).round()}%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondaryText,
                            ),
                          ),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Color Tolerance'),
                                Text(
                                  '${((ctrl?.state.tolerance ?? 0.2) * 100).round()}%',
                                ),
                              ],
                            ),
                            Slider(
                              value: ctrl?.state.tolerance ?? 0.20,
                              min: 0.05,
                              max: 0.80,
                              onChanged: (v) => ctrl?.setTolerance(v),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Edge Feathering'),
                                Text(
                                  '${((ctrl?.state.feather ?? 0.1) * 100).round()}%',
                                ),
                              ],
                            ),
                            Slider(
                              value: ctrl?.state.feather ?? 0.10,
                              min: 0.0,
                              max: 0.50,
                              onChanged: (v) => ctrl?.setFeather(v),
                            ),
                            SwitchListTile(
                              title: const Text('Show Mask Preview (Ruby Red)'),
                              value: ctrl?.state.isMaskPreviewActive ?? false,
                              onChanged: (_) => ctrl?.toggleMaskPreview(),
                            ),
                            SwitchListTile(
                              title: const Text('Preserve Original Luminance'),
                              value: ctrl?.state.preserveLuminance ?? true,
                              onChanged: (_) => ctrl?.togglePreserveLuminance(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static const List<ColorRgb> _standardTargetColors = [
    ColorRgb(220, 20, 60), // Crimson Red
    ColorRgb(255, 140, 0), // Dark Orange
    ColorRgb(255, 215, 0), // Golden Yellow
    ColorRgb(34, 139, 34), // Forest Green
    ColorRgb(30, 144, 255), // Dodger Blue
    ColorRgb(138, 43, 226), // Blue Violet
    ColorRgb(255, 20, 147), // Deep Pink
    ColorRgb(47, 79, 79), // Dark Slate
  ];
}
