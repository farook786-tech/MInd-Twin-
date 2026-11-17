import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../models/appointment_v2.dart';
import '../../services/appointment_service.dart';

// =============================================================================
// Shared appointment UI helpers (also used by the therapist AppointmentsScreen,
// SessionNotesScreen and PatientHomeScreen).
// =============================================================================

/// Formats an absolute instant in the device's local time zone.
String formatAppointmentTime(DateTime instant) =>
    DateFormat('EEE d MMM y, h:mm a').format(instant.toLocal());

String formatAppointmentTimeShort(DateTime instant) =>
    DateFormat('h:mm a').format(instant.toLocal());

/// "Times shown in your local time (IST, UTC+05:30)".
String localTimeZoneHint() {
  final now = DateTime.now();
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final hh = abs.inHours.toString().padLeft(2, '0');
  final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
  return 'Times shown in your local time (${now.timeZoneName}, UTC$sign$hh:$mm)';
}

Color appointmentStatusColor(String status) {
  switch (status) {
    case AppointmentStatus.requested:
      return AppTheme.warningAmber;
    case AppointmentStatus.scheduled:
      return AppTheme.primaryIndigo;
    case AppointmentStatus.completed:
      return AppTheme.safeGreen;
    case AppointmentStatus.declined:
    case AppointmentStatus.cancelled:
    case AppointmentStatus.noShow:
      return AppTheme.riskRed;
    default:
      return Colors.grey;
  }
}

class AppointmentStatusChip extends StatelessWidget {
  final String status;
  const AppointmentStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = appointmentStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        AppointmentStatus.label(status),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Opens the meeting link in an external app (browser / Jitsi app).
Future<void> launchMeetingUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') {
    messenger.showSnackBar(
      const SnackBar(content: Text('The session link is invalid. Please contact your therapist.')),
    );
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the session. Install a web browser and try again.')),
      );
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not open the session. Please try again.')),
    );
  }
}

/// Shows "Join session" / "Link being prepared…" / "Join opens at …" for a
/// virtual scheduled session. Re-evaluates the time window every 15 s.
class AppointmentJoinButton extends StatefulWidget {
  final AppointmentV2 appointment;
  const AppointmentJoinButton({super.key, required this.appointment});

  @override
  State<AppointmentJoinButton> createState() => _AppointmentJoinButtonState();
}

class _AppointmentJoinButtonState extends State<AppointmentJoinButton> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    if (!a.isVirtual || !a.isScheduled || a.scheduledAt == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    if (a.canJoin(now)) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => launchMeetingUrl(context, a.meetingUrl!),
          icon: const Icon(Icons.videocam),
          label: const Text('Join session'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.safeGreen,
            foregroundColor: AppColors.ink,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }
    if (a.isLinkPending(now)) {
      return const _InfoLine(icon: Icons.hourglass_top, text: 'Link being prepared…');
    }
    if (now.isBefore(a.scheduledAt!)) {
      final opens = a.scheduledAt!.subtract(kJoinWindowLead);
      final text = a.meetingUrl == null
          ? 'Link being prepared… Join opens at ${formatAppointmentTimeShort(opens)}'
          : 'Join opens at ${formatAppointmentTimeShort(opens)}';
      return _InfoLine(icon: Icons.videocam_outlined, text: text);
    }
    return const SizedBox.shrink();
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.ink70),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: AppColors.ink70, fontSize: 13)),
        ),
      ],
    );
  }
}

/// Picks a local date + time. Returns null if cancelled. Dates before today
/// cannot be chosen; callers still validate the full instant.
Future<DateTime?> pickAppointmentDateTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final initLocal = initial.toLocal();
  final initDate = initLocal.isBefore(today) ? today : initLocal;
  final date = await showDatePicker(
    context: context,
    initialDate: initDate,
    firstDate: today,
    lastDate: today.add(const Duration(days: 180)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initLocal),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// A round hour at least [lead] from now, in local time.
DateTime nextSuggestedSlot({Duration lead = const Duration(hours: 1)}) {
  final t = DateTime.now().add(lead);
  return DateTime(t.year, t.month, t.day, t.hour).add(const Duration(hours: 1));
}

/// Asks for a free-text reason. Returns null when dismissed; '' is possible
/// only when [required] is false.
Future<String?> showAppointmentReasonDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  bool required = false,
  bool destructive = true,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      hint: hint,
      confirmLabel: confirmLabel,
      required: required,
      destructive: destructive,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String confirmLabel;
  final bool required;
  final bool destructive;
  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.required,
    required this.destructive,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardDark,
      title: Text(widget.title, style: TextStyle(color: AppColors.ink)),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        maxLength: 300,
        style: TextStyle(color: AppColors.ink),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: AppColors.ink38),
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.destructive ? AppTheme.riskRed : AppTheme.primaryIndigo,
            foregroundColor: AppColors.ink,
          ),
          onPressed: () {
            final text = _controller.text.trim();
            if (widget.required && text.isEmpty) {
              setState(() => _error = 'Please enter a reason');
              return;
            }
            Navigator.pop(context, text);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// =============================================================================
// Patient appointments screen
// =============================================================================

class PatientAppointmentsScreen extends StatefulWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  State<PatientAppointmentsScreen> createState() => _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState extends State<PatientAppointmentsScreen> {
  final AppointmentService _service = AppointmentService();

  String? _uid;
  Stream<List<AppointmentV2>>? _appointmentsStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _uid = _service.currentUid;
    final uid = _uid;
    if (uid != null) {
      _appointmentsStream = _service.watchForPatient(uid);
      _userStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.riskRed : null,
      ),
    );
  }

  Future<void> _openRequestSheet(bool linked) async {
    if (!linked) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardDark,
          title: Text('No therapist yet', style: TextStyle(color: AppColors.ink)),
          content: Text(
            'You need to be linked to a therapist before you can request a session. '
            'Ask your therapist for their invite code and join them from your profile.',
            style: TextStyle(color: AppColors.ink70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RequestSessionSheet(service: _service),
    );
    if (created == true) {
      _snack('Request sent. You will be notified when your therapist responds.');
    }
  }

  Future<void> _cancel(AppointmentV2 a) async {
    final reason = await showAppointmentReasonDialog(
      context,
      title: a.isRequested ? 'Withdraw request?' : 'Cancel session?',
      hint: 'Reason (optional)',
      confirmLabel: a.isRequested ? 'Withdraw' : 'Cancel session',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy.add(a.id));
    try {
      await _service.cancel(a, byRole: 'patient', reason: reason);
      _snack(a.isRequested ? 'Request withdrawn.' : 'Session cancelled.');
    } catch (e) {
      _snack(AppointmentService.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(backgroundColor: AppTheme.cardDark, title: const Text('My Sessions')),
        body: Center(
          child: Text('Please sign in to see your sessions.', style: TextStyle(color: AppColors.ink)),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, userSnap) {
        final userData = userSnap.data?.data();
        final therapistId = (userData?['therapistId'] ?? '').toString().trim();
        final therapistName = (userData?['therapistName'] ?? '').toString().trim();
        final userLoaded = userSnap.hasData;
        final linked = therapistId.isNotEmpty;

        return Scaffold(
          backgroundColor: AppTheme.backgroundDark,
          appBar: AppBar(
            backgroundColor: AppTheme.cardDark,
            title: const Text('My Sessions'),
          ),
          floatingActionButton: userLoaded
              ? FloatingActionButton.extended(
                  onPressed: () => _openRequestSheet(linked),
                  backgroundColor: linked ? AppTheme.primaryIndigo : Colors.grey,
                  icon: const Icon(Icons.add),
                  label: const Text('Request session'),
                )
              : null,
          body: StreamBuilder<List<AppointmentV2>>(
            stream: _appointmentsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return _ErrorState(message: AppointmentService.describeError(snap.error!));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return _buildList(snap.data!, linked, userLoaded, therapistName);
            },
          ),
        );
      },
    );
  }

  Widget _buildList(
    List<AppointmentV2> all,
    bool linked,
    bool userLoaded,
    String therapistName,
  ) {
    final now = DateTime.now();
    final upcoming = all.where((a) => a.isScheduled && !a.needsOutcome(now)).toList()
      ..sort((a, b) => (a.scheduledAt ?? now).compareTo(b.scheduledAt ?? now));
    final pending = all.where((a) => a.isRequested).toList()
      ..sort((a, b) => (a.proposedAt ?? now).compareTo(b.proposedAt ?? now));
    final history = all.where((a) => a.isTerminal || a.needsOutcome(now)).toList()
      ..sort((a, b) {
        final at = a.effectiveStart ?? a.updatedAt ?? now;
        final bt = b.effectiveStart ?? b.updatedAt ?? now;
        return bt.compareTo(at);
      });

    final children = <Widget>[
      if (userLoaded && !linked)
        AppCard(
          color: AppTheme.warningAmber.withValues(alpha: 0.15),
          margin: const EdgeInsets.only(bottom: 16),
          child: Text(
            'You are not linked to a therapist yet. Join your therapist with their '
            'invite code (Profile) to request online sessions.',
            style: TextStyle(color: AppColors.ink),
          ),
        ),
      if (linked && therapistName.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Your therapist: $therapistName',
            style: TextStyle(color: AppColors.ink70, fontSize: 13),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(localTimeZoneHint(),
            style: TextStyle(color: AppColors.ink38, fontSize: 12)),
      ),
    ];

    if (all.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyState(
            emoji: '📅',
            message: 'No sessions yet. Tap "Request session" to ask your therapist '
                'for an online or in-person appointment.',
          ),
        ),
      );
    } else {
      if (upcoming.isNotEmpty) {
        children.add(const SectionHeader(title: 'Upcoming', emoji: '📅'));
        children.addAll(upcoming.map(_buildCard));
      }
      if (pending.isNotEmpty) {
        children.add(const SectionHeader(title: 'Waiting for your therapist', emoji: '⏳'));
        children.addAll(pending.map(_buildCard));
      }
      if (history.isNotEmpty) {
        children.add(const SectionHeader(title: 'Past & closed', emoji: '🗂️'));
        children.addAll(history.map(_buildCard));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: children,
    );
  }

  Widget _buildCard(AppointmentV2 a) {
    final busy = _busy.contains(a.id);
    final whenLabel = a.scheduledAt != null
        ? formatAppointmentTime(a.scheduledAt!)
        : a.proposedAt != null
            ? 'Preferred: ${formatAppointmentTime(a.proposedAt!)}'
            : 'Time not set';

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(a.isVirtual ? Icons.videocam : Icons.location_on,
                  color: AppColors.ink70, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  a.therapistName,
                  style: TextStyle(
                      color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              AppointmentStatusChip(status: a.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(whenLabel, style: TextStyle(color: AppColors.ink, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            '${a.durationMinutes} min • ${a.isVirtual ? 'Online' : 'In person'}'
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
            Text(
              a.cancelledBy == 'patient' ? 'Cancelled by you' : 'Cancelled by your therapist',
              style: TextStyle(color: AppColors.ink60, fontSize: 12),
            ),
          ],
          if (a.needsOutcome(DateTime.now())) ...[
            const SizedBox(height: 6),
            Text('Session time has passed.',
                style: TextStyle(color: AppColors.ink60, fontSize: 12)),
          ],
          if (a.isScheduled && a.isVirtual) ...[
            const SizedBox(height: 12),
            AppointmentJoinButton(appointment: a),
          ],
          if (a.canCancel) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(
                      onPressed: () => _cancel(a),
                      child: Text(a.isRequested ? 'Withdraw request' : 'Cancel session',
                          style: TextStyle(color: AppTheme.riskRed)),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load sessions.\n$message',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.ink70),
        ),
      ),
    );
  }
}

class _RequestSessionSheet extends StatefulWidget {
  final AppointmentService service;
  const _RequestSessionSheet({required this.service});

  @override
  State<_RequestSessionSheet> createState() => _RequestSessionSheetState();
}

class _RequestSessionSheetState extends State<_RequestSessionSheet> {
  final TextEditingController _reason = TextEditingController();
  DateTime _proposedAt = nextSuggestedSlot(lead: const Duration(hours: 2));
  int _duration = 45;
  bool _virtual = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await pickAppointmentDateTime(context, _proposedAt);
    if (picked == null || !mounted) return;
    setState(() {
      _proposedAt = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please add a short reason.');
      return;
    }
    if (_proposedAt.isBefore(DateTime.now().add(AppointmentService.minLeadTime))) {
      setState(() => _error = 'Please choose a time in the future.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.service.requestSession(
        proposedAt: _proposedAt,
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request a session',
                style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 500,
              enabled: !_submitting,
              style: TextStyle(color: AppColors.ink),
              decoration: InputDecoration(
                labelText: 'What would you like to talk about?',
                labelStyle: TextStyle(color: AppColors.ink70),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule, color: AppColors.ink70),
              title: Text('Preferred time', style: TextStyle(color: AppColors.ink70)),
              subtitle: Text(formatAppointmentTime(_proposedAt),
                  style: TextStyle(color: AppColors.ink)),
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _virtual,
              onChanged: _submitting ? null : (v) => setState(() => _virtual = v),
              title: Text(_virtual ? 'Online (video)' : 'In person',
                  style: TextStyle(color: AppColors.ink)),
              subtitle: Text('Online sessions get a secure video link',
                  style: TextStyle(color: AppColors.ink54, fontSize: 12)),
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
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
