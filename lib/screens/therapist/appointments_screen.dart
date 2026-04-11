import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../models/appointment.dart';
import '../../models/patient.dart';
import '../../services/backend_api_service.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final DatabaseService _dbService = DatabaseService();
  final AuthService _authService = AuthService();
  final BackendApiService _backendApiService = BackendApiService();
  List<Appointment> _appointments = [];
  List<Patient> _patients = [];
  bool _isLoading = true;
  String _filterStatus = 'all'; // all, scheduled, completed, cancelled

  String _normalizeStatus(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized == 'complete') return 'completed';
    if (normalized == 'canceled') return 'cancelled';
    if (normalized == 'no_show' || normalized == 'no-show') return 'noshow';
    if (normalized.isEmpty) return 'scheduled';
    return normalized;
  }

  String _statusLabel(String rawStatus) {
    switch (_normalizeStatus(rawStatus)) {
      case 'scheduled':
        return 'Scheduled';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'noshow':
        return 'No Show';
      default:
        return rawStatus;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final therapistId = _authService.currentUserId ?? '';
      final localAppointments =
          await _dbService.getAppointments(therapistId, isTherapist: true);
      final patients = await _dbService.getAllPatients();

      final remoteRows = await _backendApiService.fetchSharedAppointments();
      final remoteAppointments = remoteRows.map((row) {
        final rawScheduled =
            (row['scheduled_at'] ?? DateTime.now().toIso8601String())
                .toString();
        return Appointment(
          id: (row['id'] ?? const Uuid().v4()).toString(),
          patientId: (row['patient_external_id'] ?? '').toString(),
          patientName: (row['patient_name'] ?? 'Patient').toString(),
          therapistId:
              (row['therapist_external_id'] ?? 'therapist_main').toString(),
          therapistName: (row['therapist_name'] ?? 'Therapist').toString(),
          scheduledAt: DateTime.tryParse(rawScheduled) ?? DateTime.now(),
          durationMinutes: (row['duration_minutes'] as num?)?.toInt() ?? 50,
          type: (row['type'] ?? 'followup').toString(),
          status: _normalizeStatus((row['status'] ?? 'scheduled').toString()),
          notes: row['notes']?.toString(),
          isVirtual: ((row['is_virtual'] as num?)?.toInt() ?? 0) == 1,
          createdAt: DateTime.tryParse(
                  (row['created_at'] ?? DateTime.now().toIso8601String())
                      .toString()) ??
              DateTime.now(),
        );
      }).toList();

      final merged = <String, Appointment>{
        for (final a in localAppointments) a.id: a,
      };
      for (final a in remoteAppointments) {
        final existing = merged[a.id];
        if (existing == null) {
          merged[a.id] = a;
          continue;
        }

        final localStatus = _normalizeStatus(existing.status);
        final remoteStatus = _normalizeStatus(a.status);
        final shouldPreserveLocal =
            (localStatus == 'completed' ||
                localStatus == 'cancelled' ||
                localStatus == 'noshow') &&
            remoteStatus == 'scheduled';

        merged[a.id] = shouldPreserveLocal ? existing : a;
      }

      final appointments = merged.values.toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      setState(() {
        _appointments = appointments;
        _patients = patients;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading appointments: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Appointment> get _filteredAppointments {
    if (_filterStatus == 'all') return _appointments;
    return _appointments
        .where((a) => _normalizeStatus(a.status) == _filterStatus)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              child: const Icon(Icons.calendar_month_rounded,
                  color: AppTheme.primaryIndigo, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('Appointments',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter chips
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppTheme.backgroundDark,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('All', 'all'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Scheduled', 'scheduled'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Completed', 'completed'),
                        const SizedBox(width: 8),
                        _buildFilterChip('Cancelled', 'cancelled'),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      Text(
                        '${_filteredAppointments.length} appointment(s)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Filter: ${_filterStatus == 'all' ? 'All' : _statusLabel(_filterStatus)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Appointments list
                Expanded(
                  child: _filteredAppointments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF5C6BC0).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.event_busy_rounded,
                                    size: 64,
                                    color: const Color(0xFF5C6BC0)
                                        .withValues(alpha: 0.5)),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'No appointments found',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Schedule a new appointment below',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredAppointments.length,
                          itemBuilder: (context, index) {
                            final appointment = _filteredAppointments[index];
                            return _buildAppointmentCard(appointment);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateAppointmentDialog,
        backgroundColor: const Color(0xFF5C6BC0),
        elevation: 4,
        icon: const Icon(Icons.add_circle_outline, size: 24),
        label: const Text('New Appointment',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryIndigo : AppTheme.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryIndigo
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentCard(Appointment appointment) {
    final isPast = appointment.scheduledAt.isBefore(DateTime.now());
    final normalizedStatus = _normalizeStatus(appointment.status);
    final statusColor = _getStatusColor(normalizedStatus);
    final typeIcon = _getTypeIcon(appointment.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
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
          onTap: () => _showAppointmentDetailsDialog(appointment),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        typeIcon,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.patientName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatAppointmentType(appointment.type),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13,
                            ),
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
                        border: Border.all(color: statusColor, width: 1.5),
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
                            _statusLabel(normalizedStatus).toUpperCase(),
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
                const SizedBox(height: 12),

                // Date and time
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 16, color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, MMM dd, yyyy • h:mm a')
                              .format(appointment.scheduledAt),
                          style: TextStyle(
                            color: isPast
                                ? AppTheme.warningAmber
                                : Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.timer_rounded,
                          size: 16, color: Colors.white.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(
                        '${appointment.durationMinutes} min',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Virtual indicator
                if (appointment.isVirtual) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primaryIndigo.withValues(alpha: 0.3),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Notes preview
                if (appointment.notes != null &&
                    appointment.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    appointment.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                if (normalizedStatus == 'scheduled') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _markAppointmentCancelled(appointment),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.riskRed,
                            side: BorderSide(
                              color: AppTheme.riskRed.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _markAppointmentComplete(appointment),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Mark Complete'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.safeGreen,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateAppointmentDialog() {
    final currentUser = _authService.getCurrentUser();
    final therapistName = (currentUser?['name'] ?? 'Therapist').toString();
    showDialog(
      context: context,
      builder: (context) => _AppointmentFormDialog(
        patients: _patients,
        therapistId: _authService.currentUserId ?? '',
        therapistName: therapistName,
        onSave: (appointment) async {
          await _dbService.insertAppointment(appointment);
          _loadData();
        },
      ),
    );
  }

  void _showAppointmentDetailsDialog(Appointment appointment) {
    showDialog(
      context: context,
      builder: (context) => _AppointmentDetailsDialog(
        appointment: appointment,
        onUpdate: (updated) async {
          await _dbService.updateAppointment(updated);
          _loadData();
        },
        onDelete: () async {
          await _dbService.deleteAppointment(appointment.id);
          _loadData();
        },
      ),
    );
  }

  Future<void> _markAppointmentComplete(Appointment appointment) async {
    final updated = appointment.copyWith(
      status: 'completed',
      completedAt: DateTime.now(),
    );
    await _dbService.updateAppointment(updated);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appointment marked as completed.')),
    );
  }

  Future<void> _markAppointmentCancelled(Appointment appointment) async {
    final updated = appointment.copyWith(status: 'cancelled');
    await _dbService.updateAppointment(updated);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appointment marked as cancelled.')),
    );
  }

  Color _getStatusColor(String status) {
    switch (_normalizeStatus(status)) {
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

  String _getTypeIcon(String type) {
    switch (type) {
      case 'individual':
        return '👤';
      case 'group':
        return '👥';
      case 'initial':
        return '🆕';
      case 'followup':
        return '🔄';
      default:
        return '📋';
    }
  }

  String _formatAppointmentType(String type) {
    switch (type) {
      case 'individual':
        return 'Individual Therapy';
      case 'group':
        return 'Group Therapy';
      case 'initial':
        return 'Initial Consultation';
      case 'followup':
        return 'Follow-up Session';
      default:
        return type;
    }
  }
}

// Dialog for creating appointments
class _AppointmentFormDialog extends StatefulWidget {
  final List<Patient> patients;
  final String therapistId;
  final String therapistName;
  final Function(Appointment) onSave;

  const _AppointmentFormDialog({
    required this.patients,
    required this.therapistId,
    required this.therapistName,
    required this.onSave,
  });

  @override
  State<_AppointmentFormDialog> createState() => _AppointmentFormDialogState();
}

class _AppointmentFormDialogState extends State<_AppointmentFormDialog> {
  Patient? _selectedPatient;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _selectedType = 'individual';
  int _durationMinutes = 50;
  bool _isVirtual = false;
  final _notesController = TextEditingController();
  final _meetingLinkController = TextEditingController();
  final BackendApiService _backendApiService = BackendApiService();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardDark,
      title: const Text('Schedule Appointment',
          style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Patient selection
              const Text('Select Patient',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              DropdownButtonFormField<Patient>(
                initialValue: _selectedPatient,
                dropdownColor: AppTheme.backgroundDark,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.backgroundDark,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: widget.patients.map((patient) {
                  return DropdownMenuItem<Patient>(
                    value: patient,
                    child: Text(patient.name,
                        style: const TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (patient) =>
                    setState(() => _selectedPatient = patient),
              ),
              const SizedBox(height: 16),

              // Appointment type
              const Text('Appointment Type',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                dropdownColor: AppTheme.backgroundDark,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.backgroundDark,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'individual',
                      child: Text('👤 Individual Therapy',
                          style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(
                      value: 'group',
                      child: Text('👥 Group Therapy',
                          style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(
                      value: 'initial',
                      child: Text('🆕 Initial Consultation',
                          style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(
                      value: 'followup',
                      child: Text('🔄 Follow-up Session',
                          style: TextStyle(color: Colors.white))),
                ],
                onChanged: (type) => setState(() => _selectedType = type!),
              ),
              const SizedBox(height: 16),

              // Date and time
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Date',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              setState(() => _selectedDate = date);
                            }
                          },
                          icon: const Icon(Icons.calendar_today),
                          label:
                              Text(DateFormat('MMM dd').format(_selectedDate)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.backgroundDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Time',
                            style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: _selectedTime,
                            );
                            if (time != null) {
                              setState(() => _selectedTime = time);
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: Text(_selectedTime.format(context)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.backgroundDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Duration
              const Text('Duration (minutes)',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildDurationChip(30),
                  const SizedBox(width: 8),
                  _buildDurationChip(50),
                  const SizedBox(width: 8),
                  _buildDurationChip(60),
                  const SizedBox(width: 8),
                  _buildDurationChip(90),
                ],
              ),
              const SizedBox(height: 16),

              // Virtual checkbox
              CheckboxListTile(
                value: _isVirtual,
                onChanged: (value) =>
                    setState(() => _isVirtual = value ?? false),
                title: const Text('Virtual Session',
                    style: TextStyle(color: Colors.white)),
                activeColor: AppTheme.primaryIndigo,
                tileColor: AppTheme.backgroundDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),

              // Meeting link (if virtual)
              if (_isVirtual) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _meetingLinkController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Meeting Link',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: AppTheme.backgroundDark,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Notes
              TextField(
                controller: _notesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: AppTheme.backgroundDark,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => _saveAppointment(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryIndigo,
          ),
          child: const Text('Schedule'),
        ),
      ],
    );
  }

  Widget _buildDurationChip(int minutes) {
    final isSelected = _durationMinutes == minutes;
    return GestureDetector(
      onTap: () => setState(() => _durationMinutes = minutes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryIndigo : AppTheme.backgroundDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryIndigo
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          '$minutes',
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _saveAppointment() async {
    if (_selectedPatient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a patient')),
      );
      return;
    }

    final scheduledAt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final appointment = Appointment(
      id: const Uuid().v4(),
      patientId: _selectedPatient!.id,
      patientName: _selectedPatient!.name,
      therapistId: widget.therapistId,
      therapistName: widget.therapistName,
      scheduledAt: scheduledAt,
      durationMinutes: _durationMinutes,
      type: _selectedType,
      status: 'scheduled',
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      meetingLink: _isVirtual && _meetingLinkController.text.trim().isNotEmpty
          ? _meetingLinkController.text.trim()
          : null,
      isVirtual: _isVirtual,
      createdAt: DateTime.now(),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Send Appointment To Patient?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Send this appointment to ${appointment.patientName} now?\n\n${DateFormat('EEE, MMM dd • h:mm a').format(appointment.scheduledAt)}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Local Only'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryIndigo),
            child: const Text('Confirm & Send'),
          ),
        ],
      ),
    );

    widget.onSave(appointment);
    if (!mounted) return;
    Navigator.pop(context);

    if (confirmed == true) {
      final synced = await _backendApiService.bookSharedAppointment({
        'id': appointment.id,
        'patientExternalId': appointment.patientId,
        'patientName': appointment.patientName,
        'therapistExternalId': appointment.therapistId,
        'therapistName': appointment.therapistName,
        'scheduledAt': appointment.scheduledAt.toIso8601String(),
        'durationMinutes': appointment.durationMinutes,
        'type': appointment.type,
        'notes': appointment.notes,
        'isVirtual': appointment.isVirtual,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Appointment sent to patient app.'
                : 'Appointment saved locally. Sending to patient failed.',
          ),
          backgroundColor: synced ? AppTheme.safeGreen : AppTheme.warningAmber,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment saved locally only.')),
      );
    }
  }
}

// Dialog for viewing and editing appointment details
class _AppointmentDetailsDialog extends StatelessWidget {
  final Appointment appointment;
  final Function(Appointment) onUpdate;
  final VoidCallback onDelete;

  const _AppointmentDetailsDialog({
    required this.appointment,
    required this.onUpdate,
    required this.onDelete,
  });

  String _statusLabel(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'scheduled':
        return 'Scheduled';
      case 'completed':
      case 'complete':
        return 'Completed';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      case 'noshow':
      case 'no_show':
      case 'no-show':
        return 'No Show';
      default:
        return rawStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardDark,
      title: Row(
        children: [
          const Text('Appointment Details',
              style: TextStyle(color: Colors.white)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoRow('Patient', appointment.patientName, Icons.person),
            _buildInfoRow(
                'Type', _formatType(appointment.type), Icons.category),
            _buildInfoRow(
                'Date',
                DateFormat('MMM dd, yyyy').format(appointment.scheduledAt),
                Icons.calendar_today),
            _buildInfoRow(
                'Time',
                DateFormat('h:mm a').format(appointment.scheduledAt),
                Icons.access_time),
            _buildInfoRow('Duration', '${appointment.durationMinutes} minutes',
                Icons.timer),
            _buildInfoRow(
              'Status', _statusLabel(appointment.status), Icons.info),
            if (appointment.isVirtual)
              _buildInfoRow('Virtual', 'Yes', Icons.videocam),
            if (appointment.meetingLink != null)
              _buildInfoRow('Link', appointment.meetingLink!, Icons.link),
            if (appointment.notes != null) ...[
              const SizedBox(height: 12),
              const Text('Notes:',
                  style: TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(appointment.notes!,
                  style: const TextStyle(color: Colors.white)),
            ],
          ],
        ),
      ),
      actions: [
        if (appointment.status == 'scheduled') ...[
          TextButton(
            onPressed: () {
              final updated = appointment.copyWith(status: 'cancelled');
              Navigator.pop(context);
              onUpdate(updated);
            },
            child: const Text('Cancel Appointment',
                style: TextStyle(color: Colors.orange)),
          ),
          ElevatedButton(
            onPressed: () {
              final updated = appointment.copyWith(
                  status: 'completed', completedAt: DateTime.now());
              Navigator.pop(context);
              onUpdate(updated);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.safeGreen),
            child: const Text('Mark Complete'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryIndigo),
          const SizedBox(width: 12),
          Text('$label:',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatType(String type) {
    switch (type) {
      case 'individual':
        return 'Individual Therapy';
      case 'group':
        return 'Group Therapy';
      case 'initial':
        return 'Initial Consultation';
      case 'followup':
        return 'Follow-up Session';
      default:
        return type;
    }
  }
}
