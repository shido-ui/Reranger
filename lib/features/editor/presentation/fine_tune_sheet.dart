import 'package:flutter/material.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../domain/presets/preset_parameter.dart';
import 'editor_controller.dart';

/// SCR-07: Fine-Tune Parameter Bottom Sheet (Level 2 Progressive Disclosure).
///
/// Exposes only parameters relevant to the active style preset recipe.
/// Enforces:
/// - Plain-language labels and helpful small explanations.
/// - Sensible ranges and continuous feedback.
/// - Reset-per-control and reset-all actions.
/// - Never exposes internal coordinates, tensor shapes, or raw engine names.
class FineTuneSheet extends StatelessWidget {
  final EditorController controller;
  final VoidCallback? onOpenProTools;

  const FineTuneSheet({
    super.key,
    required this.controller,
    this.onOpenProTools,
  });

  /// Displays the modal fine-tune sheet.
  static Future<void> show(
    BuildContext context, {
    required EditorController controller,
    VoidCallback? onOpenProTools,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          FineTuneSheet(controller: controller, onOpenProTools: onOpenProTools),
    );
  }

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
        final borderSubtle = isDark
            ? AppColorTokens.darkBorderSubtle
            : AppColorTokens.lightBorderSubtle;

        final activePreset = controller.activePreset;
        final parameters =
            activePreset?.parameters ?? const <PresetParameter>[];

        return Material(
          color: surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: AppSpacingTokens.sm),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: secondaryText.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Sheet Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacingTokens.md,
                      vertical: AppSpacingTokens.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fine-Tune Adjustments',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: primaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (activePreset != null)
                                Text(
                                  'Customizing ${activePreset.displayName}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: secondaryText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Reset All'),
                          onPressed: parameters.isEmpty
                              ? null
                              : () => controller.resetAllParameters(),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close fine-tune',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Parameter Controls List
                  Flexible(
                    child: parameters.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(AppSpacingTokens.xl),
                            child: Center(
                              child: Text(
                                'This style is pre-calibrated without extra sliders.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: secondaryText,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(AppSpacingTokens.md),
                            itemCount: parameters.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: AppSpacingTokens.md),
                            itemBuilder: (context, index) {
                              final param = parameters[index];
                              final value =
                                  controller.parameterValues[param.id] ??
                                  param.defaultValue;
                              final isAtDefault =
                                  (value - param.defaultValue).abs() < 1e-4;

                              return Container(
                                padding: const EdgeInsets.all(
                                  AppSpacingTokens.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black12
                                      : Colors.white24,
                                  borderRadius: AppRadiusTokens.borderMd,
                                  border: Border.all(color: borderSubtle),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                param.label,
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: primaryText,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              Text(
                                                _parameterExplanation(param.id),
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: secondaryText,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          value.toStringAsFixed(2),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: secondaryText,
                                                fontFamily: 'monospace',
                                              ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.refresh,
                                            size: 18,
                                          ),
                                          tooltip: 'Reset ${param.label}',
                                          color: isAtDefault
                                              ? secondaryText.withValues(
                                                  alpha: 0.4,
                                                )
                                              : accentColor,
                                          onPressed: isAtDefault
                                              ? null
                                              : () => controller.resetParameter(
                                                  param.id,
                                                ),
                                        ),
                                      ],
                                    ),
                                    Semantics(
                                      label:
                                          '${param.label} adjustment slider, value ${(value * 100).round()}%',
                                      child: Slider(
                                        min: param.min,
                                        max: param.max,
                                        value: value,
                                        onChanged: (v) => controller
                                            .updateParameter(param.id, v),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // Footer Pro Link
                  Padding(
                    padding: const EdgeInsets.all(AppSpacingTokens.md),
                    child: InkWell(
                      borderRadius: AppRadiusTokens.borderMd,
                      onTap: () {
                        Navigator.of(context).pop();
                        onOpenProTools?.call();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacingTokens.md,
                          vertical: AppSpacingTokens.sm,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.08),
                          borderRadius: AppRadiusTokens.borderMd,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: accentColor,
                            ),
                            const SizedBox(width: AppSpacingTokens.sm),
                            Expanded(
                              child: Text(
                                'Need layers, masks & history? Open Pro Tools',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward,
                              size: 16,
                              color: accentColor,
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
        );
      },
    );
  }

  static String _parameterExplanation(String paramId) {
    switch (paramId) {
      case 'pencilHardness':
      case 'strokeWeight':
      case 'knifeEdge':
        return 'Controls stroke intensity and edge line sharpness.';
      case 'grainIntensity':
      case 'paperGrain':
      case 'paperTooth':
      case 'canvasTooth':
      case 'meshGrain':
        return 'Modulates tactile paper and canvas texture.';
      case 'inkDensity':
      case 'brushInkDensity':
      case 'charcoalDensity':
      case 'hatchDensity':
        return 'Adjusts black point richness and line saturation.';
      case 'vignette':
      case 'vignetteFalloff':
      case 'glowWarmth':
      case 'matteHaze':
        return 'Controls radial falloff and highlight diffusion.';
      case 'contrast':
      case 'popContrast':
      case 'studioGamma':
      case 'shadowCrush':
        return 'Shapes dynamic range and shadow curve steepness.';
      default:
        return 'Fine-tunes the artistic formulation of this style.';
    }
  }
}
