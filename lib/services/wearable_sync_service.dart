import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';
import 'universal_watch_health_service.dart';

class WearableSyncService {
  static final WearableSyncService _instance = WearableSyncService._internal();
  factory WearableSyncService() => _instance;

  WearableSyncService._internal();

  static const _channel = MethodChannel('com.example.mindtwin/wearable');
  final _backendApi = BackendApiService();
  AuthService get _authService => AuthService();
  final _healthService = UniversalWatchHealthService();
  Timer? _healthPollTimer;

  final _heartRateStreamController = StreamController<Map<String, dynamic>>.broadcast();

  // Observable stream of live heart rate updates: { 'bpm': int, 'timestamp': DateTime }
  Stream<Map<String, dynamic>> get heartRateStream => _heartRateStreamController.stream;

  Map<String, dynamic>? _lastReceivedVitals;
  Map<String, dynamic>? get lastReceivedVitals => _lastReceivedVitals;

  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethod);

    if (_supportsPhoneHealth) {
      await _requestHealthPermissions();
      await _fetchLatestPhoneHealth();
      _startHealthPolling();
    }
  }

  bool get _supportsPhoneHealth {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  }

  Future<void> _requestHealthPermissions() async {
    try {
      await _healthService.requestReadPermissions();
    } catch (_) {
      debugPrint('Phone health permissions request failed.');
    }
  }

  void _startHealthPolling() {
    _healthPollTimer?.cancel();
    _healthPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchLatestPhoneHealth(),
    );
  }

  Future<void> _fetchLatestPhoneHealth() async {
    try {
      final snapshot = await _healthService.fetchLatest();
      if (snapshot == null) return;
      await _addHeartRateData(snapshot.heartRate.round(), snapshot.timestamp, source: 'phone_health');
    } catch (e) {
      debugPrint('Phone health fetch failed: $e');
    }
  }

  Future<void> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onHeartRateReceived':
        final bpm = call.arguments['bpm'] as int?;
        final timestampMs = call.arguments['timestamp'] as int?;
        if (bpm != null) {
          final timestamp = timestampMs != null
              ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
              : DateTime.now();
          await _addHeartRateData(bpm, timestamp, source: 'watch');
        }
        break;
      default:
        print('WearableSyncService: Unhandled method: ${call.method}');
    }
  }

  Future<void> _addHeartRateData(int bpm, DateTime timestamp, {String source = 'watch'}) async {
    final vitalsData = {
      'bpm': bpm,
      'timestamp': timestamp,
      'source': source,
    };
    _lastReceivedVitals = vitalsData;
    _heartRateStreamController.add(vitalsData);

    final patientId = _authService.currentUserId;
    if (patientId != null) {
      try {
        await _backendApi.recordHeartRateData(
          patientId,
          bpm,
          timestamp: timestamp.toIso8601String(),
        );
      } catch (e) {
        debugPrint('Failed to record heart rate data: $e');
      }
    }
  }

  /// Simulate a heart rate reading for simulator/mock testing
  Future<void> simulateHeartRate(int bpm) async {
    final timestamp = DateTime.now();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('simulateHeartRate', {'bpm': bpm});
        return;
      } catch (_) {
        // fall through to local simulation fallback
      }
    }

    await _addHeartRateData(bpm, timestamp, source: 'simulated');
  }
}
