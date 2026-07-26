import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../patient/patient_home_screen.dart';
import '../common/backend_config_screen.dart';
import 'password_recovery_screen.dart';
import 'role_selection_screen.dart';
import 'therapist_auth_screen.dart';

class PatientAuthScreen extends StatefulWidget {
  const PatientAuthScreen({super.key});

  @override
  State<PatientAuthScreen> createState() => _PatientAuthScreenState();
}

class _PatientAuthScreenState extends State<PatientAuthScreen> {
  bool isLogin = true;
  final authService = AuthService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final question1Controller = TextEditingController();
  final answer1Controller = TextEditingController();
  final question2Controller = TextEditingController();
  final answer2Controller = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  // Therapist selection
  List<Map<String, dynamic>> _therapists = [];
  String? _selectedTherapistId;
  String? _selectedTherapistName;
  bool _loadingTherapists = false;
  String? _therapistLoadError;
  StreamSubscription<ConnectivityResult>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _fetchTherapists();
    // Listen for network restoration and retry fetching therapists automatically.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        if (_therapistLoadError != null) {
          _fetchTherapists();
        }
      }
    });
  }

  Future<void> _fetchTherapists() async {
    if (mounted) {
      setState(() {
      _loadingTherapists = true;
      _therapistLoadError = null;
    });
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'therapist')
          .get();
      debugPrint('[PatientAuth] Fetched ${snapshot.docs.length} therapists from Firestore');
      final list = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                'name': (doc.data()['name'] as String?)?.isNotEmpty == true
                    ? doc.data()['name'] as String
                    : 'Unnamed Therapist',
              })
          .toList();
      if (mounted) {
        setState(() {
          _therapists = list.isNotEmpty
              ? list
              : authService.getUsersByRole('therapist').map((user) => {
                    'id': user['id']?.toString() ?? 'local_therapist',
                    'name': (user['name'] ?? 'Therapist').toString(),
                  }).toList();
          if (_therapists.isEmpty) {
            _therapists = [
              {'id': 'therapist_demo', 'name': 'Demo Therapist'},
            ];
          }
          _selectedTherapistId ??= _therapists.first['id']?.toString();
          _selectedTherapistName ??= _therapists.first['name']?.toString();
          _loadingTherapists = false;
        });
      }
    } catch (e) {
      debugPrint('[PatientAuth] Failed to fetch therapists: $e');
      if (mounted) {
        setState(() {
          _therapists = authService.getUsersByRole('therapist').map((user) => {
                'id': user['id']?.toString() ?? 'local_therapist',
                'name': (user['name'] ?? 'Therapist').toString(),
              }).toList();
          if (_therapists.isEmpty) {
            _therapists = [
              {'id': 'therapist_demo', 'name': 'Demo Therapist'},
            ];
          }
          _selectedTherapistId ??= _therapists.first['id']?.toString();
          _selectedTherapistName ??= _therapists.first['name']?.toString();
          _loadingTherapists = false;
          _therapistLoadError = 'Using local therapist list — offline or network issue. Will retry automatically when online.';
        });
      }
    }
  }

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
            errorMessage = account['message'] ?? 'Invalid email or password';
            isLoading = false;
          });
          return;
        }

        // Validate role
        if (account['role'] != 'patient') {
          setState(() {
            errorMessage = 'This account is not registered as a patient';
            isLoading = false;
          });
          return;
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PatientHomeScreen()),
          );
        }
      } else {
        // Signup
        if (nameController.text.trim().isEmpty ||
            question1Controller.text.trim().isEmpty ||
            answer1Controller.text.trim().isEmpty ||
            question2Controller.text.trim().isEmpty ||
            answer2Controller.text.trim().isEmpty) {
          setState(() {
            errorMessage = 'Please fill in all fields';
            isLoading = false;
          });
          return;
        }

        if (_selectedTherapistId == null) {
          setState(() {
            errorMessage = 'Please select your therapist';
            isLoading = false;
          });
          return;
        }

        final result = await authService.signup(
          email: emailController.text.trim(),
          password: passwordController.text,
          name: nameController.text.trim(),
          role: 'patient',
          securityQuestions: [
            question1Controller.text.trim(),
            question2Controller.text.trim(),
          ],
          securityAnswers: [
            answer1Controller.text.trim(),
            answer2Controller.text.trim(),
          ],
          therapistId: _selectedTherapistId,
          assignedTherapist: _selectedTherapistName,
        );

        if (result['success'] && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PatientHomeScreen()),
          );
        } else {
          setState(() {
            errorMessage = result['message'] ?? 'Failed to create account. Email may already exist.';
            isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.patientAccessEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient Access Disabled')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 56, color: AppTheme.warningAmber),
                const SizedBox(height: 12),
                const Text(
                  'This build is configured for therapist-only access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Build with --dart-define=APP_MODE=patient for patient login.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const TherapistAuthScreen()),
                    );
                  },
                  child: const Text('Open Therapist Login'),
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
              AppTheme.primaryIndigo.withValues(alpha: 0.3),
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
                                AppTheme.primaryIndigo,
                                AppTheme.primaryIndigo.withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Center(
                            child: Text('🌱', style: TextStyle(fontSize: 35)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isLogin ? 'Welcome Back!' : 'Start Your Journey',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isLogin
                              ? 'Continue your wellness journey'
                              : 'Track your mental health with AI support',
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
                          const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 20),
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
                    label: 'Email',
                    hint: 'your@email.com',
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 16),

                  // Password
                  _buildTextField(
                    controller: passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
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
                            color: AppTheme.primaryIndigo,
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
                          hint: 'What should we call you?',
                          icon: Icons.person_outlined,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Security Questions (signup only)
                  if (!isLogin)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔐 Security Questions',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'These help you recover your password if needed',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: question1Controller,
                          label: 'Question 1',
                          hint: 'e.g., What is your favorite color?',
                          icon: Icons.quiz_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: answer1Controller,
                          label: 'Answer 1',
                          hint: 'Your answer',
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: question2Controller,
                          label: 'Question 2',
                          hint: 'e.g., What is your pet\'s name?',
                          icon: Icons.quiz_outlined,
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          controller: answer2Controller,
                          label: 'Answer 2',
                          hint: 'Your answer',
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),

                  // Therapist Selection (signup only)
                  if (!isLogin)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '👨‍⚕️ Select Your Therapist',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose the therapist who will support your journey',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_loadingTherapists)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_therapistLoadError != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _therapistLoadError!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _fetchTherapists,
                                  child: const Text('Retry', style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (_therapists.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No therapists found in the system.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Ask your clinic to register therapist accounts first, then retry.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: _fetchTherapists,
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text('Retry', style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _selectedTherapistId != null
                                      ? AppTheme.primaryIndigo.withValues(alpha: 0.6)
                                      : Colors.white.withValues(alpha: 0.1)),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedTherapistId,
                                hint: Text(
                                  'Select a therapist',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 14,
                                  ),
                                ),
                                dropdownColor: AppTheme.backgroundDark,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                icon: const Icon(Icons.keyboard_arrow_down,
                                    color: Colors.white54),
                                items: _therapists.map((t) {
                                  return DropdownMenuItem<String>(
                                    value: t['id'] as String,
                                    child: Text(t['name'] as String),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedTherapistId = value;
                                    _selectedTherapistName = _therapists
                                        .firstWhere((t) => t['id'] == value)['name']
                                        as String?;
                                  });
                                },
                              ),
                            ),
                          ),
                        if (_selectedTherapistName != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.greenAccent, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Selected: $_selectedTherapistName',
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
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
                        backgroundColor: AppTheme.primaryIndigo,
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
                              isLogin ? 'Sign In' : 'Create Account',
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
                              ? "Don't have an account? "
                              : 'Already have an account? ',
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
                            isLogin ? 'Sign Up' : 'Sign In',
                            style: const TextStyle(
                              color: AppTheme.primaryIndigo,
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
              prefixIcon: Icon(icon, color: AppTheme.primaryIndigo, size: 20),
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
    question1Controller.dispose();
    answer1Controller.dispose();
    question2Controller.dispose();
    answer2Controller.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }
}
