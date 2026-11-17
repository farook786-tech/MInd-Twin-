import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../models/appointment_v2.dart';
import '../../services/appointment_service.dart';
import '../patient/patient_appointments_screen.dart'
    show
        AppointmentJoinButton,
        AppointmentStatusChip,
        formatAppointmentTime,
        localTimeZoneHint,
        nextSuggestedSlot,
        pickAppointmentDateTime,
        showAppointmentReasonDialog;
import 'session_notes_screen.dart';

/// Therapist appointment hub: live requests (with badge), upcoming sessions,
/// history. Backed solely by Firestore `appointments` via [AppointmentService].
///
/// Usable with no arguments (tab / push-notification routing). When
/// [patientId] is given, the list is limited to that patient and "New session"
/// pre-selects them.
class AppointmentsScreen extends StatefulWidget {
  final String? patientId;
  final String? patientName;

  const AppointmentsScreen({super.key, this.patientId, this.patientName});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final AppointmentService _service = AppointmentService();

  String? _uid;
  Stream<List<AppointmentV2>>? _stream;
  Timer? _ticker;
  final Set<String> _busy = <String>{};

  bool get _filtered => (widget.patientId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _uid = _service.currentUid;
    final uid = _uid;
    if (uid != null) {
      _stream = _service.watchForTherapist(uid, patientId: widget.patientId);
    }
    // Re-classify sessions (upcoming -> awaiting outcome) as time passes.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppTheme.riskRed : null),
    );
  }

  Future<void> _showBlocking(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        title: Text(title, style: TextStyle(color: AppColors.ink)),
        content: Text(message, style: TextStyle(color: AppColors.ink70)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _run(String id, Future<void> Function() op, String success) async {
    setState(() => _busy.add(id));
    try {
      await op();
      _snack(success);
    } catch (e) {
      final msg = AppointmentService.describeError(e);
      if (e is AppointmentConflictException) {
        await _showBlocking('Time slot unavailable', msg);
      } else {
        _snack(msg, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _accept(AppointmentV2 a) async {
    final minStart = DateTime.now().add(AppointmentService.minLeadTime);
    final proposedUsable = a.proposedAt != null && a.proposedAt!.isAfter(minStart);

    DateTime? chosen;
    if (proposedUsable) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          title: Text('Accept request', style: TextStyle(color: AppColors.ink)),
          content: Text(
            '${a.patientName} proposed ${formatAppointmentTime(a.proposedAt!)} '
            '(${a.durationMinutes} min, ${a.isVirtual ? 'online' : 'in person'}).',
            style: TextStyle(color: AppColors.ink70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'pick'),
              child: const Text('Choose another time'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'proposed'),
              child: const Text('Accept proposed time'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      chosen = choice == 'proposed'
          ? a.proposedAt
          : await pickAppointmentDateTime(context, a.proposedAt!);
    } else {
      chosen = await pickAppointmentDateTime(context, nextSuggestedSlot());
    }
    if (chosen == null || !mounted) return;
    if (!chosen.isAfter(minStart)) {
      await _showBlocking('Time in the past', 'Please choose a time in the future.');
      return;
    }
    final at = chosen;
    await _run(a.id, () => _service.accept(a, at), 'Session scheduled for ${formatAppointmentTime(at)}.');
  }

  Future<void> _decline(AppointmentV2 a) async {
    final reason = await showAppointmentReasonDialog(
      context,
      title: 'Decline request?',
      hint: 'Reason shown to the patient',
      confirmLabel: 'Decline',
      required: true,
    );
    if (reason == null || !mounted) return;
    await _run(a.id, () => _service.decline(a, reason), 'Request declined.');
  }

  Future<void> _cancel(AppointmentV2 a) async {
    final reason = await showAppointmentReasonDialog(
      context,
      title: 'Cancel session?',
      hint: 'Reason shown to the patient (optional)',
      confirmLabel: 'Cancel session',
    );
    if (reason == null || !mounted) return;
    await _run(a.id, () => _service.cancel(a, byRole: 'therapist', reason: reason),
        'Session cancelled.');
  }

  Future<void> _outcome(AppointmentV2 a, String outcome) async {
    await _run(
      a.id,
      () => _service.markOutcome(a, outcome),
      outcome == AppointmentStatus.completed ? 'Marked as completed.' : 'Marked as no-show.',
    );
  }

  void _openNotes(AppointmentV2 a) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SessionNotesScreen.forAppointment(appointment: a)),
    );
  }

  Future<void> _newSession() async {
    final uid = _uid;
    if (uid == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NewSessionSheet(
        service: _service,
        therapistId: uid,
        initialPatientId: widget.patientId,
        initialPatientName: widget.patientName,
      ),
    );
    if (created == true) _snack('Session scheduled. The patient has been notified.');
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final title = _filtered ? 'Sessions • ${widget.patientName ?? 'Patient'}' : 'Appointments';
    if (uid == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(backgroundColor: AppTheme.cardDark, title: Text(title)),
        body: Center(
          child: Text('Please sign in again.', style: TextStyle(color: AppColors.ink)),
        ),
      );
    }

    return StreamBuilder<List<AppointmentV2>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? const <AppointmentV2>[];
        final now = DateTime.now();
        final requests = all.where((a) => a.isRequested).toList()
          ..sort((a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now));
        final upcoming = all.where((a) => a.isScheduled).toList()
          ..sort((a, b) => (a.scheduledAt ?? now).compareTo(b.scheduledAt ?? now));
        final history = all.where((a) => a.isTerminal).toList()
          ..sort((a, b) {
            final at = a.effectiveStart ?? a.updatedAt ?? now;
            final bt = b.effectiveStart ?? b.updatedAt ?? now;
            return bt.compareTo(at);
          });

        Widget body;
        if (snap.hasError) {
          body = _message('Could not load appointments.\n'
              '${AppointmentService.describeError(snap.error!)}');
        } else if (!snap.hasData) {
          body = const Center(child: CircularProgressIndicator());
        } else {
          body = TabBarView(
            children: [
              _list(requests, 'No pending requests.'),
              _list(upcoming, 'No upcoming sessions. Tap "New session" to book one.'),
              _list(history, 'No past sessions yet.'),
            ],
          );
        }

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: AppTheme.backgroundDark,
            appBar: AppBar(
              backgroundColor: AppTheme.cardDark,
              title: Text(title),
              bottom: TabBar(
                tabs: [
                  Tab(
                    child: Badge(
                      isLabelVisible: requests.isNotEmpty,
                      label: Text('${requests.length}'),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Text('Requests'),
                      ),
                    ),
                  ),
                  const Tab(text: 'Upcoming'),
                  const Tab(text: 'History'),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _newSession,
              backgroundColor: AppTheme.primaryIndigo,
              icon: const Icon(Icons.add),
              label: const Text('New session'),
            ),
            body: body,
          ),
        );
      },
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink70)),
        ),
      );

  Widget _list(List<AppointmentV2> items, String empty) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(localTimeZoneHint(), style: TextStyle(color: AppColors.ink38, fontSize: 12)),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(message: empty, emoji: '📅'),
          )
        else
          ...items.map(_card),
      ],
    );
  }

  Widget _card(AppointmentV2 a) {
    final now = DateTime.now();
    final busy = _busy.contains(a.id);
    final whenLabel = a.scheduledAt != null
        ? formatAppointmentTime(a.scheduledAt!)
        : a.proposedAt != null
            ? 'Proposed: ${formatAppointmentTime(a.proposedAt!)}'
            : 'Time not set';
    final proposedPast = a.isRequested && a.proposedAt != null && a.proposedAt!.isBefore(now);

    final actions = <Widget>[];
    if (a.isRequested) {
      actions.addAll([
        TextButton(
          onPressed: () => _decline(a),
          child: Text('Decline', style: TextStyle(color: AppTheme.riskRed)),
        ),
        ElevatedButton(
          onPressed: () => _accept(a),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.safeGreen, foregroundColor: AppColors.ink),
          child: const Text('Accept'),
        ),
      ]);
    } else if (a.isScheduled) {
      actions.add(TextButton(onPressed: () => _openNotes(a), child: const Text('Notes')));
      if (a.hasStarted(now)) {
        actions.addAll([
          TextButton(
            onPressed: () => _outcome(a, AppointmentStatus.noShow),
            child: Text('No-show', style: TextStyle(color: AppTheme.warningAmber)),
          ),
          ElevatedButton(
            onPressed: () => _outcome(a, AppointmentStatus.completed),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.safeGreen, foregroundColor: AppColors.ink),
            child: const Text('Completed'),
          ),
        ]);
      }
      if (a.canCancel) {
        actions.add(TextButton(
          onPressed: () => _cancel(a),
          child: Text('Cancel', style: TextStyle(color: AppTheme.riskRed)),
        ));
      }
    } else if (a.status == AppointmentStatus.completed || a.status == AppointmentStatus.noShow) {
      actions.add(TextButton(onPressed: () => _openNotes(a), child: const Text('Notes')));
    }

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(a.isVirtual ? Icons.videocam : Icons.location_on, color: AppColors.ink70, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(a.patientName,
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              AppointmentStatusChip(status: a.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(whenLabel, style: TextStyle(color: AppColors.ink, fontSize: 14)),
          if (proposedPast)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Proposed time has passed — choose a new time when accepting.',
                  style: TextStyle(color: AppTheme.warningAmber, fontSize: 12)),
            ),
          const SizedBox(height: 4),
          Text(
            '${a.durationMinutes} min • ${a.isVirtual ? 'Online' : 'In person'} • '
            '${a.requestedBy == 'patient' ? 'Requested by patient' : 'Booked by you'}'
            '${a.hasPendingWrites ? ' • syncing…' : ''}',
            style: TextStyle(color: AppColors.ink60, fontSize: 12),
          ),
          if (a.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason: ${a.reason}', style: TextStyle(color: AppColors.ink70)),
          ],
          if (a.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.notes, style: TextStyle(color: AppColors.ink60, fontSize: 13)),
          ],
          if (a.status == AppointmentStatus.cancelled && a.cancelledBy != null) ...[
            const SizedBox(height: 6),
            Text(a.cancelledBy == 'therapist' ? 'Cancelled by you' : 'Cancelled by patient',
                style: TextStyle(color: AppColors.ink60, fontSize: 12)),
          ],
          if (a.needsOutcome(now))
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Session ended — please record the outcome.',
                  style: TextStyle(color: AppTheme.warningAmber, fontSize: 12)),
            ),
          if (a.isScheduled && a.isVirtual) ...[
            const SizedBox(height: 12),
            AppointmentJoinButton(appointment: a),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            busy
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                : Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
          ],
        ],
      ),
    );
  }
}

class _NewSessionSheet extends StatefulWidget {
  final AppointmentService service;
  final String therapistId;
  final String? initialPatientId;
  final String? initialPatientName;

  const _NewSessionSheet({
    required this.service,
    required this.therapistId,
    this.initialPatientId,
    this.initialPatientName,
  });

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  final TextEditingController _reason = TextEditingController();
  late final Stream<List<LinkedPatient>> _patients;
  String? _patientId;
  String? _patientName;
  DateTime _start = nextSuggestedSlot();
  int _duration = 45;
  bool _virtual = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _patients = widget.service.watchLinkedPatients(widget.therapistId);
    _patientId = widget.initialPatientId;
    _patientName = widget.initialPatientName;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await pickAppointmentDateTime(context, _start);
    if (picked == null || !mounted) return;
    setState(() {
      _start = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final pid = _patientId;
    if (pid == null || pid.isEmpty) {
      setState(() => _error = 'Select a patient.');
      return;
    }
    if (!_start.isAfter(DateTime.now().add(AppointmentService.minLeadTime))) {
      setState(() => _error = 'Please choose a time in the future.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.service.createScheduled(
        patientId: pid,
        patientName: _patientName ?? 'Patient',
        scheduledAt: _start,
        durationMinutes: _duration,
        isVirtual: _virtual,
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = AppointmentService.describeError(e);
      });
    }
  }

  Widget _patientPicker() {
    return StreamBuilder<List<LinkedPatient>>(
      stream: _patients,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Could not load your patients. ${AppointmentService.describeError(snap.error!)}',
              style: TextStyle(color: AppTheme.riskRed));
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          );
        }
        final patients = snap.data!;
        if (patients.isEmpty) {
          return Text(
            'No linked patients yet. Share your invite code so patients can join you.',
            style: TextStyle(color: AppColors.ink70),
          );
        }
        final selected = patients.any((p) => p.id == _patientId) ? _patientId : null;
        return DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          dropdownColor: AppTheme.cardDark,
          style: TextStyle(color: AppColors.ink),
          decoration: InputDecoration(
            labelText: 'Patient',
            labelStyle: TextStyle(color: AppColors.ink70),
          ),
          items: patients
              .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
              .toList(),
          onChanged: _submitting
              ? null
              : (id) {
                  final p = patients.firstWhere((x) => x.id == id);
                  setState(() {
                    _patientId = p.id;
                    _patientName = p.name;
                  });
                },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New session',
                style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _patientPicker(),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule, color: AppColors.ink70),
              title: Text('Start time', style: TextStyle(color: AppColors.ink70)),
              subtitle: Text(formatAppointmentTime(_start), style: TextStyle(color: AppColors.ink)),
              trailing: Icon(Icons.edit, color: AppColors.ink54),
              onTap: _submitting ? null : _pickTime,
            ),
            Text(localTimeZoneHint(), style: TextStyle(color: AppColors.ink38, fontSize: 11)),
            const SizedBox(height: 12),
            Text('Duration', style: TextStyle(color: AppColors.ink70)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: kAppointmentDurations
                  .map((d) => ChoiceChip(
                        label: Text('$d min'),
                        selected: _duration == d,
                        onSelected: _submitting ? null : (_) => setState(() => _duration = d),
                      ))
                  .toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _virtual,
              onChanged: _submitting ? null : (v) => setState(() => _virtual = v),
              title: Text(_virtual ? 'Online (video)' : 'In person',
                  style: TextStyle(color: AppColors.ink)),
            ),
            TextField(
              controller: _reason,
              enabled: !_submitting,
              maxLength: 300,
              style: TextStyle(color: AppColors.ink),
              decoration: InputDecoration(
                labelText: 'Purpose (optional, visible to patient)',
                labelStyle: TextStyle(color: AppColors.ink70),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: AppTheme.riskRed)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryIndigo,
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Schedule session'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
