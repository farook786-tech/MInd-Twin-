import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class ThoughtDumpResult {
  final String text;
  final String sentiment;

  const ThoughtDumpResult({required this.text, required this.sentiment});
}

class ThoughtDumpScreen extends StatefulWidget {
  const ThoughtDumpScreen({super.key});

  @override
  State<ThoughtDumpScreen> createState() => _ThoughtDumpScreenState();
}

class _ThoughtDumpScreenState extends State<ThoughtDumpScreen> {
  final TextEditingController _controller = TextEditingController();
  String _sentiment = 'neutral';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Thought Dump'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Write whatever is on your mind...',
                filled: true,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _sentiment,
              dropdownColor: AppTheme.cardDark,
              items: const [
                DropdownMenuItem(value: 'positive', child: Text('Positive')),
                DropdownMenuItem(value: 'neutral', child: Text('Neutral')),
                DropdownMenuItem(value: 'negative', child: Text('Negative')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _sentiment = value;
                });
              },
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(
                  ThoughtDumpResult(text: _controller.text.trim(), sentiment: _sentiment),
                );
              },
              child: const Text('Save Thought Dump'),
            ),
          ],
        ),
      ),
    );
  }
}