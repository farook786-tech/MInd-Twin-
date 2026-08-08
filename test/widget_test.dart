import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindtwin/core/theme/app_theme.dart';
import 'package:mindtwin/screens/auth/role_selection_screen.dart';

void main() {
  testWidgets('Role selection screen renders both role options',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkMedicalTheme,
        home: const RoleSelectionScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Therapist'), findsOneWidget);
  });
}
