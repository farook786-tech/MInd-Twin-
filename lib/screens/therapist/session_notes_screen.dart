import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../models/appointment_v2.dart';
import '../../models/patient.dart';
import '../../services/appointment_service.dart';
import '../patient/patient_appointments_screen.dart'
    show AppointmentStatusChip, formatAppointmentTime;
import 'appointments_screen.dart';

/// Private therapist notes, stored per session at
/// `appointments/{appointmentId}/notes/{noteId}` = {therapistId, text, createdAt}.
/// Notes are append-only (no edit/delete) to preserve the clinical record.
class SessionNotesScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  /// When set, only this session's notes are shown.
  final String? appointmentId;

  SessionNotesScreen({super.key, required Patient patient, this.appointmentId})
      : patientId = patient.id,
        patientName = patient.name;

  SessionNotesScreen.forAppointment({super.key, required AppointmentV2 appointment})
      : patientId = appointment.patientId,
        patientName = appointment.patientName,
        appointmentId = appointment.id;

  @override
  State<SessionNotesScreen> createState() => _SessionNotesScreenState();
}

class _SessionNotesScreenState extends State<SessionNotesScreen> {
  final AppointmentService _service = AppointmentService();
  String? _uid;
  Stream<List<AppointmentV2>>? _stream;

  @override
  void initState() {
    super.initState();
    _uid = _service.currentUid;
    final uid = _uid;
    if (uid != null && widget.patientId.isNotEmpty) {
      _stream = _service.watchForTherapist(uid, patientId: widget.patientId);
    }
  }

  void _openAppointments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentsScreen(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Session Notes'),
            Text(widget.patientName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: _stream == null
          ? Center(
              child: Text('Please sign in again.', style: TextStyle(color: AppColors.ink)),
            )
          : StreamBuilder<List<AppointmentV2>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load sessions.\n${AppointmentService.describeError(snap.error!)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.ink70),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final now = DateTime.now();
                final sessions = snap.data!
                    .where((a) => widget.appointmentId != null
                        ? a.id == widget.appointmentId
                        : (a.isScheduled ||
                            a.status == AppointmentStatus.completed ||
                            a.status == AppointmentStatus.noShow))
                    .toList()
                  ..sort((a, b) =>
                      (b.effectiveStart ?? now).compareTo(a.effectiveStart ?? now));

                if (sessions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: EmptyState(
                        emoji: '📝',
                        message: widget.appointmentId != null
                            ? 'This session is not available.'
                            : 'Notes are attached to sessions. Schedule a session with '
                                '${widget.patientName} to start taking notes.',
                        action: widget.appointmentId != null
                            ? null
                            : TextButton(
                                onPressed: _openAppointments,
                                child: const Text('Open appointments →'),
                              ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  itemBuilder: (context, i) => _SessionNotesCard(
                    key: ValueKey(sessions[i].id),
                    appointment: sessions[i],
                    service: _service,
                    initiallyExpanded: widget.appointmentId != null || i == 0,
                  ),
                );
              },
            ),
    );
  }
}

class _SessionNotesCard extends StatefulWidget {
  final AppointmentV2 appointment;
  final AppointmentService service;
  final bool initiallyExpanded;

  const _SessionNotesCard({
    super.key,
    required this.appointment,
    required this.service,
    required this.initiallyExpanded,
  });

  @override
  State<_SessionNotesCard> createState() => _SessionNotesCardState();
}

class _SessionNotesCardState extends State<_SessionNotesCard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notes =
      widget.service.watchNotes(widget.appointment.id);
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.service.addNote(widget.appointment.id, text);
      _controller.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Note saved.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(AppointmentService.describeError(e)),
        backgroundColor: AppTheme.riskRed,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    final when = a.effectiveStart;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          iconColor: AppColors.ink70,
          collapsedIconColor: AppColors.ink70,
          title: Text(
            when == null ? 'Session' : formatAppointmentTime(when),
            style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                AppointmentStatusChip(status: a.status),
                const SizedBox(width: 8),
                Text('${a.durationMinutes} min',
                    style: TextStyle(color: AppColors.ink60, fontSize: 12)),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: _controller,
              enabled: !_saving,
              minLines: 2,
              maxLines: 6,
              maxLength: 5000,
              style: TextStyle(color: AppColors.ink),
              decoration: InputDecoration(
                hintText: 'Add a private note (only you can see it)',
                hintStyle: TextStyle(color: AppColors.ink38),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: const Text('Save note'),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _notes,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(
                    'Could not load notes. ${AppointmentService.describeError(snap.error!)}',
                    style: TextStyle(color: AppTheme.riskRed),
                  );
                }
                if (!snap.hasData) {
                  return const LinearProgressIndicator();
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No notes for this session yet.',
                        style: TextStyle(color: AppColors.ink54)),
                  );
                }
                return Column(
                  children: docs.map((d) {
                    final data = d.data();
                    final ts = data['createdAt'];
                    final created = ts is Timestamp ? ts.toDate() : null;
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            created == null ? 'Saving…' : formatAppointmentTime(created),
                            style: TextStyle(color: AppColors.ink54, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            (data['text'] ?? '').toString(),
                            style: TextStyle(color: AppColors.ink),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
