import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/patient/safety_resources_screen.dart';
import 'notification_router.dart';

/// Opens Safety Resources when the patient taps the phone notification
/// posted after a WATCH SOS (android WearSosHandler.kt / SosLaunchBridge.kt).
///
/// Call [attach] once the patient home screen is shown: it consumes a pending
/// cold-start action and listens for actions while the app is running.
class SosLaunchBridge {
  SosLaunchBridge._();

  static const MethodChannel _channel = MethodChannel('com.example.mindtwin/sos');
  static const String safetyResourcesAction = 'safety_resources';
  static const String _routeName = '/sos/safety_resources';
  static bool _attached = false;

  static Future<void> attach() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!_attached) {
      _attached = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onLaunchAction') _open(call.arguments?.toString());
        return null;
      });
    }
    try {
      _open(await _channel.invokeMethod<String>('takeLaunchAction'));
    } on MissingPluginException {
      // Therapist flavor / tests: no native side.
    } catch (e) {
      debugPrint('[SosLaunchBridge] takeLaunchAction failed: $e');
    }
  }

  static void _open(String? action) {
    if (action != safetyResourcesAction) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    var onTop = false;
    nav.popUntil((route) {
      onTop = route.settings.name == _routeName;
      return true;
    });
    if (onTop) return;
    nav.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: _routeName),
      builder: (_) => const SafetyResourcesScreen(),
    ));
  }
}
