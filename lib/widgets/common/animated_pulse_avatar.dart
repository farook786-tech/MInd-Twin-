import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class AnimatedPulseAvatar extends StatefulWidget {
  final double radius;
  final Color glowColor;
  final String statusText;
  final IconData icon;

  const AnimatedPulseAvatar({
    super.key,
    this.radius = 45.0,
    this.glowColor = AppColors.primaryCyan,
    this.statusText = 'TWIN ACTIVE',
    this.icon = Icons.psychology_outlined,
  });

  @override
  State<AnimatedPulseAvatar> createState() => _AnimatedPulseAvatarState();
}

class _AnimatedPulseAvatarState extends State<AnimatedPulseAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Glowing Pulse Ring
            Container(
              width: widget.radius * 2 * _pulseAnimation.value,
              height: widget.radius * 2 * _pulseAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.glowColor.withOpacity(0.18 / _pulseAnimation.value),
                boxShadow: [
                  BoxShadow(
                    color: widget.glowColor.withOpacity(0.35),
                    blurRadius: 28 * _pulseAnimation.value,
                    spreadRadius: 4 * _pulseAnimation.value,
                  ),
                ],
              ),
            ),
            // Inner Core Avatar Node
            Container(
              width: widget.radius * 2,
              height: widget.radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    widget.glowColor,
                    widget.glowColor.withOpacity(0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.6),
                  width: 2,
                ),
              ),
              child: Icon(
                widget.icon,
                color: Colors.black,
                size: widget.radius * 0.9,
              ),
            ),
          ],
        );
      },
    );
  }
}
