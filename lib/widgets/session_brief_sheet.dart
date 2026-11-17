import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../services/session_brief_service.dart';

/// Opens the pre-session brief for [patientId] as a bottom sheet
/// (therapist app). Content comes from `POST /api/brief/:patientId`.
Future<void> showSessionBriefSheet(BuildContext context, {required String patientId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SessionBriefSheet(patientId: patientId),
  );
}

class SessionBriefSheet extends StatefulWidget {
  final String patientId;
  final SessionBriefService? service;

  const SessionBriefSheet({super.key, required this.patientId, this.service});

  @override
  State<SessionBriefSheet> createState() => _SessionBriefSheetState();
}

class _SessionBriefSheetState extends State<SessionBriefSheet> {
  static const String footer = 'Decision support only. Not a diagnosis or prescription.';

  late final SessionBriefService _service = widget.service ?? SessionBriefService();
  late Future<SessionBriefResult> _future;
  final DateFormat _dateFmt = DateFormat('d MMM yyyy, HH:mm');
  final DateFormat _dayFmt = DateFormat('d MMM');

  @override
  void initState() {
    super.initState();
    _future = _service.fetch(widget.patientId);
  }

  void _retry() => setState(() => _future = _service.fetch(widget.patientId));

  String _periodLabel(SessionBrief b) {
    if (b.from == null || b.to == null) return '';
    final range = '${_dayFmt.format(b.from!)} – ${_dayFmt.format(b.to!)}';
    return b.basis == 'last_completed_session' ? 'since last session, $range' : 'last 14 days, $range';
  }

  Future<void> _copy(SessionBrief b) async {
    await Clipboard.setData(ClipboardData(text: b.toPlainText(periodLabel: _periodLabel(b))));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Brief copied to clipboard')),
    );
  }

  void _showSource(BriefItem item) {
    final s = item.source;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.text),
            const SizedBox(height: 12),
            _kv('Type', s.typeLabel),
            if (s.field != null) _kv('Field', s.field!),
            _kv('Date', s.at != null ? _dateFmt.format(s.at!) : 'not available'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('$k: $v', style: TextStyle(fontSize: 13, color: AppColors.ink70)),
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<SessionBriefResult>(
        future: _future,
        builder: (context, snap) {
          final result = snap.data;
          final brief = result?.brief;
          return Column(
            children: [
              _header(brief),
              const Divider(height: 1),
              Expanded(child: _body(snap, result, scroll)),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Text(
                  footer,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.ink60, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(SessionBrief? brief) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Icon(Icons.summarize_outlined, color: AppTheme.primaryIndigo),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pre-session brief',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (brief != null && _periodLabel(brief).isNotEmpty)
                  Text(_periodLabel(brief),
                      style: TextStyle(fontSize: 12, color: AppColors.ink60)),
              ],
            ),
          ),
          if (brief != null)
            IconButton(
              tooltip: 'Copy to clipboard',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copy(brief),
            ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncSnapshot<SessionBriefResult> snap, SessionBriefResult? result, ScrollController scroll) {
    if (snap.connectionState != ConnectionState.done) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Building brief…', style: TextStyle(color: AppColors.ink70)),
          ],
        ),
      );
    }
    final brief = result?.brief;
    if (brief == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.ink54),
              const SizedBox(height: 12),
              Text(result?.error ?? 'Could not create the brief.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (brief.flags.isNotEmpty)
          _block(
            title: 'Flags',
            icon: Icons.flag_rounded,
            color: AppTheme.riskRed,
            children: brief.flags.map(_itemTile).toList(),
          ),
        for (final s in brief.sections)
          if (s.items.isNotEmpty)
            _block(
              title: s.title,
              icon: Icons.notes_rounded,
              color: AppTheme.primaryIndigo,
              children: s.items.map(_itemTile).toList(),
            ),
        if (brief.dataGaps.isNotEmpty)
          _block(
            title: 'Data gaps',
            icon: Icons.help_outline_rounded,
            color: AppTheme.warningAmber,
            children: brief.dataGaps
                .map((g) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• $g', style: TextStyle(fontSize: 13, color: AppColors.ink70)),
                    ))
                .toList(),
          ),
        if (brief.narrative != null) _narrativeBlock(brief.narrative!),
      ],
    );
  }

  Widget _narrativeBlock(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryIndigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryIndigo.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: AppTheme.primaryIndigo),
              SizedBox(width: 8),
              Expanded(
                child: Text('AI narrative (consented, de-identified)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
          Text(
            'Generated by an AI model from the de-identified brief above, with the patient\'s '
            'consent. It may omit or misstate details — the itemised brief and its sources are '
            'authoritative. Not a diagnosis or treatment recommendation.',
            style: TextStyle(fontSize: 11, color: AppColors.ink60, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _block({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _itemTile(BriefItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showSource(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: TextStyle(color: AppColors.ink70)),
            Expanded(child: Text(item.text, style: const TextStyle(fontSize: 13.5, height: 1.35))),
            Padding(
              padding: EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.info_outline, size: 14, color: AppColors.ink38),
            ),
          ],
        ),
      ),
    );
  }
}
