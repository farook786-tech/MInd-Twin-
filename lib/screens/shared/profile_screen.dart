import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../auth/join_therapist_dialog.dart';

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

  /// users/{uid}.settings.aiSummaryConsent (patients only; default OFF).
  /// Lets the therapist's pre-session brief include an AI-written narrative
  /// built from de-identified data (backend/src/services/SessionBriefNarrative.js).
  bool _aiSummaryConsent = false;
  bool _consentLoaded = false;
  bool _consentSaving = false;

  @override
  void initState() {
    super.initState();
    final user = AuthService().getCurrentUser();
    _isTherapist = AuthService().currentRole == 'therapist';
    _nameController.text = user?['name']?.toString() ?? '';
    _email = user?['email']?.toString();
    if (!_isTherapist) _loadConsent();
  }

  Future<void> _loadConsent() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      final settings = snap.data()?['settings'];
      if (!mounted) return;
      setState(() {
        _aiSummaryConsent = settings is Map && settings['aiSummaryConsent'] == true;
        _consentLoaded = true;
      });
    } catch (e) {
      debugPrint('[Profile] consent load failed: $e');
      if (mounted) setState(() => _consentLoaded = true);
    }
  }

  Future<void> _setConsent(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final previous = _aiSummaryConsent;
    setState(() {
      _aiSummaryConsent = value;
      _consentSaving = true;
    });
    // Merge only this key inside `settings` (owner-writable per firestore.rules).
    final write = FirebaseFirestore.instance.collection('users').doc(uid).set({
      'settings': {
        'aiSummaryConsent': value,
        'aiSummaryConsentUpdatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
    try {
      await write.timeout(const Duration(seconds: 10));
      _showSnack(value
          ? 'AI-assisted summaries allowed. You can turn this off at any time.'
          : 'AI-assisted summaries turned off.');
    } on TimeoutException {
      unawaited(write.catchError((Object e) => debugPrint('[Profile] queued consent write failed: $e')));
      _showSnack('Saved on this phone; it will sync when you are back online.');
    } catch (e) {
      debugPrint('[Profile] consent write failed: $e');
      if (mounted) setState(() => _aiSummaryConsent = previous);
      _showSnack('Could not save this setting. Try again.');
    } finally {
      if (mounted) setState(() => _consentSaving = false);
    }
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

  /// Links the patient to a different therapist via the server-side
  /// `joinTherapist` callable (the dialog handles validation and errors).
  Future<void> _changeTherapist() async {
    final therapistName = await showJoinTherapistDialog(context);
    if (therapistName != null) {
      _showSnack('You are now linked to $therapistName.');
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
                style: TextStyle(color: AppColors.ink70),
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
              leading: Icon(Icons.email_outlined, color: AppColors.ink54),
              title: Text('Email',
                  style: TextStyle(color: AppColors.ink54, fontSize: 13)),
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
          if (!_isTherapist) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _saving ? null : _changeTherapist,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Change therapist (invite code)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _aiSummaryConsent,
              onChanged: (!_consentLoaded || _consentSaving) ? null : _setConsent,
              title: const Text('Allow AI-assisted summaries for my therapist'),
              subtitle: Text(
                "Off by default. When on, your therapist's pre-session summary may include a short "
                'AI-written paragraph. The AI service receives only your scores, check-in and '
                'wearable summaries, alerts, dates as "days ago" and short journal excerpts with '
                'contact details removed, never your name, email or phone number. '
                'Your therapist always sees the full non-AI summary either way.',
                style: TextStyle(fontSize: 12, color: AppColors.ink60),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
