import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get darkMedicalTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryCyan,
        secondary: AppColors.primaryTeal,
        surface: AppColors.surface,
        error: AppColors.healthCritical,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimary,
        onError: Colors.white,
      ),

      cardTheme: CardThemeData(
        color: AppColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: AppColors.glassBorder,
            width: 1,
          ),
        ),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.primaryCyan),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryCyan, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryCyan,
          foregroundColor: Colors.black,
          elevation: 4,
          shadowColor: AppColors.primaryCyan.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primaryCyan,
        inactiveTrackColor: AppColors.surfaceLight,
        thumbColor: AppColors.primaryCyan,
        overlayColor: AppColors.primaryCyan.withOpacity(0.2),
        valueIndicatorColor: AppColors.primaryCyan,
        valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
        displayMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
        displaySmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        bodySmall: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }

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

  static const Color primaryIndigo = AppColors.primaryCyan;
  static const Color accentCyan = AppColors.primaryTeal;
  static const Color riskRed = AppColors.healthCritical;
  static const Color warningAmber = AppColors.healthWarning;
  static const Color safeGreen = AppColors.healthOptimal;
  static const Color backgroundDark = AppColors.background;
  static const Color cardDark = AppColors.surfaceCard;

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
    return BoxDecoration(
      color: AppColors.surfaceCard.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: accentColor?.withValues(alpha: 0.4) ?? AppColors.glassBorder,
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: (accentColor ?? Colors.black).withValues(alpha: 0.15),
          blurRadius: 24,
          spreadRadius: 1,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

