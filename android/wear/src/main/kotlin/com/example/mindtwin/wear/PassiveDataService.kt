package com.example.mindtwin.wear

import android.util.Log
import androidx.health.services.client.PassiveListenerService
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.IntervalDataPoint
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.time.Instant

class PassiveDataService : PassiveListenerService() {

    override fun onNewDataPointsReceived(dataPoints: DataPointContainer) {
        val hrPoints = dataPoints.getData(DataType.HEART_RATE_BPM)
        if (hrPoints.isNotEmpty()) {
            val latestPoint = hrPoints.last()
            val bpm = latestPoint.value.toInt()
            Log.d("MindTwinWear", "Received heart rate point: $bpm BPM")
            syncHeartRateToPhone(bpm)
        }
    }

    private fun syncHeartRateToPhone(bpm: Int) {
        val dataClient = Wearable.getDataClient(this)
        val putDataMapRequest = PutDataMapRequest.create("/wearable/heart_rate").apply {
            dataMap.putInt("bpm", bpm)
            dataMap.putLong("timestamp", Instant.now().toEpochMilli())
            // Set as urgent to sync instantly
            setUrgent()
        }
        val putDataReq = putDataMapRequest.asPutDataRequest()
        dataClient.putDataItem(putDataReq)
            .addOnSuccessListener {
                Log.d("MindTwinWear", "Successfully synced $bpm BPM to phone")
            }
            .addOnFailureListener { e ->
                Log.e("MindTwinWear", "Failed to sync BPM to phone: ", e)
            }
    }
}
