import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import 'universal_watch_health_service.dart';
import 'vitals_repository.dart';

/// Real connection status of the MindTwin Wear OS app (from the native CapabilityClient).
class WatchStatus {
  final bool connected; // a reachable node has the MindTwin watch app installed
  final bool pairedNodeConnected; // any Wear OS node reachable (app may be missing)
  final List<String> nodeNames;
  final DateTime checkedAt;
  final String? error;

  const WatchStatus({
    required this.connected,
    required this.pairedNodeConnected,
    required this.nodeNames,
    required this.checkedAt,
    this.error,
  });
}

enum HealthConnectState { unknown, unavailable, permissionDenied, ok }

/// Patient-app-only vitals pipeline.
///
/// * Wear OS heart rate: written to Firestore natively by WearVitalsListenerService (Kotlin),
///   even when this Dart code is not running. Here we only receive live copies for the UI.
/// * Health Connect (heart rate, sleep, steps): read here and written to `vitals` with real
///   measurement times and deterministic ids. Nothing is written when there is no data.
///
/// Lifecycle: call [startForCurrentPatient] after a PATIENT signs in, [stop] on sign-out.
class WearableSyncService {
  static final WearableSyncService _instance = WearableSyncService._internal();
  factory WearableSyncService() => _instance;
  WearableSyncService._internal();

  static const _channel = MethodChannel('com.example.mindtwin/wearable');
  static const _syncInterval = Duration(minutes: 15);

  final _health = UniversalWatchHealthService();
  final _repo = VitalsRepository();

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  String? _uid;
  String? _therapistId;
  bool _syncing = false;

  final _heartRateStreamController = StreamController<Map<String, dynamic>>.broadcast();

  /// Live heart-rate readings `{ 'bpm': int, 'timestamp': DateTime, 'source': String }`.
  Stream<Map<String, dynamic>> get heartRateStream => _heartRateStreamController.stream;

  Map<String, dynamic>? _lastReceivedVitals;

  /// Latest REAL heart-rate reading seen this session (watch or Health Connect), or null.
  Map<String, dynamic>? get lastReceivedVitals => _lastReceivedVitals;

  final ValueNotifier<WatchStatus?> watchStatus = ValueNotifier<WatchStatus?>(null);
  final ValueNotifier<HealthConnectState> healthConnectState =
      ValueNotifier<HealthConnectState>(HealthConnectState.unknown);
  final ValueNotifier<DateTime?> lastHealthSyncAt = ValueNotifier<DateTime?>(null);

  bool get isRunning => _uid != null;

  /// Deprecated: kept so existing callers compile. Does nothing; use
  /// [startForCurrentPatient] after login instead.
  @Deprecated('Call startForCurrentPatient() after a patient signs in.')
  Future<void> initialize() async {}

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Starts the pipeline for the signed-in user if (and only if) they are a patient.
  /// Idempotent; safe to call on every app start / login.
  Future<void> startForCurrentPatient() async {
    if (!_supported || AppConfig.isTherapistOnlyMode) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!AppConfig.isPatientOnlyMode) {
      try {
        final token = await user.getIdTokenResult();
        if (token.claims?['role'] != 'patient') return;
      } catch (e) {
        debugPrint('[WearableSync] cannot read role claim: $e');
        return;
      }
    }

    if (_uid == user.uid) {
      unawaited(syncNow());
      return;
    }
    await stop();
    _uid = user.uid;

    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final t = snap.data()?['therapistId'];
      _therapistId = (t is String && t.isNotEmpty) ? t : null;
    } catch (e) {
      debugPrint('[WearableSync] could not read therapistId: $e');
    }

    _channel.setMethodCallHandler(_handleMethod);
    unawaited(refreshWatchStatus());
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Upload anything the watch synced while signed out.
      unawaited(_channel.invokeMethod('flushPendingWatchReadings').catchError((_) => null));
    }

    await _ensureHealthConnect(prompt: true);
    unawaited(syncNow());
    _timer = Timer.periodic(_syncInterval, (_) => syncNow());
    _lifecycle = AppLifecycleListener(onResume: () {
      unawaited(syncNow());
      unawaited(refreshWatchStatus());
    });
  }

  /// Stops syncing (call on sign-out). Native watch uploads keep a backlog until next login.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _uid = null;
    _therapistId = null;
    _lastReceivedVitals = null;
    _channel.setMethodCallHandler(null);
    healthConnectState.value = HealthConnectState.unknown;
    watchStatus.value = null;
  }

  /// Queries the native Data Layer for the real watch connection state.
  Future<WatchStatus> refreshWatchStatus() async {
    WatchStatus status;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      status = WatchStatus(
        connected: false,
        pairedNodeConnected: false,
        nodeNames: const [],
        checkedAt: DateTime.now(),
        error: 'Wear OS is only supported on Android',
      );
    } else {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>('isWatchConnected');
        status = WatchStatus(
          connected: raw?['connected'] == true,
          pairedNodeConnected: raw?['pairedNodeConnected'] == true,
          nodeNames: ((raw?['nodeNames'] as List?) ?? const []).map((e) => '$e').toList(),
          checkedAt: DateTime.now(),
          error: raw?['error'] as String?,
        );
      } catch (e) {
        status = WatchStatus(
          connected: false,
          pairedNodeConnected: false,
          nodeNames: const [],
          checkedAt: DateTime.now(),
          error: '$e',
        );
      }
    }
    watchStatus.value = status;
    return status;
  }

  Future<bool> _ensureHealthConnect({required bool prompt}) async {
    if (!await _health.isAvailable()) {
      healthConnectState.value = HealthConnectState.unavailable;
      return false;
    }
    var granted = await _health.hasReadPermissions();
    if (!granted && prompt) granted = await _health.requestReadPermissions();
    healthConnectState.value =
        granted ? HealthConnectState.ok : HealthConnectState.permissionDenied;
    return granted;
  }

  /// "Link your watch" step 1: opens the MindTwin listing in the paired watch's Play
  /// Store. The watch component is part of the patient app (same applicationId), so this
  /// is the same app, just installed on the watch. Returns null on success, else a
  /// user-facing reason.
  Future<String?> installOnWatch() => _remoteWatchAction('installOnWatch');

  /// "Link your watch" step 2: opens MindTwin on the watch so the patient can grant the
  /// heart-rate permission there (sensor permissions can only be granted on the watch).
  Future<String?> openOnWatch() => _remoteWatchAction('openOnWatch');

  Future<String?> _remoteWatchAction(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'Smartwatch linking is available on Android phones only.';
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(method);
      final sent = (raw?['sent'] as num?)?.toInt() ?? 0;
      if (sent > 0) return null;
      return raw?['error'] == 'no_watch'
          ? 'No paired watch found. Pair your watch with the Galaxy Wearable app first.'
          : 'Could not reach the watch. Make sure it is nearby and unlocked, then try again.';
    } catch (e) {
      debugPrint('[WearableSync] $method failed: $e');
      return 'Could not reach the watch. Try again.';
    } finally {
      unawaited(refreshWatchStatus());
    }
  }

  /// Re-requests Health Connect permissions (e.g. from a settings button).
  Future<bool> requestHealthPermissions() => _ensureHealthConnect(prompt: true);

  /// Reads new Health Connect data and writes it to Firestore. Never invents values.
  Future<void> syncNow() async {
    final uid = _uid;
    if (uid == null || _syncing) return;
    if (healthConnectState.value != HealthConnectState.ok &&
        !await _ensureHealthConnect(prompt: false)) {
      return;
    }
    _syncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // Heart rate: re-read the last 24 h each time (Health Connect sources such as Samsung
      // Health sync late, with old timestamps) and skip samples already written.
      final hrKey = 'vitals_hc_hr_written_$uid';
      final written = (prefs.getStringList(hrKey) ?? const <String>[]).toSet();
      final hr = await _health.readHeartRate(now.subtract(const Duration(hours: 24)), now);
      final newHr = hr
          .where((r) => !written.contains('${r.measuredAt.millisecondsSinceEpoch}'))
          .toList();

      // Sleep (per night) and steps (per day): write only when the aggregate changed.
      final sleep = await _health.readSleepNights(now.subtract(const Duration(days: 3)), now);
      final steps = await _health.readDailySteps(now.subtract(const Duration(days: 1)), now);
      final sigKey = 'vitals_hc_agg_written_$uid';
      final sigs = (prefs.getStringList(sigKey) ?? const <String>[]).toSet();
      String sig(VitalReading r) =>
          '${r.type.id}:${r.measuredAt.millisecondsSinceEpoch}:${r.value}';
      final newAgg = [...sleep, ...steps].where((r) => !sigs.contains(sig(r))).toList();

      final toWrite = [...newHr, ...newAgg];
      if (toWrite.isNotEmpty) {
        final ok = await _repo.writeReadings(
          patientId: uid,
          therapistId: _therapistId,
          readings: toWrite,
        );
        if (_uid != uid) return; // signed out meanwhile
        if (ok) {
          final cutoff = now.subtract(const Duration(hours: 26)).millisecondsSinceEpoch;
          final keepHr = {
            ...written.where((s) => (int.tryParse(s) ?? 0) >= cutoff),
            ...newHr.map((r) => '${r.measuredAt.millisecondsSinceEpoch}'),
          };
          await prefs.setStringList(hrKey, keepHr.toList());
          final keepSig = [...sigs, ...newAgg.map(sig)];
          await prefs.setStringList(
            sigKey,
            keepSig.length > 64 ? keepSig.sublist(keepSig.length - 64) : keepSig,
          );
        }
      }

      if (hr.isNotEmpty) {
        final latest = hr.last;
        _publishLive(latest.value, latest.measuredAt, 'health_connect');
      }
      lastHealthSyncAt.value = DateTime.now();
    } catch (e) {
      debugPrint('[WearableSync] Health Connect sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  void _publishLive(double bpm, DateTime measuredAt, String source) {
    final prevTs = _lastReceivedVitals?['timestamp'] as DateTime?;
    if (prevTs != null && !measuredAt.isAfter(prevTs)) return;
    final data = <String, dynamic>{
      'bpm': bpm.round(),
      'timestamp': measuredAt.toLocal(),
      'source': source,
    };
    _lastReceivedVitals = data;
    _heartRateStreamController.add(data);
  }

  Future<void> _handleMethod(MethodCall call) async {
    if (call.method != 'onHeartRateReceived') return;
    final args = call.arguments;
    if (args is! Map) return;
    final bpm = (args['bpm'] as num?)?.toDouble();
    final ms = (args['timestamp'] as num?)?.toInt();
    if (bpm == null || ms == null) return; // never substitute a time or value
    // Already persisted to Firestore natively; this is only the live UI copy.
    _publishLive(bpm, DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true), 'wear_os');
    if (watchStatus.value?.connected != true) unawaited(refreshWatchStatus());
  }
}
