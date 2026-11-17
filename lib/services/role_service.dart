import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';

/// Roles as defined in docs/DATA_MODEL.md. The ONLY trusted source of a
/// user's role is the Firebase Auth custom claim `role`, set server-side by
/// Cloud Functions. Client-written Firestore fields are never consulted.
class AppRoles {
  static const String patient = 'patient';
  static const String therapist = 'therapist';
  static const String therapistPending = 'therapist_pending';
}

/// Where a signed-in user must be sent in THIS build.
enum RoleDestination {
  /// Approved patient in the patient (or debug unified) app.
  patientHome,

  /// Approved therapist in the therapist (or debug unified) app.
  therapistHome,

  /// Therapist signed up but not yet approved by an admin.
  therapistPending,

  /// Signed in but no role claim yet (signup interrupted before the
  /// registration callable succeeded). Must finish registration.
  completeRegistration,

  /// The account's role is not served by this build (e.g. a patient
  /// logging into the therapist app). Must be signed out.
  wrongApp,
}

/// Human-readable result of a callable, with a message safe to show users.
class CallableResult {
  final bool success;
  final Map<String, dynamic> data;
  final String? message;
  final String? code;

  const CallableResult._(this.success, this.data, this.message, this.code);

  factory CallableResult.ok(Map<String, dynamic> data) =>
      CallableResult._(true, data, null, null);

  factory CallableResult.fail(String message, {String? code}) =>
      CallableResult._(false, const {}, message, code);

  /// True when the failure is (probably) transient connectivity, as opposed
  /// to the server rejecting the request.
  bool get isNetworkError =>
      code == 'unavailable' || code == 'deadline-exceeded' || code == 'internal-network';
}

class RoleService {
  RoleService._();
  static final RoleService instance = RoleService._();

  static const Duration _callTimeout = Duration(seconds: 30);

  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'us-central1');

  String? _cachedRole;
  String? _cachedRoleUid;

  /// Last role read from the ID token for the current user (may be null).
  String? get cachedRole {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != _cachedRoleUid) return null;
    return _cachedRole;
  }

  bool get isTherapistApp => AppConfig.isTherapistOnlyMode;

  /// Reads the `role` custom claim. [forceRefresh] fetches a fresh ID token
  /// from the server (required after any callable that changes claims).
  /// Returns null when signed out or when the account has no role yet.
  /// Throws [FirebaseAuthException] on network failure with forceRefresh;
  /// callers decide how to handle it.
  Future<String?> fetchRole({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _cachedRole = null;
      _cachedRoleUid = null;
      return null;
    }
    final result = await user.getIdTokenResult(forceRefresh);
    final raw = result.claims?['role'];
    final role = raw is String && raw.isNotEmpty ? raw : null;
    _cachedRole = role;
    _cachedRoleUid = user.uid;
    return role;
  }

  /// Like [fetchRole] but tries a forced refresh first and falls back to the
  /// cached (possibly stale) token when offline. Stale claims are acceptable
  /// for routing only: Firestore rules re-check the claim on every request.
  Future<String?> fetchRoleBestEffort() async {
    try {
      return await fetchRole(forceRefresh: true).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[RoleService] forced token refresh failed, using cached token: $e');
      try {
        return await fetchRole(forceRefresh: false);
      } catch (e2) {
        debugPrint('[RoleService] cached token unavailable: $e2');
        return cachedRole;
      }
    }
  }

  /// Decides where [role] may go in this build. Pure function of the role
  /// and the compile-time APP_MODE.
  RoleDestination destinationFor(String? role) {
    if (role == null) return RoleDestination.completeRegistration;
    final patientApp = AppConfig.patientAccessEnabled;
    final therapistApp = AppConfig.therapistAccessEnabled;
    switch (role) {
      case AppRoles.patient:
        return patientApp ? RoleDestination.patientHome : RoleDestination.wrongApp;
      case AppRoles.therapist:
        return therapistApp ? RoleDestination.therapistHome : RoleDestination.wrongApp;
      case AppRoles.therapistPending:
        return therapistApp ? RoleDestination.therapistPending : RoleDestination.wrongApp;
      default:
        // Unknown role (e.g. a future 'admin' role string): never guess.
        return RoleDestination.wrongApp;
    }
  }

  /// Message shown when [role] cannot use this build.
  String wrongAppMessage(String? role) {
    if (role == AppRoles.patient) {
      return 'This is a patient account. Please use the MindTwin Patient app.';
    }
    if (role == AppRoles.therapist || role == AppRoles.therapistPending) {
      return 'This is a therapist account. Please use the MindTwin Therapist app.';
    }
    return 'This account cannot be used with this app. Contact your clinic.';
  }

  // ---------------------------------------------------------------------------
  // Callables (docs/DATA_MODEL.md)
  // ---------------------------------------------------------------------------

  Future<CallableResult> registerPatient({
    required String name,
    required String inviteCode,
  }) =>
      _call('registerPatient', {'name': name, 'inviteCode': normalizeInviteCode(inviteCode)},
          refreshClaims: true);

  Future<CallableResult> registerTherapist({
    required String name,
    String? licenseNumber,
    String? specialty,
  }) =>
      _call(
        'registerTherapist',
        {
          'name': name,
          if (licenseNumber != null && licenseNumber.isNotEmpty) 'licenseNumber': licenseNumber,
          if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        },
        refreshClaims: true,
      );

  Future<CallableResult> joinTherapist({required String inviteCode}) =>
      _call('joinTherapist', {'inviteCode': normalizeInviteCode(inviteCode)},
          refreshClaims: true);

  Future<CallableResult> getMyInviteCode() => _call('getMyInviteCode', const {});

  static String normalizeInviteCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  Future<CallableResult> _call(
    String name,
    Map<String, dynamic> data, {
    bool refreshClaims = false,
  }) async {
    try {
      final result = await _functions.httpsCallable(name).call<dynamic>(data).timeout(_callTimeout);
      final raw = result.data;
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (refreshClaims) {
        // Contract: force-refresh the ID token after any claim-changing call
        // before touching Firestore again.
        try {
          await fetchRole(forceRefresh: true);
        } catch (e) {
          debugPrint('[RoleService] token refresh after $name failed: $e');
        }
      }
      return CallableResult.ok(map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[RoleService] $name failed: ${e.code} ${e.message}');
      return CallableResult.fail(_messageFor(name, e), code: e.code);
    } on TimeoutException {
      return CallableResult.fail(
        'The server did not respond. Check your connection and try again.',
        code: 'deadline-exceeded',
      );
    } catch (e) {
      debugPrint('[RoleService] $name failed: $e');
      return CallableResult.fail(
        'Could not reach the server. Check your connection and try again.',
        code: 'internal-network',
      );
    }
  }

  String _messageFor(String name, FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return name == 'getMyInviteCode'
            ? 'No invite code is available yet.'
            : 'That invite code was not found or is no longer active. Ask your therapist for a new code.';
      case 'invalid-argument':
        return e.message?.isNotEmpty == true ? e.message! : 'Some details are invalid.';
      case 'permission-denied':
        return name == 'getMyInviteCode'
            ? 'Your therapist account has not been approved yet.'
            : 'You are not allowed to do this with this account.';
      case 'failed-precondition':
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'This account is not in the right state for this action.';
      case 'already-exists':
        return e.message?.isNotEmpty == true ? e.message! : 'This account is already registered.';
      case 'unauthenticated':
        return 'Your session expired. Please sign in again.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The server is unreachable. Check your connection and try again.';
      default:
        return 'Something went wrong (${e.code}). Please try again.';
    }
  }
}
