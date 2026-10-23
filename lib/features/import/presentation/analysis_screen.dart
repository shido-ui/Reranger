import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import 'import_controller.dart';

/// SCR-03: Image Analysis & Staging Screen.
/// Displays honest indeterminate stages, cancellation, and error retry states (Invariant 7).
class AnalysisScreen extends StatefulWidget {
  final ImportController controller;

  const AnalysisScreen({super.key, required this.controller});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.state is ImportInitial &&
          !widget.controller.isExecuting &&
          widget.controller.pickerService != null) {
        widget.controller.pickAndImport();
      }
    });
  }

  void _navigateHome(BuildContext context) {
    if (GoRouter.maybeOf(context) != null) {
      context.go(AppRouteNames.home);
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
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
        final errorColor = isDark
            ? AppColorTokens.darkAccentError
            : AppColorTokens.lightAccentError;
        final surfaceElevated = isDark
            ? AppColorTokens.darkSurfaceElevated
            : AppColorTokens.lightSurfaceElevated;
        final borderSubtle = isDark
            ? AppColorTokens.darkBorderSubtle
            : AppColorTokens.lightBorderSubtle;

        // Auto-navigate to editor on success
        if (state is ImportSuccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && GoRouter.maybeOf(context) != null) {
              context.go('/editor/${state.project.id}');
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Preparing Canvas'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Gallery',
              onPressed: () {
                if (widget.controller.isExecuting) {
                  widget.controller.cancel();
                }
                _navigateHome(context);
              },
            ),
          ),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacingTokens.lg,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacingTokens.xl),
                    decoration: BoxDecoration(
                      color: surfaceElevated,
                      borderRadius: AppRadiusTokens.borderLg,
                      border: Border.all(color: borderSubtle),
                    ),
                    child: switch (state) {
                      ImportInProgress(:final stage) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label:
                                'Analysis progress: ${stage.title}. ${stage.description}',
                            liveRegion: true,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  accentColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacingTokens.lg),
                          Text(
                            stage.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacingTokens.xs),
                          Text(
                            stage.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacingTokens.lg),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacingTokens.sm,
                              vertical: AppSpacingTokens.xs,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: AppRadiusTokens.borderSm,
                            ),
                            child: Text(
                              'Offline • Zero Cloud Telemetry',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacingTokens.xl),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(180, 48),
                            ),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel Analysis'),
                            onPressed: () {
                              widget.controller.cancel();
                              _navigateHome(context);
                            },
                          ),
                        ],
                      ),

                      ImportFailureState(
                        :final errorMessage,
                        :final canRetry,
                      ) =>
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 56,
                              color: errorColor,
                            ),
                            const SizedBox(height: AppSpacingTokens.md),
                            Text(
                              'Import Failed',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: primaryText,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacingTokens.sm),
                            Text(
                              errorMessage,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: secondaryText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacingTokens.lg),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: AppSpacingTokens.sm,
                              runSpacing: AppSpacingTokens.sm,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(140, 48),
                                  ),
                                  onPressed: () => _navigateHome(context),
                                  child: const Text('Back to Gallery'),
                                ),
                                if (canRetry)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(140, 48),
                                    ),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Try Again'),
                                    onPressed: () => widget.controller.retry(),
                                  ),
                              ],
                            ),
                          ],
                        ),

                      ImportCancelled() => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            size: 48,
                            color: secondaryText,
                          ),
                          const SizedBox(height: AppSpacingTokens.md),
                          Text(
                            'Import Cancelled',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: primaryText,
                            ),
                          ),
                          const SizedBox(height: AppSpacingTokens.md),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(160, 48),
                            ),
                            onPressed: () => _navigateHome(context),
                            child: const Text('Return to Home'),
                          ),
                        ],
                      ),

                      ImportSuccess(:final project) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 56,
                            color: accentColor,
                          ),
                          const SizedBox(height: AppSpacingTokens.md),
                          Text(
                            'Image Ready',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacingTokens.xs),
                          Text(
                            'Opening project ${project.name}...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                            ),
                          ),
                        ],
                      ),

                      _ => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacingTokens.md),
                          Text(
                            'Selecting Image...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                            ),
                          ),
                          const SizedBox(height: AppSpacingTokens.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacingTokens.sm,
                              vertical: AppSpacingTokens.xs,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: AppRadiusTokens.borderSm,
                            ),
                            child: Text(
                              'Offline • Zero Cloud Telemetry',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacingTokens.xl),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel Analysis'),
                            onPressed: () {
                              widget.controller.cancel();
                              _navigateHome(context);
                            },
                          ),
                        ],
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
