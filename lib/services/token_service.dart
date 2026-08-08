import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the JWT issued by the MindTwin backend.
///
/// SECURITY: The client must never sign its own tokens. Every token used here
/// is issued by the backend (POST /api/auth/login or /api/auth/firebase-sync)
/// and signed with the server-side secret that the client cannot access.
class TokenService {
  static final TokenService _instance = TokenService._internal();
  late SharedPreferences _prefs;
  String? _cachedToken;
  DateTime? _tokenExpiry;

  factory TokenService() {
    return _instance;
  }

  TokenService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _cachedToken = _prefs.getString('auth_token');
    final expiryString = _prefs.getString('token_expiry');
    if (expiryString != null) {
      _tokenExpiry = DateTime.tryParse(expiryString);
    }
  }

  /// Store a backend-issued token. Expiry is read from the token's `exp`
  /// claim when present, otherwise a default lifetime is used.
  Future<void> storeToken(String token, {Duration lifetime = const Duration(days: 7)}) async {
    final exp = _readExp(token);
    _tokenExpiry = exp ?? DateTime.now().add(lifetime);
    _cachedToken = token;
    await _prefs.setString('auth_token', token);
    await _prefs.setString('token_expiry', _tokenExpiry!.toIso8601String());
  }

  /// Get current token (null when absent or expired).
  String? getToken() {
    if (_isTokenExpired()) {
      clearToken();
      return null;
    }
    return _cachedToken;
  }

  /// True when a non-expired token is cached.
  bool isTokenValid() {
    return !_isTokenExpired() && _cachedToken != null;
  }

  bool _isTokenExpired() {
    if (_tokenExpiry == null) return true;
    return DateTime.now().isAfter(_tokenExpiry!);
  }

  /// Clear token.
  Future<void> clearToken() async {
    _cachedToken = null;
    _tokenExpiry = null;
    await _prefs.remove('auth_token');
    await _prefs.remove('token_expiry');
  }

  /// Get Authorization header.
  Map<String, String> getAuthHeaders() {
    final token = getToken();
    if (token == null) return {'Content-Type': 'application/json'};
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Read the `exp` claim from a JWT payload without verifying the signature
  /// (the server verifies; this is only for client-side expiry bookkeeping).
  DateTime? _readExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final data = jsonDecode(payload);
      final exp = data['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      }
    } catch (e) {
      debugPrint('Failed to decode token expiry: $e');
    }
    return null;
  }
}
