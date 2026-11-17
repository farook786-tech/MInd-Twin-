import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../services/auth_service.dart';
import 'app_entry_screen.dart';
import 'auth_common.dart';

/// For a signed-in account that has no `role` claim (signup was interrupted
/// before the registration callable succeeded). Finishes registration via
/// `registerPatient` / `registerTherapist`, or lets the user sign out.
class CompleteRegistrationScreen extends StatefulWidget {
  const CompleteRegistrationScreen({super.key});

  @override
  State<CompleteRegistrationScreen> createState() => _CompleteRegistrationScreenState();
}

class _CompleteRegistrationScreenState extends State<CompleteRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _invite = TextEditingController();
  final _license = TextEditingController();
  final _specialty = TextEditingController();
  late bool _asTherapist = AppConfig.isTherapistOnlyMode;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = AuthService().getCurrentUser()?['name']?.toString() ?? '';
    _name.text = n;
  }

  @override
  void dispose() {
    _name.dispose();
    _invite.dispose();
    _license.dispose();
    _specialty.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = AuthService();
    final outcome = _asTherapist
        ? await auth.completeTherapistRegistration(
            name: _name.text.trim(),
            licenseNumber: _license.text.trim(),
            specialty: _specialty.text.trim(),
          )
        : await auth.completePatientRegistration(name: _name.text.trim(), inviteCode: _invite.text);
    if (!mounted) return;
    if (outcome.success || outcome.code == 'wrong-app') {
      AppEntryScreen.restart(context, notice: outcome.success ? null : outcome.message);
      return;
    }
    setState(() {
      _loading = false;
      _error = outcome.message;
    });
  }

  Future<void> _signOut() async {
    await AuthService().logout();
    if (!mounted) return;
    AppEntryScreen.restart(context);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      emoji: _asTherapist ? '🩺' : '🌱',
      title: 'Finish registration',
      subtitle: _asTherapist
          ? 'Tell us about your practice. An administrator will review your account.'
          : 'Enter the invite code your therapist gave you to link your account.',
      leading: IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: _signOut),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) AuthMessageBanner(message: _error!),
              if (AppConfig.isUnifiedMode)
                SwitchListTile(
                  title: const Text('Register as therapist (debug build)'),
                  value: _asTherapist,
                  onChanged: (v) => setState(() => _asTherapist = v),
                ),
              AuthTextField(
                controller: _name,
                label: 'Full name',
                hint: 'Your name',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
                validator: AuthValidators.name,
              ),
              if (!_asTherapist)
                AuthTextField(
                  controller: _invite,
                  label: 'Therapist invite code',
                  hint: 'e.g. 7KQ2-MX4P',
                  icon: Icons.vpn_key_outlined,
                  textCapitalization: TextCapitalization.characters,
                  validator: AuthValidators.inviteCode,
                ),
              if (_asTherapist) ...[
                AuthTextField(
                  controller: _license,
                  label: 'License number',
                  hint: 'Professional license / registration',
                  icon: Icons.badge_outlined,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'License number is required' : null,
                ),
                AuthTextField(
                  controller: _specialty,
                  label: 'Specialty (optional)',
                  hint: 'e.g. CBT, adolescent care',
                  icon: Icons.psychology_outlined,
                ),
              ],
              const SizedBox(height: 8),
              AuthPrimaryButton(label: 'Continue', loading: _loading, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}
