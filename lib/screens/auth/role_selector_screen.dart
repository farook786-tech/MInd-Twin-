import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class RoleSelectorScreen extends StatelessWidget {
  const RoleSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.backgroundDark,
              Color(0xFF1a1a2e),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  const Icon(
                    Icons.psychology,
                    size: 100,
                    color: AppTheme.primaryIndigo,
                  ),
                  const SizedBox(height: 24),
                  
                  // Title
                  Text(
                    'MindTwin',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 48,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI Digital Twin Mental Health System',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white60,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),

                  // Role Selection Cards
                  _buildRoleCard(
                    context,
                    title: 'Patient Portal',
                    description: 'Daily check-ins, voice journal, and your digital twin',
                    icon: Icons.person,
                    color: AppTheme.primaryIndigo,
                    route: '/patient',
                  ),
                  const SizedBox(height: 20),
                  _buildRoleCard(
                    context,
                    title: 'Therapist Dashboard',
                    description: 'Monitor patients, simulate interventions, view network',
                    icon: Icons.medical_services,
                    color: AppTheme.safeGreen,
                    route: '/therapist',
                  ),
                  const SizedBox(height: 40),

                  // Footer
                  Text(
                    'High-Fidelity Real-Time Medical SaaS',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.4),
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

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppTheme.glassGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: color,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
