package com.example.mindtwin

import android.os.Bundle
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {

    private val CHANNEL = "com.example.mindtwin/wearable"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "isWatchConnected") {
                // For simulator/dev purposes, always return true or check nodes
                result.success(true)
            } else if (call.method == "simulateHeartRate") {
                val bpm = call.argument<Int>("bpm") ?: 75
                val timestamp = System.currentTimeMillis()
                forwardHeartRate(bpm, timestamp)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Wearable.getDataClient(this).addListener(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        Wearable.getDataClient(this).removeListener(this)
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type == DataEvent.TYPE_CHANGED) {
                val item = event.dataItem
                if (item.uri.path == "/wearable/heart_rate") {
                    val dataMap = DataMapItem.fromDataItem(item).dataMap
                    val bpm = dataMap.getInt("bpm")
                    val timestamp = dataMap.getLong("timestamp")
                    forwardHeartRate(bpm, timestamp)
                }
            }
        }
    }

    private fun forwardHeartRate(bpm: Int, timestamp: Long) {
        runOnUiThread {
            methodChannel?.invokeMethod(
                "onHeartRateReceived",
                mapOf(
                    "bpm" to bpm,
                    "timestamp" to timestamp
                )
            )
        }
    }
}
