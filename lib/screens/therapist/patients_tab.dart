import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/clinical_scoring.dart';
import '../../widgets/clinical_status_card.dart';
import '../chat/chat_screen.dart';
import 'patient_detail_screen.dart';

class PatientsTab extends StatefulWidget {
  const PatientsTab({super.key});

  @override
  State<PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<PatientsTab> {
  String _search = '';
  String? _boundTherapistId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _usersStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _unackStream;

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

    if (_boundTherapistId != therapistId) {
      _boundTherapistId = therapistId;
      final db = FirebaseFirestore.instance;
      _usersStream = db
          .collection('users')
          .where('role', isEqualTo: 'patient')
          .where('therapistId', isEqualTo: therapistId)
          .snapshots();
      // Unacknowledged alerts for this therapist's patients: an unacknowledged
      // C-SSRS HIGH keeps the patient at the top of the list.
      _unackStream = db
          .collection('crisis_events')
          .where('therapistId', isEqualTo: therapistId)
          .where('acknowledged', isEqualTo: false)
          .snapshots();
    }

    return _PatientShell(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _unackStream,
        builder: (context, unackSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _usersStream,
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
          final unackTypes = <String, List<String>>{};
          for (final d in unackSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
            final pid = d.data()['patientId'];
            final type = d.data()['eventType'];
            if (pid is String && type is String) (unackTypes[pid] ??= []).add(type);
          }
          final patients = _dedupeAndSortPatients(docs, unackTypes);

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
                  style: TextStyle(color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Search by patient name',
                    hintStyle: TextStyle(color: AppColors.ink.withValues(alpha: 0.46)),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.ink.withValues(alpha: 0.62)),
                    filled: true,
                    fillColor: AppTheme.cardDark,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.ink.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.primaryIndigo),
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
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, color: AppColors.ink54, size: 46),
            const SizedBox(height: 10),
            Text(
              'No patients assigned yet',
              style: TextStyle(
                color: AppColors.ink,
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
                color: AppColors.ink.withValues(alpha: 0.6),
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
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'My Patients',
                style: TextStyle(
                  color: AppColors.ink,
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
                border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
              ),
              child: Text(
                '$totalCount Patients',
                style: TextStyle(
                  color: AppColors.ink,
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
    final level = patient.clinicalLevel;
    final levelColor = patient.hasInstrumentData ? ClinicalStatusCard.colorFor(level) : AppColors.ink54;
    final riskColor = patient.hasInstrumentData ? levelColor : (risk == null ? AppColors.ink54 : _riskColor(risk));
    // Check-in heuristic: early-warning only, never labelled as "risk".
    final riskText = risk == null
        ? 'Check-in indicator: —'
        : 'Check-in indicator: ${risk.toStringAsFixed(0)}/100 (${_riskLabel(risk)})';
    final levelText = patient.hasInstrumentData
        ? 'Clinical status: ${level.label.toUpperCase()}'
        : 'Clinical status: no validated assessment yet';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.1)),
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
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      levelText,
                      style: TextStyle(
                        color: levelColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      riskText,
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.76),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Emotion: ${patient.latestMood}',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.76),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last check-in: ${patient.lastCheckInRelative}',
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.65),
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
                            ? AppColors.ink.withValues(alpha: 0.5)
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
                        color: AppColors.ink.withValues(alpha: 0.8),
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
    final color = AppTheme.primaryIndigo;
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
              CircularProgressIndicator(color: AppTheme.primaryIndigo)
            else
              Icon(icon, color: color, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.62),
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
  final ClinicalLevel clinicalLevel;
  final bool hasInstrumentData;

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
    this.clinicalLevel = ClinicalLevel.none,
    this.hasInstrumentData = false,
  });
}

/// Same defaults as functions/src/logic/vitals.js and PatientVitalsPanel.
const double _defaultHrHigh = 120;
const double _defaultHrLow = 45;
const Duration _vitalsStaleAfter = Duration(hours: 2);

int? _snapshotTotal(dynamic snap) {
  if (snap is Map && snap['total'] is num) return (snap['total'] as num).round();
  return null;
}

List<_PatientUI> _dedupeAndSortPatients(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, [
  Map<String, List<String>> unacknowledgedTypes = const {},
]) {
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

    // Clinical level from validated-instrument snapshots + unacknowledged
    // C-SSRS / PHQ-9 alerts (same mapping as the Clinical status card).
    final phq9Total = _snapshotTotal(data['latestPhq9']);
    final gad7Total = _snapshotTotal(data['latestGad7']);
    final cssrsSnap = data['latestCssrs'];
    final cssrsRisk = cssrsSnap is Map ? parseCssrsRisk(cssrsSnap['risk']) : null;
    final unack = unacknowledgedTypes[id] ?? const <String>[];
    final level = ClinicalScoring.rosterLevel(
      phq9Total: phq9Total,
      gad7Total: gad7Total,
      cssrsRisk: cssrsRisk,
      unacknowledgedEventTypes: unack,
    );
    final hasInstrumentData = phq9Total != null ||
        gad7Total != null ||
        cssrsRisk != null ||
        unack.any((t) => t == 'cssrs_high' || t == 'cssrs_moderate' || t == 'phq9_severe');

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
      clinicalLevel: level,
      hasInstrumentData: hasInstrumentData,
    );

    final old = map[id];
    if (old == null || item.sortingTime.isAfter(old.sortingTime)) {
      map[id] = item;
    }
  }

  final items = map.values.toList()
    ..sort((a, b) {
      // Clinical level (validated instruments) first: critical > high > ... > none.
      final levelCmp = b.clinicalLevel.rank.compareTo(a.clinicalLevel.rank);
      if (levelCmp != 0) return levelCmp;
      // Then a live out-of-range heart rate (early-warning signal).
      if (a.heartRateOutOfRange != b.heartRateOutOfRange) {
        return a.heartRateOutOfRange ? -1 : 1;
      }
      // Then highest check-in indicator; patients without one sort after scored ones.
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

/// Check-in self-report heuristic band (early warning; not a clinical risk level).
String _riskLabel(double risk) {
  if (risk >= 75) return 'very high strain';
  if (risk >= 50) return 'high strain';
  if (risk >= 25) return 'some strain';
  return 'little strain';
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
