import 'package:flutter/material.dart';

import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';

/// SCR-15: Creations & Export Archive Screen.
/// Displays exported and saved project variants with an honest empty state.
class CreationsScreen extends StatelessWidget {
  const CreationsScreen({super.key});

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
    final borderSubtle = isDark
        ? AppColorTokens.darkBorderSubtle
        : AppColorTokens.lightBorderSubtle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Creations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_folder_upload_outlined),
            tooltip: 'Import Project Package (.rrproj)',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Select an .rrproj package to import.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
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
                    Icons.collections_bookmark_outlined,
                    size: 56,
                    color: accentColor,
                  ),
                  const SizedBox(height: AppSpacingTokens.md),
                  Text(
                    'No Creations Saved Yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacingTokens.xs),
                  Text(
                    'When you export or branch project variants, they will be preserved safely here on your local device.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondaryText,
                    ),
                    textAlign: TextAlign.center,
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
