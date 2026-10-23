import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'typography_tokens.dart';

/// Authoritative Application Themes defined in docs/DESIGN_SYSTEM.md.
/// Conforms to WCAG 2.1 AA contrast requirements and Material 3 design specs.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    final textTheme = _buildTextTheme(
      primaryColor: AppColorTokens.darkTextPrimary,
      secondaryColor: AppColorTokens.darkTextSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColorTokens.darkBgCanvas,
      colorScheme: const ColorScheme.dark(
        surface: AppColorTokens.darkSurfaceBase,
        surfaceContainerHighest: AppColorTokens.darkSurfaceElevated,
        primary: AppColorTokens.darkAccentPrimary,
        onPrimary: Colors.white,
        onSurface: AppColorTokens.darkTextPrimary,
        onSurfaceVariant: AppColorTokens.darkTextSecondary,
        outline: AppColorTokens.darkBorderSubtle,
        outlineVariant: AppColorTokens.darkBorderFocus,
        error: AppColorTokens.darkAccentError,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColorTokens.darkSurfaceBase,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypographyTokens.titleLarge.copyWith(
          color: AppColorTokens.darkTextPrimary,
        ),
        iconTheme: const IconThemeData(
          color: AppColorTokens.darkTextPrimary,
          size: 24,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColorTokens.darkSurfaceBase,
        elevation: 3,
        indicatorColor: AppColorTokens.darkSurfaceElevated,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypographyTokens.labelSmall.copyWith(
              color: AppColorTokens.darkAccentPrimary,
            );
          }
          return AppTypographyTokens.labelSmall.copyWith(
            color: AppColorTokens.darkTextSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: AppColorTokens.darkAccentPrimary,
              size: 24,
            );
          }
          return const IconThemeData(
            color: AppColorTokens.darkTextSecondary,
            size: 24,
          );
        }),
      ),
      textTheme: textTheme,
    );
  }

  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme(
      primaryColor: AppColorTokens.lightTextPrimary,
      secondaryColor: AppColorTokens.lightTextSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColorTokens.lightBgCanvas,
      colorScheme: const ColorScheme.light(
        surface: AppColorTokens.lightSurfaceBase,
        surfaceContainerHighest: AppColorTokens.lightSurfaceElevated,
        primary: AppColorTokens.lightAccentPrimary,
        onPrimary: Colors.white,
        onSurface: AppColorTokens.lightTextPrimary,
        onSurfaceVariant: AppColorTokens.lightTextSecondary,
        outline: AppColorTokens.lightBorderSubtle,
        outlineVariant: AppColorTokens.lightBorderFocus,
        error: AppColorTokens.lightAccentError,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColorTokens.lightSurfaceBase,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypographyTokens.titleLarge.copyWith(
          color: AppColorTokens.lightTextPrimary,
        ),
        iconTheme: const IconThemeData(
          color: AppColorTokens.lightTextPrimary,
          size: 24,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColorTokens.lightSurfaceBase,
        elevation: 3,
        indicatorColor: AppColorTokens.lightSurfaceElevated,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypographyTokens.labelSmall.copyWith(
              color: AppColorTokens.lightAccentPrimary,
            );
          }
          return AppTypographyTokens.labelSmall.copyWith(
            color: AppColorTokens.lightTextSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: AppColorTokens.lightAccentPrimary,
              size: 24,
            );
          }
          return const IconThemeData(
            color: AppColorTokens.lightTextSecondary,
            size: 24,
          );
        }),
      ),
      textTheme: textTheme,
    );
  }

  static TextTheme _buildTextTheme({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      titleLarge: AppTypographyTokens.titleLarge.copyWith(color: primaryColor),
      titleMedium: AppTypographyTokens.titleMedium.copyWith(
        color: primaryColor,
      ),
      bodyLarge: AppTypographyTokens.bodyLarge.copyWith(color: primaryColor),
      bodyMedium: AppTypographyTokens.bodyMedium.copyWith(
        color: secondaryColor,
      ),
      labelLarge: AppTypographyTokens.labelLarge.copyWith(color: primaryColor),
      labelMedium: AppTypographyTokens.labelMedium.copyWith(
        color: primaryColor,
      ),
      labelSmall: AppTypographyTokens.labelSmall.copyWith(
        color: secondaryColor,
      ),
    );
  }
}
