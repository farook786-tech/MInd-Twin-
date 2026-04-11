import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'patient_auth_screen.dart';
import '../therapist/therapist_dashboard_screen.dart';
import '../common/backend_config_screen.dart';
import 'password_recovery_screen.dart';
import 'role_selection_screen.dart';

class TherapistAuthScreen extends StatefulWidget {
  const TherapistAuthScreen({super.key});

  @override
  State<TherapistAuthScreen> createState() => _TherapistAuthScreenState();
}

class _TherapistAuthScreenState extends State<TherapistAuthScreen> {
  bool isLogin = true;
  final authService = AuthService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final licenseController = TextEditingController();
  final question1Controller = TextEditingController();
  final answer1Controller = TextEditingController();
  final question2Controller = TextEditingController();
  final answer2Controller = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  Future<void> _handleAuth() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (isLogin) {
        // Login
        final account = await authService.login(
          email: emailController.text.trim(),
          password: passwordController.text,
        );

        if (!account['success']) {
          setState(() {
            errorMessage = account['message'] ?? 'Invalid credentials';
            isLoading = false;
          });
          return;
        }

        // Validate role
        if (account['role'] != 'therapist') {
          setState(() {
            errorMessage = 'This account is not registered as a therapist';
            isLoading = false;
          });
          return;
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TherapistDashboardScreen()),
          );
        }
      } else {
        // Signup
        if (nameController.text.trim().isEmpty ||
            licenseController.text.trim().isEmpty ||
            question1Controller.text.trim().isEmpty ||
            answer1Controller.text.trim().isEmpty ||
            question2Controller.text.trim().isEmpty ||
            answer2Controller.text.trim().isEmpty) {
          setState(() {
            errorMessage = 'All fields are required';
            isLoading = false;
          });
          return;
        }

        final result = await authService.signup(
          email: emailController.text.trim(),
          password: passwordController.text,
          name: nameController.text.trim(),
          role: 'therapist',
          securityQuestions: [
            question1Controller.text.trim(),
            question2Controller.text.trim(),
          ],
          securityAnswers: [
            answer1Controller.text.trim(),
            answer2Controller.text.trim(),
          ],
        );

        if (result['success'] && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TherapistDashboardScreen()),
          );
        } else {
          setState(() {
            errorMessage = result['message'] ?? 'Registration failed. Email may already be in use.';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.therapistAccessEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Therapist Access Disabled')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56, color: AppTheme.warningAmber),
                const SizedBox(height: 12),
                const Text(
                  'This build is configured for patient-only access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Build with --dart-define=APP_MODE=unified for therapist login.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const PatientAuthScreen()),
                    );
                  },
                  child: const Text('Open Patient Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Backend Configuration',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BackendConfigScreen()),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.backgroundDark,
              AppTheme.accentCyan.withValues(alpha: 0.2),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.accentCyan,
                                AppTheme.accentCyan.withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: Text('👨‍⚕️', style: TextStyle(fontSize: 35)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isLogin ? 'Clinician Portal' : 'Professional Registration',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isLogin
                              ? 'Access your clinical dashboard'
                              : 'Register for professional access',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Error message
                  if (errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.riskRed.withValues(alpha: 0.2),
                        border: Border.all(color: AppTheme.riskRed),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFef4444), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFef4444),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Email
                  _buildTextField(
                    controller: emailController,
                    label: 'Professional Email',
                    hint: 'clinician@practice.com',
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  _buildTextField(
                    controller: passwordController,
                    label: 'Password',
                    hint: 'Secure password',
                    icon: Icons.lock_outlined,
                    isPassword: true,
                  ),

                  // Forgot password link (login only)
                  if (isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PasswordRecoveryScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: AppTheme.accentCyan,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Name (signup only)
                  if (!isLogin)
                    Column(
                      children: [
                        _buildTextField(
                          controller: nameController,
                          label: 'Full Name',
                          hint: 'Dr. John Smith',
                          icon: Icons.person_outlined,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: licenseController,
                          label: 'License Number',
                          hint: 'Professional license or credential',
                          icon: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Security Questions (signup only)
                  if (!isLogin)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.accentCyan.withValues(alpha: 0.1),
                            border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.security, color: AppTheme.accentCyan, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Security Questions for Account Recovery',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: question1Controller,
                          label: 'Security Question 1',
                          hint: 'What was the name of your first pet?',
                          icon: Icons.help_outline,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: answer1Controller,
                          label: 'Answer 1',
                          hint: 'Your answer',
                          icon: Icons.vpn_key_outlined,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: question2Controller,
                          label: 'Security Question 2',
                          hint: 'What city were you born in?',
                          icon: Icons.help_outline,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: answer2Controller,
                          label: 'Answer 2',
                          hint: 'Your answer',
                          icon: Icons.vpn_key_outlined,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _handleAuth,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentCyan,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isLogin ? 'Sign In' : 'Register',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Toggle login/signup
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLogin
                              ? "Need professional access? "
                              : 'Already registered? ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              isLogin = !isLogin;
                              errorMessage = null;
                            });
                          },
                          child: Text(
                            isLogin ? 'Register' : 'Sign In',
                            style: const TextStyle(
                              color: AppTheme.accentCyan,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
              ),
              prefixIcon: Icon(icon, color: AppTheme.accentCyan, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    licenseController.dispose();
    question1Controller.dispose();
    answer1Controller.dispose();
    question2Controller.dispose();
    answer2Controller.dispose();
    super.dispose();
  }
}
