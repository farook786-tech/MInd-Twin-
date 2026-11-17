import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import 'backend_api_service.dart';

/// Roles as defined in docs/DATA_MODEL.md. The ONLY trusted source of a
/// user's role is the Firebase Auth custom claim `role`, set server-side (by
/// the MindTwin server's /api/callable endpoints, or by Cloud Functions on
/// the Blaze plan). Client-written Firestore fields are never consulted.
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

  /// True when the failure is (probably) transient - connectivity, server
  /// not running, rate limit, outdated server, or a sign-in token the server
  /// could not accept (e.g. clock skew) - as opposed to the server rejecting
  /// the request itself. Callers keep the account and let the user retry.
  bool get isNetworkError =>
      code == 'unavailable' ||
      code == 'unauthenticated' ||
      code == 'deadline-exceeded' ||
      code == 'internal-network' ||
      code == 'resource-exhausted' ||
      code == 'unimplemented';
}

class RoleService {
  RoleService._();
  static final RoleService instance = RoleService._();

  static const Duration _callTimeout = Duration(seconds: 30);

  /// A sleeping free Render instance needs up to about a minute to wake up.
  static const Duration _coldStartTimeout = Duration(seconds: 75);

  /// Build-time server URL (--dart-define=MINDTWIN_API_BASE_URL=https://...).
  static const String _buildTimeBaseUrl =
      String.fromEnvironment('MINDTWIN_API_BASE_URL', defaultValue: '');

  /// Shown whenever the MindTwin server (laptop / Render) cannot be reached.
  static const String serverUnreachableMessage =
      'MindTwin server is not reachable — make sure the clinic server is running.';

  BackendApiService? _backendApi;
  BackendApiService get _backend => _backendApi ??= BackendApiService();

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

  /// Calls `POST <server>/api/callable/<name>` with the Firebase ID token.
  /// Retries once on a connection failure and once with a refreshed token
  /// when the server reports an expired session.
  Future<CallableResult> _call(
    String name,
    Map<String, dynamic> data, {
    bool refreshClaims = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return CallableResult.fail('Please sign in first.', code: 'unauthenticated');
    }

    _CallOutcome outcome = await _post(user, name, data, forceTokenRefresh: false);
    if (outcome.connectionFailed) {
      await Future<void>.delayed(const Duration(seconds: 1));
      outcome = await _post(user, name, data, forceTokenRefresh: false);
    } else if (outcome.code == 'unauthenticated') {
      outcome = await _post(user, name, data, forceTokenRefresh: true);
    }

    final code = outcome.code;
    if (code == null) {
      if (refreshClaims) {
        // Contract: force-refresh the ID token after any claim-changing call
        // before touching Firestore again.
        try {
          await fetchRole(forceRefresh: true);
        } catch (e) {
          debugPrint('[RoleService] token refresh after $name failed: $e');
        }
      }
      return CallableResult.ok(outcome.data);
    }
    debugPrint('[RoleService] $name failed: $code ${outcome.message ?? ''}');
    return CallableResult.fail(_messageFor(name, code, outcome.message), code: code);
  }

  Future<_ServerUrl?> _serverUrl() async {
    String? resolved;
    try {
      resolved = await _backend.resolveBaseUrl();
    } catch (e) {
      debugPrint('[RoleService] server discovery failed: $e');
    }
    if (resolved != null && resolved.isNotEmpty) return _ServerUrl(resolved, coldStart: false);
    // A free Render instance that is asleep fails the quick /health probe;
    // call it anyway with a long timeout - Render wakes it on the request.
    final built = _buildTimeBaseUrl.trim();
    if (built.startsWith('https://')) {
      return _ServerUrl(built.endsWith('/') ? built.substring(0, built.length - 1) : built,
          coldStart: true);
    }
    return null;
  }

  Future<_CallOutcome> _post(
    User user,
    String name,
    Map<String, dynamic> data, {
    required bool forceTokenRefresh,
  }) async {
    final server = await _serverUrl();
    if (server == null) return const _CallOutcome.connectionFailure();

    String? idToken;
    try {
      idToken = await user.getIdToken(forceTokenRefresh);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') return const _CallOutcome.connectionFailure();
      return const _CallOutcome.error('unauthenticated', null);
    } catch (_) {
      return const _CallOutcome.connectionFailure();
    }
    if (idToken == null || idToken.isEmpty) return const _CallOutcome.error('unauthenticated', null);

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${server.baseUrl}/api/callable/$name'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(server.coldStart ? _coldStartTimeout : _callTimeout);
    } on TimeoutException {
      return const _CallOutcome.error('deadline-exceeded', null);
    } on SocketException {
      return const _CallOutcome.connectionFailure();
    } on http.ClientException {
      return const _CallOutcome.connectionFailure();
    } on FormatException {
      return const _CallOutcome.connectionFailure();
    }

    Object? body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      body = null;
    }
    if (response.statusCode == 200 && body is Map && body.containsKey('data')) {
      final raw = body['data'];
      return _CallOutcome.success(raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
    }
    final error = body is Map ? body['error'] : null;
    if (error is Map && error['code'] is String) {
      final message = error['message'];
      return _CallOutcome.error(error['code'] as String, message is String ? message : null);
    }
    // No MindTwin error envelope: another service on that address, or a
    // backend version without /api/callable.
    switch (response.statusCode) {
      case 401:
        return const _CallOutcome.error('unauthenticated', null);
      case 429:
        return const _CallOutcome.error('resource-exhausted', null);
      case 404:
        return const _CallOutcome.error('unimplemented', null);
      default:
        return const _CallOutcome.error('unavailable', null);
    }
  }

  String _messageFor(String name, String code, String? serverMessage) {
    final message = (serverMessage != null && serverMessage.isNotEmpty) ? serverMessage : null;
    switch (code) {
      case 'not-found':
        return name == 'getMyInviteCode'
            ? 'No invite code is available yet.'
            : 'That invite code was not found or is no longer active. Ask your therapist for a new code.';
      case 'invalid-argument':
        return message ?? 'Some details are invalid.';
      case 'permission-denied':
        return name == 'getMyInviteCode'
            ? 'Your therapist account has not been approved yet.'
            : 'You are not allowed to do this with this account.';
      case 'failed-precondition':
        return message ?? 'This account is not in the right state for this action.';
      case 'already-exists':
        return message ?? 'This account is already registered.';
      case 'unauthenticated':
        return 'Your session expired. Please sign in again.';
      case 'resource-exhausted':
        return 'Too many attempts. Please wait a minute and try again.';
      case 'unimplemented':
        return 'The MindTwin server at the clinic needs to be updated. Please contact the clinic.';
      case 'internal-network':
        return serverUnreachableMessage;
      case 'unavailable':
        return message ?? serverUnreachableMessage;
      case 'deadline-exceeded':
        return 'The MindTwin server did not respond in time. Check your connection and try again.';
      default:
        return 'Something went wrong ($code). Please try again.';
    }
  }
}

class _ServerUrl {
  final String baseUrl;
  final bool coldStart;
  const _ServerUrl(this.baseUrl, {required this.coldStart});
}

/// Result of one HTTP attempt. [code] is null on success.
class _CallOutcome {
  final Map<String, dynamic> data;
  final String? code;
  final String? message;
  final bool connectionFailed;

  const _CallOutcome.success(this.data)
      : code = null,
        message = null,
        connectionFailed = false;

  const _CallOutcome.error(this.code, this.message)
      : data = const {},
        connectionFailed = false;

  /// Server not found or connection refused/reset (safe to retry).
  const _CallOutcome.connectionFailure()
      : data = const {},
        code = 'unavailable',
        message = null,
        connectionFailed = true;
}
