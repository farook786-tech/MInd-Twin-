class AppConfig {
  // Build with:
  // flutter build apk --dart-define=APP_MODE=patient
  // flutter build apk --dart-define=APP_MODE=therapist
  // flutter build apk --dart-define=APP_MODE=unified
  static const String _appMode =
      String.fromEnvironment('APP_MODE', defaultValue: 'unified');

  static bool get isPatientOnlyMode => _appMode.toLowerCase() == 'patient';
  static bool get isTherapistOnlyMode => _appMode.toLowerCase() == 'therapist';

  static bool get patientAccessEnabled => !isTherapistOnlyMode;

  static bool get therapistAccessEnabled => !isPatientOnlyMode;

  static String get modeLabel {
    if (isPatientOnlyMode) return 'patient';
    if (isTherapistOnlyMode) return 'therapist';
    return 'unified';
  }

}
