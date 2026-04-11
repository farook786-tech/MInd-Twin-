import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';

class WearableDataTrackingScreen extends StatefulWidget {
  const WearableDataTrackingScreen({super.key});

  @override
  State<WearableDataTrackingScreen> createState() =>
      _WearableDataTrackingScreenState();
}

class _WearableDataTrackingScreenState extends State<WearableDataTrackingScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  final AuthService _authService = AuthService();

  String? _patientId;
  bool _submitting = false;

  // Wearable Data Controllers
  int _moodScore = 5;
  int _anxietyScore = 5;
  double _sleepDuration = 7;
  int _sleepQuality = 5;
  int _heartRate = 70;
  int _steps = 5000;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _patientId = _authService.currentUserId;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _submitWearableData() async {
    if (_patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient ID not found')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // Submit all data points in batch
      final dataPoints = [
        {'type': 'mood', 'value': _moodScore, 'timestamp': DateTime.now().toIso8601String()},
        {'type': 'anxiety', 'value': _anxietyScore, 'timestamp': DateTime.now().toIso8601String()},
        {
          'type': 'sleep',
          'value': {'duration': _sleepDuration, 'quality': _sleepQuality},
          'timestamp': DateTime.now().toIso8601String(),
        },
        {
          'type': 'heartrate',
          'value': {'rate': _heartRate, 'isResting': true},
          'timestamp': DateTime.now().toIso8601String(),
        },
        {
          'type': 'activity',
          'value': {'steps': _steps, 'minutes': 0, 'calories': 0},
          'timestamp': DateTime.now().toIso8601String(),
        },
      ];

      final success = await _backendApiService.ingestWearableBatch(_patientId!, dataPoints);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Wearable data submitted successfully')),
        );

        setState(() => _submitting = false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error submitting data')),
        );
        setState(() => _submitting = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Wearable Data Tracking',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildHealthMetrics(),
            const SizedBox(height: 24),
            _buildSubmitButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Real-Time Health Metrics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your wearable device data helps your therapist track your health and optimize treatment. '
            'All data is real-time and uploaded immediately.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthMetrics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Health Metrics',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        // Mood
        _buildMetricCard(
          'Mood',
          _moodScore,
          1,
          10,
          'How are you feeling?',
          Icons.emoji_emotions_rounded,
          const Color(0xFFFFB74D),
          (value) => setState(() => _moodScore = value.toInt()),
        ),
        const SizedBox(height: 12),
        // Anxiety
        _buildMetricCard(
          'Anxiety Level',
          _anxietyScore,
          1,
          10,
          'Current anxiety (1=calm, 10=severe)',
          Icons.psychology_rounded,
          Colors.orange,
          (value) => setState(() => _anxietyScore = value.toInt()),
        ),
        const SizedBox(height: 12),
        // Sleep Duration
        _buildSleepCard(),
        const SizedBox(height: 12),
        // Sleep Quality
        _buildMetricCard(
          'Sleep Quality',
          _sleepQuality,
          1,
          10,
          'Rate your sleep quality',
          Icons.bedtime_rounded,
          Colors.indigo,
          (value) => setState(() => _sleepQuality = value.toInt()),
        ),
        const SizedBox(height: 12),
        // Heart Rate
        _buildHeartRateCard(),
        const SizedBox(height: 12),
        // Steps
        _buildStepsCard(),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    num value,
    num minValue,
    num maxValue,
    String subtitle,
    IconData icon,
    Color color,
    Function(double) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: value.toDouble(),
              min: minValue.toDouble(),
              max: maxValue.toDouble(),
              divisions: (maxValue - minValue).toInt(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bedtime_rounded, color: Colors.indigo, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sleep Duration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Hours of sleep last night',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_sleepDuration.toStringAsFixed(1)}h',
                  style: const TextStyle(
                    color: Colors.indigo,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.indigo,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.indigo,
              overlayColor: Colors.indigo.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: _sleepDuration,
              min: 0,
              max: 12,
              divisions: 24,
              onChanged: (value) => setState(() => _sleepDuration = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeartRateCard() {
    Color hrColor;
    String hrStatus;

    if (_heartRate < 60) {
      hrColor = Colors.blue;
      hrStatus = 'Low (athletic)';
    } else if (_heartRate < 80) {
      hrColor = Colors.green;
      hrStatus = 'Normal';
    } else if (_heartRate < 100) {
      hrColor = Colors.orange;
      hrStatus = 'Elevated';
    } else {
      hrColor = Colors.red;
      hrStatus = 'High';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hrColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, color: hrColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resting Heart Rate',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hrStatus,
                      style: TextStyle(
                        color: hrColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hrColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_heartRate bpm',
                  style: TextStyle(
                    color: hrColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: hrColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: hrColor,
              overlayColor: hrColor.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: _heartRate.toDouble(),
              min: 40,
              max: 120,
              divisions: 80,
              onChanged: (value) => setState(() => _heartRate = value.toInt()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepsCard() {
    Color activityColor;
    String activityStatus;

    if (_steps < 5000) {
      activityColor = Colors.red;
      activityStatus = 'Low activity';
    } else if (_steps < 10000) {
      activityColor = Colors.orange;
      activityStatus = 'Moderate activity';
    } else {
      activityColor = Colors.green;
      activityStatus = 'Active day';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activityColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_walk_rounded, color: activityColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily Steps',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activityStatus,
                      style: TextStyle(
                        color: activityColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: activityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _steps.toString(),
                  style: TextStyle(
                    color: activityColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: activityColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: activityColor,
              overlayColor: activityColor.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: _steps.toDouble(),
              min: 0,
              max: 20000,
              divisions: 200,
              onChanged: (value) => setState(() => _steps = value.toInt()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _submitting ? null : _submitWearableData,
        icon: _submitting ? null : const Icon(Icons.upload_rounded),
        label: Text(_submitting ? 'Submitting...' : 'Submit Wearable Data'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryIndigo,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
