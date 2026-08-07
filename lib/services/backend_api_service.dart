import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'token_service.dart';

class BackendApiService {
  static const String _baseUrl =
      String.fromEnvironment('MINDTWIN_API_BASE_URL', defaultValue: '');
  static const String _clinicCode =
      String.fromEnvironment('MINDTWIN_CLINIC_CODE', defaultValue: 'DEMO_CLINIC_001');
  static const String _manualBaseUrlKey = 'backend_base_url_manual';
  
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_manualBaseUrlKey, normalized);
    _resolvedBaseUrl = normalized;
  }

  Future<String?> getManualBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manualBaseUrlKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return _normalizeBaseUrl(raw);
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

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final host = int.tryParse(parts[3]) ?? 0;

          candidates.add('http://$ip:$port');

          for (int delta = 1; delta <= 16; delta++) {
            final low = host - delta;
            final high = host + delta;
            if (low >= 1 && low <= 254) {
              candidates.add('http://$prefix.$low:$port');
            }
            if (high >= 1 && high <= 254) {
              candidates.add('http://$prefix.$high:$port');
            }
          }

          for (int i = 1; i <= 254; i++) {
            candidates.add('http://$prefix.$i:$port');
          }
        }
      }
    } catch (_) {}

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

  Future<Map<String, dynamic>> loginRemote({
    required String email,
    required String password,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) {
      return {'success': false, 'message': 'Backend not configured'};
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final token = decoded['token']?.toString();
          if (token != null && token.isNotEmpty) {
            await _tokenService.storeToken(token);
          }
          return {
            'success': true,
            ...decoded,
          };
        }
      }

      return {
        'success': false,
        'message': 'Invalid credentials',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Remote login failed: $e',
      };
    }
  }

  Future<Map<String, dynamic>> registerRemotePatient({
    required String email,
    required String password,
    required String name,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) {
      return {'success': false, 'message': 'Backend not configured'};
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final token = decoded['token']?.toString();
          if (token != null && token.isNotEmpty) {
            await _tokenService.storeToken(token);
          }
          return {
            'success': true,
            ...decoded,
          };
        }
      }

      return {
        'success': false,
        'message': 'Remote registration failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Remote registration failed: $e',
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

  /// Register FCM token with backend
  Future<bool> registerFcmToken(String userId, String token) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/$userId/fcm-token'),
        headers: headers,
        body: jsonEncode({'token': token}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Sync patient data to backend
  Future<bool> syncPatientData(Map<String, dynamic> data) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/patient-data'),
        headers: headers,
        body: jsonEncode(data),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Sync error: $e');
      return false;
    }
  }

  /// Pull updates from backend
  Future<Map<String, dynamic>> pullUpdates(DateTime since) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/pull?since=${since.toIso8601String()}'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      print('Pull error: $e');
      return {};
    }
  }

  /// Create crisis alert on backend
  Future<bool> createCrisisAlert(String patientId, Map<String, dynamic> alert) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/patients/$patientId/alerts'),
        headers: headers,
        body: jsonEncode(alert),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Alert creation error: $e');
      return false;
    }
  }

  /// Add daily log to backend
  Future<bool> addDailyLog(String patientId, Map<String, dynamic> log) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/patients/$patientId/daily-logs'),
        headers: headers,
        body: jsonEncode(log),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Log creation error: $e');
      return false;
    }
  }

  Future<bool> submitSharedCheckin(Map<String, dynamic> payload) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/public/checkin'),
        headers: headers,
        body: jsonEncode({
          'clinicCode': _clinicCode,
          ...payload,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Shared check-in sync error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchSharedTherapistDashboard({int limit = 80}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/sync/public/therapist-dashboard?clinicCode=$_clinicCode&limit=$limit',
        ),
        headers: headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return {};
    } catch (e) {
      print('Therapist shared dashboard fetch error: $e');
      return {};
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

  Future<Map<String, dynamic>> submitPHQ9Assessment({
    required String patientId,
    required String therapistId,
    required List<int> responses,
    String? notes,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {'success': false};
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/clinical/phq9'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'therapistId': therapistId,
          'responses': responses,
          'notes': notes,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false};
    } catch (e) {
      print('PHQ9 submission error: $e');
      return {'success': false};
    }
  }

  Future<List<Map<String, dynamic>>> getAssessmentHistory(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return const [];
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/clinical/assessment-history/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['assessments'] is List) {
          return (data['assessments'] as List)
              .cast<Map<String, dynamic>>();
        }
      }
      return const [];
    } catch (e) {
      print('Assessment history error: $e');
      return const [];
    }
  }

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

  Future<Map<String, dynamic>> getRiskFactors(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/clinical/risk-factors/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return (data['riskFactors'] as Map).cast<String, dynamic>();
      }
      return {};
    } catch (e) {
      print('Risk factors error: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getClinicalAlerts(String therapistId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return const [];
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/clinical/alerts/$therapistId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data['alerts'] is List) {
          return (data['alerts'] as List)
              .cast<Map<String, dynamic>>();
        }
      }
      return const [];
    } catch (e) {
      print('Clinical alerts error: $e');
      return const [];
    }
  }

  Future<bool> acknowledgeAlert(String alertId, {String? actionTaken}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/clinical/alerts/$alertId/acknowledge'),
        headers: headers,
        body: jsonEncode({
          'actionTaken': actionTaken,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Acknowledge alert error: $e');
      return false;
    }
  }

  Future<bool> createIntervention({
    required String patientId,
    String? therapistId,
    required String type,
    required String evidenceLevel,
    String? description,
    List<String>? cbtInterventions,
    List<String>? medicationSuggestions,
    List<String>? lifestyleRecommendations,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/clinical/interventions'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'therapistId': therapistId,
          'type': type,
          'evidenceLevel': evidenceLevel,
          'description': description,
          'cbtInterventions': cbtInterventions ?? [],
          'medicationSuggestions': medicationSuggestions ?? [],
          'lifestyleRecommendations': lifestyleRecommendations ?? [],
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Create intervention error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPatientInterventions(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return const [];
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/clinical/interventions/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data['interventions'] is List) {
          return (data['interventions'] as List)
              .cast<Map<String, dynamic>>();
        }
      }
      return const [];
    } catch (e) {
      print('Get interventions error: $e');
      return const [];
    }
  }

  // ===== REAL-TIME WEARABLE DATA ENDPOINTS =====

  /// Record real-time mood data from wearable device
  /// moodScore: 1 (very sad) to 10 (very happy)
  Future<bool> recordMoodData(String patientId, int moodScore, {String? timestamp}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/wearable/mood'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'moodScore': moodScore,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Record mood data error: $e');
      return false;
    }
  }

  /// Record real-time anxiety data from wearable device
  /// anxietyScore: 1 (calm) to 10 (severe)
  Future<bool> recordAnxietyData(String patientId, int anxietyScore, {String? timestamp}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/wearable/anxiety'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'anxietyScore': anxietyScore,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Record anxiety data error: $e');
      return false;
    }
  }

  /// Record real-time sleep data from wearable device
  /// sleepDuration: hours (0-12), sleepQuality: 1-10 scale
  Future<bool> recordSleepData(
    String patientId,
    double sleepDuration,
    int sleepQuality, {
    String? timestamp,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/wearable/sleep'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'sleepDuration': sleepDuration,
          'sleepQuality': sleepQuality,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Record sleep data error: $e');
      return false;
    }
  }

  /// Record real-time heart rate data from wearable device
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
  Future<bool> recordActivityData(
    String patientId,
    int steps, {
    int activityMinutes = 0,
    double caloriesBurned = 0,
    String? timestamp,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/wearable/activity'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'steps': steps,
          'activityMinutes': activityMinutes,
          'caloriesBurned': caloriesBurned,
          'timestamp': timestamp ?? DateTime.now().toIso8601String(),
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Record activity data error: $e');
      return false;
    }
  }

  /// Batch ingest multiple wearable data points
  /// dataPoints: [{ type: 'mood'|'anxiety'|'sleep'|'heartrate'|'activity', value, timestamp }]
  Future<bool> ingestWearableBatch(String patientId, List<Map<String, dynamic>> dataPoints) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/wearable/batch'),
        headers: headers,
        body: jsonEncode({
          'patientId': patientId,
          'dataPoints': dataPoints,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Ingest wearable batch error: $e');
      return false;
    }
  }

  /// Get wearable data summary for patient (last 7 days)
  Future<Map<String, dynamic>> getWearableSummary(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return {};
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/realtime/wearable/summary/$patientId'),
        headers: headers,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return (data['summary'] as Map?)?.cast<String, dynamic>() ?? {};
      }
      return {};
    } catch (e) {
      print('Get wearable summary error: $e');
      return {};
    }
  }

  // ===== NOTIFICATION ENDPOINTS =====

  /// Register device token for FCM push notifications
  /// platform: 'android', 'ios', or 'web'
  Future<bool> registerDeviceToken(String therapistId, String deviceToken, {String platform = 'android'}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/notifications/register-device'),
        headers: headers,
        body: jsonEncode({
          'therapistId': therapistId,
          'deviceToken': deviceToken,
          'platform': platform,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Register device token error: $e');
      return false;
    }
  }

  /// Send test alert notification (for configuration verification)
  Future<bool> sendTestAlert(String therapistId, {String patientName = 'Test Patient'}) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/notifications/test-alert'),
        headers: headers,
        body: jsonEncode({
          'therapistId': therapistId,
          'patientName': patientName,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Send test alert error: $e');
      return false;
    }
  }

  // ===== ENGAGEMENT REMINDER ENDPOINTS =====

  /// Trigger manual reminder for specific patient
  Future<bool> triggerManualReminder(String patientId) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) return false;
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/realtime/reminders/manual/$patientId'),
        headers: headers,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Trigger manual reminder error: $e');
      return false;
    }
  }

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
        // In real implementation, save PDF to file storage
        // For now, return success indicator
        return 'report_${patientId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
        return 'progress_${patientId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
        return 'wearable_${patientId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      }
      return null;
    } catch (e) {
      print('Download wearable report error: $e');
      return null;
    }
  }
}
