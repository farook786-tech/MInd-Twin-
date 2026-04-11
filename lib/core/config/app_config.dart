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

  static const String geminiApiKey = 'AIzaSyCduTbmjeGdDKPsaCk_QPg7M2S1Z70ha9w';
    static const String geminiModel = 'gemini-2.0-flash';
  static const String geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
}
