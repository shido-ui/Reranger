import 'package:flutter/material.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import 'humanize_controller.dart';

/// SCR-10 & SCR-11: Humanize Studio Screen.
/// Provides beginner-first look choices (<= 3), single dominant CTA,
/// trade-off warnings, authentic offline progress, and graceful hardware gating.
class HumanizeScreen extends StatelessWidget {
  final HumanizeController controller;
  final VoidCallback? onBackToConventional;

  const HumanizeScreen({
    super.key,
    required this.controller,
    this.onBackToConventional,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
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

        final successColor = isDark
            ? AppColorTokens.darkAccentSuccess
            : AppColorTokens.lightAccentSuccess;

        return Scaffold(
          backgroundColor: surfaceBase,
          appBar: AppBar(
            title: const Text(
              'Humanize Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Studio',
              onPressed:
                  onBackToConventional ??
                  () => Navigator.of(context).maybePop(),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacingTokens.sm,
                  vertical: AppSpacingTokens.xs,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacingTokens.sm,
                  vertical: AppSpacingTokens.xxs,
                ),
                decoration: BoxDecoration(
                  color: successColor.withValues(alpha: 0.15),
                  borderRadius: AppRadiusTokens.borderSm,
                  border: Border.all(
                    color: successColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.offline_bolt, size: 14, color: successColor),
                    const SizedBox(width: AppSpacingTokens.xxs),
                    Text(
                      '100% OFFLINE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: successColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: controller.isGated
                ? _buildGatedNotice(
                    context,
                    theme,
                    primaryText,
                    secondaryText,
                    accentColor,
                    surfaceElevated,
                  )
                : _buildStudioContent(
                    context,
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

  /// SCR-11: Truthful Hardware / Weights Gating Notice.
  Widget _buildGatedNotice(
    BuildContext context,
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceElevated,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacingTokens.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacingTokens.lg),
          decoration: BoxDecoration(
            color: surfaceElevated,
            borderRadius: AppRadiusTokens.borderLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.memory_outlined, size: 56, color: Colors.amber),
              const SizedBox(height: AppSpacingTokens.md),
              Text(
                'Humanize Studio Unavailable on this Device',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: primaryText,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacingTokens.sm),
              Text(
                controller.unavailabilityReason ??
                    'Humanize Studio requires at least 6 GB of physical device RAM '
                        'to run on-device latent diffusion safely without crashing. '
                        'Recolor Studio and Style & Render Studio are fully supported and operational.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryText,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacingTokens.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Conventional Studio'),
                  onPressed:
                      onBackToConventional ??
                      () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// SCR-10: Main Active Studio Content.
  Widget _buildStudioContent(
    BuildContext context,
    ThemeData theme,
    Color primaryText,
    Color secondaryText,
    Color accentColor,
    Color surfaceElevated,
    Color surfaceBase,
    Color borderSubtle,
  ) {
    final displayBytes = controller.isComparing
        ? controller.displaySourceBytes
        : (controller.resultImageBytes ?? controller.displaySourceBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Viewport Display with Hold-to-Compare & Stage Overlay
        Expanded(
          flex: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                onTapDown: (_) => controller.setComparing(true),
                onTapUp: (_) => controller.setComparing(false),
                onTapCancel: () => controller.setComparing(false),
                child: Container(
                  margin: const EdgeInsets.all(AppSpacingTokens.sm),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: AppRadiusTokens.borderMd,
                    border: Border.all(color: borderSubtle),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadiusTokens.borderMd,
                    child: displayBytes != null
                        ? Image.memory(
                            displayBytes,
                            fit: BoxFit.contain,
                            key: const ValueKey('humanize_viewport_image'),
                            errorBuilder: (ctx, err, stack) => const ColoredBox(
                              color: Colors.black26,
                              child: Center(
                                child: Icon(
                                  Icons.image,
                                  size: 48,
                                  color: Colors.white24,
                                ),
                              ),
                            ),
                          )
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),

              // Status / Compare Indicator Badge
              Positioned(
                top: AppSpacingTokens.md,
                left: AppSpacingTokens.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacingTokens.sm,
                    vertical: AppSpacingTokens.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: AppRadiusTokens.borderSm,
                  ),
                  child: Text(
                    controller.isComparing
                        ? 'ORIGINAL (BEFORE)'
                        : (controller.status == HumanizeUiStatus.completed
                              ? 'HUMANIZED RESULT'
                              : 'SOURCE IMAGE'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),

              // Running Progress Overlay
              if (controller.isRunning)
                Positioned.fill(
                  child: Semantics(
                    liveRegion: true,
                    label:
                        'Neural inference in progress: ${controller.progress?.message ?? "Preparing on-device neural model"}. '
                        '${controller.progress != null && controller.progress!.totalSteps > 0 ? "Step ${controller.progress!.step} of ${controller.progress!.totalSteps}" : ""}',
                    child: Container(
                      margin: const EdgeInsets.all(AppSpacingTokens.sm),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.70),
                        borderRadius: AppRadiusTokens.borderMd,
                      ),
                      padding: const EdgeInsets.all(AppSpacingTokens.md),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacingTokens.md),
                          Text(
                            controller.progress?.message ?? 'Preparing on-device neural model (100% offline)...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacingTokens.xs),
                          if (controller.progress != null &&
                              controller.progress!.totalSteps > 0)
                            Text(
                              'Step ${controller.progress!.step} of ${controller.progress!.totalSteps} '
                              '(${(controller.progress!.progressFraction * 100).toInt()}%)',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          const SizedBox(height: AppSpacingTokens.md),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(140, 48),
                            ),
                            icon: const Icon(Icons.cancel, color: Colors.white),
                            label: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white),
                            ),
                            onPressed: () => controller.cancel(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 2. Beginner Controls Tray
        Expanded(
          flex: 5,
          child: Material(
            color: surfaceElevated,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacingTokens.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Look Choices (Exactly 3)
                        Text(
                          'Choose Humanize Look',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: primaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacingTokens.xs),
                        Wrap(
                          spacing: AppSpacingTokens.xs,
                          runSpacing: AppSpacingTokens.xs,
                          children: HumanizeLook.values.map((look) {
                            final isSelected = controller.selectedLook == look;
                            return ChoiceChip(
                              label: Text(look.displayName),
                              selected: isSelected,
                              tooltip:
                                  '${look.displayName}: ${look.description}',
                              onSelected: controller.isRunning
                                  ? null
                                  : (_) => controller.selectLook(look),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppSpacingTokens.sm),

                        // Strength Slider
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Transformation Strength',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(controller.strength * 100).round()}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Semantics(
                          label:
                              'Transformation strength slider, value ${(controller.strength * 100).round()}%',
                          child: Slider(
                            value: controller.strength,
                            min: 0.0,
                            max: 1.0,
                            onChanged: controller.isRunning
                                ? null
                                : (val) => controller.setStrength(val),
                          ),
                        ),

                        // Trade-Off Disclaimer Guardrail
                        Container(
                          padding: const EdgeInsets.all(AppSpacingTokens.xs),
                          decoration: BoxDecoration(
                            color: surfaceBase,
                            borderRadius: AppRadiusTokens.borderSm,
                            border: Border.all(color: borderSubtle),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: AppSpacingTokens.xs),
                              Expanded(
                                child: Text(
                                  'Higher strength re-synthesizes micro-textures but may alter '
                                  'facial likeness and subject identity. Does not claim undetectable AI.',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: secondaryText,
                                    fontSize: 11,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacingTokens.sm),

                        // Composition Preservation Toggle
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Anchor Subject Likeness',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: primaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Limits perturbation to preserve composition and facial ratios.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: secondaryText,
                            ),
                          ),
                          value: controller.preserveComposition,
                          onChanged: controller.isRunning
                              ? null
                              : (val) => controller.setPreserveComposition(val),
                        ),
                      ],
                    ),
                  ),
                ),

                // Docked Dominant CTA
                Padding(
                  padding: const EdgeInsets.all(AppSpacingTokens.md),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: controller.isRunning
                        ? OutlinedButton.icon(
                            key: const ValueKey('cancel_humanize_cta'),
                            icon: const Icon(Icons.stop),
                            label: const Text('Cancel Humanize'),
                            onPressed: () => controller.cancel(),
                          )
                        : ElevatedButton.icon(
                            key: const ValueKey('humanize_photo_cta'),
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Humanize Photo'),
                            onPressed: () => controller.humanize(),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
