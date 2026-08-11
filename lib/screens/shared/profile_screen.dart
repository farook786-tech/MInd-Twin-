import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_colors.dart';
import '../../services/auth_service.dart';

/// Shared profile screen for both patient and therapist roles.
/// Lets the user edit their display name; the change is pushed to
/// Firestore, the local SQLite patient row (mobile), and the backend.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;
  bool _isTherapist = false;
  String? _email;

  @override
  void initState() {
    super.initState();
    final user = AuthService().getCurrentUser();
    _isTherapist = AuthService().currentRole == 'therapist';
    _nameController.text = user?['name']?.toString() ?? '';
    _email = user?['email']?.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      _showSnack('Name must be at least 2 characters.');
      return;
    }

    setState(() => _saving = true);
    final updated = await AuthService().updateDisplayName(name);
    setState(() => _saving = false);

    if (!mounted) return;
    if (updated != null) {
      _showSnack('Profile updated');
      Navigator.of(context).pop(true);
    } else {
      _showSnack('Could not update profile. Try again.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          CircleAvatar(
            radius: 44,
            backgroundColor: AppTheme.primaryIndigo.withValues(alpha: 0.25),
            child: Icon(
              _isTherapist ? Icons.psychology : Icons.person,
              size: 44,
              color: AppTheme.primaryIndigo,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Chip(
              label: Text(
                _isTherapist ? 'Therapist' : 'Patient',
                style: const TextStyle(color: Colors.white70),
              ),
              backgroundColor: AppTheme.cardDark,
              side: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _nameController,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z0-9\s.\-']")),
            ],
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          if (_email != null && _email!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined, color: Colors.white54),
              title: const Text('Email',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              subtitle: Text(_email!, style: const TextStyle(fontSize: 15)),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_saving ? 'Saving…' : 'Save changes'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
