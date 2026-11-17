import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared building blocks for the authentication screens.
class AuthScaffold extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? leading;
  final List<Widget>? actions;

  const AuthScaffold({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.children,
    this.leading,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: leading == null,
        leading: leading,
        actions: actions,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.backgroundDark,
              AppTheme.primaryIndigo.withValues(alpha: 0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppTheme.primaryIndigo,
                            AppTheme.primaryIndigo.withValues(alpha: 0.6),
                          ]),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 35))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthMessageBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const AuthMessageBanner({super.key, required this.message, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.riskRed : AppTheme.safeGreen;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}

class AuthTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.autofillHints,
    this.textInputAction,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: widget.controller,
        obscureText: widget.isPassword && _obscure,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.textCapitalization,
        validator: widget.validator,
        autofillHints: widget.autofillHints,
        textInputAction: widget.textInputAction ?? TextInputAction.next,
        autocorrect: false,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, color: AppTheme.primaryIndigo),
          suffixIcon: widget.isPassword
              ? IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                  onPressed: () => setState(() => _obscure = !_obscure),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primaryIndigo, width: 2),
          ),
        ),
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({super.key, required this.label, required this.loading, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryIndigo,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Validators shared by the auth forms.
class AuthValidators {
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Email is required';
    if (!_email.hasMatch(s)) return 'Enter a valid email address';
    return null;
  }

  static String? loginPassword(String? v) => (v ?? '').isEmpty ? 'Password is required' : null;

  static String? newPassword(String? v) {
    final s = v ?? '';
    if (s.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[0-9]').hasMatch(s)) {
      return 'Use letters and at least one number';
    }
    return null;
  }

  static String? name(String? v) {
    final s = (v ?? '').trim();
    if (s.length < 2) return 'Please enter your name';
    if (s.length > 80) return 'Name is too long';
    return null;
  }

  static String? inviteCode(String? v) {
    final s = (v ?? '').trim().replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) return 'Invite code is required (ask your therapist)';
    if (s.length < 4 || s.length > 32) return 'That does not look like a valid invite code';
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(s)) return 'Invite codes contain only letters, numbers and dashes';
    return null;
  }
}
