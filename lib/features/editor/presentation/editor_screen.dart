import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../data/render/render_job_controller.dart';
import '../../presets/data/preset_catalog.dart';
import '../../export/presentation/export_sheet.dart';
import 'editor_controller.dart';
import 'editor_providers.dart';
import 'fine_tune_sheet.dart';
import 'pro_tools_sheet.dart';

/// SCR-04: Editor Viewport Screen.
/// Provides Level 1 simple controls (style carousel, single strength slider, compare, save),
/// with progressive disclosure into Level 2 (Fine-Tune Sheet) and Level 3 (Pro Tools Studio).
class EditorScreen extends ConsumerWidget {
  final String projectId;
  final EditorController? controller;

  const EditorScreen({super.key, required this.projectId, this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EditorController activeController =
        controller ?? ref.watch(editorControllerProvider(projectId));

    return ListenableBuilder(
      listenable: activeController,
      builder: (context, _) {
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

        final projectName = activeController.project?.name ?? 'Editor Viewport';

        return Scaffold(
          backgroundColor: surfaceBase,
          appBar: AppBar(
            title: Text(
              projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Home',
              onPressed: () {
                if (GoRouter.maybeOf(context) != null) {
                  context.go(AppRouteNames.home);
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            ),
            actions: [
              // Recolor Studio Entry Button (Prompt B)
              IconButton(
                key: const ValueKey('recolor_studio_button'),
                icon: const Icon(Icons.palette_outlined),
                tooltip: 'Recolor Studio',
                onPressed: () {
                  final target = AppRouteNames.recolor.replaceAll(
                    ':id',
                    projectId,
                  );
                  if (GoRouter.maybeOf(context) != null) {
                    context.push(
                      target,
                      extra: {
                        'sourceImageBytes': activeController.sourceImageBytes,
                        'processedImageBytes': activeController.previewPngBytes,
                        'renderGraph': activeController.activePreset
                            ?.buildGraph(
                              activeController.project?.sourceImageHash ?? '',
                              activeController.project?.sourceWidth ?? 1024,
                              activeController.project?.sourceHeight ?? 1024,
                              activeController.parameterValues,
                            ),
                      },
                    );
                  }
                },
              ),
              // Humanize Studio Entry Button (Prompt B)
              IconButton(
                key: const ValueKey('humanize_studio_button'),
                icon: const Icon(Icons.face_retouching_natural_outlined),
                tooltip: 'Humanize Studio',
                onPressed: () {
                  final target = AppRouteNames.humanize.replaceAll(
                    ':id',
                    projectId,
                  );
                  if (GoRouter.maybeOf(context) != null) {
                    context.push(
                      target,
                      extra: {
                        'sourceImageBytes': activeController.sourceImageBytes,
                        'processedImageBytes': activeController.previewPngBytes,
                        'renderGraph': activeController.activePreset
                            ?.buildGraph(
                              activeController.project?.sourceImageHash ?? '',
                              activeController.project?.sourceWidth ?? 1024,
                              activeController.project?.sourceHeight ?? 1024,
                              activeController.parameterValues,
                            ),
                      },
                    );
                  }
                },
              ),
              // Autodraw Studio Entry Button (Prompt 4)
              IconButton(
                key: const ValueKey('autodraw_studio_button'),
                icon: const Icon(Icons.draw_outlined),
                tooltip: 'Autodraw Studio',
                onPressed: () {
                  final target = AppRouteNames.autodraw.replaceAll(
                    ':id',
                    projectId,
                  );
                  if (GoRouter.maybeOf(context) != null) {
                    context.push(
                      target,
                      extra: {
                        'sourceImageBytes': activeController.sourceImageBytes,
                        'processedImageBytes': activeController.previewPngBytes,
                        'renderGraph': activeController.activePreset
                            ?.buildGraph(
                              activeController.project?.sourceImageHash ?? '',
                              activeController.project?.sourceWidth ?? 1024,
                              activeController.project?.sourceHeight ?? 1024,
                              activeController.parameterValues,
                            ),
                      },
                    );
                  }
                },
              ),
              // Pro Tools Studio Entry Button
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'Open Pro Tools Studio',
                onPressed: () =>
                    ProToolsSheet.show(context, controller: activeController),
              ),
              // Export Studio Modal Entry Button (Prompt 24)
              IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Export Options',
                onPressed: activeController.previewPngBytes == null
                    ? null
                    : () => ExportSheet.show(
                        context,
                        controller: activeController,
                      ),
              ),
              if (activeController.isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacingTokens.md,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    activeController.isSaved
                        ? Icons.check_circle_outline
                        : Icons.save_outlined,
                    color: activeController.isSaved ? Colors.green : null,
                  ),
                  tooltip: 'Save Image',
                  onPressed: activeController.previewPngBytes == null
                      ? null
                      : () async {
                          HapticFeedback.mediumImpact();
                          final ok = await activeController.saveProject();
                          if (context.mounted && ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Saved to Creations safely!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                ),
            ],
          ),
          body: SafeArea(
            child: activeController.isLoading
                ? const Center(child: CircularProgressIndicator())
                : activeController.errorMessage != null
                ? _buildErrorView(
                    context,
                    activeController,
                    theme,
                    primaryText,
                    secondaryText,
                  )
                : _buildEditorContent(
                    context,
                    activeController,
                    theme,
                    primaryText,
                    secondaryText,
                    accentColor,
                    surfaceElevated,
                    surfaceBase,
                    borderSubtle,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildErrorView(
    BuildContext context,
    EditorController controller,
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: AppSpacingTokens.md),
            Text(
              'Cannot Load Canvas',
              style: theme.textTheme.titleMedium?.copyWith(
                color: primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacingTokens.xs),
            Text(
              controller.errorMessage ?? 'Unknown error occurred.',
              style: theme.textTheme.bodyMedium?.copyWith(color: secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacingTokens.lg),
            ElevatedButton(
              onPressed: () => controller.loadProject(projectId),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorContent(
    BuildContext context,
    EditorController controller,
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceElevated,
    Color surfaceBase,
    Color borderSubtle,
  ) {
    final isExecuting = controller.renderState is RenderJobExecuting;
    final activePreset = controller.activePreset;
    final primaryParam =
        activePreset != null && activePreset.parameters.isNotEmpty
        ? activePreset.parameters.first
        : null;
    final paramValue = primaryParam != null
        ? (controller.parameterValues[primaryParam.id] ??
              primaryParam.defaultValue)
        : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Viewport Display (with Split Curtain or Standard Compare)
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(AppSpacingTokens.sm),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: AppRadiusTokens.borderMd,
              border: Border.all(color: borderSubtle),
            ),
            child: ClipRRect(
              borderRadius: AppRadiusTokens.borderMd,
              child:
                  controller.isSplitComparisonActive &&
                      controller.sourceImageBytes != null &&
                      controller.previewPngBytes != null
                  ? _buildSplitCurtainViewport(
                      context,
                      controller,
                      theme,
                      accentColor,
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // Main Viewport Image
                        controller.isComparing &&
                                controller.sourceImageBytes != null
                            ? Image.memory(
                                controller.sourceImageBytes!,
                                fit: BoxFit.contain,
                                key: const ValueKey('source_original_view'),
                              )
                            : controller.previewPngBytes != null
                            ? Image.memory(
                                controller.previewPngBytes!,
                                fit: BoxFit.contain,
                                key: const ValueKey('rendered_preview_view'),
                              )
                            : const Center(child: CircularProgressIndicator()),

                        // Compare Badge / Status Badge
                        Positioned(
                          top: AppSpacingTokens.md,
                          left: AppSpacingTokens.md,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacingTokens.sm,
                              vertical: AppSpacingTokens.xs,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: AppRadiusTokens.borderSm,
                            ),
                            child: Text(
                              controller.isComparing
                                  ? 'ORIGINAL (BEFORE)'
                                  : (activePreset?.displayName.toUpperCase() ??
                                        'PREVIEW'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),

                        // Compare Floating Action Pill
                        Positioned(
                          bottom: AppSpacingTokens.md,
                          right: AppSpacingTokens.md,
                          child: Semantics(
                            button: true,
                            label: 'Hold to compare with original image',
                            child: GestureDetector(
                              onTapDown: (_) {
                                HapticFeedback.lightImpact();
                                controller.setComparing(true);
                              },
                              onTapUp: (_) => controller.setComparing(false),
                              onTapCancel: () => controller.setComparing(false),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                  minWidth: 48,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacingTokens.md,
                                  vertical: AppSpacingTokens.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: controller.isComparing
                                      ? accentColor
                                      : surfaceElevated,
                                  borderRadius: AppRadiusTokens.borderMd,
                                  border: Border.all(color: borderSubtle),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.compare_outlined,
                                      size: 18,
                                      color: controller.isComparing
                                          ? Colors.white
                                          : primaryText,
                                    ),
                                    const SizedBox(width: AppSpacingTokens.xs),
                                    Text(
                                      'Compare',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: controller.isComparing
                                                ? Colors.white
                                                : primaryText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // In-Flight Render Progress Banner
                        if (isExecuting)
                          Positioned(
                            top: AppSpacingTokens.md,
                            right: AppSpacingTokens.md,
                            child: Semantics(
                              liveRegion: true,
                              label: 'Rendering preview in progress',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacingTokens.sm,
                                  vertical: AppSpacingTokens.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: AppRadiusTokens.borderSm,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacingTokens.xs),
                                    Text(
                                      'Rendering...',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(width: AppSpacingTokens.xs),
                                    Semantics(
                                      button: true,
                                      label: 'Cancel in-flight render',
                                      child: Tooltip(
                                        message: 'Cancel Render',
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minWidth: 48,
                                            minHeight: 48,
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: controller.cancelRender,
                                            child: const Center(
                                              child: Icon(
                                                Icons.close,
                                                size: 18,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),

        // 2. Simple Mode: Single Effect Strength Slider with Fine-Tune Trigger
        if (primaryParam != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacingTokens.sm,
              vertical: AppSpacingTokens.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        primaryParam.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacingTokens.xs),
                    Text(
                      paramValue.toStringAsFixed(2),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryText,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (activePreset?.isLockedStudioPreset != true) ...[
                      const SizedBox(width: AppSpacingTokens.xs),
                      // Fine-Tune Opt-in Trigger Button
                      Semantics(
                        button: true,
                        label:
                            'Open fine-tune controls for ${primaryParam.label}',
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.tune, size: 14),
                          label: Text(
                            'Fine-Tune',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => FineTuneSheet.show(
                            context,
                            controller: controller,
                            onOpenProTools: () => ProToolsSheet.show(
                              context,
                              controller: controller,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Semantics(
                  label:
                      '${primaryParam.label} strength slider, value ${(paramValue * 100).round()}%',
                  child: Slider(
                    min: primaryParam.min,
                    max: primaryParam.max,
                    value: paramValue,
                    onChanged: (val) =>
                        controller.updateParameter(primaryParam.id, val),
                  ),
                ),
              ],
            ),
          ),

        // 3. Category Filter Chips (SCR-05)
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacingTokens.sm,
            ),
            children: [
              FilterChip(
                label: const Text('All'),
                selected: controller.selectedCategory == null,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  controller.setSelectedCategory(null);
                },
              ),
              const SizedBox(width: AppSpacingTokens.xs),
              FilterChip(
                label: const Text('Studio'),
                selected: controller.selectedCategory == 'Studio',
                onSelected: (selected) {
                  HapticFeedback.selectionClick();
                  controller.setSelectedCategory(selected ? 'Studio' : null);
                },
              ),
              const SizedBox(width: AppSpacingTokens.xs),
              for (final cat in PresetCatalog.categories) ...[
                FilterChip(
                  label: Text(cat),
                  selected: controller.selectedCategory == cat,
                  onSelected: (selected) {
                    HapticFeedback.selectionClick();
                    controller.setSelectedCategory(selected ? cat : null);
                  },
                ),
                const SizedBox(width: AppSpacingTokens.xs),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacingTokens.xxs),

        // 4. Preset Carousel
        Container(
          height: 110,
          padding: const EdgeInsets.symmetric(vertical: AppSpacingTokens.xs),
          decoration: BoxDecoration(
            color: surfaceElevated,
            border: Border(top: BorderSide(color: borderSubtle)),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacingTokens.sm,
            ),
            itemCount: controller.visiblePresets.length,
            itemBuilder: (context, index) {
              final preset = controller.visiblePresets[index];
              final isSelected = activePreset?.id == preset.id;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacingTokens.xs,
                ),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: preset.accessibleLabel,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.selectPreset(preset);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: AppRadiusTokens.borderMd,
                            border: Border.all(
                              color: isSelected ? accentColor : borderSubtle,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: AppRadiusTokens.borderMd,
                            child: Image.asset(
                              preset.thumbnailAssetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, _, _) => Container(
                                color: surfaceBase,
                                child: Center(
                                  child: Icon(
                                    Icons.palette_outlined,
                                    size: 24,
                                    color: isSelected
                                        ? accentColor
                                        : secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacingTokens.xxs),
                        SizedBox(
                          width: 72,
                          child: Text(
                            preset.displayName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected ? accentColor : secondaryText,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Builds SCR-06 Split Comparison Curtain view with interactive draggable divider.
  Widget _buildSplitCurtainViewport(
    BuildContext context,
    EditorController controller,
    ThemeData theme,
    Color accentColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final splitPx = width * controller.splitPosition;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Transformed preview (Right / Base)
            Image.memory(
              controller.previewPngBytes!,
              fit: BoxFit.contain,
              key: const ValueKey('split_curtain_preview'),
            ),

            // Original source image (Left clipped)
            ClipRect(
              clipper: _LeftSplitClipper(splitPx),
              child: Image.memory(
                controller.sourceImageBytes!,
                fit: BoxFit.contain,
                key: const ValueKey('split_curtain_source'),
              ),
            ),

            // Draggable Divider Line (Accessible Touch Target >= 48dp)
            Positioned(
              left: splitPx - 24.0,
              top: 0,
              bottom: 0,
              child: Semantics(
                slider: true,
                label:
                    'Split comparison curtain divider, position ${(controller.splitPosition * 100).round()}%',
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    final newPosition = details.globalPosition.dx / width;
                    controller.setSplitComparison(position: newPosition);
                  },
                  child: SizedBox(
                    width: 48,
                    child: Center(
                      child: Container(
                        width: 3,
                        color: Colors.white,
                        child: Center(
                          child: Container(
                            width: 24,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Left Label
            Positioned(
              top: AppSpacingTokens.md,
              left: AppSpacingTokens.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacingTokens.sm,
                  vertical: AppSpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: AppRadiusTokens.borderSm,
                ),
                child: Text(
                  'ORIGINAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            // Right Label
            Positioned(
              top: AppSpacingTokens.md,
              right: AppSpacingTokens.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacingTokens.sm,
                  vertical: AppSpacingTokens.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: AppRadiusTokens.borderSm,
                ),
                child: Text(
                  'TRANSFORMED',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LeftSplitClipper extends CustomClipper<Rect> {
  final double splitWidth;
  const _LeftSplitClipper(this.splitWidth);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, splitWidth, size.height);

  @override
  bool shouldReclip(_LeftSplitClipper oldClipper) =>
      oldClipper.splitWidth != splitWidth;
}
