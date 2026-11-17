import 'package:flutter/foundation.dart';

/// Compile-time selection of which app this binary is.
///
/// Build with (Gradle flavor + matching dart-define):
///   flutter build apk --flavor patient   --dart-define=APP_MODE=patient
///   flutter build apk --flavor therapist --dart-define=APP_MODE=therapist
///
/// `unified` (both roles in one binary, role picker on launch) exists ONLY
/// for local development and is honoured only in debug builds.
///
/// Fail-safe policy for release/profile builds when APP_MODE is missing,
/// misspelled, or `unified`: the binary is forced into PATIENT mode and a
/// loud error is printed at startup ([logStartupDiagnostics]).
/// Rationale: patient mode is the least-privileged configuration. It can
/// never render therapist screens (which show other people's health data),
/// and a therapist account signing into it is rejected and signed out by
/// the role check. Defaulting to `therapist` or `unified` would instead
/// expose clinician UI in a binary that may have shipped to patients.
class AppConfig {
  static const String _rawAppMode = String.fromEnvironment('APP_MODE');

  static String get _normalized => _rawAppMode.trim().toLowerCase();

  /// True when the dart-define was missing or invalid for this build type
  /// and a fallback was applied.
  static bool get isMisconfigured {
    final m = _normalized;
    if (m == 'patient' || m == 'therapist') return false;
    if (kDebugMode && (m.isEmpty || m == 'unified')) return false;
    return true;
  }

  /// Effective mode: 'patient' | 'therapist' | 'unified' (debug only).
  static String get _effectiveMode {
    final m = _normalized;
    if (m == 'patient' || m == 'therapist') return m;
    if (kDebugMode && (m.isEmpty || m == 'unified')) return 'unified';
    return 'patient';
  }

  static bool get isPatientOnlyMode => _effectiveMode == 'patient';
  static bool get isTherapistOnlyMode => _effectiveMode == 'therapist';
  static bool get isUnifiedMode => _effectiveMode == 'unified';

  static bool get patientAccessEnabled => !isTherapistOnlyMode;
  static bool get therapistAccessEnabled => !isPatientOnlyMode;

  static String get modeLabel => _effectiveMode;

  /// Prints a loud warning when the build is misconfigured. In debug builds
  /// an invalid explicit value (typo) also trips an assert.
  static void logStartupDiagnostics() {
    if (!isMisconfigured) {
      debugPrint('[AppConfig] APP_MODE=$_effectiveMode');
      return;
    }
    final msg = '[AppConfig] *** BUILD MISCONFIGURED *** APP_MODE="$_rawAppMode" is not valid '
        'for a ${kReleaseMode ? 'release' : 'profile/debug'} build. '
        'Falling back to PATIENT mode (least privilege). '
        'Build with --dart-define=APP_MODE=patient or APP_MODE=therapist.';
    // print (not debugPrint) so it is visible in release logcat too.
    // ignore: avoid_print
    print(msg);
    assert(false, msg);
  }
}
