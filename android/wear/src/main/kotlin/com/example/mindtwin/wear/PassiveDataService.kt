package com.example.mindtwin.wear

import android.util.Log
import androidx.health.services.client.PassiveListenerService
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType

class PassiveDataService : PassiveListenerService() {

    override fun onNewDataPointsReceived(dataPoints: DataPointContainer) {
        // Every point in the batch, each with its own real measurement time.
        val hrPoints = dataPoints.getData(DataType.HEART_RATE_BPM)
        if (hrPoints.isNotEmpty()) {
            Log.d("MindTwinWear", "Passive batch: ${hrPoints.size} heart-rate points")
            PhoneSync.sendHeartRatePoints(this, hrPoints, origin = "passive")
        }
    }

    override fun onPermissionLost() {
        Log.w("MindTwinWear", "Sensor permission revoked; passive monitoring stopped")
    }
}
