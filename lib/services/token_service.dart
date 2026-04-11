import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenService {
  static final TokenService _instance = TokenService._internal();
  late SharedPreferences _prefs;
  String? _cachedToken;
  DateTime? _tokenExpiry;
  
  // Secret key for JWT (in production, this should come from secure environment config)
  static const String _jwtSecret = 'mindtwin_secret_key_changeme_in_production';
  
  factory TokenService() {
    return _instance;
  }

  TokenService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _cachedToken = _prefs.getString('auth_token');
    final expiryString = _prefs.getString('token_expiry');
    if (expiryString != null) {
      _tokenExpiry = DateTime.parse(expiryString);
    }
  }

  /// Generate JWT token for user
  Future<String> generateToken({
    required String userId,
    required String userRole,
    required String email,
    int expiryHours = 24,
  }) async {
    try {
      final now = DateTime.now();
      final expiry = now.add(Duration(hours: expiryHours));

      final payload = {
        'userId': userId,
        'email': email,
        'role': userRole,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': expiry.millisecondsSinceEpoch ~/ 1000,
      };

      // Create JWT token using dart_jsonwebtoken
      final token = JWT(payload).sign(SecretKey(_jwtSecret));

      // Cache token
      _cachedToken = token;
      _tokenExpiry = expiry;

      await _prefs.setString('auth_token', token);
      await _prefs.setString('token_expiry', expiry.toIso8601String());

      return token;
    } catch (e) {
      print('Error generating token: $e');
      rethrow;
    }
  }

  /// Get current token
  String? getToken() {
    if (_isTokenExpired()) {
      clearToken();
      return null;
    }
    return _cachedToken;
  }

  /// Refresh token if close to expiry
  Future<String?> refreshTokenIfNeeded({
    required String userId,
    required String userRole,
    required String email,
  }) async {
    if (_tokenExpiry != null) {
      final now = DateTime.now();
      final timeUntilExpiry = _tokenExpiry!.difference(now);

      // Refresh if less than 1 hour remaining
      if (timeUntilExpiry.inMinutes < 60) {
        return await generateToken(
          userId: userId,
          userRole: userRole,
          email: email,
        );
      }
    }
    return getToken();
  }

  /// Verify token validity
  bool isTokenValid() {
    return !_isTokenExpired() && _cachedToken != null;
  }

  /// Check if token is expired
  bool _isTokenExpired() {
    if (_tokenExpiry == null) return true;
    return DateTime.now().isAfter(_tokenExpiry!);
  }

  /// Clear token
  Future<void> clearToken() async {
    _cachedToken = null;
    _tokenExpiry = null;
    await _prefs.remove('auth_token');
    await _prefs.remove('token_expiry');
  }

  /// Parse and validate token
  Map<String, dynamic>? parseToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_jwtSecret));
      return jwt.payload as Map<String, dynamic>;
    } catch (e) {
      print('Token verification failed: $e');
      return null;
    }
  }

  /// Get Authorization header
  Map<String, String> getAuthHeaders() {
    final token = getToken();
    if (token == null) return {};
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }
}
