import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../services/emergency_contacts.dart';
import '../../widgets/emergency_help_sheet.dart';
import 'safety_plan_screen.dart';

/// Crisis resources for patients in India (Tele-MANAS, 112), with other
/// countries in a secondary section. Opened from every crisis path (SOS,
/// check-in, PHQ-9 item 9, C-SSRS, AI chat, watch SOS notification).
class SafetyResourcesScreen extends StatelessWidget {
  const SafetyResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.cardDark,
        title: const Text('Safety Resources'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle('Get help now (India)'),
                const SizedBox(height: 4),
                Text(
                  'If you are in immediate danger, call 112. To talk to a trained mental health '
                  'counsellor any time, call Tele-MANAS on 14416 — free, confidential, 24x7.',
                  style: TextStyle(color: AppColors.ink70),
                ),
                const SizedBox(height: 4),
                ...EmergencyContacts.india.map((n) => EmergencyNumberTile(
                      number: n,
                      prominent: n != EmergencyContacts.teleManasTollFree,
                    )),
              ],
            ),
          ),
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SafetyPlanScreen()),
            ),
            child: Row(
              children: [
                Icon(Icons.assignment_turned_in_outlined, color: AppTheme.accentCyan),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CardTitle('My safety plan'),
                      SizedBox(height: 4),
                      Text('Your warning signs, coping steps and people to contact.',
                          style: TextStyle(color: AppColors.ink70)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.ink54),
              ],
            ),
          ),
          AppCard(
            margin: EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardTitle('Trusted person'),
                SizedBox(height: 4),
                Text(
                  'Reach out to a friend, family member, or your therapist and let them know you need '
                  'support. The message opens in your SMS app — nothing is sent until you press send.',
                  style: TextStyle(color: AppColors.ink70),
                ),
                SizedBox(height: 10),
                TrustedContactButton(),
              ],
            ),
          ),
          AppCard(
            margin: EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle('Grounding step'),
                SizedBox(height: 8),
                Text('Try slow breathing: inhale for 4, exhale for 6, and repeat five times.',
                    style: TextStyle(color: AppColors.ink70)),
              ],
            ),
          ),
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const _CardTitle('Outside India'),
                subtitle: Text('If you are travelling', style: TextStyle(color: AppColors.ink60)),
                children: EmergencyContacts.outsideIndia
                    .map((n) => EmergencyNumberTile(number: n))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w700));
  }
}
