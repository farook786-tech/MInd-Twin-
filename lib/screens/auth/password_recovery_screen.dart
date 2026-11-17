import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'auth_common.dart';

/// Password recovery via FirebaseAuth.sendPasswordResetEmail.
///
/// Replaces the old security-question flow, which queried `users` by email
/// WITHOUT authentication (leaking account existence and hashed answers).
class PasswordRecoveryScreen extends StatefulWidget {
  final String initialEmail;

  const PasswordRecoveryScreen({super.key, this.initialEmail = ''});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  bool _loading = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _message = null;
    });
    final outcome = await AuthService().sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _message = outcome.message;
      _isError = !outcome.success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      emoji: '🔑',
      title: 'Reset password',
      subtitle: "Enter your account email and we'll send you a secure reset link.",
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_message != null) AuthMessageBanner(message: _message!, isError: _isError),
              AuthTextField(
                controller: _email,
                label: 'Email',
                hint: 'your@email.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                validator: AuthValidators.email,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 8),
              AuthPrimaryButton(label: 'Send reset link', loading: _loading, onPressed: _send),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
