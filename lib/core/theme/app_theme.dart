import 'package:flutter/material.dart';

/// Dark Medical Mode Theme
/// Background: #0a0a0f, Card: #111118, Indigo: #6366f1
/// Risk Red: #ef4444, Warning Amber: #f59e0b, Safe Green: #22c55e
class AppTheme {
  // Core Colors
  static const Color backgroundDark = Color(0xFF0a0a0f);
  static const Color cardDark = Color(0xFF111118);
  static const Color primaryIndigo = Color(0xFF6366f1);
  static const Color accentCyan = Color(0xFF06b6d4);
  static const Color riskRed = Color(0xFFef4444);
  static const Color warningAmber = Color(0xFFf59e0b);
  static const Color safeGreen = Color(0xFF22c55e);
  
  // Gradient for Glassmorphism
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x33ffffff),
      Color(0x11ffffff),
    ],
  );

  static ThemeData get darkMedicalTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      
      colorScheme: const ColorScheme.dark(
        primary: primaryIndigo,
        secondary: primaryIndigo,
        surface: backgroundDark,
        error: riskRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.white,
      ),
      
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: Colors.white70,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: Colors.white60,
        ),
      ),
      
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryIndigo,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
        thumbColor: primaryIndigo,
        overlayColor: primaryIndigo.withValues(alpha: 0.2),
        valueIndicatorColor: primaryIndigo,
      ),
      
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryIndigo;
          }
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryIndigo.withValues(alpha: 0.5);
          }
          return Colors.grey.withValues(alpha: 0.3);
        }),
      ),
    );
  }

  // Risk Color Helper
  static Color getRiskColor(double riskScore) {
    if (riskScore >= 0.75) return riskRed;
    if (riskScore >= 0.50) return warningAmber;
    return safeGreen;
  }

  // Glassmorphism Container Decoration
  static BoxDecoration glassDecoration({Color? color}) {
    return BoxDecoration(
      gradient: glassGradient,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.2),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}
