import 'package:flutter/material.dart';

import '../../models/patient.dart';
import 'patient_details_screen.dart';

/// Entry point used by the Patients tab. The detail screen itself listens to
/// `users/{patientId}` live (snapshots), so this only seeds it with the id and
/// the name already shown in the roster. No fabricated scores: everything
/// else comes from Firestore and is null until it exists.
class PatientDetailScreen extends StatelessWidget {
  final String patientId;
  final String initialName;

  const PatientDetailScreen({
    super.key,
    required this.patientId,
    required this.initialName,
  });

  @override
  Widget build(BuildContext context) {
    return PatientDetailsScreen(
      key: ValueKey(patientId),
      patient: Patient.fromFirestore(
        patientId,
        const <String, dynamic>{},
        fallbackName: initialName,
      ),
    );
  }
}
