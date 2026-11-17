import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/safety_plan.dart';
import '../screens/patient/safety_plan_screen.dart';
import '../screens/patient/safety_resources_screen.dart';
import '../services/emergency_contacts.dart';
import '../services/safety_plan_service.dart';

/// Tappable row that dials [number].
class EmergencyNumberTile extends StatelessWidget {
  final EmergencyNumber number;
  final bool prominent;

  const EmergencyNumberTile({super.key, required this.number, this.prominent = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.phone, color: prominent ? AppTheme.riskRed : AppColors.ink70),
      title: Text(
        '${number.display}  ·  ${number.name}',
        style: TextStyle(
          color: AppColors.ink,
          fontSize: prominent ? 17 : 15,
          fontWeight: prominent ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(number.description, style: TextStyle(color: AppColors.ink60)),
      onTap: () => callNumber(context, number.dial, number.display),
    );
  }
}

/// Dials [dial]; tells the patient to dial manually if no dialer opened.
Future<void> callNumber(BuildContext context, String dial, [String? display]) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await EmergencyContacts.call(dial);
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text('Please dial ${display ?? dial} manually.')));
  }
}

/// "Text my trusted contact" — opens the SMS app pre-filled for the first
/// help contact (with a phone number) in the patient's safety plan. Nothing is
/// ever sent without the patient pressing send.
class TrustedContactButton extends StatefulWidget {
  const TrustedContactButton({super.key});

  @override
  State<TrustedContactButton> createState() => _TrustedContactButtonState();
}

class _TrustedContactButtonState extends State<TrustedContactButton> {
  late final Future<SafetyPlanContact?> _contact = _load();

  Future<SafetyPlanContact?> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final plan = await SafetyPlanService().loadFast(uid, serverTimeout: const Duration(seconds: 2));
    return plan?.firstCallableHelpContact;
  }

  Future<void> _text(SafetyPlanContact c) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await EmergencyContacts.openSms(c.phone!);
    if (!ok) {
      messenger?.showSnackBar(SnackBar(
        content: Text('Could not open messages. Please call ${c.name} on ${c.phone}.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SafetyPlanContact?>(
      future: _contact,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 48, child: Center(child: LinearProgressIndicator()));
        }
        final c = snap.data;
        if (c == null) {
          return OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SafetyPlanScreen()),
            ),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add a trusted contact to your safety plan'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warningAmber,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _text(c),
              icon: const Icon(Icons.sms),
              label: Text('Text my trusted contact (${c.name})'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => callNumber(context, c.phone!, c.phone),
              icon: const Icon(Icons.phone, size: 18),
              label: Text('Call ${c.name}'),
            ),
          ],
        );
      },
    );
  }
}

/// Bottom sheet shown after the SOS button. [delivered] = the server
/// acknowledged the crisis event. When it did not (offline / slow / failed),
/// the patient is offered the trusted contact and Tele-MANAS directly.
Future<void> showEmergencyHelpSheet(
  BuildContext context, {
  required String status,
  required bool delivered,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.cardDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(delivered ? Icons.check_circle : Icons.error,
                    color: delivered ? AppTheme.safeGreen : AppTheme.warningAmber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(status,
                      style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!delivered) ...[
              Text(
                'Reach someone now:',
                style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const TrustedContactButton(),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.riskRed,
                  foregroundColor: AppColors.ink,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => callNumber(ctx, EmergencyContacts.teleManas.dial, '14416'),
                icon: const Icon(Icons.phone),
                label: const Text('Call Tele-MANAS 14416 (free, 24x7)'),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'If you are in immediate danger, call 112 now.',
              style: TextStyle(color: AppColors.ink70),
            ),
            const SizedBox(height: 4),
            ...EmergencyContacts.india.map((n) => EmergencyNumberTile(
                  number: n,
                  prominent: n != EmergencyContacts.teleManasTollFree,
                )),
            Theme(
              data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Outside India', style: TextStyle(color: AppColors.ink70)),
                children: EmergencyContacts.outsideIndia
                    .map((n) => EmergencyNumberTile(number: n))
                    .toList(),
              ),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyPlanScreen()));
              },
              icon: const Icon(Icons.assignment_turned_in_outlined),
              label: const Text('Open my safety plan'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SafetyResourcesScreen()),
                );
              },
              icon: const Icon(Icons.shield_outlined),
              label: const Text('More safety resources'),
            ),
          ],
        ),
      ),
    ),
  );
}
