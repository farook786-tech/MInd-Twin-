import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import 'universal_watch_health_service.dart';
import 'vitals_aggregation.dart';
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
/// * Health Connect (heart rate, sleep, steps): read here. Heart rate is written as one
///   `vitals` doc per closed 5-minute window plus out-of-range samples as `immediate` docs;
///   sleep as one doc per night; steps and sleep also go to `vitals_daily` (throttled). Real
///   measurement times and deterministic ids. Nothing is written when there is no data.
///   Write budget: docs/DATA_MODEL.md "Free-tier budget".
///
/// Lifecycle: call [startForCurrentPatient] after a PATIENT signs in, [stop] on sign-out.
class WearableSyncService {
  static final WearableSyncService _instance = WearableSyncService._internal();
  factory WearableSyncService() => _instance;
  WearableSyncService._internal();

  static const _channel = MethodChannel('com.example.mindtwin/wearable');
  static const _syncInterval = Duration(minutes: 15);

  /// Health Connect sources (e.g. Samsung Health) sync late: a window is written only once
  /// it closed this long ago. Samples arriving after that are not added to the (immutable)
  /// window doc; out-of-range ones are still written as immediate docs.
  static const _windowGrace = Duration(minutes: 20);
  static const _profileRefresh = Duration(hours: 1);
  static const _latestEvery = Duration(minutes: 15);
  static const _dailyEvery = Duration(hours: 3);

  final _health = UniversalWatchHealthService();
  final _repo = VitalsRepository();

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  String? _uid;
  String? _therapistId;
  HrThresholds _thresholds = const HrThresholds();
  DateTime? _profileAt;
  DateTime? _latestWrittenAt;
  String? _latestSig;
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
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

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
    await _refreshProfile(force: true);

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
    _thresholds = const HrThresholds();
    _profileAt = null;
    _latestWrittenAt = null;
    _latestSig = null;
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
    healthConnectState.value = granted ? HealthConnectState.ok : HealthConnectState.permissionDenied;
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

  /// therapistId + vitalThresholds from users/{uid} (cached for [_profileRefresh]).
  Future<void> _refreshProfile({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return;
    final at = _profileAt;
    if (!force && at != null && DateTime.now().difference(at) < _profileRefresh) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (_uid != uid) return;
      final data = snap.data();
      final t = data?['therapistId'];
      _therapistId = (t is String && t.isNotEmpty) ? t : null;
      _thresholds = HrThresholds.fromUserDoc(data);
      _profileAt = DateTime.now();
    } catch (e) {
      debugPrint('[WearableSync] could not read users/$uid: $e');
    }
  }

  static Set<String> _recent(Iterable<String> keys, int cutoffMs) =>
      keys.where((s) => (int.tryParse(s) ?? 0) >= cutoffMs).toSet();

  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  /// Reads new Health Connect data and writes it to Firestore. Never invents values.
  Future<void> syncNow() async {
    final uid = _uid;
    if (uid == null || _syncing) return;
    if (healthConnectState.value != HealthConnectState.ok && !await _ensureHealthConnect(prompt: false)) {
      return;
    }
    _syncing = true;
    try {
      await _refreshProfile();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final from = now.subtract(const Duration(hours: 24));
      final cutoff = now.subtract(const Duration(hours: 26)).millisecondsSinceEpoch;

      // Heart rate: re-read the last 24 h each time (Health Connect sources such as Samsung
      // Health sync late, with old timestamps).
      final hr = await _health.readHeartRate(from, now);

      // (a) Out-of-range samples -> individual immediate docs (rate-limited, see
      //     HeartRateAggregation.selectImmediate), so threshold alerts are not delayed.
      final immKey = 'vitals_hc_hr_imm_$uid';
      final immWritten = (prefs.getStringList(immKey) ?? const <String>[]).toSet();
      final immediates = HeartRateAggregation.selectImmediate(hr, _thresholds)
          .where((r) => !immWritten.contains('${r.measuredAt.millisecondsSinceEpoch}'))
          .map((r) => VitalReading(
                type: VitalType.heartRate,
                value: _round1(r.value),
                measuredAt: r.measuredAt,
                source: r.source,
                immediate: true,
              ))
          .toList();

      // (b) Closed 5-minute windows -> one doc each.
      final winKey = 'vitals_hc_hr_win_$uid';
      final winWritten = (prefs.getStringList(winKey) ?? const <String>[]).toSet();
      final closed = HeartRateAggregation.aggregate(hr)
          .where((w) =>
              !w.start.isBefore(from) && // first window may be cut by the query range
              !w.end.isAfter(now.subtract(_windowGrace)))
          .toList();
      final newWindows = closed
          .where((w) => !winWritten.contains('${w.startMillis}'))
          .map((w) => VitalReading(
                type: VitalType.heartRate,
                value: w.roundedAvg.toDouble(),
                measuredAt: w.end,
                source: 'health_connect',
                windowStart: w.start,
                min: _round1(w.min),
                max: _round1(w.max),
                sampleCount: w.count,
              ))
          .toList();

      // (c) Sleep: one doc per night, only when the night's total changed.
      //     Steps: no per-change vitals docs any more (that was up to ~96/day); daily totals
      //     go to vitals_daily and users.latestVitals.steps.
      final sleep = await _health.readSleepNights(now.subtract(const Duration(days: 3)), now);
      final steps = await _health.readDailySteps(now.subtract(const Duration(days: 1)), now);
      final sigKey = 'vitals_hc_agg_written_$uid';
      final sigs = (prefs.getStringList(sigKey) ?? const <String>[]).toSet();
      String sig(VitalReading r) => '${r.type.id}:${r.measuredAt.millisecondsSinceEpoch}:${r.value}';
      final newSleep = sleep.where((r) => !sigs.contains(sig(r))).toList();

      final toWrite = [...immediates, ...newWindows, ...newSleep];
      if (toWrite.isNotEmpty) {
        final ok = await _repo.writeReadings(
          patientId: uid,
          therapistId: _therapistId,
          readings: toWrite,
        );
        if (_uid != uid) return; // signed out meanwhile
        if (ok) {
          await prefs.setStringList(
              immKey,
              {
                ..._recent(immWritten, cutoff),
                ...immediates.map((r) => '${r.measuredAt.millisecondsSinceEpoch}'),
              }.toList());
          await prefs.setStringList(
              winKey,
              {
                ..._recent(winWritten, cutoff),
                ...newWindows.map((r) => '${r.windowStart!.millisecondsSinceEpoch}'),
              }.toList());
          final keepSig = [...sigs, ...newSleep.map(sig)];
          await prefs.setStringList(
            sigKey,
            keepSig.length > 64 ? keepSig.sublist(keepSig.length - 64) : keepSig,
          );
        }
      }

      // Daily heart-rate summary: on Android the native uploader owns the hr* fields of
      // vitals_daily (it also sees Wear OS windows while this Dart code is not running), so
      // Health Connect windows are handed to it (deduplicated by window start there).
      if (closed.isNotEmpty && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(_channel.invokeMethod('recordHeartRateWindows', [
          for (final w in closed)
            {
              'start': w.startMillis,
              'avg': w.avg,
              'min': w.min,
              'max': w.max,
              'count': w.count,
            },
        ]).catchError((Object e) {
          debugPrint('[WearableSync] recordHeartRateWindows failed: $e');
          return null;
        }));
      }
      await _mergeDaily(prefs, uid, now, sleep: sleep, steps: steps, hrWindows: closed);
      if (_uid != uid) return;

      final todayKey = HeartRateAggregation.localDateKey(now);
      _maybeUpdateLatest(uid, now, [
        if (hr.isNotEmpty) hr.last,
        if (sleep.isNotEmpty) sleep.last,
        ...steps.where((r) => HeartRateAggregation.localDateKey(r.measuredAt) == todayKey),
      ]);

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

  /// users.latestVitals: at most once per [_latestEvery], and only when something changed.
  /// A Health Connect heart rate older than a live Wear OS reading is not written (the
  /// native uploader keeps the Wear value current).
  void _maybeUpdateLatest(String uid, DateTime now, List<VitalReading> candidates) {
    final wearAt =
        _lastReceivedVitals?['source'] == 'wear_os' ? _lastReceivedVitals!['timestamp'] as DateTime? : null;
    final list = candidates
        .where((r) => r.type != VitalType.heartRate || wearAt == null || r.measuredAt.isAfter(wearAt))
        .toList();
    if (list.isEmpty) return;
    final sig = list.map((r) => '${r.type.id}:${r.measuredAt.millisecondsSinceEpoch}:${r.value}').join('|');
    final at = _latestWrittenAt;
    if (sig == _latestSig || (at != null && now.difference(at) < _latestEvery)) return;
    _latestSig = sig;
    _latestWrittenAt = now;
    _repo.updateLatestVitals(uid, list);
  }

  /// Merges sleep / steps (and, off Android, heart-rate) daily summaries into
  /// `vitals_daily/{uid}_{yyyy-MM-dd}` (patient-local date). Throttled: a past day is
  /// written when its values change; today at most every [_dailyEvery] unless the sleep
  /// value changed. Typically 3-8 writes/day.
  Future<void> _mergeDaily(
    SharedPreferences prefs,
    String uid,
    DateTime now, {
    required List<VitalReading> sleep,
    required List<VitalReading> steps,
    required List<HrWindow> hrWindows,
  }) async {
    final today = HeartRateAggregation.localDateKey(now);
    final byDate = <String, Map<String, Object?>>{};
    for (final r in sleep) {
      byDate.putIfAbsent(HeartRateAggregation.localDateKey(r.measuredAt), () => {})['sleepHours'] =
          _round1(r.value);
    }
    for (final r in steps) {
      byDate.putIfAbsent(HeartRateAggregation.localDateKey(r.measuredAt), () => {})['steps'] =
          r.value.round();
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      final todays = hrWindows.where((w) => HeartRateAggregation.localDateKey(w.start) == today);
      final s = HeartRateAggregation.summarizeDay(todays);
      if (s != null) {
        byDate.putIfAbsent(today, () => {}).addAll({
          'hrRestingEstimate': s.restingEstimate,
          'hrAvg': s.avg,
          'hrMin': s.min,
          'hrMax': s.max,
          'hrWindows': s.windows,
        });
      }
    }
    if (byDate.isEmpty) return;

    final stateKey = 'vitals_daily_state_$uid';
    Map<String, dynamic> state;
    try {
      state = (jsonDecode(prefs.getString(stateKey) ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      state = <String, dynamic>{};
    }
    var changed = false;
    for (final e in byDate.entries) {
      final prev = state[e.key] is Map ? (state[e.key] as Map).cast<String, dynamic>() : null;
      final sig = jsonEncode(e.value);
      if (prev?['sig'] == sig) continue;
      final lastAt = (prev?['at'] as num?)?.toInt();
      final sleepChanged = e.value['sleepHours'] != null && e.value['sleepHours'] != prev?['sleep'];
      final due = e.key != today ||
          lastAt == null ||
          sleepChanged ||
          now.millisecondsSinceEpoch - lastAt >= _dailyEvery.inMilliseconds;
      if (!due) continue;
      final ok = await _repo.mergeDaily(
        patientId: uid,
        therapistId: _therapistId,
        dateKey: e.key,
        fields: e.value,
      );
      if (_uid != uid) return;
      if (!ok) continue;
      state[e.key] = {'sig': sig, 'at': now.millisecondsSinceEpoch, 'sleep': e.value['sleepHours']};
      changed = true;
    }
    if (!changed) return;
    final keys = state.keys.toList()..sort();
    while (keys.length > 7) {
      state.remove(keys.removeAt(0));
    }
    await prefs.setString(stateKey, jsonEncode(state));
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
