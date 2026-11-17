import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

export 'app_colors.dart';

/// MindTwin design system: builds light + dark [ThemeData] from the
/// [AppPalette] tokens, plus legacy static aliases used across screens.
class AppTheme {
  AppTheme._();

  /// Existing dark theme (name kept for callers/tests).
  static ThemeData get darkMedicalTheme => build(AppPalette.dark);
  static ThemeData get dark => build(AppPalette.dark);
  static ThemeData get light => build(AppPalette.light);

  static TextTheme _textTheme(AppPalette p) {
    // Type scale: display 32/28/24, headline 22/20/18, title 18/16/14,
    // body 16/14/12, label 14/12/11. Line heights favour readability.
    return TextTheme(
      displayLarge: TextStyle(fontSize: 32, height: 1.2, fontWeight: FontWeight.w700, color: p.ink, letterSpacing: -0.5),
      displayMedium: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, color: p.ink, letterSpacing: -0.3),
      displaySmall: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w700, color: p.ink),
      headlineLarge: TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w700, color: p.ink),
      headlineMedium: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, color: p.textPrimary),
      headlineSmall: TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, color: p.textPrimary),
      titleLarge: TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w700, color: p.ink),
      titleMedium: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600, color: p.ink),
      titleSmall: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: p.textPrimary),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: p.textPrimary),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: p.textSecondary),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: p.textMuted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: p.textPrimary),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: p.textSecondary),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: p.textMuted),
    );
  }

  static ThemeData build(AppPalette p) {
    final isDark = p.brightness == Brightness.dark;
    final text = _textTheme(p);
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: Color.alphaBlend(p.primary.withValues(alpha: 0.18), p.surface),
      onPrimaryContainer: p.ink,
      secondary: p.teal,
      onSecondary: isDark ? const Color(0xFF052E1C) : Colors.white,
      secondaryContainer: Color.alphaBlend(p.teal.withValues(alpha: 0.18), p.surface),
      onSecondaryContainer: p.ink,
      tertiary: p.violet,
      onTertiary: isDark ? const Color(0xFF1E1240) : Colors.white,
      error: p.critical,
      onError: isDark ? const Color(0xFF3B0A0A) : Colors.white,
      errorContainer: Color.alphaBlend(p.critical.withValues(alpha: 0.16), p.surface),
      onErrorContainer: p.ink,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceCard,
      surfaceContainerHigh: p.surfaceLight,
      surfaceContainerHighest: p.surfaceLight,
      outline: p.outline,
      outlineVariant: p.outline.withValues(alpha: 0.6),
      inverseSurface: p.ink,
      onInverseSurface: p.background,
      inversePrimary: isDark ? AppPalette.light.primary : AppPalette.dark.primary,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final shapeMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md));
    final border = isDark ? Colors.white.withValues(alpha: 0.08) : p.outline;
    const minButton = Size(AppSpacing.minTouchTarget, AppSpacing.minTouchTarget);
    const buttonText = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2);

    OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c, width: w),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.surface,
      dividerColor: p.outline,
      textTheme: text,
      primaryTextTheme: text,
      iconTheme: IconThemeData(color: p.textSecondary),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        iconTheme: IconThemeData(color: p.ink),
        actionsIconTheme: IconThemeData(color: p.textSecondary),
        titleTextStyle: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.1),
      ),

      cardTheme: CardThemeData(
        color: p.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          disabledBackgroundColor: p.surfaceLight,
          disabledForegroundColor: p.textMuted,
          elevation: 0,
          minimumSize: minButton,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: shapeMd,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          minimumSize: minButton,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: shapeMd,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primary,
          minimumSize: minButton,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: p.primary.withValues(alpha: 0.6)),
          shape: shapeMd,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          minimumSize: minButton,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: shapeMd,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: minButton),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? p.surfaceCard : p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(border),
        enabledBorder: inputBorder(border),
        focusedBorder: inputBorder(p.primary, 2),
        errorBorder: inputBorder(p.critical),
        focusedErrorBorder: inputBorder(p.critical, 2),
        labelStyle: TextStyle(color: p.textSecondary),
        floatingLabelStyle: TextStyle(color: p.primary, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: p.textMuted),
        helperStyle: TextStyle(color: p.textMuted),
        errorStyle: TextStyle(color: p.critical),
        prefixIconColor: p.textSecondary,
        suffixIconColor: p.textSecondary,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceLight,
        selectedColor: p.primary.withValues(alpha: 0.22),
        disabledColor: p.surfaceLight.withValues(alpha: 0.5),
        labelStyle: TextStyle(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        checkmarkColor: p.primary,
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.surfaceLight,
        thumbColor: p.primary,
        overlayColor: p.primary.withValues(alpha: 0.18),
        valueIndicatorColor: p.primary,
        valueIndicatorTextStyle: TextStyle(color: p.onPrimary, fontWeight: FontWeight.bold),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.onPrimary : p.textMuted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceLight),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary : Colors.transparent),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: BorderSide(color: p.textMuted, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? p.primary : p.textMuted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceLight,
        circularTrackColor: Colors.transparent,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        titleTextStyle: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w600),
        subtitleTextStyle: TextStyle(color: p.textSecondary, fontSize: 13),
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.textSecondary,
        indicatorColor: p.primary,
        dividerColor: border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primary.withValues(alpha: 0.18),
        height: 68,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? p.ink : p.textSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? p.primary : p.textSecondary,
            )),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.surface,
        selectedItemColor: p.primary,
        unselectedItemColor: p.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.primary.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: p.primary),
        unselectedIconTheme: IconThemeData(color: p.textSecondary),
        selectedLabelTextStyle: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w500, fontSize: 12),
        labelType: NavigationRailLabelType.all,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.modal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: p.textPrimary, fontSize: 15, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceCard,
        modalBackgroundColor: p.surfaceCard,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? p.surfaceLight : const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: isDark ? p.primary : AppPalette.dark.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surfaceCard,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: p.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? p.surfaceLight : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  // ── Risk helpers (unchanged thresholds) ──────────────────────────────
  static Color getRiskColor(double riskScore) {
    if (riskScore >= 0.75) return AppColors.healthCritical;
    if (riskScore >= 0.50) return AppColors.healthWarning;
    if (riskScore >= 0.25) return AppColors.healthModerate;
    return AppColors.healthOptimal;
  }

  static String getRiskLabel(double riskScore) {
    if (riskScore >= 0.75) return 'CRITICAL RISK';
    if (riskScore >= 0.50) return 'ELEVATED RISK';
    if (riskScore >= 0.25) return 'MODERATE MONITORING';
    return 'OPTIMAL DIGITAL TWIN';
  }

  // ── Legacy aliases (resolve against the active palette) ──────────────
  static Color get primaryIndigo => AppColors.primaryCyan;
  static Color get accentCyan => AppColors.primaryTeal;
  static Color get riskRed => AppColors.healthCritical;
  static Color get warningAmber => AppColors.healthWarning;
  static Color get safeGreen => AppColors.healthOptimal;
  static Color get backgroundDark => AppColors.background;
  static Color get cardDark => AppColors.surfaceCard;

  static LinearGradient get glassGradient {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppColors.surfaceCard.withValues(alpha: 0.25),
        AppColors.primaryCyan.withValues(alpha: 0.10),
      ],
    );
  }

  static BoxDecoration glassDecoration({Color? accentColor, double borderRadius = 20.0}) {
    final dark = AppColors.isDark;
    return BoxDecoration(
      color: dark ? AppColors.surfaceCard.withValues(alpha: 0.92) : AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: accentColor?.withValues(alpha: 0.4) ?? AppColors.glassBorder,
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: (accentColor ?? (dark ? Colors.black : const Color(0xFF0F1B2D)))
              .withValues(alpha: dark ? 0.15 : 0.06),
          blurRadius: dark ? 24 : 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}

/// App-wide theme mode (System / Light / Dark), persisted locally.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.system);
  static final ThemeController instance = ThemeController._();

  static const String _prefKey = 'ui_theme_mode';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_prefKey)) {
        case 'light':
          value = ThemeMode.light;
          break;
        case 'dark':
          value = ThemeMode.dark;
          break;
        default:
          value = ThemeMode.system;
      }
    } catch (_) {
      // Preference storage unavailable: keep following the system.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {}
  }
}

/// Keeps [AppColors]' active palette in sync with the resolved theme and
/// rebuilds the whole subtree when the brightness flips, so widgets that read
/// colour tokens (including const widgets) repaint with the new palette.
/// Place it in `MaterialApp.builder`.
class ThemePaletteScope extends StatefulWidget {
  final Widget child;
  const ThemePaletteScope({super.key, required this.child});

  @override
  State<ThemePaletteScope> createState() => _ThemePaletteScopeState();
}

class _ThemePaletteScopeState extends State<ThemePaletteScope> {
  @override
  Widget build(BuildContext context) {
    final changed = AppColors.applyBrightness(Theme.of(context).brightness);
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void rebuild(Element el) {
          el.markNeedsBuild();
          el.visitChildren(rebuild);
        }

        (context as Element).visitChildren(rebuild);
      });
    }
    return widget.child;
  }
}
