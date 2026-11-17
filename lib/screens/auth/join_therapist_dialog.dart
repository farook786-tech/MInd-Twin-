import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'auth_common.dart';

/// Patient "Link / Change therapist" flow via callable `joinTherapist`.
/// Returns the new therapist's name on success, null otherwise.
///
/// Usage (e.g. from the patient profile screen):
///   final name = await showJoinTherapistDialog(context);
Future<String?> showJoinTherapistDialog(BuildContext context, {bool isChange = true}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _JoinTherapistDialog(isChange: isChange),
  );
}

class _JoinTherapistDialog extends StatefulWidget {
  final bool isChange;
  const _JoinTherapistDialog({required this.isChange});

  @override
  State<_JoinTherapistDialog> createState() => _JoinTherapistDialogState();
}

class _JoinTherapistDialogState extends State<_JoinTherapistDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AuthService().joinTherapist(_code.text);
    if (!mounted) return;
    if (r.success) {
      final name = r.data['therapistName']?.toString();
      Navigator.of(context).pop(name?.isNotEmpty == true ? name : 'your therapist');
      return;
    }
    setState(() {
      _loading = false;
      _error = r.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isChange ? 'Change therapist' : 'Link your therapist'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isChange
                  ? 'Enter the invite code from your new therapist. Your future check-ins, '
                      'alerts and messages will go to them instead of your current therapist.'
                  : 'Enter the invite code your therapist gave you so they can see your check-ins '
                      'and receive your alerts.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (_error != null) AuthMessageBanner(message: _error!),
            AuthTextField(
              controller: _code,
              label: 'Invite code',
              hint: 'e.g. 7KQ2-MX4P',
              icon: Icons.vpn_key_outlined,
              textCapitalization: TextCapitalization.characters,
              validator: AuthValidators.inviteCode,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Link'),
        ),
      ],
    );
  }
}
