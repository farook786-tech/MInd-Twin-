package com.example.mindtwin.wear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import java.util.concurrent.Executors

/**
 * Foreground service keeping an active heart-rate measurement running so readings continue
 * while the watch screen is off. Readings are forwarded (max one per minute, real sample and
 * real timestamp) by [PhoneSync].
 */
class HeartRateService : Service() {

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var registered = false

    private val measureCallback = object : MeasureCallback {
        override fun onDataReceived(data: DataPointContainer) {
            val hrPoints = data.getData(DataType.HEART_RATE_BPM)
            if (hrPoints.isNotEmpty()) {
                PhoneSync.sendHeartRatePoints(this@HeartRateService, hrPoints, origin = "active")
            }
        }

        override fun onRegistered() {
            registered = true
            Log.d(TAG, "Measure callback registered.")
        }

        override fun onRegistrationFailed(throwable: Throwable) {
            registered = false
            Log.e(TAG, "Measure callback registration failed", throwable)
        }

        override fun onAvailabilityChanged(dataType: DeltaDataType<*, *>, availability: Availability) {
            Log.d(TAG, "Measure availability changed: $dataType -> $availability")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Monitoring.hasSensorPermission(this)) {
            Log.w(TAG, "Sensor permission missing; stopping HeartRateService")
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            // API 34+ requires the FGS type at start; ServiceCompat ignores it on older versions.
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
            )
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return START_NOT_STICKY
        }
        registerMeasure()
        return START_STICKY
    }

    private fun registerMeasure() {
        if (registered) return
        try {
            HealthServices.getClient(this).measureClient
                .registerMeasureCallback(DataType.HEART_RATE_BPM, executor, measureCallback)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register measure callback", e)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Heart rate monitoring",
            NotificationManager.IMPORTANCE_LOW
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MindTwin")
            .setContentText("Monitoring heart rate")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

    override fun onDestroy() {
        try {
            HealthServices.getClient(this).measureClient
                .unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, measureCallback)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to unregister measure callback", e)
        }
        registered = false
        executor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MindTwinWear"
        private const val CHANNEL_ID = "heart_rate_monitoring"
        private const val NOTIFICATION_ID = 42
    }
}
