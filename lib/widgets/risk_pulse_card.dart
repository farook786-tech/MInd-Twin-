import 'package:flutter/material.dart';
// import 'dart:math' as math;
import '../core/theme/app_theme.dart';
import '../models/patient.dart';
import '../screens/therapist/patient_details_screen.dart';

/// Reusable Risk Pulse Card Widget
/// Features: Animated pulse, risk score display, glassmorphism styling
class RiskPulseCard extends StatefulWidget {
  final Patient patient;
  final VoidCallback? onTap;
  final bool showPulse;

  const RiskPulseCard({
    super.key,
    required this.patient,
    this.onTap,
    this.showPulse = true,
  });

  @override
  State<RiskPulseCard> createState() => _RiskPulseCardState();
}

class _RiskPulseCardState extends State<RiskPulseCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.showPulse && widget.patient.currentRiskScore >= 0.75) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RiskPulseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showPulse &&
        widget.patient.currentRiskScore >= 0.75 &&
        !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.showPulse || widget.patient.currentRiskScore < 0.75) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCheckIn = widget.patient.currentRiskScore >= 0;
    final riskColor = _getRiskColor(widget.patient.currentRiskScore);
    final riskPercentage = hasCheckIn ? (widget.patient.currentRiskScore * 100).toInt() : null;
    final riskLevel = _getRiskLevel(widget.patient.currentRiskScore);

    return GestureDetector(
      onTap: widget.onTap ?? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientDetailsScreen(patient: widget.patient),
          ),
        );
      },
      child: Container(
        decoration: AppTheme.glassDecoration(),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Animated Risk Circle
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: widget.showPulse && widget.patient.currentRiskScore >= 0.75
                      ? _pulseAnimation.value
                      : 1.0,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          riskColor.withValues(alpha: 0.8),
                          riskColor.withValues(alpha: 0.3),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: riskColor.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            hasCheckIn ? '$riskPercentage%' : 'No check-in yet',
                            style: TextStyle(
                              fontSize: hasCheckIn ? 24 : 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            hasCheckIn ? 'RISK' : 'NO DATA',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 20),
            // Patient Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.patient.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (widget.patient.isDemo) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'DEMO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryIndigo,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Risk Level: $riskLevel',
                    style: TextStyle(
                      fontSize: 14,
                      color: riskColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.patient.missedSessions} missed sessions',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getLastCheckInText(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Chevron
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  String _getRiskLevel(double score) {
    if (score < 0) return 'No Check-in';
    if (score >= 0.75) return 'Critical';
    if (score >= 0.50) return 'High Risk';
    if (score >= 0.25) return 'Moderate';
    return 'Low Risk';
  }

  Color _getRiskColor(double score) {
    if (score < 0) return Colors.grey;
    if (score >= 0.75) return AppTheme.riskRed;
    if (score >= 0.50) return Colors.orange;
    if (score >= 0.25) return AppTheme.warningAmber;
    return AppTheme.safeGreen;
  }

  String _getLastCheckInText() {
    final now = DateTime.now();
    final difference = now.difference(widget.patient.lastCheckIn);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
