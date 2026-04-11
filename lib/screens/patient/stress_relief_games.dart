import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'patient_home_screen.dart';

class StressReliefGamesScreen extends StatelessWidget {
  final int riskPercentage;

  const StressReliefGamesScreen({
    super.key,
    required this.riskPercentage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stress Relief Arcade'),
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryIndigo.withValues(alpha: 0.24),
                    AppTheme.primaryIndigo.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryIndigo.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    'Current risk level',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$riskPercentage%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Play one activity for 3 to 5 minutes to reset your focus and calm your nervous system.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Choose Your Relief Mode',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _GameTile(
              title: 'Bubble Pop Lab',
              subtitle: 'Tap and clear bubbles. Level speed increases.',
              icon: Icons.bubble_chart,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BubblePopGame(),
                ),
              ),
            ),
            _GameTile(
              title: 'Zen Flow Sandbox',
              subtitle: 'Paint flowing particles with your finger.',
              icon: Icons.auto_fix_high,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ZenFlowGame(),
                ),
              ),
            ),
            _GameTile(
              title: 'Infinite Spinner',
              subtitle: 'Swipe to spin and sustain momentum.',
              icon: Icons.sync,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InfiniteSpinnerGame(),
                ),
              ),
            ),
            _GameTile(
              title: 'Breathing Nebula',
              subtitle: '4-4-4 guided breath with visual rhythm.',
              icon: Icons.nights_stay,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BreathingNebulaGame(),
                ),
              ),
            ),
            _GameTile(
              title: 'Soundscape Mixer',
              subtitle: 'Build calming mixes through challenge levels.',
              icon: Icons.graphic_eq,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SoundscapeMixerGame(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const PatientHomeScreen(),
                  ),
                  (route) => false,
                ),
                child: const Text(
                  'Back to Dashboard',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _GameTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class BubblePopGame extends StatefulWidget {
  const BubblePopGame({super.key});

  @override
  State<BubblePopGame> createState() => _BubblePopGameState();
}

class _BubblePopGameState extends State<BubblePopGame> {
  final math.Random _random = math.Random();
  final List<Color> _palette = [
    const Color(0xFF60A5FA),
    const Color(0xFF34D399),
    const Color(0xFFF472B6),
    const Color(0xFFFBBF24),
    const Color(0xFFA78BFA),
  ];

  late List<_Bubble> _bubbles;
  int _level = 1;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _generateBubbles();
  }

  void _generateBubbles() {
    final count = math.min(18 + (_level * 4), 50);
    _bubbles = List.generate(
      count,
      (_) => _Bubble(
        id: _random.nextInt(1 << 30),
        color: _palette[_random.nextInt(_palette.length)],
      ),
    );
  }

  void _popBubble(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      _bubbles.removeWhere((b) => b.id == id);
      _score += 5;
      if (_bubbles.isEmpty) {
        _level++;
        _score += 50;
        _generateBubbles();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bubble Pop Lab'),
        backgroundColor: AppTheme.backgroundDark,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _metric('Level', '$_level'),
                _metric('Score', '$_score'),
                _metric('Left', '${_bubbles.length}'),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                padding: const EdgeInsets.all(10),
                child: GridView.builder(
                  itemCount: _bubbles.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final bubble = _bubbles[index];
                    return GestureDetector(
                      onTap: () => _popBubble(bubble.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: bubble.color.withValues(alpha: 0.85),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              color: bubble.color.withValues(alpha: 0.45),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble {
  final int id;
  final Color color;

  _Bubble({required this.id, required this.color});
}

class ZenFlowGame extends StatefulWidget {
  const ZenFlowGame({super.key});

  @override
  State<ZenFlowGame> createState() => _ZenFlowGameState();
}

class _ZenFlowGameState extends State<ZenFlowGame> {
  final math.Random _random = math.Random();
  final List<_Particle> _particles = [];
  Timer? _decayTimer;
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (!mounted) return;
      setState(() {
        for (final p in _particles) {
          p.life -= 0.015;
          p.offset = Offset(
            p.offset.dx + p.velocity.dx,
            p.offset.dy + p.velocity.dy,
          );
          p.velocity = Offset(p.velocity.dx * 0.98, p.velocity.dy * 0.98);
        }
        _particles.removeWhere((p) => p.life <= 0);
      });
    });
  }

  @override
  void dispose() {
    _decayTimer?.cancel();
    super.dispose();
  }

  void _spawnParticles(Offset pos) {
    final amount = 10 + (_level * 2);
    for (int i = 0; i < amount; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 0.4 + _random.nextDouble() * 1.8;
      _particles.add(
        _Particle(
          offset: pos,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          life: 1.0,
          color: HSVColor.fromAHSV(
            1,
            (_random.nextDouble() * 360),
            0.45,
            0.95,
          ).toColor(),
          size: 2 + _random.nextDouble() * 4,
        ),
      );
    }

    if (_particles.length > 3000) {
      _particles.removeRange(0, _particles.length - 3000);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zen Flow Sandbox'),
        backgroundColor: AppTheme.backgroundDark,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Level $_level',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  'Particles ${_particles.length}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _level = math.min(_level + 1, 8);
                    });
                  },
                  child: const Text('Next Level'),
                ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onPanStart: (d) => setState(() => _spawnParticles(d.localPosition)),
              onPanUpdate: (d) => setState(() => _spawnParticles(d.localPosition)),
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF12182A),
                      Color(0xFF0D1120),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: CustomPaint(
                  painter: _ZenFlowPainter(_particles),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  Offset offset;
  Offset velocity;
  double life;
  Color color;
  double size;

  _Particle({
    required this.offset,
    required this.velocity,
    required this.life,
    required this.color,
    required this.size,
  });
}

class _ZenFlowPainter extends CustomPainter {
  final List<_Particle> particles;

  _ZenFlowPainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: p.life.clamp(0, 1))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p.offset, p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ZenFlowPainter oldDelegate) => true;
}

class InfiniteSpinnerGame extends StatefulWidget {
  const InfiniteSpinnerGame({super.key});

  @override
  State<InfiniteSpinnerGame> createState() => _InfiniteSpinnerGameState();
}

class _InfiniteSpinnerGameState extends State<InfiniteSpinnerGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _angle = 0;
  double _velocity = 0;
  int _level = 1;
  int _globalSpins = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      setState(() {
        _angle += _velocity;
        _velocity *= 0.985;
        if (_velocity.abs() < 0.0002) {
          _velocity = 0;
        }
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _flick(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    setState(() {
      _velocity += (v / 120000) * (_level * 0.8);
      _globalSpins += 1;
      if (_globalSpins % 12 == 0) {
        _level = math.min(_level + 1, 10);
      }
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Infinite Spinner'),
        backgroundColor: AppTheme.backgroundDark,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Level $_level', style: const TextStyle(color: Colors.white)),
                Text('Flicks $_globalSpins', style: const TextStyle(color: Colors.white)),
              ],
            ),
            const SizedBox(height: 30),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: _flick,
                onVerticalDragEnd: _flick,
                child: Center(
                  child: Transform.rotate(
                    angle: _angle,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [
                            Color(0xFF7DD3FC),
                            Color(0xFF6366F1),
                            Color(0xFF111827),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryIndigo.withValues(alpha: 0.45),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.blur_circular,
                          color: Colors.white,
                          size: 80,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Text(
              _velocity == 0
                  ? 'Swipe on spinner to flick it'
                  : 'Keep momentum above zero to stabilize focus',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class BreathingNebulaGame extends StatefulWidget {
  const BreathingNebulaGame({super.key});

  @override
  State<BreathingNebulaGame> createState() => _BreathingNebulaGameState();
}

class _BreathingNebulaGameState extends State<BreathingNebulaGame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _sessionCycles = 0;
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 12), // 4 inhale, 4 hold, 4 exhale
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _sessionCycles += 1;
            if (_sessionCycles % 5 == 0) {
              _level = math.min(_level + 1, 10);
            }
          });
          _controller.forward(from: 0);
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _phaseText(double t) {
    if (t < 0.3333) return 'Inhale';
    if (t < 0.6666) return 'Hold';
    return 'Exhale';
  }

  double _nebulaScale(double t) {
    if (t < 0.3333) {
      return 0.7 + (t / 0.3333) * 0.5;
    }
    if (t < 0.6666) {
      return 1.2;
    }
    final p = (t - 0.6666) / 0.3334;
    return 1.2 - (p * 0.5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breathing Nebula'),
        backgroundColor: AppTheme.backgroundDark,
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final phase = _phaseText(t);
          final scale = _nebulaScale(t);

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Level $_level', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 20),
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF93C5FD).withValues(alpha: 0.95),
                          const Color(0xFF6366F1).withValues(alpha: 0.6),
                          const Color(0xFF111827).withValues(alpha: 0.3),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryIndigo.withValues(alpha: 0.45),
                          blurRadius: 24,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  phase,
                  style: const TextStyle(
                    fontSize: 30,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cycles completed: $_sessionCycles',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SoundscapeMixerGame extends StatefulWidget {
  const SoundscapeMixerGame({super.key});

  @override
  State<SoundscapeMixerGame> createState() => _SoundscapeMixerGameState();
}

class _SoundscapeMixerGameState extends State<SoundscapeMixerGame> {
  double rain = 0.3;
  double wind = 0.2;
  double cafe = 0.1;
  double whiteNoise = 0.4;

  int level = 1;
  int streak = 0;

  String get _targetProfile {
    switch (level) {
      case 1:
        return 'Balanced calm';
      case 2:
        return 'Rain dominant';
      case 3:
        return 'Deep focus';
      case 4:
        return 'Cafe light';
      default:
        return 'Personal perfect mix';
    }
  }

  double get _comfortScore {
    final variance = _variance([rain, wind, cafe, whiteNoise]);
    final balance = (1 - (variance * 2.2)).clamp(0.0, 1.0);
    final loudness = ((rain + wind + cafe + whiteNoise) / 4).clamp(0.0, 1.0);
    final calm = (1 - (loudness - 0.55).abs() * 1.5).clamp(0.0, 1.0);
    return ((balance * 0.55) + (calm * 0.45)).clamp(0.0, 1.0);
  }

  void _validateMix() {
    final score = _comfortScore;
    final pass = switch (level) {
      1 => score > 0.62,
      2 => rain > 0.55 && wind < 0.35,
      3 => whiteNoise > 0.55 && cafe < 0.35,
      4 => cafe > 0.42 && rain < 0.5,
      _ => score > 0.7,
    };

    if (pass) {
      setState(() {
        streak += 1;
        level = math.min(level + 1, 6);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Great mix! Nervous system calming achieved.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    } else {
      setState(() => streak = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Try adjusting layers to match the target profile.'),
        ),
      );
    }
  }

  double _variance(List<double> x) {
    final mean = x.reduce((a, b) => a + b) / x.length;
    final sum = x.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b);
    return (sum / x.length).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final score = (_comfortScore * 100).toStringAsFixed(0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Soundscape Mixer'),
        backgroundColor: AppTheme.backgroundDark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Level $level',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Target: $_targetProfile',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Comfort score: $score%',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _slider('Rain', rain, (v) => setState(() => rain = v), const Color(0xFF60A5FA)),
            _slider('Wind', wind, (v) => setState(() => wind = v), const Color(0xFFA3E635)),
            _slider('Cafe', cafe, (v) => setState(() => cafe = v), const Color(0xFFF59E0B)),
            _slider(
              'White Noise',
              whiteNoise,
              (v) => setState(() => whiteNoise = v),
              const Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _validateMix,
                child: const Text('Validate Mix'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Streak: $streak',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    ValueChanged<double> onChanged,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${(value * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white),
          ),
          Slider(
            value: value,
            min: 0,
            max: 1,
            activeColor: color,
            inactiveColor: Colors.white.withValues(alpha: 0.18),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
