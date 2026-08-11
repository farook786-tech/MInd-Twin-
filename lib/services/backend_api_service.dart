import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'token_service.dart';

class BackendApiService {
  static const String _baseUrl =
      String.fromEnvironment('MINDTWIN_API_BASE_URL', defaultValue: '');
  static const String _clinicCode =
      String.fromEnvironment('MINDTWIN_CLINIC_CODE', defaultValue: 'DEMO_CLINIC_001');
  static const String _manualBaseUrlKey = 'backend_base_url_manual';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  late final TokenService _tokenService;
  String? _resolvedBaseUrl;
  
  BackendApiService() {
    _tokenService = TokenService();
    if (_baseUrl.isNotEmpty) {
      _resolvedBaseUrl = _baseUrl;
    }
  }

  bool get isConfigured => (_resolvedBaseUrl ?? _baseUrl).isNotEmpty;
  String get clinicCode => _clinicCode;

  Future<void> setManualBaseUrl(String rawUrl) async {
    final normalized = _normalizeBaseUrl(rawUrl);
    await _storeManualBaseUrl(normalized);
    _resolvedBaseUrl = normalized;
  }

  Future<String?> getManualBaseUrl() async {
    final raw = await _readManualBaseUrl();
    if (raw == null || raw.trim().isEmpty) return null;
    return _normalizeBaseUrl(raw);
  }

  // Store the manually entered backend URL in the platform keychain/keystore
  // (falls back to SharedPreferences on web where secure storage is unavailable).
  Future<void> _storeManualBaseUrl(String url) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_manualBaseUrlKey, url);
      return;
    }
    try {
      await _secureStorage.write(key: _manualBaseUrlKey, value: url);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_manualBaseUrlKey, url);
    }
  }

  Future<String?> _readManualBaseUrl() async {
    if (!kIsWeb) {
      try {
        final secure = await _secureStorage.read(key: _manualBaseUrlKey);
        if (secure != null && secure.isNotEmpty) return secure;
      } catch (_) {
        // Fall through to SharedPreferences below.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_manualBaseUrlKey);
  }

  Future<bool> testConnection({String? baseUrl}) async {
    final candidate = baseUrl == null || baseUrl.trim().isEmpty
        ? await _resolveBaseUrl()
        : _normalizeBaseUrl(baseUrl);
    if (candidate == null) return false;

    try {
      final response = await http
          .get(Uri.parse('$candidate/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<String?> autoDetectAndSaveBackendUrl({int port = 5000}) async {
    final detected = await autoDetectLanBackendUrl(port: port);
    if (detected == null) return null;
    await setManualBaseUrl(detected);
    return detected;
  }

  Future<String?> autoDetectLanBackendUrl({int port = 5000}) async {
    if (kIsWeb) return null;

    final preferred = <String>[];
    final known = [
      'http://10.0.2.2:$port',
      'http://127.0.0.1:$port',
      'http://localhost:$port',
    ];

    final manual = await getManualBaseUrl();
    if (manual != null) preferred.add(manual);
    if (_baseUrl.isNotEmpty) preferred.add(_baseUrl);
    preferred.addAll(known);

    for (final candidate in preferred.toSet()) {
      if (await testConnection(baseUrl: candidate)) {
        _resolvedBaseUrl = candidate;
        return candidate;
      }
    }

    final candidates = <String>{};

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Only test the device's own assigned addresses, never sweep the subnet.
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;
          candidates.add('http://$ip:$port');
        }
      }
    } catch (e) {
      debugPrint('Network interface enumeration failed: $e');
    }

    final candidateList = candidates.toList();
    const batchSize = 24;
    for (int i = 0; i < candidateList.length; i += batchSize) {
      final end = (i + batchSize < candidateList.length)
          ? i + batchSize
          : candidateList.length;
      final batch = candidateList.sublist(i, end);

      final results = await Future.wait(
        batch.map((url) async => MapEntry(url, await testConnection(baseUrl: url))),
      );

      for (final result in results) {
        if (result.value) {
          _resolvedBaseUrl = result.key;
          return result.key;
        }
      }
    }

    // Fallback URL when backend not configured
    _resolvedBaseUrl = 'http://localhost:5000';
    return _resolvedBaseUrl;
  }

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<String?> _resolveBaseUrl() async {
    if (_resolvedBaseUrl != null && _resolvedBaseUrl!.isNotEmpty) {
      return _resolvedBaseUrl;
    }

    final manual = await getManualBaseUrl();
    if (manual != null) {
      final ok = await testConnection(baseUrl: manual);
      if (ok) {
        _resolvedBaseUrl = manual;
        return _resolvedBaseUrl;
      }
    }

    if (_baseUrl.isNotEmpty) {
      final ok = await testConnection(baseUrl: _baseUrl);
      if (ok) {
        _resolvedBaseUrl = _baseUrl;
        return _resolvedBaseUrl;
      }
    }

    if (!kIsWeb) {
      const localCandidates = [
        'http://10.0.2.2:5000',
        'http://127.0.0.1:5000',
        'http://localhost:5000',
      ];
      for (final candidate in localCandidates) {
        final ok = await testConnection(baseUrl: candidate);
        if (ok) {
          _resolvedBaseUrl = candidate;
          return _resolvedBaseUrl;
        }
      }
    }

    return null;
  }

  /// Get headers with JWT token
  Future<Map<String, String>> _getHeaders() async {
    return _tokenService.getAuthHeaders();
  }

  /// Predict crisis risk via the ML bridge (server-side model + phrase + idiom decision).
  /// Returns null when the backend is unreachable so callers can fall back
  /// to local detection. Otherwise returns the bridge payload:
  /// { success, available, model_version, decision: { escalate, severity, ... } }.
  Future<Map<String, dynamic>?> predictCrisis({
    required String text,
    required String patientId,
    List<String> recentHistory = const [],
  }) async {
    final baseUrl = await _resolveBaseUrl() ?? 'http://127.0.0.1:5000';

    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/ml/predict'),
            headers: headers,
            body: jsonEncode({
              'text': text,
              'patientId': patientId,
              'recentHistory': recentHistory,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendSosAlert(Map<String, dynamic> payload) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/alerts/sos'),
        headers: headers,
        body: jsonEncode(payload),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Exchange a Firebase sign-in for a backend JWT (and sync the account).
  /// Returns the backend response { success, token, userId, role, name, email }
  /// or { success: false, message } when the backend is unreachable.
  Future<Map<String, dynamic>> firebaseSync({
    required String uid,
    required String email,
    String? name,
    String? role,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) {
      return {'success': false, 'message': 'Backend not configured'};
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/firebase-sync'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'email': email,
          'name': name,
          'role': role,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final token = decoded['token']?.toString();
          if (token != null && token.isNotEmpty) {
            await _tokenService.storeToken(token);
          }
          return {'success': true, ...decoded};
        }
      }

      return {
        'success': false,
        'message': 'Backend sync failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Backend sync failed: $e',
      };
    }
  }



  Future<bool> sendMessage(Map<String, dynamic> payload) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/chat/send'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          ...payload,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchConversation(
    String userA,
    String userB,
  ) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return const [];
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/public/chat/messages?clinicCode=$_clinicCode&userA=$userA&userB=$userB'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['messages'] is List) {
          return (decoded['messages'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .cast<Map<String, dynamic>>()
              .toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Register (or refresh) the device FCM token with the backend so the
  /// server can push chat/clinical notifications to this device.
  /// Returns true when the backend accepted the token.
  Future<bool> registerFcmToken({
    required String userId,
    required String token,
    String platform = 'android',
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/$userId/fcm-token'),
        headers: headers,
        body: jsonEncode({'token': token, 'platform': platform}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Fetch the authenticated user's backend profile.
  /// Returns { user } map or null when unreachable.
  Future<Map<String, dynamic>?> fetchMyProfile() async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return null;
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/me'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded['user'] as Map<String, dynamic>?;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update the authenticated user's display name on the backend.
  /// Returns true when the backend accepted the change.
  Future<bool> updateMyName(String name) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/api/users/me'),
        headers: headers,
        body: jsonEncode({'name': name}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> bookSharedAppointment(Map<String, dynamic> payload) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/appointments/book'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          ...payload,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Shared appointment booking error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSharedAppointments({String? patientExternalId}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return const [];
    try {
      final headers = await _getHeaders();
      final uri = patientExternalId == null || patientExternalId.isEmpty
          ? Uri.parse('$baseUrl/api/sync/public/appointments?clinicCode=$_clinicCode')
          : Uri.parse(
              '$baseUrl/api/sync/public/appointments?clinicCode=$_clinicCode&patientExternalId=$patientExternalId',
            );

      final response = await http.get(
        uri,
        headers: headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['appointments'] is List) {
          return (decoded['appointments'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .cast<Map<String, dynamic>>()
              .toList();
        }
      }
      return const [];
    } catch (e) {
      print('Shared appointments fetch error: $e');
      return const [];
    }
  }

  Future<bool> sendSharedTreatmentPlan(Map<String, dynamic> payload) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/treatment-plans/send'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          ...payload,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Shared treatment plan send error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSharedTreatmentPlans({String? patientExternalId}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return const [];
    try {
      final headers = await _getHeaders();
      final uri = patientExternalId == null || patientExternalId.isEmpty
          ? Uri.parse('$baseUrl/api/sync/public/treatment-plans?clinicCode=$_clinicCode')
          : Uri.parse(
              '$baseUrl/api/sync/public/treatment-plans?clinicCode=$_clinicCode&patientExternalId=$patientExternalId',
            );

      final response = await http.get(
        uri,
        headers: headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['plans'] is List) {
          return (decoded['plans'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .cast<Map<String, dynamic>>()
              .toList();
        }
      }
      return const [];
    } catch (e) {
      print('Shared treatment plans fetch error: $e');
      return const [];
    }
  }

  Future<bool> markAppointmentSeen(String appointmentId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/appointments/mark-seen'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          'appointmentId': appointmentId,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Mark appointment seen error: $e');
      return false;
    }
  }

  Future<bool> markAppointmentAccepted(String appointmentId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/appointments/mark-accepted'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          'appointmentId': appointmentId,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Mark appointment accepted error: $e');
      return false;
    }
  }

  Future<bool> markPlanSeen(String planId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/treatment-plans/mark-seen'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          'planId': planId,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Mark treatment plan seen error: $e');
      return false;
    }
  }

  Future<bool> markPlanAccepted(String planId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/treatment-plans/mark-accepted'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          'planId': planId,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Mark treatment plan accepted error: $e');
      return false;
    }
  }

  Future<bool> markMessageRead(String messageId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/messages/mark-read'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          'messageId': messageId,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Mark message read error: $e');
      return false;
    }
  }

  // Clinical Assessment Methods



  Future<Map<String, dynamic>> getTreatmentSummary(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/clinical/summary/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return (data['summary'] as Map).cast<String, dynamic>();
      }
      return {};
    } catch (e) {
      print('Treatment summary error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> getEngagementMetrics(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/clinical/engagement/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return (data['engagement'] as Map).cast<String, dynamic>();
      }
      return {};
    } catch (e) {
      print('Engagement metrics error: $e');
      return {};
    }
  }





  /// moodScore: 1 (very sad) to 10 (very happy)
  /// anxietyScore: 1 (calm) to 10 (severe)
  /// sleepDuration: hours (0-12), sleepQuality: 1-10 scale
  /// heartRate: BPM (30-220), isResting: true for resting heart rate
  Future<bool> recordHeartRateData(
    String patientId,
    int heartRate, {
    bool isResting = false,
    String? timestamp,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/wearable/heartrate'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'heartRate': heartRate,
          'isResting': isResting,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Record heart rate data error: $e');
      return false;
    }
  }

  /// Record real-time activity data from wearable device
  /// steps: step count, activityMinutes: minutes active, caloriesBurned: estimated calories
  /// dataPoints: [{ type: 'mood'|'anxiety'|'sleep'|'heartrate'|'activity', value, timestamp }]
  /// Get wearable data summary for patient (last 7 days)
  /// platform: 'android', 'ios', or 'web'
  /// Send test alert notification (for configuration verification)
  /// Trigger manual reminder for specific patient
  /// Get reminder statistics for therapist
  Future<Map<String, dynamic>> getReminderStats(String therapistId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/realtime/reminders/stats/$therapistId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return (data['stats'] as Map?)?.cast<String, dynamic>() ?? {};
      }
      return {};
    } catch (e) {
      print('Get reminder stats error: $e');
      return {};
    }
  }

  // ===== REPORT GENERATION ENDPOINTS =====

  /// Persist raw PDF bytes from the backend to the app documents directory.
  Future<String?> _savePdfBytes(Uint8List bytes, String fileName) async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      print('Save PDF error: $e');
      return null;
    }
  }

  /// Download comprehensive treatment outcome PDF report
  /// Returns file path if successful
  Future<String?> downloadTreatmentReport(String patientId, String therapistId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return null;
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/realtime/reports/treatment/$patientId?therapistId=$therapistId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _savePdfBytes(
          response.bodyBytes,
          'report_${patientId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
      }
      return null;
    } catch (e) {
      print('Download treatment report error: $e');
      return null;
    }
  }

  /// Download simple progress report PDF
  Future<String?> downloadProgressReport(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return null;
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/realtime/reports/progress/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _savePdfBytes(
          response.bodyBytes,
          'progress_${patientId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
      }
      return null;
    } catch (e) {
      print('Download progress report error: $e');
      return null;
    }
  }

  /// Download wearable data summary report PDF
  /// days: number of days to include (default 30)
  Future<String?> downloadWearableReport(String patientId, {int days = 30}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return null;
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/realtime/reports/wearable/$patientId?days=$days'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _savePdfBytes(
          response.bodyBytes,
          'wearable_${patientId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
      }
      return null;
    } catch (e) {
      print('Download wearable report error: $e');
      return null;
    }
  }
}
