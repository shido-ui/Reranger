import 'package:flutter/material.dart';

/// Authoritative Color Tokens defined in docs/DESIGN_SYSTEM.md.
/// Conforms to WCAG 2.1 AA contrast requirements across Dark and Light themes.
class AppColorTokens {
  AppColorTokens._();

  // Dark Theme Primitives & Semantics (Default Creative Studio Theme)
  static const Color darkBgCanvas = Color(0xFF121214);
  static const Color darkSurfaceBase = Color(0xFF1E1E22);
  static const Color darkSurfaceElevated = Color(0xFF2A2A30);
  static const Color darkBorderSubtle = Color(0xFF3E3E48);
  static const Color darkBorderFocus = Color(0xFF8A7BFF);
  static const Color darkTextPrimary = Color(0xFFF4F4F6);
  static const Color darkTextSecondary = Color(0xFFA8A8B4);
  static const Color darkTextDisabled = Color(0xFF6C6C78);
  static const Color darkAccentPrimary = Color(0xFF8A7BFF);
  static const Color darkAccentSuccess = Color(0xFF00D2A0);
  static const Color darkAccentWarning = Color(0xFFFDCB6E);
  static const Color darkAccentError = Color(0xFFFF7675);

  // Light Theme Primitives & Semantics
  static const Color lightBgCanvas = Color(0xFFF8F9FA);
  static const Color lightSurfaceBase = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF0F1F4);
  static const Color lightBorderSubtle = Color(0xFFE2E4E8);
  static const Color lightBorderFocus = Color(0xFF5843D8);
  static const Color lightTextPrimary = Color(0xFF18181C);
  static const Color lightTextSecondary = Color(0xFF5A5A68);
  static const Color lightTextDisabled = Color(0xFF9E9EA8);
  static const Color lightAccentPrimary = Color(0xFF5843D8);
  static const Color lightAccentSuccess = Color(0xFF00B894);
  static const Color lightAccentWarning = Color(0xFFD97706);
  static const Color lightAccentError = Color(0xFFD63031);
}
