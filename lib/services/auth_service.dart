import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/patient.dart';
import 'backend_api_service.dart';
import 'database_service.dart';
import 'push_token_service.dart';
import 'role_service.dart';
import 'token_service.dart';
import 'wearable_sync_service.dart';

/// Outcome of a login / signup attempt.
class AuthOutcome {
  final bool success;
  final String? message;
  final String? code;
  final String? role;
  final RoleDestination? destination;

  const AuthOutcome({
    required this.success,
    this.message,
    this.code,
    this.role,
    this.destination,
  });

  factory AuthOutcome.error(String message, {String? code}) =>
      AuthOutcome(success: false, message: message, code: code);
}

/// Firebase Authentication wrapper.
///
/// * Identity = FirebaseAuth only (no local/offline fake sessions).
/// * Role = custom claim `role` via [RoleService] only. Client-written
///   Firestore fields (e.g. `users/{uid}.role`) are NEVER used for routing.
/// * `users/{uid}` server-owned fields (role, therapistId, ...) are never
///   written by the client; registration goes through callables.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  late final FirebaseAuth _auth = FirebaseAuth.instance;
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();
  final BackendApiService _backendApi = BackendApiService();
  final TokenService _tokenService = TokenService();
  final RoleService _roles = RoleService.instance;
  SharedPreferences? _prefs;

  String? _currentRole;
  Map<String, dynamic>? _cachedUserData;
  bool _loggingOut = false;

  /// True while [logout] is running (the caller handles navigation).
  bool get isLoggingOut => _loggingOut;

  Future<SharedPreferences> get _sp async => _prefs ??= await SharedPreferences.getInstance();

  /// Restores state for a persisted Firebase session. Never throws.
  Future<void> init() async {
    try {
      final prefs = await _sp;
      // Remove legacy offline "local session" data from older builds; it
      // allowed acting as a user without Firebase credentials.
      await prefs.remove('local_auth_session');
      await prefs.remove('local_auth_accounts');
    } catch (e) {
      debugPrint('[AuthService] prefs unavailable: $e');
    }

    final user = _auth.currentUser;
    if (user == null) {
      _currentRole = null;
      _cachedUserData = null;
      return;
    }
    _currentRole = await _roles.fetchRoleBestEffort();
    await refreshProfile();
    unawaited(_syncBackendToken(
      uid: user.uid,
      name: _cachedUserData?['name']?.toString(),
      role: _currentRole,
    ));
  }

  String? get currentUserId => _auth.currentUser?.uid;

  /// Role from the custom claim (null when signed out / not registered).
  String? get currentRole => _auth.currentUser == null ? null : _currentRole;

  bool get isAuthenticated => _auth.currentUser != null;

  /// Cached profile map: {id, email, name, role, therapistId?, therapistName?}.
  /// `role` here is the CLAIM role, never the Firestore field.
  Map<String, dynamic>? getCurrentUser() => _cachedUserData;

  /// Re-reads the role claim (forced refresh when online).
  Future<String?> refreshRole() async {
    _currentRole = await _roles.fetchRoleBestEffort();
    if (_cachedUserData != null) {
      _cachedUserData = {..._cachedUserData!, 'role': _currentRole};
    }
    return _currentRole;
  }

  /// Reloads `users/{uid}` into the cache. Never throws.
  Future<Map<String, dynamic>?> refreshProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    Map<String, dynamic> data = const {};
    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));
      data = doc.data() ?? const {};
    } catch (e) {
      debugPrint('[AuthService] could not load users/${user.uid}: $e');
      if (_cachedUserData != null && _cachedUserData!['id'] == user.uid) {
        return _cachedUserData;
      }
    }
    final rawName = data['name'];
    final therapistId = data['therapistId'];
    final therapistName = data['therapistName'];
    _cachedUserData = {
      'id': user.uid,
      'email': user.email ?? '',
      'name': (rawName is String && rawName.trim().isNotEmpty)
          ? rawName.trim()
          : (user.displayName ?? (user.email ?? '').split('@').first),
      'role': _currentRole,
      if (therapistId is String && therapistId.isNotEmpty) 'therapistId': therapistId,
      if (therapistName is String && therapistName.isNotEmpty) 'therapistName': therapistName,
    };
    return _cachedUserData;
  }

  /// Authoritative `users/{uid}.therapistId` (server-owned). Returns null if
  /// the patient is not linked or the doc cannot be read. Awaits a server
  /// read, falling back to Firestore's offline cache.
  Future<String?> loadTherapistId() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final ref = _firestore.collection('users').doc(uid);
    try {
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await ref.get().timeout(const Duration(seconds: 8));
      } catch (_) {
        doc = await ref.get(const GetOptions(source: Source.cache));
      }
      final t = doc.data()?['therapistId'];
      if (t is String && t.trim().isNotEmpty) {
        if (_cachedUserData != null) {
          _cachedUserData = {..._cachedUserData!, 'therapistId': t};
        }
        return t;
      }
      return null;
    } catch (e) {
      debugPrint('[AuthService] loadTherapistId failed: $e');
      final cached = _cachedUserData?['therapistId'];
      return cached is String && cached.isNotEmpty ? cached : null;
    }
  }

  /// Exchange the Firebase session for a backend JWT (AI chat / ML only).
  Future<void> _syncBackendToken({required String uid, String? name, String? role}) async {
    try {
      final firebaseUser = _auth.currentUser;
      final idToken = await firebaseUser?.getIdToken();
      if (firebaseUser == null || firebaseUser.uid != uid || idToken == null) {
        await _tokenService.clearToken();
        return;
      }
      final result = await _backendApi.firebaseSync(idToken: idToken, name: name, role: role);
      if (result['success'] != true) await _tokenService.clearToken();
    } catch (_) {
      await _tokenService.clearToken();
    }
  }

  /// Steps performed after any successful sign-in / registration: read the
  /// claim, enforce the app/role match (sign out on mismatch), warm caches.
  Future<AuthOutcome> _completeSignIn() async {
    final user = _auth.currentUser;
    if (user == null) return AuthOutcome.error('Sign-in failed. Please try again.');

    String? role;
    try {
      role = await _roles.fetchRole(forceRefresh: true).timeout(const Duration(seconds: 15));
    } catch (_) {
      role = await _roles.fetchRoleBestEffort();
    }
    _currentRole = role;
    final destination = _roles.destinationFor(role);

    if (destination == RoleDestination.wrongApp) {
      final msg = _roles.wrongAppMessage(role);
      await logout();
      return AuthOutcome(
        success: false,
        message: msg,
        code: 'wrong-app',
        role: role,
        destination: destination,
      );
    }

    await refreshProfile();
    if (role == AppRoles.patient) {
      if (!kIsWeb) {
        await _ensurePatientProfile(
          userId: user.uid,
          email: user.email ?? '',
          name: _cachedUserData?['name']?.toString() ?? '',
        );
      }
      unawaited(WearableSyncService().startForCurrentPatient());
    }
    unawaited(_syncBackendToken(
      uid: user.uid,
      name: _cachedUserData?['name']?.toString(),
      role: role,
    ));
    return AuthOutcome(success: true, role: role, destination: destination);
  }

  /// Login with email and password, then verify the role claim matches this
  /// app. On mismatch the user is signed out and an error is returned.
  Future<AuthOutcome> login({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return await _completeSignIn();
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] login failed: ${e.code}');
      return AuthOutcome.error(_authMessage(e), code: e.code);
    } catch (e) {
      debugPrint('[AuthService] login failed: $e');
      return AuthOutcome.error('Sign-in failed. Check your connection and try again.');
    }
  }

  /// Creates the Firebase account and registers it as a patient of the
  /// therapist who owns [inviteCode] (callable `registerPatient`).
  Future<AuthOutcome> signupPatient({
    required String email,
    required String password,
    required String name,
    required String inviteCode,
  }) {
    return _signupWith(
      email: email,
      password: password,
      name: name,
      register: () => _roles.registerPatient(name: name, inviteCode: inviteCode),
    );
  }

  /// Creates the Firebase account and requests therapist registration
  /// (callable `registerTherapist`; claim becomes `therapist_pending`).
  Future<AuthOutcome> signupTherapist({
    required String email,
    required String password,
    required String name,
    String? licenseNumber,
    String? specialty,
  }) {
    return _signupWith(
      email: email,
      password: password,
      name: name,
      register: () => _roles.registerTherapist(
        name: name,
        licenseNumber: licenseNumber,
        specialty: specialty,
      ),
    );
  }

  Future<AuthOutcome> _signupWith({
    required String email,
    required String password,
    required String name,
    required Future<CallableResult> Function() register,
  }) async {
    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      return AuthOutcome.error(_authMessage(e), code: e.code);
    } catch (e) {
      return AuthOutcome.error('Could not create the account. Check your connection and try again.');
    }

    try {
      await credential.user?.updateDisplayName(name);
    } catch (_) {}

    final result = await register();
    if (!result.success) {
      if (result.isNetworkError) {
        // Keep the account; the next sign-in routes to "complete registration".
        return AuthOutcome(
          success: false,
          code: 'registration-incomplete',
          message: '${result.message} Your account was created - sign in again to finish registration.',
        );
      }
      // Server rejected (e.g. bad invite code): delete the orphan account so
      // the email can be reused, then sign out.
      try {
        await credential.user?.delete();
      } catch (e) {
        debugPrint('[AuthService] could not delete orphan account: $e');
      }
      await logout();
      return AuthOutcome.error(result.message ?? 'Registration failed.', code: result.code);
    }
    return _completeSignIn();
  }

  /// For an already signed-in account that has no role claim yet.
  Future<AuthOutcome> completePatientRegistration({required String name, required String inviteCode}) async {
    final r = await _roles.registerPatient(name: name, inviteCode: inviteCode);
    if (!r.success) return AuthOutcome.error(r.message ?? 'Registration failed.', code: r.code);
    return _completeSignIn();
  }

  Future<AuthOutcome> completeTherapistRegistration({
    required String name,
    String? licenseNumber,
    String? specialty,
  }) async {
    final r = await _roles.registerTherapist(name: name, licenseNumber: licenseNumber, specialty: specialty);
    if (!r.success) return AuthOutcome.error(r.message ?? 'Registration failed.', code: r.code);
    return _completeSignIn();
  }

  /// Patient switches/links therapist via invite code (callable `joinTherapist`).
  Future<CallableResult> joinTherapist(String inviteCode) async {
    final r = await _roles.joinTherapist(inviteCode: inviteCode);
    if (r.success) {
      await refreshProfile();
      // Restart wearable sync so new vitals carry the new therapistId.
      try {
        await WearableSyncService().stop();
        await WearableSyncService().startForCurrentPatient();
      } catch (e) {
        debugPrint('[AuthService] wearable restart failed: $e');
      }
    }
    return r;
  }

  /// Password recovery via Firebase email link. Unknown emails get the same
  /// neutral message to avoid account enumeration.
  Future<AuthOutcome> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email' ||
          e.code == 'network-request-failed' ||
          e.code == 'too-many-requests') {
        return AuthOutcome.error(_authMessage(e), code: e.code);
      }
      // user-not-found etc.: fall through to the neutral message.
    } catch (e) {
      return AuthOutcome.error('Could not send the email. Check your connection and try again.');
    }
    return const AuthOutcome(
      success: true,
      message: 'If an account exists for that email, a password reset link has been sent. '
          'Check your inbox and spam folder.',
    );
  }

  /// Update the user's display name (client-writable `name` field).
  Future<Map<String, dynamic>?> updateDisplayName(String newName) async {
    final name = newName.trim();
    if (name.length < 2) return null;
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      await _firestore.collection('users').doc(uid).update({'name': name});
    } catch (e) {
      debugPrint('Firestore name update failed: $e');
    }
    try {
      await _auth.currentUser?.updateDisplayName(name);
    } catch (_) {}
    if (_cachedUserData != null) {
      _cachedUserData = {..._cachedUserData!, 'name': name};
    }
    if (!kIsWeb && _currentRole == AppRoles.patient) {
      try {
        final existing = await _dbService.getPatient(uid);
        if (existing != null) await _dbService.updatePatient(existing.copyWith(name: name));
      } catch (e) {
        debugPrint('SQLite name update failed: $e');
      }
    }
    try {
      await _backendApi.updateMyName(name);
    } catch (e) {
      debugPrint('Backend name update failed: $e');
    }
    return _cachedUserData;
  }

  /// Logout: unregister this device's push token and stop wearable sync
  /// BEFORE signing out (both need the user's credentials to pass rules).
  Future<void> logout() async {
    _loggingOut = true;
    try {
      await _logout();
    } finally {
      _loggingOut = false;
    }
  }

  Future<void> _logout() async {
    try {
      await PushTokenService.unregister();
    } catch (e) {
      debugPrint('[AuthService] push unregister failed: $e');
    }
    try {
      await WearableSyncService().stop();
    } catch (e) {
      debugPrint('[AuthService] wearable stop failed: $e');
    }
    try {
      final prefs = await _sp;
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('last_assessment_') ||
            key.startsWith('privacy_') ||
            key.startsWith('cached_user_') ||
            key == 'chat_last_open_thread' ||
            key == 'current_role' ||
            key == 'local_auth_session' ||
            key == 'local_auth_accounts') {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('[AuthService] prefs cleanup failed: $e');
    }
    _currentRole = null;
    _cachedUserData = null;
    try {
      await _tokenService.clearToken();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Sign-out error (continuing local logout): $e');
    }
  }

  /// Delete the Firebase account (requires a recent login). Server-side
  /// cleanup of `users/{uid}` is the backend's responsibility (clients may
  /// not delete server-owned docs).
  Future<bool> deleteAccount(String email) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      await PushTokenService.unregister();
    } catch (_) {}
    try {
      await WearableSyncService().stop();
    } catch (_) {}
    try {
      await user.delete();
    } catch (e) {
      debugPrint('[AuthService] account delete failed: $e');
      return false;
    }
    _currentRole = null;
    _cachedUserData = null;
    try {
      await _tokenService.clearToken();
      final prefs = await _sp;
      await prefs.remove('current_role');
    } catch (_) {}
    return true;
  }

  Future<void> _ensurePatientProfile({
    required String userId,
    required String email,
    required String name,
  }) async {
    if (kIsWeb) return;
    try {
      final existing = await _dbService.getPatient(userId);
      final now = DateTime.now();
      if (existing != null) {
        await _dbService.updatePatient(existing.copyWith(name: name, email: email));
        return;
      }
      // Local on-device cache row only (used by on-device ML history).
      await _dbService.insertPatient(Patient(
        id: userId,
        name: name,
        email: email,
        age: 0,
        currentRiskScore: 0.0,
        riskScore: 0.0,
        wellbeingScore: 50.0,
        lastUpdated: now.toIso8601String(),
        createdAt: now,
        lastCheckIn: now,
      ));
    } catch (_) {
      // Keep auth flow responsive even if local profile sync fails.
    }
  }

  String _authMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your clinic.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for this email. Sign in instead.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Please try again when online.';
      default:
        return e.message ?? 'Authentication failed (${e.code}).';
    }
  }
}
