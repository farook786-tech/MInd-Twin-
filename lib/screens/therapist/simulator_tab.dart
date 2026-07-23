import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/backend_api_service.dart';
import '../../services/auth_service.dart';

class SimulatorTab extends StatefulWidget {
  const SimulatorTab({super.key});

  @override
  State<SimulatorTab> createState() => _SimulatorTabState();
}

class _SimulatorTabState extends State<SimulatorTab> {
  final BackendApiService _apiService = BackendApiService();

  String? _selectedPatientId;
  String? _apiBase;
  bool _recommendationsLoading = false;
  bool _explanationLoading = false;
  String? _selectedIntervention;
  String? _geminiExplanation;
  List<_ApiIntervention> _apiRecommendations = const [];

  static const List<_SimulatorIntervention> _options = [
    _SimulatorIntervention('Crisis Support', '🆘', 0.42),
    _SimulatorIntervention('Increase Sessions', '📈', 0.30),
    _SimulatorIntervention('CBT Exercises', '🧠', 0.24),
    _SimulatorIntervention('Medication Review', '💊', 0.21),
    _SimulatorIntervention('Group Therapy', '👥', 0.18),
    _SimulatorIntervention('Mindfulness', '🌬️', 0.16),
    _SimulatorIntervention('Sleep Hygiene', '🌙', 0.14),
    _SimulatorIntervention('Social Activation', '🤝', 0.12),
  ];

  @override
  void initState() {
    super.initState();
    _resolveBackendBase();
  }

  Future<void> _resolveBackendBase() async {
    final manual = await _apiService.getManualBaseUrl();
    final base = manual ?? await _apiService.autoDetectLanBackendUrl();
    if (!mounted) return;
    setState(() {
      _apiBase = base ?? 'http://localhost:5000';
    });
  }

  Future<void> _loadRecommendations(String patientId) async {
    if (_apiBase == null) return;

    setState(() {
      _recommendationsLoading = true;
      _apiRecommendations = const [];
    });

    try {
      final resp = await http.post(
        Uri.parse('$_apiBase/api/ml/recommend-intervention'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'patientId': patientId}),
      );

      final body = jsonDecode(resp.body);
      final payload = body is Map<String, dynamic> ? body : <String, dynamic>{};
      final raw = payload['topRecommendations'] ?? payload['interventions'] ?? payload['result']?['interventions'];
      final list = raw is List ? raw.whereType<Map>().toList() : const <Map>[];

      final parsed = list.take(3).map((item) {
        final map = item.map((k, v) => MapEntry(k.toString(), v));
        return _ApiIntervention(
          title: _safeString(map['title'], fallback: _safeString(map['id'], fallback: 'Intervention')),
          reason: _safeString(map['description'], fallback: 'Recommended by ML service.'),
          confidence: _confidencePercent(map['confidence'] ?? map['matchScore']),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _apiRecommendations = parsed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _apiRecommendations = const [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _recommendationsLoading = false;
      });
    }
  }

  Future<void> _loadGeminiExplanation({
    required String patientName,
    required double currentRisk,
    required String intervention,
  }) async {
    if (_apiBase == null) return;

    setState(() {
      _explanationLoading = true;
      _geminiExplanation = null;
    });

    final prompt = 'Patient has ${currentRisk.toStringAsFixed(0)}% risk. '
        'Therapist selected $intervention. '
        'Explain in 3 bullet points why this will help this specific patient.';

    try {
      final resp = await http.post(
        Uri.parse('$_apiBase/api/gemini/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': prompt,
          'systemPrompt': 'You are a clinical AI assistant. Be concise and practical for therapists.',
        }),
      );

      final payload = jsonDecode(resp.body);
      final map = payload is Map<String, dynamic> ? payload : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _geminiExplanation = _safeString(
          map['response'],
          fallback: 'AI explanation is unavailable for $patientName right now.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _geminiExplanation = 'AI explanation is unavailable for $patientName right now.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _explanationLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final therapistId = AuthService().currentUserId;

    if (therapistId == null) {
      return const Center(
        child: Text('Please sign in as therapist.', style: TextStyle(color: Colors.white70)),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A0A0F), Color(0xFF111521)],
        ),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'patient')
            .where('therapistId', isEqualTo: therapistId)
            .snapshots(),
        builder: (context, patientSnapshot) {
          if (patientSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryIndigo));
          }

          final docs = patientSnapshot.data?.docs ?? const [];
          final patients = _dedupePatients(docs);

          if (patientSnapshot.hasError && patients.isEmpty) {
            return const Center(
              child: Text('No simulator data available.', style: TextStyle(color: Colors.white70)),
            );
          }

          if (patients.isEmpty) {
            return const Center(
              child: Text('No assigned patients found for simulation.', style: TextStyle(color: Colors.white70)),
            );
          }

          _selectedPatientId ??= patients.first.id;

          final selected = patients.firstWhere(
            (p) => p.id == _selectedPatientId,
            orElse: () => patients.first,
          );

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('daily_logs')
                .where('patientId', isEqualTo: selected.id)
                .limit(20)
                .snapshots(),
            builder: (context, logSnapshot) {
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('clinical_assessments')
                    .where('patientId', isEqualTo: selected.id)
                    .limit(10)
                    .snapshots(),
                builder: (context, assessmentSnapshot) {
                  final logs = (logSnapshot.data?.docs ?? const [])
                      .map((e) => e.data())
                      .toList()
                    ..sort((a, b) => _timestamp(b).compareTo(_timestamp(a)));

                  final assessments = (assessmentSnapshot.data?.docs ?? const [])
                      .map((e) => e.data())
                      .toList()
                    ..sort((a, b) => _timestamp(b).compareTo(_timestamp(a)));

                  final latestAssessment = assessments.isEmpty ? <String, dynamic>{} : assessments.first;
                  final latestLog = logs.isEmpty ? <String, dynamic>{} : logs.first;
                  final risk = _riskPercent(selected.data);
                  final chosenIntervention = _options.firstWhere(
                    (e) => e.name == _selectedIntervention,
                    orElse: () => const _SimulatorIntervention('', '', 0),
                  );
                  final projected = _selectedIntervention == null
                      ? risk
                      : (risk * (1 - chosenIntervention.reduction)).clamp(0.0, 100.0);

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Intervention Simulator',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CardSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Patient',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: selected.id,
                                dropdownColor: AppTheme.cardDark,
                                style: const TextStyle(color: Colors.white),
                                decoration: _inputDecoration(),
                                items: patients
                                    .map(
                                      (p) => DropdownMenuItem<String>(
                                        value: p.id,
                                        child: Text('${p.name} (${_riskPercent(p.data).toStringAsFixed(0)}%)'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _selectedPatientId = value;
                                    _selectedIntervention = null;
                                    _geminiExplanation = null;
                                    _apiRecommendations = const [];
                                  });
                                  _loadRecommendations(value);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CardSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selected.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _line('Risk Score', '${risk.toStringAsFixed(0)}%'),
                              _line('Emotion', _safeString(selected.data['latestMood'], fallback: 'Unknown')),
                              _line('Last check-in', _relative(_dateOf(selected.data['lastCheckInDate']))),
                              _line('Latest PHQ-9', (_toDouble(latestAssessment['phq9Score']) ?? 0).toStringAsFixed(0)),
                              _line('Latest GAD-7', (_toDouble(latestAssessment['gad7Score']) ?? 0).toStringAsFixed(0)),
                              if (latestLog.isNotEmpty)
                                _line('Latest Mood', '${(_toDouble(latestLog['moodScore']) ?? 0).toStringAsFixed(1)}/10'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CardSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🤖 AI Recommends for ${selected.name}:',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_recommendationsLoading)
                                const LinearProgressIndicator(color: AppTheme.primaryIndigo)
                              else if (_apiRecommendations.isEmpty)
                                Text(
                                  'No recommendations received from backend yet.',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                                )
                              else
                                ..._apiRecommendations.map((rec) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.backgroundDark,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${rec.title} • ${rec.confidence.toStringAsFixed(0)}%',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(rec.reason, style: TextStyle(color: Colors.white.withValues(alpha: 0.68))),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CardSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Interventions',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _options.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 1.8,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemBuilder: (context, index) {
                                  final option = _options[index];
                                  final selectedOption = _selectedIntervention == option.name;
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedIntervention = option.name;
                                      });
                                      _loadGeminiExplanation(
                                        patientName: selected.name,
                                        currentRisk: risk,
                                        intervention: option.name,
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: selectedOption
                                            ? AppTheme.primaryIndigo.withValues(alpha: 0.2)
                                            : AppTheme.backgroundDark,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: selectedOption
                                              ? AppTheme.primaryIndigo
                                              : Colors.white.withValues(alpha: 0.08),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${option.icon} ${option.name}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${(option.reduction * 100).toStringAsFixed(0)}% risk reduction',
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.68),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CardSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Before / After',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _riskBlock(
                                      title: 'Before',
                                      value: '${risk.toStringAsFixed(0)}%',
                                      color: risk >= 50 ? AppTheme.warningAmber : AppTheme.safeGreen,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Icon(Icons.arrow_forward_rounded, color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: _riskBlock(
                                      title: 'After',
                                      value: '${projected.toStringAsFixed(0)}%',
                                      color: AppTheme.safeGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _CardSurface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Why this works for ${selected.name}:',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              if (_explanationLoading)
                                const LinearProgressIndicator(color: AppTheme.primaryIndigo)
                              else
                                Text(
                                  _geminiExplanation ??
                                      'Select an intervention to request a Gemini explanation.',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _selectedIntervention == null
                                ? null
                                : () async {
                                    final intervention = _selectedIntervention!;
                                    await FirebaseFirestore.instance.collection('interventions').add({
                                      'patientId': selected.id,
                                      'therapistId': therapistId,
                                      'type': intervention,
                                      'beforeRisk': risk,
                                      'afterRisk': projected,
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });

                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Intervention applied successfully.'),
                                        backgroundColor: AppTheme.primaryIndigo,
                                      ),
                                    );
                                  },
                            child: const Text('Apply This Intervention'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.58), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskBlock({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppTheme.backgroundDark,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primaryIndigo),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    );
  }
}

class _CardSurface extends StatelessWidget {
  final Widget child;

  const _CardSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _PatientState {
  final String id;
  final String name;
  final Map<String, dynamic> data;
  final DateTime updatedAt;

  const _PatientState({
    required this.id,
    required this.name,
    required this.data,
    required this.updatedAt,
  });
}

class _ApiIntervention {
  final String title;
  final String reason;
  final double confidence;

  const _ApiIntervention({
    required this.title,
    required this.reason,
    required this.confidence,
  });
}

class _SimulatorIntervention {
  final String name;
  final String icon;
  final double reduction;

  const _SimulatorIntervention(this.name, this.icon, this.reduction);
}

List<_PatientState> _dedupePatients(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final map = <String, _PatientState>{};

  for (final doc in docs) {
    final data = doc.data();
    final id = _safeString(data['uid'], fallback: _safeString(data['patientId'], fallback: doc.id));
    final item = _PatientState(
      id: id,
      name: _safeString(data['name'], fallback: 'Unnamed Patient'),
      data: data,
      updatedAt: _timestamp(data),
    );

    final previous = map[id];
    if (previous == null || item.updatedAt.isAfter(previous.updatedAt)) {
      map[id] = item;
    }
  }

  final list = map.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

double _riskPercent(Map<String, dynamic> data) {
  final raw = _toDouble(data['latestRiskScore'] ?? data['riskScore'] ?? data['risk']);
  if (raw == null) return 0;
  if (raw <= 1) return (raw * 100).clamp(0.0, 100.0);
  return raw.clamp(0.0, 100.0);
}

DateTime _timestamp(Map<String, dynamic> data) {
  final values = [data['timestamp'], data['lastCheckInDate'], data['updatedAt'], data['createdAt']];
  for (final value in values) {
    final date = _dateOf(value);
    if (date != null) return date;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _dateOf(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

String _relative(DateTime? date) {
  if (date == null) return 'No check-in';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} d ago';
}

String _safeString(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return fallback;
}

double _confidencePercent(dynamic value) {
  final parsed = _toDouble(value) ?? 0;
  if (parsed <= 1) return (parsed * 100).clamp(0.0, 100.0);
  return parsed.clamp(0.0, 100.0);
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
