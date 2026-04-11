import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'password_recovery_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  final authService = AuthService();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final question1Controller = TextEditingController();
  final answer1Controller = TextEditingController();
  final question2Controller = TextEditingController();
  final answer2Controller = TextEditingController();
  String selectedRole = 'patient';
  bool isLoading = false;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundDark,
              AppTheme.backgroundDark.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo/Header
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primaryIndigo,
                              AppTheme.primaryIndigo.withValues(alpha: 0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Text(
                            '🧠',
                            style: TextStyle(fontSize: 40),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'MindTwin',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AI Digital Twin Mental Health',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Title
                Text(
                  isLogin ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isLogin
                      ? 'Continue your wellness journey'
                      : 'Start your mental health transformation',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

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
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFef4444),
                        fontSize: 12,
                      ),
                    ),
                  ),

                // Email
                _buildTextField(
                  controller: emailController,
                  label: 'Email Address',
                  hint: 'your@email.com',
                  icon: Icons.email_outlined,
                ),
                const SizedBox(height: 16),

                // Password
                _buildTextField(
                  controller: passwordController,
                  label: 'Password',
                  hint: 'Enter password',
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
                        hint: 'Your full name',
                        icon: Icons.person_outlined,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Role selection (signup only)
                if (!isLogin)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'I am a',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRoleButton(
                              label: 'Patient',
                              value: 'patient',
                              icon: '👤',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildRoleButton(
                              label: 'Therapist',
                              value: 'therapist',
                              icon: '👨‍⚕️',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.safeGreen.withValues(alpha: 0.1),
                          border: Border.all(color: AppTheme.safeGreen.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '💡 Testing Mode: Both roles can sign up locally. In production, therapists are admin-created only.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Security Questions (signup only)
                if (!isLogin)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Security Questions for Password Recovery',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'These will help you recover your password if you forget it',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: question1Controller,
                        label: 'Security Question 1',
                        hint: 'e.g., What city were you born in?',
                        icon: Icons.help_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: answer1Controller,
                        label: 'Answer 1',
                        hint: 'Your answer',
                        icon: Icons.lock_outline,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: question2Controller,
                        label: 'Security Question 2',
                        hint: 'e.g., What is your mother\'s maiden name?',
                        icon: Icons.help_outline,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: answer2Controller,
                        label: 'Answer 2',
                        hint: 'Your answer',
                        icon: Icons.lock_outline,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Login/Signup Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _handleAuth,
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            isLogin ? 'Sign In' : 'Create Account',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Toggle button
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        isLogin = !isLogin;
                        errorMessage = null;
                        emailController.clear();
                        passwordController.clear();
                        nameController.clear();
                      });
                    },
                    child: Text(
                      isLogin
                          ? 'Don\'t have account? Sign up'
                          : 'Already have account? Sign in',
                      style: const TextStyle(
                        color: AppTheme.primaryIndigo,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            prefixIcon: Icon(icon, color: AppTheme.primaryIndigo),
            filled: true,
            fillColor: AppTheme.cardDark,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.primaryIndigo,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleButton({
    required String label,
    required String value,
    required String icon,
  }) {
    final isSelected = selectedRole == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedRole = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryIndigo.withValues(alpha: 0.2)
              : AppTheme.cardDark,
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryIndigo
                : Colors.white.withValues(alpha: 0.1),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                icon,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color:
                      isSelected ? AppTheme.primaryIndigo : Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAuth() async {
    setState(() {
      errorMessage = null;
      isLoading = true;
    });

    try {
      final email = emailController.text.trim();
      final password = passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        setState(() {
          errorMessage = 'Please fill all fields';
        });
        return;
      }

      Map<String, dynamic> result;

      if (isLogin) {
        // Login: no role selection needed, use account's actual role
        result = await authService.login(email: email, password: password);
        
        // Validate that user is logging into correct role
        if (result['success'] && result['role'] != null) {
          // No additional validation needed - use actual account role
          // This prevents patients from accessing therapist features
        }
      } else {
        final name = nameController.text.trim();
        if (name.isEmpty) {
          setState(() {
            errorMessage = 'Please enter your name';
          });
          return;
        }

        // Validate security questions
        final q1 = question1Controller.text.trim();
        final a1 = answer1Controller.text.trim();
        final q2 = question2Controller.text.trim();
        final a2 = answer2Controller.text.trim();

        if (q1.isEmpty || a1.isEmpty || q2.isEmpty || a2.isEmpty) {
          setState(() {
            errorMessage = 'Please complete all security questions and answers';
          });
          return;
        }

        result = await authService.signup(
          email: email,
          password: password,
          name: name,
          role: selectedRole,
          securityQuestions: [q1, q2],
          securityAnswers: [a1, a2],
        );
      }

      if (result['success']) {
        if (mounted) {
          final role = result['role'];
          Navigator.of(context).pushReplacementNamed(
            role == 'patient' ? '/patient' : '/therapist',
          );
        }
      } else {
        setState(() {
          errorMessage = result['message'];
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'An error occurred: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
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
    super.dispose();
  }
}
