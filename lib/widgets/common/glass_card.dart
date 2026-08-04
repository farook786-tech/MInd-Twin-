import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? glowColor;
  final VoidCallback? onTap;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.glowColor,
    this.onTap,
    this.borderRadius = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardContent = Container(
      padding: padding,
      margin: margin,
      decoration: AppTheme.glassDecoration(
        accentColor: glowColor,
        borderRadius: borderRadius,
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        splashColor: (glowColor ?? AppColors.primaryCyan).withOpacity(0.1),
        highlightColor: Colors.transparent,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
