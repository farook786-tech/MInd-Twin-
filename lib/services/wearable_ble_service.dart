import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum WearableConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class WearableDeviceInfo {
  final String id;
  final String name;
  final int rssi;

  const WearableDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

class WearableMetrics {
  final double heartRate;
  final double activityLevel;
  final double screenTimeHours;
  final double sleepQuality;
  final int steps;
  final DateTime timestamp;
  final bool hasHeartRate;
  final bool hasActivityLevel;
  final bool hasScreenTime;
  final bool hasSleepQuality;
  final bool hasSteps;
  final String source;

  const WearableMetrics({
    required this.heartRate,
    required this.activityLevel,
    required this.screenTimeHours,
    required this.sleepQuality,
    required this.steps,
    required this.timestamp,
    required this.hasHeartRate,
    required this.hasActivityLevel,
    required this.hasScreenTime,
    required this.hasSleepQuality,
    required this.hasSteps,
    required this.source,
  });

  bool get isClinicalComplete =>
      hasHeartRate && hasActivityLevel && hasScreenTime && hasSleepQuality;

  WearableMetrics copyWith({
    double? heartRate,
    double? activityLevel,
    double? screenTimeHours,
    double? sleepQuality,
    int? steps,
    bool? hasHeartRate,
    bool? hasActivityLevel,
    bool? hasScreenTime,
    bool? hasSleepQuality,
    bool? hasSteps,
    String? source,
  }) {
    return WearableMetrics(
      heartRate: heartRate ?? this.heartRate,
      activityLevel: activityLevel ?? this.activityLevel,
      screenTimeHours: screenTimeHours ?? this.screenTimeHours,
      sleepQuality: sleepQuality ?? this.sleepQuality,
      steps: steps ?? this.steps,
      timestamp: DateTime.now(),
      hasHeartRate: hasHeartRate ?? this.hasHeartRate,
      hasActivityLevel: hasActivityLevel ?? this.hasActivityLevel,
      hasScreenTime: hasScreenTime ?? this.hasScreenTime,
      hasSleepQuality: hasSleepQuality ?? this.hasSleepQuality,
      hasSteps: hasSteps ?? this.hasSteps,
      source: source ?? this.source,
    );
  }
}

class WearableBleService {
  static final WearableBleService _instance = WearableBleService._internal();
  factory WearableBleService() => _instance;
  WearableBleService._internal();

  final _connectionController =
      StreamController<WearableConnectionState>.broadcast();
  final _metricsController = StreamController<WearableMetrics>.broadcast();

  Stream<WearableConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<WearableMetrics> get metricsStream => _metricsController.stream;

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final List<StreamSubscription<List<int>>> _charSubscriptions = [];
  final Map<String, BluetoothDevice> _lastScanDevices = {};

  WearableConnectionState _state = WearableConnectionState.disconnected;
  WearableConnectionState get state => _state;

  WearableMetrics _latestMetrics = WearableMetrics(
    heartRate: 0,
    activityLevel: 0,
    screenTimeHours: 0,
    sleepQuality: 0,
    steps: 0,
    timestamp: DateTime.now(),
    hasHeartRate: false,
    hasActivityLevel: false,
    hasScreenTime: false,
    hasSleepQuality: false,
    hasSteps: false,
    source: 'none',
  );

  Future<List<WearableDeviceInfo>> scanForDevices({int timeoutSeconds = 10}) async {
    if (kIsWeb) return const [];
    final allowed = await _requestBlePermissions();
    if (!allowed) return const [];

    _setState(WearableConnectionState.scanning);

    try {
      final found = <String, WearableDeviceInfo>{};
      _lastScanDevices.clear();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final result in results) {
          final id = result.device.remoteId.str;
          final name =
              result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : (result.advertisementData.advName.isNotEmpty
                      ? result.advertisementData.advName
                      : 'Unknown device');
          _lastScanDevices[id] = result.device;
          found[id] = WearableDeviceInfo(id: id, name: name, rssi: result.rssi);
        }
      });

      await FlutterBluePlus.startScan(timeout: Duration(seconds: timeoutSeconds));
      await Future.delayed(Duration(seconds: timeoutSeconds));
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      _setState(WearableConnectionState.disconnected);

      final list = found.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      return list;
    } catch (_) {
      _setState(WearableConnectionState.error);
      return const [];
    }
  }

  Future<bool> connectToWearable({List<String>? nameHints}) async {
    if (kIsWeb) {
      _setState(WearableConnectionState.error);
      return false;
    }

    final allowed = await _requestBlePermissions();
    if (!allowed) {
      _setState(WearableConnectionState.error);
      return false;
    }

    await disconnect();

    final hints = (nameHints ?? ['watch', 'band', 'fit', 'mi', 'galaxy'])
        .map((e) => e.toLowerCase())
        .toList();
    final devices = await scanForDevices(timeoutSeconds: 12);

    WearableDeviceInfo? selected;
    for (final d in devices) {
      final lower = d.name.toLowerCase();
      if (hints.any((hint) => lower.contains(hint))) {
        selected = d;
        break;
      }
    }

    if (selected == null) {
      _setState(WearableConnectionState.disconnected);
      return false;
    }

    return connectToDevice(selected.id);
  }

  Future<bool> connectToDevice(String deviceId) async {
    if (kIsWeb) return false;

    final allowed = await _requestBlePermissions();
    if (!allowed) {
      _setState(WearableConnectionState.error);
      return false;
    }

    final device = _lastScanDevices[deviceId];
    if (device == null) {
      _setState(WearableConnectionState.error);
      return false;
    }

    _setState(WearableConnectionState.connecting);
    _latestMetrics = WearableMetrics(
      heartRate: _latestMetrics.heartRate,
      activityLevel: _latestMetrics.activityLevel,
      screenTimeHours: _latestMetrics.screenTimeHours,
      sleepQuality: _latestMetrics.sleepQuality,
      steps: _latestMetrics.steps,
      timestamp: DateTime.now(),
      hasHeartRate: false,
      hasActivityLevel: false,
      hasScreenTime: false,
      hasSleepQuality: false,
      hasSteps: false,
      source: 'none',
    );

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;
      await _subscribeToMetrics(device);
      _setState(WearableConnectionState.connected);
      _metricsController.add(_latestMetrics);
      return true;
    } catch (_) {
      _setState(WearableConnectionState.error);
      return false;
    }
  }

  Future<void> disconnect() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    for (final sub in _charSubscriptions) {
      await sub.cancel();
    }
    _charSubscriptions.clear();

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
    }

    _connectedDevice = null;
    _latestMetrics = WearableMetrics(
      heartRate: 0,
      activityLevel: 0,
      screenTimeHours: 0,
      sleepQuality: 0,
      steps: 0,
      timestamp: DateTime.now(),
      hasHeartRate: false,
      hasActivityLevel: false,
      hasScreenTime: false,
      hasSleepQuality: false,
      hasSteps: false,
      source: 'none',
    );
    _setState(WearableConnectionState.disconnected);
  }

  Future<void> _subscribeToMetrics(BluetoothDevice device) async {
    final services = await device.discoverServices();
    bool hasNotifyChannel = false;

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (!characteristic.properties.notify && !characteristic.properties.indicate) {
          continue;
        }
        hasNotifyChannel = true;

        await characteristic.setNotifyValue(true);
        final sub = characteristic.lastValueStream.listen((value) {
          _handleCharacteristicPacket(characteristic.uuid.str, value);
        });
        _charSubscriptions.add(sub);
      }
    }

    // Some watch firmwares don't expose notify for HR. Try a direct read once.
    if (!hasNotifyChannel) {
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.str.toLowerCase();
          if (!characteristic.properties.read) continue;
          if (!uuid.contains('2a37')) continue;
          try {
            final packet = await characteristic.read();
            _handleCharacteristicPacket(characteristic.uuid.str, packet);
          } catch (_) {
            // Ignore read errors for non-readable devices.
          }
        }
      }
    }
  }

  void _handleCharacteristicPacket(String uuid, List<int> data) {
    if (data.isEmpty) return;

    final lowerUuid = uuid.toLowerCase();

    if (lowerUuid.contains('2a37')) {
      final parsedHr = _parseHeartRateFromStandardPacket(data);
      if (parsedHr != null) {
        _latestMetrics = _latestMetrics.copyWith(
          heartRate: parsedHr.toDouble(),
          hasHeartRate: true,
          source: 'hr_characteristic',
        );
        _metricsController.add(_latestMetrics);
        return;
      }
    }

    final jsonMetrics = _parseJsonMetrics(data);
    if (jsonMetrics != null) {
      final parsedSteps = (jsonMetrics['steps'] ?? _latestMetrics.steps.toDouble()).round();
      final derivedActivity = _deriveActivityLevel(
        explicitActivity: jsonMetrics['activityLevel'],
        steps: parsedSteps,
      );
      _latestMetrics = _latestMetrics.copyWith(
        heartRate: jsonMetrics['heartRate'],
        activityLevel: derivedActivity,
        screenTimeHours: jsonMetrics['screenTimeHours'],
        sleepQuality: jsonMetrics['sleepQuality'],
        steps: parsedSteps,
        hasHeartRate: true,
        hasActivityLevel: jsonMetrics['activityLevel'] != null || jsonMetrics['steps'] != null,
        hasScreenTime: jsonMetrics['screenTimeHours'] != null,
        hasSleepQuality: jsonMetrics['sleepQuality'] != null,
        hasSteps: jsonMetrics['steps'] != null,
        source: 'json_packet',
      );
      _metricsController.add(_latestMetrics);
      return;
    }

  }

  int? _parseHeartRateFromStandardPacket(List<int> data) {
    if (data.length < 2) return null;
    final flags = data.first;
    final is16Bit = (flags & 0x01) != 0;
    if (is16Bit && data.length >= 3) {
      return data[1] | (data[2] << 8);
    }
    return data[1];
  }

  Map<String, double?>? _parseJsonMetrics(List<int> data) {
    try {
      final text = utf8.decode(data);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;

      double? asDouble(dynamic value) {
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value);
        return null;
      }

      final heartRate = asDouble(decoded['heartRate'] ?? decoded['hr']);
      final activity = asDouble(decoded['activityLevel'] ?? decoded['activity']);
      final screen = asDouble(decoded['screenTimeHours'] ?? decoded['screenTime']);
      final sleep = asDouble(decoded['sleepQuality'] ?? decoded['sleep']);
      final steps = asDouble(
        decoded['steps'] ??
            decoded['stepCount'] ??
            decoded['footSteps'] ??
            decoded['totalSteps'],
      );

      return {
        'heartRate': heartRate?.clamp(40.0, 180.0),
        'activityLevel': activity?.clamp(0.0, 10.0),
        'screenTimeHours': screen?.clamp(0.0, 16.0),
        'sleepQuality': sleep?.clamp(0.0, 10.0),
        'steps': steps?.clamp(0.0, 100000.0),
      };
    } catch (_) {
      return null;
    }
  }

  double _deriveActivityLevel({double? explicitActivity, int? steps}) {
    if (explicitActivity != null) {
      return explicitActivity.clamp(0.0, 10.0);
    }

    if (steps == null) {
      return _latestMetrics.activityLevel;
    }

    if (steps <= 2000) return 1.5;
    if (steps <= 4000) return 3.0;
    if (steps <= 7000) return 5.0;
    if (steps <= 10000) return 7.0;
    return 9.0;
  }

  Future<bool> _requestBlePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();

    if (scan.isGranted && connect.isGranted) {
      return true;
    }

    final location = await Permission.locationWhenInUse.request();
    return location.isGranted;
  }

  void _setState(WearableConnectionState next) {
    _state = next;
    _connectionController.add(next);
  }
}
