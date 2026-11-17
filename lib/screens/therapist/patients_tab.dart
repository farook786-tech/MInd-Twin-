import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../chat/chat_screen.dart';
import 'patient_detail_screen.dart';

class PatientsTab extends StatefulWidget {
  const PatientsTab({super.key});

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final therapistId = AuthService().currentUserId;

    if (therapistId == null) {
      return _PatientShell(
        child: _CenteredInfo(
          icon: Icons.lock_outline_rounded,
          title: 'Therapist Session Required',
          subtitle: 'Please sign in to load your patient roster.',
        ),
      );
    }

    final usersQuery = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'patient')
        .where('therapistId', isEqualTo: therapistId)
        .snapshots();

    return _PatientShell(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersQuery,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _CenteredInfo(
              icon: Icons.sync_rounded,
              title: 'Loading Patients',
              subtitle: 'Fetching assigned patients in real-time...',
              isLoading: true,
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          final patients = _dedupeAndSortPatients(docs);

          final filtered = _search.trim().isEmpty
              ? patients
              : patients
                  .where((p) => p.name.toLowerCase().contains(_search.toLowerCase()))
                  .toList();

          if (snapshot.hasError && patients.isEmpty) {
            final error = snapshot.error;
            return _CenteredInfo(
              icon: Icons.error_outline_rounded,
              title: 'Unable To Load Patients',
              subtitle: error is FirebaseException && error.code == 'permission-denied'
                  ? 'Permission denied. Confirm your therapist account is approved, then sign out and back in.'
                  : 'Patient roster could not be loaded: ${error ?? 'unknown error'}',
              tint: AppTheme.riskRed,
            );
          }

          return Column(
            children: [
              _PatientsHeader(totalCount: patients.length),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by patient name',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.46)),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.62)),
                    filled: true,
                    fillColor: AppTheme.cardDark,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryIndigo),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(
                        hasAnyPatient: patients.isNotEmpty,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final patient = filtered[index];
                          return _PatientCard(
                            patient: patient,
                            onViewDetails: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientDetailScreen(
                                    patientId: patient.id,
                                    initialName: patient.name,
                                  ),
                                ),
                              );
                            },
                            onMessage: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    otherUserId: patient.id,
                                    otherUserName: patient.name,
                                    isTherapist: true,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required bool hasAnyPatient,
  }) {
    if (hasAnyPatient && _search.trim().isNotEmpty) {
      return const _CenteredInfo(
        icon: Icons.filter_alt_off_rounded,
        title: 'No Matching Patients',
        subtitle: 'Try a different search term.',
      );
    }

    return Center(
      child: Container(
        width: 520,
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded, color: Colors.white54, size: 46),
            const SizedBox(height: 10),
            const Text(
              'No patients assigned yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Patients link to you with your invite code. Find it on the Dashboard tab '
              '("Your invite code") and share it with your patient.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientShell extends StatelessWidget {
  final Widget child;

  const _PatientShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0F), Color(0xFF10131C)],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

class _PatientsHeader extends StatelessWidget {
  final int totalCount;

  const _PatientsHeader({required this.totalCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'My Patients',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.backgroundDark,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Text(
                '$totalCount Patients',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final _PatientUI patient;
  final VoidCallback onViewDetails;
  final VoidCallback onMessage;

  const _PatientCard({
    required this.patient,
    required this.onViewDetails,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final risk = patient.riskPercent;
    final riskColor = risk == null ? Colors.white54 : _riskColor(risk);
    final riskText = risk == null
        ? 'Risk: no check-in data yet'
        : 'Risk: ${risk.toStringAsFixed(0)}% ${_riskLabel(risk)} ${_riskEmoji(risk)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: riskColor.withValues(alpha: 0.2),
                child: Text(
                  patient.name.isNotEmpty ? patient.name[0].toUpperCase() : 'P',
                  style: TextStyle(
                    color: riskColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      riskText,
                      style: TextStyle(
                        color: riskColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Emotion: ${patient.latestMood}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last check-in: ${patient.lastCheckInRelative}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Live smartwatch heart rate (users.latestVitals, kept current by the
                    // onVitalCreated Cloud Function), coloured against this patient's thresholds.
                    Text(
                      patient.heartRate == null
                          ? '❤ No watch data yet'
                          : '❤ ${patient.heartRate!.round()} bpm · ${patient.heartRateRelative}'
                              '${patient.heartRateStale ? ' (watch not syncing)' : ''}',
                      style: TextStyle(
                        color: patient.heartRate == null || patient.heartRateStale
                            ? Colors.white.withValues(alpha: 0.5)
                            : patient.heartRateOutOfRange
                                ? AppTheme.riskRed
                                : AppTheme.safeGreen,
                        fontSize: 12,
                        fontWeight: patient.heartRateOutOfRange ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Streak: 🔥 ${patient.streak} days',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionBtn(label: 'View Details', onTap: onViewDetails),
              _ActionBtn(label: 'Message', onTap: onMessage),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.primaryIndigo;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CenteredInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tint;
  final bool isLoading;

  const _CenteredInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppTheme.primaryIndigo;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const CircularProgressIndicator(color: AppTheme.primaryIndigo)
            else
              Icon(icon, color: color, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientUI {
  final String id;
  final String name;
  final double? riskPercent;
  final String latestMood;
  final String lastCheckInRelative;
  final int streak;
  final DateTime sortingTime;
  final double? heartRate;
  final String heartRateRelative;
  final bool heartRateStale;
  final bool heartRateOutOfRange;

  const _PatientUI({
    required this.id,
    required this.name,
    required this.riskPercent,
    required this.latestMood,
    required this.lastCheckInRelative,
    required this.streak,
    required this.sortingTime,
    this.heartRate,
    this.heartRateRelative = '',
    this.heartRateStale = false,
    this.heartRateOutOfRange = false,
  });
}

/// Same defaults as functions/src/logic/vitals.js and PatientVitalsPanel.
const double _defaultHrHigh = 120;
const double _defaultHrLow = 45;
const Duration _vitalsStaleAfter = Duration(hours: 2);

List<_PatientUI> _dedupeAndSortPatients(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final map = <String, _PatientUI>{};

  for (final doc in docs) {
    final data = doc.data();
    // users/{uid}: the document id IS the patient uid.
    final id = doc.id;
    final name = _safeString(data['name'], fallback: 'Unnamed Patient');
    final risk = _riskPercent(data);
    final checkInDate = _readDate(data['lastCheckInAt']) ?? _readDate(data['lastCheckInDate']);

    final vitals = data['latestVitals'];
    final hr = vitals is Map ? vitals['heartRate'] : null;
    final hrValue = hr is Map ? _toDouble(hr['value']) : null;
    final hrAt = hr is Map ? _readDate(hr['measuredAt']) : null;
    final thresholds = data['vitalThresholds'];
    final hrHigh = (thresholds is Map ? _toDouble(thresholds['heartRateHigh']) : null) ?? _defaultHrHigh;
    final hrLow = (thresholds is Map ? _toDouble(thresholds['heartRateLow']) : null) ?? _defaultHrLow;
    final hrStale = hrAt == null || DateTime.now().difference(hrAt) > _vitalsStaleAfter;

    final item = _PatientUI(
      id: id,
      name: name,
      riskPercent: risk,
      latestMood: _safeString(data['latestMood'], fallback: 'Unknown'),
      lastCheckInRelative: checkInDate == null ? 'Never' : _relativeTime(checkInDate),
      streak: _readInt(data['streak']),
      sortingTime: checkInDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      heartRate: hrValue,
      heartRateRelative: hrAt == null ? '' : _relativeTime(hrAt),
      heartRateStale: hrValue != null && hrStale,
      heartRateOutOfRange: hrValue != null && !hrStale && (hrValue > hrHigh || hrValue < hrLow),
    );

    final old = map[id];
    if (old == null || item.sortingTime.isAfter(old.sortingTime)) {
      map[id] = item;
    }
  }

  final items = map.values.toList()
    ..sort((a, b) {
      // A live out-of-range heart rate is the most urgent signal: list those first.
      if (a.heartRateOutOfRange != b.heartRateOutOfRange) {
        return a.heartRateOutOfRange ? -1 : 1;
      }
      // Then highest risk; patients without a score sort after scored ones.
      final riskCmp = (b.riskPercent ?? -1).compareTo(a.riskPercent ?? -1);
      if (riskCmp != 0) return riskCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return items;
}

int _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _safeString(dynamic value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is num) return value.toString();
  return fallback;
}

DateTime? _readDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// users.latestRiskScore on the contract's 0-100 scale; null if never scored.
double? _riskPercent(Map<String, dynamic> data) {
  final asNum = _toDouble(data['latestRiskScore']);
  if (asNum == null || asNum.isNaN) return null;
  return asNum.clamp(0.0, 100.0);
}

String _riskLabel(double risk) {
  if (risk >= 75) return 'Critical';
  if (risk >= 50) return 'High';
  if (risk >= 25) return 'Moderate';
  return 'Low';
}

String _riskEmoji(double risk) {
  if (risk >= 75) return '😟';
  if (risk >= 50) return '😣';
  if (risk >= 25) return '😐';
  return '🙂';
}

Color _riskColor(double risk) {
  if (risk >= 75) return AppTheme.riskRed;
  if (risk >= 50) return const Color(0xFFE37A42);
  if (risk >= 25) return AppTheme.warningAmber;
  return AppTheme.safeGreen;
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${(diff.inDays / 7).floor()} weeks ago';
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
