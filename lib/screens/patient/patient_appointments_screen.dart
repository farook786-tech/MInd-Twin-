import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  State<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState extends State<PatientAppointmentsScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _appointments = const [];
  List<Map<String, dynamic>> _treatmentPlans = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _loading = true);
    try {
      final userId = _authService.currentUserId ?? '';
      final rows = await _backendApiService.fetchSharedAppointments(
        patientExternalId: userId,
      );
      final plans = await _backendApiService.fetchSharedTreatmentPlans(
        patientExternalId: userId,
      );
      if (!mounted) return;
      
      // Auto-mark appointments as seen
      for (final appointment in rows) {
        final appointmentId = appointment['id']?.toString() ?? '';
        final patientSeen = (appointment['patient_seen'] as num?)?.toInt() ?? 0;
        if (appointmentId.isNotEmpty && patientSeen == 0) {
          await _backendApiService.markAppointmentSeen(appointmentId);
        }
      }
      
      // Auto-mark treatment plans as seen
      for (final plan in plans) {
        final planId = plan['id']?.toString() ?? '';
        final patientSeen = (plan['patient_seen'] as num?)?.toInt() ?? 0;
        if (planId.isNotEmpty && patientSeen == 0) {
          await _backendApiService.markPlanSeen(planId);
        }
      }
      
      setState(() {
        _appointments = rows;
        _treatmentPlans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _markAppointmentAccepted(String appointmentId) async {
    final success = await _backendApiService.markAppointmentAccepted(appointmentId);
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Appointment accepted!' : 'Failed to accept appointment'),
        backgroundColor: success ? AppTheme.safeGreen : AppTheme.riskRed,
        duration: const Duration(seconds: 2),
      ),
    );
    
    if (success) {
      await _loadAppointments();
    }
  }

  Future<void> _markPlanAccepted(String planId) async {
    final success = await _backendApiService.markPlanAccepted(planId);
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Treatment plan accepted!' : 'Failed to accept plan'),
        backgroundColor: success ? AppTheme.safeGreen : AppTheme.riskRed,
        duration: const Duration(seconds: 2),
      ),
    );
    
    if (success) {
      await _loadAppointments();
    }
  }

  Future<void> _bookAppointment() async {
    final currentUser = _authService.getCurrentUser();
    final patientId = _authService.currentUserId ?? '';
    final patientName = (currentUser?['name'] ?? 'Patient').toString();

    DateTime selected = DateTime.now().add(const Duration(days: 1));
    final notesController = TextEditingController();
    int duration = 50;
    bool isVirtual = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.event_note,
                    color: Color(0xFF4FC3F7), size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Book Appointment',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Date & Time',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF4FC3F7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF4FC3F7).withValues(alpha: 0.3)),
                  ),
                  child: TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 180)),
                        initialDate: selected,
                      );
                      if (date == null) return;

                      final time = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(selected),
                      );
                      if (time == null) return;

                      setDialogState(() {
                        selected = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                    icon: const Icon(Icons.calendar_month,
                        color: Color(0xFF4FC3F7)),
                    label: Text(
                      DateFormat('EEEE, MMM dd, yyyy • h:mm a')
                          .format(selected),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Session Duration',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: DropdownButtonFormField<int>(
                    initialValue: duration,
                    dropdownColor: AppTheme.backgroundDark,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.timelapse,
                          color: Color(0xFF4FC3F7), size: 20),
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    items: const [30, 50, 60, 90]
                        .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('$d minutes',
                                style: const TextStyle(color: Colors.white))))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => duration = value);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: isVirtual
                        ? const Color(0xFF7E57C2).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isVirtual
                            ? const Color(0xFF7E57C2).withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: SwitchListTile(
                    value: isVirtual,
                    onChanged: (v) => setDialogState(() => isVirtual = v),
                    title: Row(
                      children: [
                        Icon(Icons.videocam,
                            color: isVirtual
                                ? const Color(0xFF7E57C2)
                                : Colors.white.withValues(alpha: 0.5),
                            size: 20),
                        const SizedBox(width: 8),
                        const Text('Virtual Session',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                      ],
                    ),
                    activeThumbColor: const Color(0xFF7E57C2),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Additional Notes',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText:
                        'Mention your preferred focus for this session...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                    filled: true,
                    fillColor: AppTheme.backgroundDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(0xFF4FC3F7), width: 2),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text('Cancel',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7), fontSize: 15)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              icon: const Icon(Icons.check_circle, size: 20),
              label: const Text('Confirm Booking',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final synced = await _backendApiService.bookSharedAppointment({
      'patientExternalId': patientId,
      'patientName': patientName,
      'therapistExternalId': 'therapist_main',
      'therapistName': 'Therapist',
      'scheduledAt': selected.toIso8601String(),
      'durationMinutes': duration,
      'type': 'followup',
      'notes': notesController.text.trim(),
      'isVirtual': isVirtual,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Appointment request sent to therapist dashboard.'
              : 'Booking failed. Ensure backend is reachable.',
        ),
        backgroundColor: synced ? AppTheme.safeGreen : AppTheme.riskRed,
      ),
    );

    await _loadAppointments();
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
              child: const Icon(Icons.calendar_month,
                  color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('My Appointments',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showTreatmentPlansSheet,
            icon: const Icon(Icons.assignment_rounded),
            tooltip: 'Treatment Plans',
          ),
          IconButton(
            onPressed: _loadAppointments,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                      color: AppTheme.primaryIndigo),
                  const SizedBox(height: 16),
                  Text('Loading appointments...',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
                ],
              ),
            )
          : _appointments.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyState(
                      emoji: '📅',
                      message: _backendApiService.isConfigured
                          ? (_treatmentPlans.isNotEmpty
                              ? 'You still have ${_treatmentPlans.length} treatment plan update(s).'
                              : 'No appointments scheduled\nBook your first appointment to get started')
                          : 'Backend not configured\nSet backend URL to enable booking sync',
                      action: _treatmentPlans.isNotEmpty
                          ? OutlinedButton.icon(
                              onPressed: _showTreatmentPlansSheet,
                              icon: const Icon(Icons.assignment_rounded),
                              label: const Text('View Treatment Plans'),
                            )
                          : null,
                    ),
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _appointments.length,
                  itemBuilder: (context, index) {
                    final item = _appointments[index];
                    final date = DateTime.tryParse(
                        (item['scheduled_at'] ?? '').toString());
                    final status = (item['status'] ?? 'scheduled').toString();
                    final statusColor = _getStatusColor(status);
                    final isPast = date?.isBefore(DateTime.now()) ?? false;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        Icons.medical_services_rounded,
                                        color: statusColor,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            date != null
                                                ? DateFormat(
                                                        'EEEE, MMM dd, yyyy')
                                                    .format(date)
                                                : 'Date not set',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.access_time_rounded,
                                                  size: 14,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6)),
                                              const SizedBox(width: 4),
                                              Text(
                                                date != null
                                                    ? DateFormat('h:mm a')
                                                        .format(date)
                                                    : 'Time not set',
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.7),
                                                  fontSize: 13,
                                                ),
                                              ),
                                              if (item['duration_minutes'] !=
                                                  null) ...[
                                                Text(' • ',
                                                    style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(alpha: 0.5))),
                                                Text(
                                                  '${item['duration_minutes']} min',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.7),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: statusColor, width: 1.5),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if ((item['is_virtual'] as num?)?.toInt() ==
                                    1) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryIndigo
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppTheme.primaryIndigo
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.videocam_rounded,
                                          size: 16,
                                          color: AppTheme.primaryIndigo,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Virtual Session',
                                          style: TextStyle(
                                            color: AppTheme.primaryIndigo,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if ((item['notes'] ?? '')
                                    .toString()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.note_alt_outlined,
                                          size: 16,
                                          color: Colors.white.withValues(alpha: 0.5),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            (item['notes'] ?? '').toString(),
                                            style: TextStyle(
                                              color:
                                                  Colors.white.withValues(alpha: 0.7),
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (isPast && status == 'scheduled') ...[
                                  const SizedBox(height: 12),
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 14,
                                        color: AppTheme.warningAmber,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Past appointment',
                                        style: TextStyle(
                                          color: AppTheme.warningAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        if ((item['patient_seen'] as num?)?.toInt() == 1)
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 14,
                                                  color: AppTheme.safeGreen),
                                              SizedBox(width: 4),
                                              Text('Seen',
                                                  style: TextStyle(
                                                    color: AppTheme.safeGreen,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  )),
                                            ],
                                          ),
                                        if ((item['patient_accepted'] as num?)?.toInt() == 1) ...[
                                          const SizedBox(width: 12),
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 14,
                                                  color: Color(0xFF66BB6A)),
                                              SizedBox(width: 4),
                                              Text('Accepted',
                                                  style: TextStyle(
                                                    color: Color(0xFF66BB6A),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  )),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                    if ((item['patient_accepted'] as num?)?.toInt() != 1 && !isPast)
                                      ElevatedButton.icon(
                                        onPressed: () => _markAppointmentAccepted(item['id'].toString()),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryIndigo,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: const Icon(Icons.check, size: 14),
                                        label: const Text(
                                          'Accept',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bookAppointment,
        backgroundColor: AppTheme.primaryIndigo,
        elevation: 4,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('Book Appointment',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showTreatmentPlansSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Treatment Plans From Therapist',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (_treatmentPlans.isEmpty)
                  Text(
                    'No treatment plans received yet.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _treatmentPlans.length,
                      itemBuilder: (context, index) {
                        final plan = _treatmentPlans[index];
                        final createdAt = DateTime.tryParse((plan['created_at'] ?? '').toString());
                        final goals = (plan['goals'] is List) ? (plan['goals'] as List) : const [];
                        return Card(
                          color: AppTheme.backgroundDark,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (plan['primary_diagnosis'] ?? 'Treatment Plan').toString(),
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryIndigo.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        (plan['status'] ?? 'active').toString().toUpperCase(),
                                        style: const TextStyle(
                                          color: AppTheme.primaryIndigo,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Approach: ${(plan['treatment_approach'] ?? 'Not specified').toString()}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                                ),
                                Text(
                                  'Frequency: ${(plan['session_frequency'] ?? 'Not specified').toString()}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                                ),
                                Text(
                                  'Goals: ${goals.length}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                                ),
                                if (createdAt != null)
                                  Text(
                                    'Sent: ${DateFormat('MMM dd, yyyy • h:mm a').format(createdAt)}',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        if ((plan['patient_seen'] as num?)?.toInt() == 1)
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 14,
                                                  color: AppTheme.safeGreen),
                                              SizedBox(width: 4),
                                              Text('Seen',
                                                  style: TextStyle(
                                                    color: AppTheme.safeGreen,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  )),
                                            ],
                                          ),
                                        if ((plan['patient_accepted'] as num?)?.toInt() == 1) ...[
                                          const SizedBox(width: 8),
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle,
                                                  size: 14,
                                                  color: Color(0xFF66BB6A)),
                                              SizedBox(width: 4),
                                              Text('Accepted',
                                                  style: TextStyle(
                                                    color: Color(0xFF66BB6A),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  )),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                    if ((plan['patient_accepted'] as num?)?.toInt() != 1)
                                      ElevatedButton.icon(
                                        onPressed: () => _markPlanAccepted(plan['id'].toString()),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryIndigo,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: const Icon(Icons.check, size: 14),
                                        label: const Text(
                                          'Accept',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
        return AppTheme.primaryIndigo;
      case 'completed':
        return AppTheme.safeGreen;
      case 'cancelled':
        return AppTheme.riskRed;
      case 'noshow':
        return AppTheme.warningAmber;
      default:
        return Colors.grey;
    }
  }
}
