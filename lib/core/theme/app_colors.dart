import 'package:flutter/material.dart';

class AppColors {
  // Primary Deep Dark Obsidian Theme
  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF121824);
  static const Color surfaceCard = Color(0xFF1A2332);
  static const Color surfaceLight = Color(0xFF253147);

  // Vibrant Medical SaaS Accents
  static const Color primaryCyan = Color(0xFF00F0FF);
  static const Color primaryTeal = Color(0xFF00E676);
  static const Color primaryViolet = Color(0xFF8A2BE2);
  static const Color secondaryBlue = Color(0xFF2979FF);

  // Health Status Indicators
  static const Color healthOptimal = Color(0xFF00E676);
  static const Color healthModerate = Color(0xFF00B0FF);
  static const Color healthWarning = Color(0xFFFFB300);
  static const Color healthCritical = Color(0xFFFF3366);

  // Text Colors
  static const Color textPrimary = Color(0xFF8FAFC8);
  static const Color textSecondary = Color(0xFF90A4AE);
  static const Color textMuted = Color(0xFF607D8B);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryCyan, secondaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient twinGradient = LinearGradient(
    colors: [primaryViolet, primaryCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient healthGradient = LinearGradient(
    colors: [primaryTeal, primaryCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [healthWarning, healthCritical],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Glassmorphism Borders
  static Color glassBorder = Colors.white.withValues(alpha: 0.08);
  static Color glassBorderActive = primaryCyan.withValues(alpha: 0.3);
}
