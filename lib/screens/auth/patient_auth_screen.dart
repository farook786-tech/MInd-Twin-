import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../common/backend_config_screen.dart';
import 'app_entry_screen.dart';
import 'auth_common.dart';
import 'password_recovery_screen.dart';
import 'therapist_auth_screen.dart';

/// Patient sign-in / sign-up.
///
/// Sign-up = Firebase email/password + therapist invite code → callable
/// `registerPatient` (server validates the code, sets the `patient` claim and
/// writes `users/{uid}` incl. therapistId). There is deliberately no
/// therapist directory: patients can only link via a code from their own
/// therapist.
class PatientAuthScreen extends StatefulWidget {
  final String? initialMessage;

  const PatientAuthScreen({super.key, this.initialMessage});

  @override
  State<PatientAuthScreen> createState() => _PatientAuthScreenState();
}

class _PatientAuthScreenState extends State<PatientAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _invite = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialMessage;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = AuthService();
    final outcome = _isLogin
        ? await auth.login(email: _email.text, password: _password.text)
        : await auth.signupPatient(
            email: _email.text,
            password: _password.text,
            name: _name.text.trim(),
            inviteCode: _invite.text,
          );
    if (!mounted) return;
    // Success, or account created but the registration call failed on the
    // network: the gate routes to home / pending / "finish registration".
    if (outcome.success || outcome.code == 'registration-incomplete') {
      AppEntryScreen.restart(context);
      return;
    }
    setState(() {
      _loading = false;
      _error = outcome.message ?? 'Something went wrong. Please try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.patientAccessEnabled) {
      // Never reachable in a therapist build; defensive only.
      return const Scaffold(body: Center(child: Text('Patient access is not available in this app.')));
    }

    return AuthScaffold(
      emoji: '🌱',
      title: _isLogin ? 'Welcome back' : 'Start your journey',
      subtitle: _isLogin
          ? 'Sign in to continue your wellness journey'
          : 'Create your account with the invite code from your therapist',
      leading: AppConfig.isUnifiedMode && Navigator.of(context).canPop()
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop())
          : const SizedBox.shrink(),
      actions: [
        if (kDebugMode)
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Backend configuration (debug)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackendConfigScreen()),
            ),
          ),
      ],
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) AuthMessageBanner(message: _error!),
                if (!_isLogin)
                  AuthTextField(
                    controller: _name,
                    label: 'Full name',
                    hint: 'What should we call you?',
                    icon: Icons.person_outline,
                    textCapitalization: TextCapitalization.words,
                    validator: AuthValidators.name,
                    autofillHints: const [AutofillHints.name],
                  ),
                AuthTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'your@email.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: AuthValidators.email,
                  autofillHints: const [AutofillHints.email],
                ),
                AuthTextField(
                  controller: _password,
                  label: 'Password',
                  hint: _isLogin ? 'Enter your password' : 'At least 8 characters incl. a number',
                  icon: Icons.lock_outline,
                  isPassword: true,
                  validator: _isLogin ? AuthValidators.loginPassword : AuthValidators.newPassword,
                  autofillHints: [_isLogin ? AutofillHints.password : AutofillHints.newPassword],
                  textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                ),
                if (!_isLogin) ...[
                  AuthTextField(
                    controller: _invite,
                    label: 'Therapist invite code',
                    hint: 'e.g. 7KQ2-MX4P',
                    icon: Icons.vpn_key_outlined,
                    textCapitalization: TextCapitalization.characters,
                    validator: AuthValidators.inviteCode,
                    textInputAction: TextInputAction.done,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Your therapist shares this code with you. It links your account so they '
                      'can see your check-ins and be alerted if you need help.',
                      style: TextStyle(color: AppColors.ink.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ),
                ],
                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PasswordRecoveryScreen(initialEmail: _email.text.trim()),
                        ),
                      ),
                      child: Text('Forgot password?', style: TextStyle(color: AppTheme.primaryIndigo)),
                    ),
                  ),
                const SizedBox(height: 8),
                AuthPrimaryButton(
                  label: _isLogin ? 'Sign in' : 'Create account',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _isLogin = !_isLogin;
                            _error = null;
                          }),
                  child: Text(_isLogin ? "Don't have an account? Sign up" : 'Already have an account? Sign in'),
                ),
                if (AppConfig.isUnifiedMode)
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const TherapistAuthScreen()),
                    ),
                    child: const Text('Therapist login (debug unified build)'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
