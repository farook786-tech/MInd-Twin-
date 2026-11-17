import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/role_service.dart';
import 'app_entry_screen.dart';

/// Shown while the therapist's claim is `therapist_pending`. No patient data
/// is reachable from here. "Check again" forces an ID-token refresh
/// (getIdTokenResult(true)) to pick up the `therapist` claim once an admin
/// approves the account.
class TherapistPendingScreen extends StatefulWidget {
  const TherapistPendingScreen({super.key});

  @override
  State<TherapistPendingScreen> createState() => _TherapistPendingScreenState();
}

class _TherapistPendingScreenState extends State<TherapistPendingScreen> {
  bool _checking = false;
  String? _message;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    String? role;
    String? error;
    try {
      role = await RoleService.instance.fetchRole(forceRefresh: true);
    } catch (e) {
      error = 'Could not reach the server. Check your connection and try again.';
    }
    if (!mounted) return;
    if (error == null && role != AppRoles.therapistPending) {
      // Approved (or changed): let the routing gate decide.
      AppEntryScreen.restart(context);
      return;
    }
    setState(() {
      _checking = false;
      _message = error ?? 'Your account is still awaiting approval.';
    });
  }

  Future<void> _signOut() async {
    await AuthService().logout();
    if (!mounted) return;
    AppEntryScreen.restart(context);
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService().getCurrentUser()?['email']?.toString() ?? '';
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Approval pending'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: _signOut),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top_rounded, size: 72, color: AppTheme.warningAmber),
                const SizedBox(height: 16),
                Text(
                  'Your therapist account is awaiting approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'A clinic administrator must verify your credentials before you can see '
                  'patients or receive alerts.${email.isNotEmpty ? '\n\nSigned in as $email' : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.ink.withValues(alpha: 0.75)),
                ),
                const SizedBox(height: 24),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_message!,
                        textAlign: TextAlign.center, style: TextStyle(color: AppTheme.warningAmber)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _checking ? null : _check,
                    icon: _checking
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: const Text('Check approval status'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: _signOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
