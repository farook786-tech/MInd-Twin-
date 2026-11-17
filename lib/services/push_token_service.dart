import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import 'auth_service.dart';

/// Keeps `fcm_tokens/{token}` in sync with the signed-in user
/// (docs/DATA_MODEL.md): `{uid, platform: 'android'|'ios',
/// app: 'patient'|'therapist', updatedAt}`.
///
/// * Registers automatically whenever FirebaseAuth reports a signed-in user
///   (including an already-signed-in user at app start), independent of the
///   order in which main.dart initialises services.
/// * Re-registers on `onTokenRefresh`.
/// * [unregister] MUST be called BEFORE `FirebaseAuth.signOut()` (the delete
///   needs the user's credentials to pass security rules).
class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  static const Duration _netTimeout = Duration(seconds: 15);

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _refreshSub;
  String? _appOverride;
  String? _registeredToken;
  String? _registeredUid;
  bool _suspended = false; // true while logging out
  Future<void> _queue = Future<void>.value();

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Register this device's token for the current user. [app] is
  /// 'patient' or 'therapist'; when omitted it is derived from APP_MODE or
  /// the user's role claim. Also starts the auth/token-refresh listeners.
  static Future<void> registerForCurrentUser({String? app}) =>
      instance._registerForCurrentUser(app: app);

  /// Delete this device's token document and invalidate the FCM token.
  /// Call before signing out. Never throws; bounded by timeouts so logout is
  /// not blocked when offline.
  static Future<void> unregister() => instance._unregister();

  /// Start listening to auth changes and token refreshes (idempotent).
  /// Called by FCMService.initialize().
  void start({String? app}) {
    if (app != null) _appOverride = app;
    if (!isSupported || Firebase.apps.isEmpty) return;

    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        _registeredToken = null;
        _registeredUid = null;
        _suspended = false; // logout finished; allow the next login
        return;
      }
      if (_suspended) return;
      _enqueue(() => _register(user));
    });

    _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null || _suspended) return;
        _enqueue(() => _register(user));
      },
      onError: (Object e) => debugPrint('onTokenRefresh error: $e'),
    );
  }

  Future<void> _registerForCurrentUser({String? app}) {
    if (app != null) _appOverride = app;
    if (!isSupported || Firebase.apps.isEmpty) return Future.value();
    start();
    _suspended = false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Future.value();
    return _enqueue(() => _register(user));
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((Object e) {
      debugPrint('PushTokenService: $e');
    });
    _queue = next;
    return next;
  }

  Future<void> _register(User user) async {
    if (_suspended || FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return;
    }
    final messaging = FirebaseMessaging.instance;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // On iOS the FCM token is only available once APNs has issued one.
      String? apns;
      for (var i = 0; i < 10 && apns == null; i++) {
        apns = await messaging.getAPNSToken();
        if (apns == null) await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (apns == null) {
        debugPrint('PushTokenService: APNs token unavailable; will retry on '
            'token refresh / next login');
        return;
      }
    }

    var token = await messaging.getToken();
    if (token == null || token.isEmpty) return;
    final app = await _resolveApp(user);

    try {
      await _writeToken(token, user.uid, app);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      // The token doc still belongs to a previous user of this device (they
      // never unregistered). Rotate the token so pushes for the old account
      // stop reaching this device, then register the fresh one.
      await messaging.deleteToken();
      token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _writeToken(token, user.uid, app);
    }

    final previous = _registeredToken;
    if (previous != null && previous != token && _registeredUid == user.uid) {
      unawaited(_deleteTokenDoc(previous));
    }
    _registeredToken = token;
    _registeredUid = user.uid;
  }

  Future<void> _writeToken(String token, String uid, String app) async {
    final write = FirebaseFirestore.instance
        .collection('fcm_tokens')
        .doc(token)
        .set({
      'uid': uid,
      'platform':
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'app': app,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    try {
      await write.timeout(_netTimeout);
    } on TimeoutException {
      // Offline: the write stays queued in Firestore and is sent on
      // reconnect. Surface rule failures later in the log.
      unawaited(write.catchError(
          (Object e) => debugPrint('Deferred fcm token write failed: $e')));
    }
  }

  Future<void> _deleteTokenDoc(String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('fcm_tokens')
          .doc(token)
          .delete()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('PushTokenService: could not delete token doc: $e');
    }
  }

  Future<String> _resolveApp(User user) async {
    final override = _appOverride;
    if (override == 'patient' || override == 'therapist') return override!;
    if (AppConfig.isTherapistOnlyMode) return 'therapist';
    if (AppConfig.isPatientOnlyMode) return 'patient';
    String? role;
    try {
      final result = await user.getIdTokenResult();
      role = result.claims?['role']?.toString();
    } catch (_) {
      role = AuthService().currentRole;
    }
    return (role ?? '').startsWith('therapist') ? 'therapist' : 'patient';
  }

  Future<void> _unregister() async {
    if (!isSupported || Firebase.apps.isEmpty) return;
    _suspended = true;
    try {
      await _queue.timeout(const Duration(seconds: 5));
    } catch (_) {}

    final messaging = FirebaseMessaging.instance;
    var token = _registeredToken;
    if (token == null) {
      try {
        token = await messaging.getToken().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    if (token != null && FirebaseAuth.instance.currentUser != null) {
      await _deleteTokenDoc(token);
    }
    try {
      // Invalidates the token server-side so nothing addressed to the old
      // account can reach this device even if the doc delete was queued.
      await messaging.deleteToken().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('PushTokenService: deleteToken failed: $e');
    }
    _registeredToken = null;
    _registeredUid = null;
    // _suspended is reset by the auth listener once sign-out completes, or
    // by an explicit registerForCurrentUser().
    if (_authSub == null) _suspended = false;
  }
}
