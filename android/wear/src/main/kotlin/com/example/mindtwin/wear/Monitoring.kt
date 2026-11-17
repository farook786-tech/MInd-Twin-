package com.example.mindtwin.wear

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.PassiveListenerConfig

/** Permission model + start logic shared by MainActivity and BootReceiver. */
object Monitoring {
    private const val TAG = "MindTwinWear"

    // Wear OS 6 (API 36) replaced BODY_SENSORS with granular health permissions.
    private const val READ_HEART_RATE = "android.permission.health.READ_HEART_RATE"
    private const val READ_IN_BACKGROUND = "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"
    private const val API_36 = 36

    /** Permission that gates heart-rate sensor access on this OS version. */
    val sensorPermission: String
        get() = if (Build.VERSION.SDK_INT >= API_36) READ_HEART_RATE else Manifest.permission.BODY_SENSORS

    /** Background sensor permission (needed for passive delivery / restart from boot), or null. */
    val backgroundPermission: String?
        get() = when {
            Build.VERSION.SDK_INT >= API_36 -> READ_IN_BACKGROUND
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> Manifest.permission.BODY_SENSORS_BACKGROUND
            else -> null // API 30-32: BODY_SENSORS already covers background use.
        }

    fun foregroundPermissions(): Array<String> {
        val list = mutableListOf(sensorPermission)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            list.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        return list.toTypedArray()
    }

    fun granted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    fun hasSensorPermission(context: Context) = granted(context, sensorPermission)

    fun hasBackgroundPermission(context: Context): Boolean =
        backgroundPermission?.let { granted(context, it) } ?: true

    /** Registers passive monitoring and starts the foreground HR service. Safe to call repeatedly. */
    fun startAll(context: Context) {
        val app = context.applicationContext
        if (!hasSensorPermission(app)) {
            Log.w(TAG, "Not starting monitoring: $sensorPermission not granted")
            return
        }
        registerPassive(app)
        try {
            ContextCompat.startForegroundService(app, Intent(app, HeartRateService::class.java))
        } catch (e: Exception) {
            // e.g. ForegroundServiceStartNotAllowedException; passive monitoring still runs.
            Log.e(TAG, "Failed to start HeartRateService", e)
        }
    }

    private fun registerPassive(app: Context) {
        try {
            val config = PassiveListenerConfig.builder()
                .setDataTypes(setOf(DataType.HEART_RATE_BPM))
                .build()
            val future = HealthServices.getClient(app).passiveMonitoringClient
                .setPassiveListenerServiceAsync(PassiveDataService::class.java, config)
            future.addListener({
                try {
                    future.get()
                    Log.d(TAG, "Passive heart-rate listener registered")
                } catch (e: Exception) {
                    Log.e(TAG, "Passive listener registration failed", e)
                }
            }, ContextCompat.getMainExecutor(app))
        } catch (e: Exception) {
            Log.e(TAG, "Passive listener registration failed", e)
        }
    }
}
