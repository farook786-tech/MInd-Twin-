import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class BreathingExerciseScreen extends StatelessWidget {
  const BreathingExerciseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Breathing Exercise'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Inhale for 4, hold for 4, exhale for 6.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('Breathing exercise completed'),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}