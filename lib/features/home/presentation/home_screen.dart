import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';

/// SCR-01: Home & Project Gallery Screen.
/// Follows beginner-first progressive disclosure with a single dominant CTA.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
        title: Text(
          'RERANGER',
          style: theme.textTheme.titleLarge?.copyWith(
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(AppRouteNames.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacingTokens.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacingTokens.lg),
              // Empty State Hero Card
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 480),
                      padding: const EdgeInsets.all(AppSpacingTokens.lg),
                      decoration: BoxDecoration(
                        color: surfaceElevated,
                        borderRadius: AppRadiusTokens.borderLg,
                        border: Border.all(color: borderSubtle),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_mosaic_outlined,
                            size: 64,
                            color: accentColor,
                          ),
                          const SizedBox(height: AppSpacingTokens.md),
                          Text(
                            '100% On-Device Photo Studio',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacingTokens.xs),
                          Text(
                            'Non-destructive recoloring, stylistic rendering, and neural refinement. Your original media is never modified.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondaryText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacingTokens.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacingTokens.sm,
                              vertical: AppSpacingTokens.xs,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: AppRadiusTokens.borderSm,
                            ),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.center,
                              spacing: AppSpacingTokens.xs,
                              runSpacing: AppSpacingTokens.xs,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 16,
                                  color: accentColor,
                                ),
                                Text(
                                  'Offline • Zero Cloud Telemetry',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: accentColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacingTokens.md),
              // Single Dominant Primary Call-to-Action (CTA)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SizedBox(
                    height: AppSpacingTokens.xxl,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadiusTokens.borderFull,
                        ),
                      ),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        'Select Image',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        context.push(AppRouteNames.analysis);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacingTokens.md),
            ],
          ),
        ),
      ),
    );
  }
}
