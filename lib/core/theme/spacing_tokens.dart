import 'package:flutter/material.dart';

/// Spacing and Layout Tokens defined in docs/DESIGN_SYSTEM.md.
/// Conforms to the standard 4dp grid system and 48x48dp minimum touch target.
class AppSpacingTokens {
  AppSpacingTokens._();

  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  static const double minTouchTarget = 48.0;
}

/// Corner Radius Tokens defined in docs/DESIGN_SYSTEM.md.
class AppRadiusTokens {
  AppRadiusTokens._();

  static const double none = 0.0;
  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 16.0;
  static const double full = 9999.0;

  static const BorderRadius borderNone = BorderRadius.zero;
  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderFull = BorderRadius.all(
    Radius.circular(full),
  );
}
