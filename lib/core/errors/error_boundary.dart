import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';

/// Global Error Boundary Widget catching unhandled UI errors.
/// Displays an honest, graceful recovery UI without crashing or losing user context.
class ErrorBoundary extends StatelessWidget {
  final FlutterErrorDetails details;

  const ErrorBoundary({super.key, required this.details});

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
    final errorColor = isDark
        ? AppColorTokens.darkAccentError
        : AppColorTokens.lightAccentError;
    final surfaceElevated = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurfaceElevated;
    final borderSubtle = isDark
        ? AppColorTokens.darkBorderSubtle
        : AppColorTokens.lightBorderSubtle;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacingTokens.lg),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(AppSpacingTokens.xl),
              decoration: BoxDecoration(
                color: surfaceElevated,
                borderRadius: AppRadiusTokens.borderLg,
                border: Border.all(color: borderSubtle),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: errorColor,
                  ),
                  const SizedBox(height: AppSpacingTokens.md),
                  Text(
                    'Something Went Wrong',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacingTokens.xs),
                  Text(
                    'An unexpected view error occurred. Your source images and projects are safe.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondaryText,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacingTokens.lg),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadiusTokens.borderFull,
                      ),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload Screen'),
                    onPressed: () {
                      // Navigate back or reset
                      Navigator.of(context).maybePop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
