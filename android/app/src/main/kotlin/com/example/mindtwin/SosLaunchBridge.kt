package com.example.mindtwin

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands "open Safety Resources" (from the watch-SOS notification, see [WearSosHandler]) to
 * Flutter over the "com.example.mindtwin/sos" channel.
 *  - cold start: Flutter calls `takeLaunchAction` once it is ready;
 *  - app already running: `onLaunchAction` is invoked on Flutter directly.
 */
object SosLaunchBridge {
    private const val CHANNEL = "com.example.mindtwin/sos"

    private var channel: MethodChannel? = null
    private var pending: String? = null

    fun attach(engine: FlutterEngine, launchIntent: Intent?) {
        capture(launchIntent)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeLaunchAction" -> {
                        result.success(pending)
                        pending = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    fun onNewIntent(intent: Intent?) {
        val action = capture(intent) ?: return
        val ch = channel ?: return
        pending = null
        ch.invokeMethod("onLaunchAction", action)
    }

    private fun capture(intent: Intent?): String? {
        val action = intent?.getStringExtra(WearSosHandler.EXTRA_ACTION) ?: return null
        intent.removeExtra(WearSosHandler.EXTRA_ACTION) // consume once (not on recreate)
        pending = action
        return action
    }
}
