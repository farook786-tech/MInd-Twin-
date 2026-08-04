import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/patient.dart';
import 'patient_details_screen.dart';

class PatientDetailScreen extends StatefulWidget {
  final String patientId;
  final String initialName;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.initialName,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  late final Future<Patient> _patientFuture;

  @override
  void initState() {
    super.initState();
    _patientFuture = _loadPatient();
  }

  Future<Patient> _loadPatient() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.patientId).get();
      final data = doc.data() ?? <String, dynamic>{};
      return Patient(
        id: widget.patientId,
        name: (data['name'] ?? widget.initialName).toString(),
        email: (data['email'] ?? '').toString(),
        age: int.tryParse(data['age']?.toString() ?? '') ?? 0,
        therapistId: data['therapistId']?.toString(),
        currentRiskScore: _toRiskScore(data['currentRiskScore'] ?? data['riskScore'] ?? data['latestRiskScore']),
        riskScore: _toRiskScore(data['riskScore'] ?? data['latestRiskScore']),
        wellbeingScore: _toDouble(data['wellbeingScore']) ?? 50.0,
        lastUpdated: (data['lastUpdated'] ?? '').toString(),
        createdAt: DateTime.now(),
        lastCheckIn: _toDateTime(data['lastCheckIn']) ?? DateTime.now(),
        missedSessions: int.tryParse(data['missedSessions']?.toString() ?? '') ?? 0,
        isDemo: data['isDemo'] == true,
      );
    } catch (_) {
      return Patient(
        id: widget.patientId,
        name: widget.initialName,
        email: '',
        age: 0,
        currentRiskScore: 0,
        createdAt: DateTime.now(),
        lastCheckIn: DateTime.now(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: FutureBuilder<Patient>(
        future: _patientFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryIndigo));
          }

          final patient = snapshot.data;
          if (patient == null) {
            return const Center(
              child: Text('Unable to load patient details.', style: TextStyle(color: Colors.white70)),
            );
          }

          return PatientDetailsScreen(patient: patient);
        },
      ),
    );
  }

  double _toRiskScore(dynamic value) {
    final result = _toDouble(value) ?? 0.0;
    return result <= 1 ? result : (result / 100.0).clamp(0.0, 1.0);
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}