import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/capabilities/app_capabilities.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';

/// SCR-16: Settings & System Information Screen.
/// Provides transparency on offline status, hardware tier, and open source licenses.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(appCapabilitiesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryText = isDark
        ? AppColorTokens.darkTextPrimary
        : AppColorTokens.lightTextPrimary;
    final secondaryText = isDark
        ? AppColorTokens.darkTextSecondary
        : AppColorTokens.lightTextSecondary;
    final surfaceElevated = isDark
        ? AppColorTokens.darkSurfaceElevated
        : AppColorTokens.lightSurfaceElevated;
    final borderSubtle = isDark
        ? AppColorTokens.darkBorderSubtle
        : AppColorTokens.lightBorderSubtle;
    final successColor = isDark
        ? AppColorTokens.darkAccentSuccess
        : AppColorTokens.lightAccentSuccess;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacingTokens.md),
          children: [
            // Section 1: System & Hardware Status
            Text(
              'DEVICE & RUNTIME CAPABILITIES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondaryText,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: AppSpacingTokens.xs),
            Material(
              color: surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadiusTokens.borderMd,
                side: BorderSide(color: borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      'Execution Architecture',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      '100% Local On-Device (Offline-First)',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: Icon(
                      Icons.check_circle_outline,
                      color: successColor,
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      'Hardware Memory Profile',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      '${capabilities.totalRamGb} GB RAM (${capabilities.ramTier.name.toUpperCase()})',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: const Icon(Icons.memory_outlined),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      'Neural Humanize Studio',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      capabilities.isNeuralHumanizeSupported
                          ? 'Supported (Flagship Tier Active)'
                          : 'Disabled (< 6 GB RAM Budget)',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: Icon(
                      capabilities.isNeuralHumanizeSupported
                          ? Icons.verified_outlined
                          : Icons.info_outline,
                      color: capabilities.isNeuralHumanizeSupported
                          ? successColor
                          : null,
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      'Classical Engine',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      'Native C++ 34KB Archive (${capabilities.activeAbi})',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: Icon(Icons.speed_outlined, color: successColor),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacingTokens.lg),

            // Section 2: Privacy & Licensing (Product Constitution)
            Text(
              'PRIVACY & LICENSES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondaryText,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: AppSpacingTokens.xs),
            Material(
              color: surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadiusTokens.borderMd,
                side: BorderSide(color: borderSubtle),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      'Cloud Analytics & Tracking',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      'None (Invariant 6: Zero Telemetry)',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: Icon(Icons.lock_outline, color: successColor),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      'Source Image Immutability',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      'Read-Only Input (Invariant 4: Non-Destructive)',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: Icon(
                      Icons.security_outlined,
                      color: successColor,
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(
                      'Open Source Licenses',
                      style: TextStyle(color: primaryText),
                    ),
                    subtitle: Text(
                      'Apache-2.0, MIT, CreativeML OpenRAIL-M',
                      style: TextStyle(color: secondaryText),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'Reranger',
                        applicationVersion: '0.1.0',
                        applicationLegalese: '© 2026 Reranger Contributors. Built strictly offline-first.',
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacingTokens.xl),

            // Version Footer
            Center(
              child: Text(
                'Reranger v0.1.0 (Build 1) • Android First',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
