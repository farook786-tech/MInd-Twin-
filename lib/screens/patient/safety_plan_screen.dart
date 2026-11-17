import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../models/safety_plan.dart';
import '../../services/emergency_contacts.dart';
import '../../services/safety_plan_service.dart';
import '../../widgets/emergency_help_sheet.dart';

/// The seven Stanley-Brown safety plan steps (Stanley & Brown 2012).
enum _Step {
  warningSigns,
  coping,
  distractions,
  help,
  professionals,
  environment,
  reasons,
}

extension on _Step {
  String get title => switch (this) {
        _Step.warningSigns => '1. My warning signs',
        _Step.coping => '2. Things I can do on my own',
        _Step.distractions => '3. People and places that take my mind off things',
        _Step.help => '4. People I can ask for help',
        _Step.professionals => '5. Professionals and helplines',
        _Step.environment => '6. Making my surroundings safer',
        _Step.reasons => '7. My reasons for living',
      };

  String get prompt => switch (this) {
        _Step.warningSigns =>
          'Thoughts, feelings, situations or behaviours that tell you a crisis may be starting.',
        _Step.coping =>
          'Things you can do by yourself to feel a little calmer (e.g. a walk, music, prayer, a shower).',
        _Step.distractions =>
          'People or places that help you take your mind off things. A phone number is optional.',
        _Step.help => 'People you trust and can tell that you are not okay. The first one with a phone '
            'number is used for "Text my trusted contact".',
        _Step.professionals => 'Your therapist, doctor, or a helpline such as Tele-MANAS 14416.',
        _Step.environment => 'How you will keep yourself safe — for example, giving medicines, blades or '
            'pesticides to someone you trust to keep, or not being alone.',
        _Step.reasons => 'The things, people or hopes that matter most to you.',
      };

  String get hint => switch (this) {
        _Step.warningSigns => 'e.g. I stop replying to friends',
        _Step.coping => 'e.g. Listen to my favourite songs',
        _Step.reasons => 'e.g. My sister',
        _ => '',
      };
}

/// Patient's Stanley-Brown safety plan (`safety_plans/{patientId}`).
///
/// * Patient (default): opens their own plan; view first, "Edit step by step".
/// * Therapist: pass [patientId] (+ [patientName]) and [asTherapist] = true.
///
/// Works offline: Firestore's cache serves the plan, and edits are queued.
class SafetyPlanScreen extends StatelessWidget {
  final String? patientId;
  final String? patientName;
  final bool asTherapist;

  const SafetyPlanScreen({super.key, this.patientId, this.patientName, this.asTherapist = false});

  @override
  Widget build(BuildContext context) {
    final pid = patientId ?? FirebaseAuth.instance.currentUser?.uid;
    final title = asTherapist
        ? 'Safety plan${patientName != null && patientName!.isNotEmpty ? ' — $patientName' : ''}'
        : 'My safety plan';
    if (pid == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        appBar: AppBar(backgroundColor: AppTheme.cardDark, title: Text(title)),
        body: Center(
          child: Text('Please sign in to see your safety plan.', style: TextStyle(color: AppColors.ink70)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(backgroundColor: AppTheme.cardDark, title: Text(title)),
      body: StreamBuilder<SafetyPlan>(
        stream: SafetyPlanService().watch(pid),
        builder: (context, snap) {
          if (snap.hasError && !snap.hasData) {
            return _ErrorView(asTherapist: asTherapist);
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return _PlanView(plan: snap.data!, asTherapist: asTherapist);
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final bool asTherapist;
  const _ErrorView({required this.asTherapist});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('The safety plan could not be loaded right now.',
            style: TextStyle(color: AppColors.ink70)),
        if (!asTherapist) ...[
          const SizedBox(height: 12),
          ...EmergencyContacts.india.map((n) => EmergencyNumberTile(number: n, prominent: true)),
        ],
      ],
    );
  }
}

class _PlanView extends StatelessWidget {
  final SafetyPlan plan;
  final bool asTherapist;

  const _PlanView({required this.plan, required this.asTherapist});

  void _edit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SafetyPlanEditor(initial: plan, asTherapist: asTherapist)),
    );
  }

  Widget _strings(List<String> items) {
    if (items.isEmpty) {
      return Text('Not filled in yet', style: TextStyle(color: AppColors.ink38));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('•  $s', style: TextStyle(color: AppColors.ink)),
              ))
          .toList(),
    );
  }

  Widget _contacts(BuildContext context, List<SafetyPlanContact> items) {
    if (items.isEmpty) {
      return Text('Not filled in yet', style: TextStyle(color: AppColors.ink38));
    }
    return Column(
      children: items
          .map((c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(c.name, style: TextStyle(color: AppColors.ink)),
                subtitle: c.hasPhone ? Text(c.phone!, style: TextStyle(color: AppColors.ink60)) : null,
                trailing: c.hasPhone
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Call ${c.name}',
                            icon: Icon(Icons.phone, color: AppTheme.safeGreen),
                            onPressed: () => callNumber(context, c.phone!, c.phone),
                          ),
                          if (!asTherapist)
                            IconButton(
                              tooltip: 'Text ${c.name}',
                              icon: Icon(Icons.sms, color: AppTheme.accentCyan),
                              onPressed: () => EmergencyContacts.openSms(c.phone!),
                            ),
                        ],
                      )
                    : null,
              ))
          .toList(),
    );
  }

  Widget _section(String title, Widget body) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updated = plan.updatedAt;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (plan.isEmpty)
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Text(
              asTherapist
                  ? 'No safety plan yet. You can draft one with the patient in session.'
                  : 'A safety plan is a short list you write now, while you feel calmer, to help you '
                      'get through a crisis later. It takes about 10 minutes. You can fill it in '
                      'with your therapist too.',
              style: TextStyle(color: AppColors.ink70),
            ),
          ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => _edit(context),
          icon: const Icon(Icons.edit_note),
          label: Text(plan.isEmpty ? 'Create safety plan step by step' : 'Edit step by step'),
        ),
        if (updated != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              'Last updated ${MaterialLocalizations.of(context).formatMediumDate(updated)}'
              '${plan.updatedBy != null && plan.updatedBy != plan.patientId ? ' by therapist' : ''}',
              style: TextStyle(color: AppColors.ink38, fontSize: 12),
            ),
          ),
        const SizedBox(height: 10),
        _section(_Step.warningSigns.title, _strings(plan.warningSigns)),
        _section(_Step.coping.title, _strings(plan.copingStrategies)),
        _section(_Step.distractions.title, _contacts(context, plan.distractionsPeople)),
        _section(_Step.help.title, _contacts(context, plan.helpContacts)),
        _section(_Step.professionals.title, _contacts(context, plan.professionals)),
        _section(
          _Step.environment.title,
          plan.environmentSafety.trim().isEmpty
              ? Text('Not filled in yet', style: TextStyle(color: AppColors.ink38))
              : Text(plan.environmentSafety, style: TextStyle(color: AppColors.ink)),
        ),
        _section(_Step.reasons.title, _strings(plan.reasonsToLive)),
        if (!asTherapist)
          _section(
            'If I am still not safe',
            Column(
              children: EmergencyContacts.india
                  .where((n) => n != EmergencyContacts.teleManasTollFree)
                  .map((n) => EmergencyNumberTile(number: n, prominent: true))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Step-by-step editor
// -----------------------------------------------------------------------------

class _SafetyPlanEditor extends StatefulWidget {
  final SafetyPlan initial;
  final bool asTherapist;

  const _SafetyPlanEditor({required this.initial, required this.asTherapist});

  @override
  State<_SafetyPlanEditor> createState() => _SafetyPlanEditorState();
}

class _SafetyPlanEditorState extends State<_SafetyPlanEditor> {
  late SafetyPlan _plan = widget.initial;
  late final TextEditingController _environment =
      TextEditingController(text: widget.initial.environmentSafety);
  int _index = 0;
  bool _saving = false;

  @override
  void dispose() {
    _environment.dispose();
    super.dispose();
  }

  _Step get _step => _Step.values[_index];

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final plan = _plan.copyWith(environmentSafety: _environment.text);
    final status = await SafetyPlanService().save(plan, asTherapist: widget.asTherapist);
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (status) {
      case SafetyPlanSaveStatus.saved:
        messenger.showSnackBar(const SnackBar(content: Text('Safety plan saved.')));
        Navigator.pop(context);
      case SafetyPlanSaveStatus.savedOffline:
        messenger.showSnackBar(const SnackBar(
          content: Text('Saved on this phone. It will sync automatically when you are back online.'),
        ));
        Navigator.pop(context);
      case SafetyPlanSaveStatus.failed:
        messenger.showSnackBar(SnackBar(
          content: Text('Could not save the safety plan. Please try again.'),
          backgroundColor: AppTheme.riskRed,
        ));
    }
  }

  Widget _body() {
    switch (_step) {
      case _Step.warningSigns:
        return _StringListEditor(
          key: const ValueKey('warningSigns'),
          items: _plan.warningSigns,
          hint: _step.hint,
          onChanged: (v) => setState(() => _plan = _plan.copyWith(warningSigns: v)),
        );
      case _Step.coping:
        return _StringListEditor(
          key: const ValueKey('coping'),
          items: _plan.copingStrategies,
          hint: _step.hint,
          onChanged: (v) => setState(() => _plan = _plan.copyWith(copingStrategies: v)),
        );
      case _Step.distractions:
        return _ContactListEditor(
          key: const ValueKey('distractions'),
          items: _plan.distractionsPeople,
          phoneRequired: false,
          onChanged: (v) => setState(() => _plan = _plan.copyWith(distractionsPeople: v)),
        );
      case _Step.help:
        return _ContactListEditor(
          key: const ValueKey('help'),
          items: _plan.helpContacts,
          phoneRequired: true,
          onChanged: (v) => setState(() => _plan = _plan.copyWith(helpContacts: v)),
        );
      case _Step.professionals:
        final hasTeleManas = _plan.professionals.any((c) => (c.phone ?? '').contains('14416'));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasTeleManas)
              OutlinedButton.icon(
                onPressed: () => setState(() => _plan = _plan.copyWith(professionals: [
                      ..._plan.professionals,
                      const SafetyPlanContact(name: 'Tele-MANAS (24x7)', phone: '14416'),
                    ])),
                icon: const Icon(Icons.add),
                label: const Text('Add Tele-MANAS 14416'),
              ),
            _ContactListEditor(
              key: ValueKey('professionals${_plan.professionals.length}'),
              items: _plan.professionals,
              phoneRequired: true,
              onChanged: (v) => setState(() => _plan = _plan.copyWith(professionals: v)),
            ),
          ],
        );
      case _Step.environment:
        return TextField(
          controller: _environment,
          maxLines: 6,
          maxLength: SafetyPlan.maxEnvironmentLength,
          style: TextStyle(color: AppColors.ink),
          decoration: const InputDecoration(
            hintText: 'e.g. My brother keeps my tablets and gives me one each day',
            border: OutlineInputBorder(),
          ),
        );
      case _Step.reasons:
        return _StringListEditor(
          key: const ValueKey('reasons'),
          items: _plan.reasonsToLive,
          hint: _step.hint,
          onChanged: (v) => setState(() => _plan = _plan.copyWith(reasonsToLive: v)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _Step.values.length - 1;
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: Text('Step ${_index + 1} of ${_Step.values.length}'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_index + 1) / _Step.values.length),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(_step.title,
                      style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_step.prompt, style: TextStyle(color: AppColors.ink70)),
                  const SizedBox(height: 14),
                  _body(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton(
                      onPressed: () => setState(() => _index--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (last) {
                              _save();
                            } else {
                              FocusScope.of(context).unfocus();
                              setState(() => _index++);
                            }
                          },
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(last ? 'Save plan' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StringListEditor extends StatefulWidget {
  final List<String> items;
  final String hint;
  final ValueChanged<List<String>> onChanged;

  const _StringListEditor({super.key, required this.items, required this.hint, required this.onChanged});

  @override
  State<_StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<_StringListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final t = _controller.text.trim();
    if (t.isEmpty || widget.items.length >= SafetyPlan.maxItems) return;
    widget.onChanged([...widget.items, t]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.items.asMap().entries.map((e) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.value, style: TextStyle(color: AppColors.ink)),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.close, color: AppColors.ink54),
                onPressed: () => widget.onChanged([...widget.items]..removeAt(e.key)),
              ),
            )),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLength: SafetyPlan.maxTextLength,
                style: TextStyle(color: AppColors.ink),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(hintText: widget.hint.isEmpty ? 'Add an item' : widget.hint),
              ),
            ),
            IconButton(
              tooltip: 'Add',
              icon: Icon(Icons.add_circle, color: AppTheme.accentCyan),
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}

class _ContactListEditor extends StatefulWidget {
  final List<SafetyPlanContact> items;
  final bool phoneRequired;
  final ValueChanged<List<SafetyPlanContact>> onChanged;

  const _ContactListEditor({
    super.key,
    required this.items,
    required this.phoneRequired,
    required this.onChanged,
  });

  @override
  State<_ContactListEditor> createState() => _ContactListEditorState();
}

class _ContactListEditorState extends State<_ContactListEditor> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _add() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name.');
      return;
    }
    if (widget.phoneRequired && phone.replaceAll(RegExp(r'[^0-9]'), '').length < 3) {
      setState(() => _error = 'Please enter a phone number so you can reach them quickly.');
      return;
    }
    if (widget.items.length >= SafetyPlan.maxItems) return;
    widget.onChanged([...widget.items, SafetyPlanContact(name: name, phone: phone.isEmpty ? null : phone)]);
    _name.clear();
    _phone.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.items.asMap().entries.map((e) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person, color: AppColors.ink54),
              title: Text(e.value.name, style: TextStyle(color: AppColors.ink)),
              subtitle: e.value.hasPhone
                  ? Text(e.value.phone!, style: TextStyle(color: AppColors.ink60))
                  : null,
              trailing: IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.close, color: AppColors.ink54),
                onPressed: () => widget.onChanged([...widget.items]..removeAt(e.key)),
              ),
            )),
        TextField(
          controller: _name,
          maxLength: SafetyPlan.maxNameLength,
          style: TextStyle(color: AppColors.ink),
          decoration: const InputDecoration(labelText: 'Name (or place)'),
        ),
        TextField(
          controller: _phone,
          maxLength: SafetyPlan.maxPhoneLength,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: AppColors.ink),
          decoration: InputDecoration(
            labelText: widget.phoneRequired ? 'Phone number' : 'Phone number (optional)',
            errorText: _error,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add')),
        ),
      ],
    );
  }
}
