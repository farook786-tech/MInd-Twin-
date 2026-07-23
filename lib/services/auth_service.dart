import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/patient.dart';
import 'database_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseService _dbService = DatabaseService();
  late SharedPreferences _prefs;
  String? _currentRole;
  String? _localUserId;
  Map<String, dynamic>? _cachedUserData;
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _localAccounts = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadLocalAccounts();

    final storedSession = _prefs.getString('local_auth_session');
    if (storedSession != null) {
      try {
        final session = jsonDecode(storedSession) as Map<String, dynamic>;
        _localUserId = session['id']?.toString();
        _currentRole = session['role']?.toString();
        _cachedUserData = session;
        if (_localUserId != null) {
          _userCache[_localUserId!] = _cachedUserData!;
        }
      } catch (_) {}
    }

    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          _currentRole = data['role'] as String?;
          _cachedUserData = _buildUserMap(user.uid, data);
          _userCache[user.uid] = _cachedUserData!;
          _localUserId = null;
        }
      } else {
        if (_localUserId == null) {
          _currentRole = null;
          _cachedUserData = null;
        }
      }
    } catch (_) {
      // Firebase unavailable or offline — use local cache/session if present.
      if (_localUserId == null) {
        _currentRole = _prefs.getString('current_role') ?? _currentRole;
        final cached = _prefs.getString('local_auth_session');
        if (cached != null) {
          try {
            _cachedUserData = jsonDecode(cached) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
    }
  }

  String? get currentUserId => _auth.currentUser?.uid ?? _localUserId;
  String? get currentRole => _currentRole;
  bool get isAuthenticated => _auth.currentUser != null || _localUserId != null;

  Map<String, dynamic> _buildUserMap(String uid, Map<String, dynamic> data) {
    return {
      'id': uid,
      'email': data['email'] ?? '',
      'name': data['name'] ?? '',
      'role': data['role'] ?? '',
      'createdAt': _timestampToString(data['createdAt']),
      'lastLogin': _timestampToString(data['lastLogin']),
      if (data['therapistId'] != null) 'therapistId': data['therapistId'],
      if (data['assignedTherapist'] != null) 'assignedTherapist': data['assignedTherapist'],
    };
  }

  String _timestampToString(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is String) return value;
    return DateTime.now().toIso8601String();
  }

  Future<void> _cacheLocally(String uid, Map<String, dynamic> userData) async {
    await _prefs.setString('current_role', userData['role'] ?? '');
    await _prefs.setString('cached_user_$uid', jsonEncode(userData));
    await _prefs.setString('local_auth_session', jsonEncode(userData));
  }

  void _loadLocalAccounts() {
    final raw = _prefs.getString('local_auth_accounts');
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _localAccounts[entry.key] = value;
            final uid = value['id']?.toString();
            if (uid != null) {
              _userCache[uid] = value;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLocalAccounts() async {
    await _prefs.setString('local_auth_accounts', jsonEncode(_localAccounts));
  }

  Future<Map<String, dynamic>> _signupLocal({
    required String email,
    required String password,
    required String name,
    required String role,
    List<String>? securityQuestions,
    List<String>? securityAnswers,
    String? therapistId,
    String? assignedTherapist,
  }) async {
    final emailKey = email.toLowerCase().trim();
    if (_localAccounts.containsKey(emailKey)) {
      return {'success': false, 'message': 'An account with this email already exists'};
    }

    final uid = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toIso8601String();
    final hashedAnswers = securityAnswers
            ?.map((a) => sha256.convert(utf8.encode(a.toLowerCase().trim())).toString())
            .toList() ??
        [];

    final userData = {
      'id': uid,
      'email': email,
      'name': name,
      'role': role,
      'createdAt': now,
      'lastLogin': now,
      'securityQuestions': securityQuestions ?? [],
      'securityAnswers': hashedAnswers,
      if (therapistId != null) 'therapistId': therapistId,
      if (assignedTherapist != null) 'assignedTherapist': assignedTherapist,
      'authProvider': 'local',
    };

    _localAccounts[emailKey] = {
      ...userData,
      'password': password,
    };
    _userCache[uid] = userData;
    _currentRole = role;
    _localUserId = uid;
    _cachedUserData = userData;
    await _saveLocalAccounts();
    await _cacheLocally(uid, userData);

    if (role == 'patient' && !kIsWeb) {
      await _ensurePatientProfile(userId: uid, email: email, name: name);
    }

    return {
      'success': true,
      'userId': uid,
      'role': role,
      'token': 'local-session-token',
    };
  }

  /// Signup with email and password
  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String name,
    required String role, // 'patient' or 'therapist'
    List<String>? securityQuestions,
    List<String>? securityAnswers,
    String? therapistId,
    String? assignedTherapist,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;
      final now = DateTime.now().toIso8601String();

      final hashedAnswers = securityAnswers
              ?.map((a) => sha256
                  .convert(utf8.encode(a.toLowerCase().trim()))
                  .toString())
              .toList() ??
          [];

      // Save extra user data to Firestore
      final userDoc = {
        'name': name,
        'email': email,
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
        'securityQuestions': securityQuestions ?? [],
        'securityAnswers': hashedAnswers,
        if (therapistId != null) 'therapistId': therapistId,
        if (assignedTherapist != null) 'assignedTherapist': assignedTherapist,
      };
      debugPrint('[AuthService] Writing user doc for uid=$uid role=$role therapistId=$therapistId');
      await _firestore.collection('users').doc(uid).set(userDoc);
      debugPrint('[AuthService] Firestore write succeeded for uid=$uid');

      _currentRole = role;
      _cachedUserData = {
        'id': uid,
        'email': email,
        'name': name,
        'role': role,
        'createdAt': now,
        'lastLogin': now,
        if (therapistId != null) 'therapistId': therapistId,
        if (assignedTherapist != null) 'assignedTherapist': assignedTherapist,
      };
      _userCache[uid] = _cachedUserData!;
      await _cacheLocally(uid, _cachedUserData!);

      if (role == 'patient' && !kIsWeb) {
        await _ensurePatientProfile(userId: uid, email: email, name: name);
      }

      final token = await credential.user!.getIdToken();
      return {
        'success': true,
        'userId': uid,
        'role': role,
        'token': token,
      };
    } on FirebaseAuthException catch (e) {
      return _signupLocal(
        email: email,
        password: password,
        name: name,
        role: role,
        securityQuestions: securityQuestions,
        securityAnswers: securityAnswers,
        therapistId: therapistId,
        assignedTherapist: assignedTherapist,
      );
    } catch (e) {
      return _signupLocal(
        email: email,
        password: password,
        name: name,
        role: role,
        securityQuestions: securityQuestions,
        securityAnswers: securityAnswers,
        therapistId: therapistId,
        assignedTherapist: assignedTherapist,
      );
    }
  }

  /// Login with email and password
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;

      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? {};

      _currentRole = (data['role'] as String?) ?? 'patient';
      _cachedUserData = _buildUserMap(uid, {
        'email': email,
        'name': data['name'] ?? email.split('@').first,
        'role': _currentRole,
        ...data,
      });
      _userCache[uid] = _cachedUserData!;
      await _cacheLocally(uid, _cachedUserData!);

      // Update last login (non-blocking)
      _firestore.collection('users').doc(uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      if (_currentRole == 'patient' && !kIsWeb) {
        await _ensurePatientProfile(
          userId: uid,
          email: email,
          name: _cachedUserData!['name'] as String,
        );
      }

      final token = await credential.user!.getIdToken();
      return {
        'success': true,
        'userId': uid,
        'role': _currentRole,
        'name': _cachedUserData!['name'],
        'token': token,
      };
    } on FirebaseAuthException catch (e) {
      return _loginLocal(email: email, password: password);
    } catch (e) {
      return _loginLocal(email: email, password: password);
    }
  }

  Future<Map<String, dynamic>> _loginLocal({
    required String email,
    required String password,
  }) async {
    final account = _localAccounts[email.toLowerCase().trim()];
    if (account == null) {
      return {'success': false, 'message': 'Login failed'};
    }

    if ((account['password'] ?? '') != password) {
      return {'success': false, 'message': 'Incorrect password'};
    }

    final uid = account['id']?.toString() ?? 'local_${email.hashCode.abs()}';
    final userData = {
      ...account,
      'id': uid,
      'lastLogin': DateTime.now().toIso8601String(),
      'authProvider': 'local',
    };

    _localUserId = uid;
    _currentRole = userData['role'] as String?;
    _cachedUserData = userData;
    _userCache[uid] = userData;
    await _cacheLocally(uid, userData);

    return {
      'success': true,
      'userId': uid,
      'role': _currentRole,
      'name': userData['name'],
      'token': 'local-session-token',
    };
  }

  /// Logout
  Future<void> logout() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('last_assessment_') ||
          key.startsWith('privacy_') ||
          key == 'chat_last_open_thread') {
        await _prefs.remove(key);
      }
    }
    _currentRole = null;
    _localUserId = null;
    _cachedUserData = null;
    await _prefs.remove('current_role');
    await _prefs.remove('local_auth_session');
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  /// Get current user data
  Map<String, dynamic>? getCurrentUser() {
    return _cachedUserData;
  }

  Map<String, dynamic>? getUserById(String userId) {
    return _userCache[userId];
  }

  List<Map<String, dynamic>> getUsersByRole(String role) {
    return _userCache.values
        .where((u) => u['role'] == role)
        .toList();
  }

  Map<String, dynamic>? getFirstUserByRole(String role) {
    final users = getUsersByRole(role);
    return users.isNotEmpty ? users.first : null;
  }

  /// Delete account
  Future<bool> deleteAccount(String email) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).delete();
        await user.delete();
      }
      _currentRole = null;
      _cachedUserData = null;
      await _prefs.remove('current_role');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _ensurePatientProfile({
    required String userId,
    required String email,
    required String name,
  }) async {
    if (kIsWeb) return;

    try {
      final existing = await _dbService.getPatient(userId);
      final now = DateTime.now().toIso8601String();
      if (existing != null) {
        await _dbService.updatePatient(
          Patient(
            id: existing.id,
            name: name,
            email: email,
            age: existing.age,
            therapistId: existing.therapistId,
            currentRiskScore: existing.currentRiskScore,
            riskScore: existing.riskScore,
            wellbeingScore: existing.wellbeingScore,
            lastUpdated: now,
            createdAt: existing.createdAt,
            lastCheckIn: existing.lastCheckIn,
            missedSessions: existing.missedSessions,
            isDemo: existing.isDemo,
          ),
        );
        return;
      }

      final patient = Patient(
        id: userId,
        name: name,
        email: email,
        age: 25,
        currentRiskScore: 0.0,
        riskScore: 0.0,
        wellbeingScore: 50.0,
        lastUpdated: now,
        createdAt: DateTime.now(),
        lastCheckIn: DateTime.now(),
        missedSessions: 0,
        isDemo: false,
      );

      await _dbService.insertPatient(patient);
    } catch (_) {
      // Keep auth flow responsive even if profile sync fails.
    }
  }

  /// Get security questions for password recovery
  Future<Map<String, dynamic>> getSecurityQuestions(String email) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return {'success': false, 'message': 'Email not found'};
      }

      final data = query.docs.first.data();
      final questions = data['securityQuestions'] as List<dynamic>?;

      if (questions == null || questions.isEmpty) {
        return {'success': false, 'message': 'No security questions set for this account'};
      }

      return {'success': true, 'questions': questions};
    } catch (e) {
      return {'success': false, 'message': 'Error retrieving questions: $e'};
    }
  }

  /// Verify security answers
  Future<Map<String, dynamic>> verifySecurityAnswers({
    required String email,
    required List<String> answers,
  }) async {
    try {
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return {'success': false, 'message': 'User not found'};
      }

      final data = query.docs.first.data();
      final storedAnswers = List<String>.from(data['securityAnswers'] ?? []);

      if (storedAnswers.isEmpty) {
        return {'success': false, 'message': 'No security answers configured'};
      }

      final hashedAnswers = answers
          .map((a) => sha256.convert(utf8.encode(a.toLowerCase().trim())).toString())
          .toList();

      bool allMatch = true;
      for (int i = 0; i < storedAnswers.length && i < hashedAnswers.length; i++) {
        if (storedAnswers[i] != hashedAnswers[i]) {
          allMatch = false;
          break;
        }
      }

      return allMatch
          ? {'success': true}
          : {'success': false, 'message': 'Incorrect answers'};
    } catch (e) {
      return {'success': false, 'message': 'Error verifying answers: $e'};
    }
  }

  /// Reset password via Firebase email link
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return {'success': true, 'message': 'Password reset email sent. Check your inbox.'};
    } catch (e) {
      return {'success': false, 'message': 'Error resetting password: $e'};
    }
  }
}
