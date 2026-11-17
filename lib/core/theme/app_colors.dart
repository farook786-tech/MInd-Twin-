import 'package:flutter/material.dart';

/// MindTwin colour tokens.
///
/// Two palettes ([AppPalette.dark] / [AppPalette.light]) share one set of
/// token names. Widgets read the *active* palette through the static getters
/// on [AppColors] (and the legacy aliases on `AppTheme`), so a screen written
/// once renders correctly in both themes. The active palette follows the
/// resolved [ThemeData.brightness] and is switched by `ThemePaletteScope`
/// (see app_theme.dart), which also rebuilds the tree when it changes.
///
/// Contrast: every text token meets WCAG AA (>= 4.5:1) on `background`,
/// `surface` and `surfaceCard` of its own palette. Status colours meet
/// >= 3:1 (non-text / large text) and are always paired with an icon and a
/// label in the UI — never colour alone.
@immutable
class AppPalette {
  final Brightness brightness;

  // Surfaces
  final Color background;
  final Color surface;
  final Color surfaceCard;
  final Color surfaceLight;
  final Color outline;

  // Brand / accents
  final Color primary;
  final Color onPrimary;
  final Color teal;
  final Color violet;
  final Color blue;

  // Text
  final Color ink; // highest-emphasis text/icons on surfaces
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Status / clinical levels
  final Color critical;
  final Color high;
  final Color moderate;
  final Color low;
  final Color none;
  final Color info;

  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceCard,
    required this.surfaceLight,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.teal,
    required this.violet,
    required this.blue,
    required this.ink,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.critical,
    required this.high,
    required this.moderate,
    required this.low,
    required this.none,
    required this.info,
  });

  /// Calm "night clinic" palette (dark theme).
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0B1220),
    surface: Color(0xFF111A2B),
    surfaceCard: Color(0xFF16213A),
    surfaceLight: Color(0xFF22304A),
    outline: Color(0xFF2C3B57),
    primary: Color(0xFF5EEAD4), // teal-300, ~13:1 on background
    onPrimary: Color(0xFF042F2E),
    teal: Color(0xFF34D399),
    violet: Color(0xFFA78BFA),
    blue: Color(0xFF7DB4FB),
    ink: Color(0xFFF1F5F9),
    textPrimary: Color(0xFFE2E8F0),
    textSecondary: Color(0xFFB4C0D3),
    textMuted: Color(0xFF8A9AB2),
    critical: Color(0xFFF87171),
    high: Color(0xFFFB923C),
    moderate: Color(0xFFFBBF24),
    low: Color(0xFFA3E635),
    none: Color(0xFF34D399),
    info: Color(0xFF7DB4FB),
  );

  /// Clean clinical light palette.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFE6ECF4),
    outline: Color(0xFFD3DCE8),
    primary: Color(0xFF0F766E), // teal-700, ~5.5:1 on white
    onPrimary: Color(0xFFFFFFFF),
    teal: Color(0xFF047857),
    violet: Color(0xFF6D28D9),
    blue: Color(0xFF1D4ED8),
    ink: Color(0xFF0F1B2D),
    textPrimary: Color(0xFF1E293B),
    textSecondary: Color(0xFF3F4D63),
    textMuted: Color(0xFF5B6B82),
    critical: Color(0xFFB91C1C),
    high: Color(0xFFC2410C),
    moderate: Color(0xFFA16207),
    low: Color(0xFF4D7C0F),
    none: Color(0xFF047857),
    info: Color(0xFF1D4ED8),
  );
}

class AppColors {
  AppColors._();

  static AppPalette _p = AppPalette.dark;

  /// The palette currently used by the static getters.
  static AppPalette get palette => _p;
  static Brightness get brightness => _p.brightness;
  static bool get isDark => _p.brightness == Brightness.dark;

  /// Switches the active palette. Returns true when it changed.
  static bool applyBrightness(Brightness b) {
    final next = b == Brightness.dark ? AppPalette.dark : AppPalette.light;
    if (identical(next, _p)) return false;
    _p = next;
    return true;
  }

  // ── Surfaces ──────────────────────────────────────────────────────────
  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceCard => _p.surfaceCard;
  static Color get surfaceLight => _p.surfaceLight;
  static Color get outline => _p.outline;
  static Color get divider => _p.outline;

  // ── Accents (legacy names kept for existing screens) ─────────────────
  static Color get primaryCyan => _p.primary;
  static Color get primaryTeal => _p.teal;
  static Color get primaryViolet => _p.violet;
  static Color get secondaryBlue => _p.blue;
  static Color get primary => _p.primary;
  static Color get onPrimary => _p.onPrimary;

  // ── Health status (legacy) ───────────────────────────────────────────
  static Color get healthOptimal => _p.none;
  static Color get healthModerate => _p.info;
  static Color get healthWarning => _p.moderate;
  static Color get healthCritical => _p.critical;

  // ── Clinical levels (critical / high / moderate / low / none) ────────
  static Color get levelCritical => _p.critical;
  static Color get levelHigh => _p.high;
  static Color get levelModerate => _p.moderate;
  static Color get levelLow => _p.low;
  static Color get levelNone => _p.none;
  static Color get info => _p.info;

  // ── Vitals ───────────────────────────────────────────────────────────
  static Color get vitalHeartRate => _p.critical;
  static Color get vitalHrv => _p.violet;
  static Color get vitalSleep => _p.blue;
  static Color get vitalSteps => _p.teal;

  // ── Foreground ───────────────────────────────────────────────────────
  /// High-emphasis foreground on app surfaces (near-white in dark, navy in
  /// light). Use [onColor] for text/icons placed on saturated fills.
  static Color get ink => _p.ink;
  static Color get ink70 => _p.ink.withValues(alpha: 0.72);
  static Color get ink60 => _p.ink.withValues(alpha: isDark ? 0.62 : 0.68);
  static Color get ink54 => _p.ink.withValues(alpha: isDark ? 0.56 : 0.64);
  static Color get ink38 => _p.ink.withValues(alpha: isDark ? 0.42 : 0.52);
  static Color get ink30 => _p.ink.withValues(alpha: 0.30);
  static Color get ink24 => _p.ink.withValues(alpha: 0.24);
  static Color get ink12 => _p.ink.withValues(alpha: 0.12);
  static Color get ink10 => _p.ink.withValues(alpha: 0.10);

  /// Foreground for text/icons on saturated fills (status badges, SOS).
  static const Color onColor = Colors.white;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textMuted => _p.textMuted;

  // ── Gradients ────────────────────────────────────────────────────────
  static LinearGradient get primaryGradient => LinearGradient(
        colors: [_p.primary, _p.blue],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get twinGradient => LinearGradient(
        colors: [_p.violet, _p.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get healthGradient => LinearGradient(
        colors: [_p.teal, _p.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get warningGradient => LinearGradient(
        colors: [_p.moderate, _p.critical],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── Borders ──────────────────────────────────────────────────────────
  static Color get glassBorder => isDark ? Colors.white.withValues(alpha: 0.08) : _p.outline;
  static Color get glassBorderActive => _p.primary.withValues(alpha: 0.35);
}

/// Spacing scale (4dp grid).
class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Minimum interactive target (Material / WCAG 2.5.5).
  static const double minTouchTarget = 48;
}

/// Corner radii.
class AppRadius {
  AppRadius._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

/// Elevation levels (surfaces use Material 3 tonal elevation + borders).
class AppElevation {
  AppElevation._();
  static const double flat = 0;
  static const double raised = 1;
  static const double overlay = 3;
  static const double modal = 6;
}

/// Layout breakpoints.
class AppBreakpoints {
  AppBreakpoints._();
  static const double compact = 600;
  static const double medium = 840;

  /// Wide layout (side navigation + master/detail).
  static const double wide = 1000;
}
