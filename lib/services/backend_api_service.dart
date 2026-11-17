import 'dart:convert';
import 'dart:async';
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

  BackendApiService() {
    _tokenService = TokenService();
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

  // ── Backend URL resolution ──────────────────────────────────────────────
  //
  // The resolved URL is shared by every BackendApiService instance (screens
  // create their own instances), so resolution happens once per app session
  // rather than once per screen.
  static String? _resolvedBaseUrl;
  static DateTime? _resolvedAt;
  static DateTime? _lastFailedResolutionAt;
  static Future<String?>? _inflightResolution;

  /// How long a working URL is trusted before it is re-checked. Keeps the
  /// app recovering on its own when the laptop's Wi-Fi IP changes.
  static const Duration _revalidateAfter = Duration(seconds: 30);

  /// After a failed resolution, callers get null immediately for this long
  /// instead of each paying the full probe cost while the backend is down.
  static const Duration _failureBackoff = Duration(seconds: 10);

  static const int _discoveryPort = 47777;
  static const String _discoveryRequest = 'MINDTWIN_DISCOVER_V1';

  Future<bool> testConnection({String? baseUrl}) async {
    final candidate = baseUrl == null || baseUrl.trim().isEmpty
        ? await _resolveBaseUrl()
        : _normalizeBaseUrl(baseUrl);
    if (candidate == null) return false;
    return _probeHealth(candidate);
  }

  /// True only when [baseUrl] answers /health as a MindTwin backend.
  Future<bool> _probeHealth(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final body = jsonDecode(response.body);
      if (body is! Map) return false;
      // Older backends report only {status: ok}; newer ones also name the service.
      final service = body['service'];
      return body['status'] == 'ok' &&
          (service == null || service == 'mindtwin-backend');
    } catch (_) {
      return false;
    }
  }

  /// Finds the backend on the local Wi-Fi by UDP broadcast. The backend's
  /// LanDiscoveryService replies with its HTTP port; the reply's source
  /// address is the laptop's current IP. Returns null when nothing answers
  /// (different network, or Wi-Fi with client isolation).
  Future<String?> _discoverViaBroadcast() async {
    if (kIsWeb) return null;

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final found = Completer<String?>();
      final boundSocket = socket;
      boundSocket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = boundSocket.receive();
        if (datagram == null) return;
        try {
          final data = jsonDecode(utf8.decode(datagram.data));
          if (data is Map && data['service'] == 'mindtwin-backend') {
            final port = (data['port'] as num?)?.toInt() ?? 5000;
            if (!found.isCompleted) {
              found.complete('http://${datagram.address.address}:$port');
            }
          }
        } catch (_) {
          // Ignore unrelated datagrams.
        }
      });

      final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            final octets = addr.address.split('.');
            if (octets.length == 4) {
              // Directed /24 broadcast; some routers drop 255.255.255.255.
              targets.add(InternetAddress('${octets[0]}.${octets[1]}.${octets[2]}.255'));
            }
          }
        }
      } catch (e) {
        debugPrint('Network interface enumeration failed: $e');
      }

      final payload = utf8.encode(_discoveryRequest);
      // UDP is lossy on Wi-Fi: send a few rounds, stop as soon as one answers.
      for (var round = 0; round < 3 && !found.isCompleted; round++) {
        for (final target in targets) {
          try {
            boundSocket.send(payload, target, _discoveryPort);
          } catch (_) {}
        }
        await Future.any([
          found.future,
          Future.delayed(const Duration(milliseconds: 700)),
        ]);
      }

      if (!found.isCompleted) return null;
      final url = await found.future;
      if (url != null && await _probeHealth(url)) return url;
      return null;
    } catch (e) {
      debugPrint('LAN discovery failed: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  Future<String?> autoDetectAndSaveBackendUrl({int port = 5000}) async {
    final detected = await autoDetectLanBackendUrl(port: port);
    if (detected == null) return null;
    await setManualBaseUrl(detected);
    return detected;
  }

  /// Locates a reachable backend without touching the saved manual URL.
  /// Returns null when none is reachable; never guesses `localhost`, which
  /// on a physical phone is the phone itself.
  Future<String?> autoDetectLanBackendUrl({int port = 5000}) async {
    if (kIsWeb) return null;

    final discovered = await _discoverViaBroadcast();
    if (discovered != null) {
      _cacheResolved(discovered);
      return discovered;
    }

    // Emulator host alias and same-device backends (desktop builds, adb reverse).
    for (final candidate in ['http://10.0.2.2:$port', 'http://127.0.0.1:$port']) {
      if (await _probeHealth(candidate)) {
        _cacheResolved(candidate);
        return candidate;
      }
    }
    return null;
  }

  Future<String?> resolveBaseUrl() => _resolveBaseUrl();

  String _normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void _cacheResolved(String url) {
    _resolvedBaseUrl = url;
    _resolvedAt = DateTime.now();
    _lastFailedResolutionAt = null;
  }

  Future<String?> _resolveBaseUrl() {
    final cached = _resolvedBaseUrl;
    final at = _resolvedAt;
    if (cached != null && at != null &&
        DateTime.now().difference(at) < _revalidateAfter) {
      return Future.value(cached);
    }
    final failedAt = _lastFailedResolutionAt;
    if (cached == null && failedAt != null &&
        DateTime.now().difference(failedAt) < _failureBackoff) {
      return Future.value(null);
    }
    // Concurrent callers share one resolution instead of each probing.
    return _inflightResolution ??=
        _resolveBaseUrlUncached().whenComplete(() => _inflightResolution = null);
  }

  Future<String?> _resolveBaseUrlUncached() async {
    // 1. Re-validate the URL that worked last time (cheap, usual case).
    final previous = _resolvedBaseUrl;
    if (previous != null && await _probeHealth(previous)) {
      _cacheResolved(previous);
      return previous;
    }
    _resolvedBaseUrl = null;
    _resolvedAt = null;

    // 2. URL the user saved in settings.
    final manual = await getManualBaseUrl();
    if (manual != null && await _probeHealth(manual)) {
      _cacheResolved(manual);
      return manual;
    }

    // 3. URL baked in at build time (--dart-define=MINDTWIN_API_BASE_URL=...).
    if (_baseUrl.isNotEmpty && await _probeHealth(_normalizeBaseUrl(_baseUrl))) {
      final url = _normalizeBaseUrl(_baseUrl);
      _cacheResolved(url);
      return url;
    }

    // 4. Find the laptop on the current Wi-Fi. If the saved URL went stale
    //    (laptop got a new IP), replace it so the next launch is instant.
    if (!kIsWeb) {
      final discovered = await _discoverViaBroadcast();
      if (discovered != null) {
        if (manual != null && manual != discovered) {
          await _storeManualBaseUrl(discovered);
        }
        _cacheResolved(discovered);
        return discovered;
      }
    }

    // 5. Same-machine / emulator backends.
    final localCandidates = [
      'http://localhost:5000',
      'http://127.0.0.1:5000',
      if (!kIsWeb) 'http://10.0.2.2:5000',
    ];
    for (final candidate in localCandidates) {
      if (await _probeHealth(candidate)) {
        _cacheResolved(candidate);
        return candidate;
      }
    }

    _lastFailedResolutionAt = DateTime.now();
    debugPrint('MindTwin backend not reachable (manual, build-time, LAN discovery, local all failed).');
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
  ///
  /// [idToken] is the signed-in user's Firebase ID token; the backend verifies
  /// it and derives uid/email from it, so identity cannot be spoofed.
  Future<Map<String, dynamic>> firebaseSync({
    required String idToken,
    String? name,
    String? role,
  }) async {
    final baseUrl = await _resolveBaseUrl();
    if (baseUrl == null) {
      return {'success': false, 'message': 'Backend not configured'};
    }

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/firebase-sync'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'name': name,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 15));

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
      debugPrint('Shared appointment booking error: $e');
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
      debugPrint('Shared appointments fetch error: $e');
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
      debugPrint('Shared treatment plan send error: $e');
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
      debugPrint('Shared treatment plans fetch error: $e');
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
      debugPrint('Mark appointment seen error: $e');
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
      debugPrint('Mark appointment accepted error: $e');
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
      debugPrint('Mark treatment plan seen error: $e');
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
      debugPrint('Mark treatment plan accepted error: $e');
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
      debugPrint('Mark message read error: $e');
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
      debugPrint('Treatment summary error: $e');
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
      debugPrint('Engagement metrics error: $e');
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
      debugPrint('Record heart rate data error: $e');
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
      debugPrint('Get reminder stats error: $e');
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
      debugPrint('Save PDF error: $e');
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
      debugPrint('Download treatment report error: $e');
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
      debugPrint('Download progress report error: $e');
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
      debugPrint('Download wearable report error: $e');
      return null;
    }
  }
}
