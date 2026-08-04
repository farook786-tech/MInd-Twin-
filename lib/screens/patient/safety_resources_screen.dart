import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class SafetyResourcesScreen extends StatelessWidget {
  const SafetyResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Safety Resources'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _ResourceCard(
            title: 'Emergency Help',
            body: 'If you are in immediate danger, call your local emergency number now.',
          ),
          _ResourceCard(
            title: 'Trusted Person',
            body: 'Reach out to a friend, family member, or therapist and let them know you need support.',
          ),
          _ResourceCard(
            title: 'Grounding Step',
            body: 'Try slow breathing: inhale for 4, exhale for 6, and repeat five times.',
          ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final String title;
  final String body;

  const _ResourceCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.cardDark,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}