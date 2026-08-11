package com.example.mindtwin.wear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DeltaDataType
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.time.Instant
import java.util.concurrent.Executors

class HeartRateService : Service() {

    private val executor = Executors.newSingleThreadExecutor()
    private var registered = false

    private val measureCallback = object : MeasureCallback {
        override fun onDataReceived(dataPoints: DataPointContainer) {
            val hrPoints = dataPoints.getData(DataType.HEART_RATE_BPM)
            if (hrPoints.isNotEmpty()) {
                val bpm = hrPoints.last().value.toInt()
                Log.d("MindTwinWear", "Active measurement received: $bpm BPM")
                syncHeartRateToPhone(bpm)
            }
        }

        override fun onRegistered() {
            registered = true
            Log.d("MindTwinWear", "Measure callback registered.")
        }

        override fun onRegistrationFailed(t: Throwable) {
            Log.e("MindTwinWear", "Measure callback registration failed: ", t)
        }

        override fun onAvailabilityChanged(dataType: DeltaDataType<*, *>, availability: Availability) {
            Log.d("MindTwinWear", "Measure availability changed: $dataType -> $availability")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        registerMeasure()
        return START_STICKY
    }

    private fun registerMeasure() {
        if (registered) return
        val client = HealthServices.getClient(this).measureClient
        try {
            client.registerMeasureCallback(DataType.HEART_RATE_BPM, executor, measureCallback)
        } catch (e: Exception) {
            Log.e("MindTwinWear", "Failed to register measure callback: ", e)
        }
    }

    private fun syncHeartRateToPhone(bpm: Int) {
        val dataClient = Wearable.getDataClient(this)
        val putDataMapRequest = PutDataMapRequest.create("/wearable/heart_rate").apply {
            dataMap.putInt("bpm", bpm)
            dataMap.putLong("timestamp", Instant.now().toEpochMilli())
            setUrgent()
        }
        dataClient.putDataItem(putDataMapRequest.asPutDataRequest())
            .addOnSuccessListener {
                Log.d("MindTwinWear", "Successfully synced $bpm BPM to phone")
            }
            .addOnFailureListener { e ->
                Log.e("MindTwinWear", "Failed to sync BPM to phone: ", e)
            }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Heart Rate Monitoring",
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
            .build()

    override fun onDestroy() {
        super.onDestroy()
        try {
            val client = HealthServices.getClient(this).measureClient
            client.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, measureCallback)
        } catch (e: Exception) {
            Log.e("MindTwinWear", "Failed to unregister measure callback: ", e)
        }
        executor.shutdown()
    }

    companion object {
        private const val CHANNEL_ID = "heart_rate_monitoring"
        private const val NOTIFICATION_ID = 42
    }
}
