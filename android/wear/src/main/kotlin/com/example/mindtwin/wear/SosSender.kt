package com.example.mindtwin.wear

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Watch SOS -> phone over the Wearable Data Layer.
 *
 * Contract (mirrored in android/app WearSosHandler.kt):
 *   path "/mindtwin/sos/<pressedAtMillis>", one urgent DataItem per SOS press
 *   pressedAt : Long   (epoch millis UTC when the patient confirmed the SOS)
 *   source    : String ("wear_os")
 *
 * A DataItem (not a fire-and-forget message) is used so the SOS is persisted by Play services
 * and delivered as soon as the phone becomes reachable again; the phone deletes it after
 * writing the crisis_events doc.
 */
object SosSender {
    private const val TAG = "MindTwinWearSos"
    const val PATH_PREFIX = "/mindtwin/sos"

    enum class Result {
        /** Queued in the Data Layer and a phone node is connected. */
        SENT,
        /** Queued, but no phone is connected now; delivered when it reconnects. */
        PHONE_NOT_REACHABLE,
        /** Could not even be queued. */
        FAILED,
    }

    suspend fun send(context: Context): Result {
        val app = context.applicationContext
        val pressedAt = System.currentTimeMillis()
        val request = PutDataMapRequest.create("$PATH_PREFIX/$pressedAt").apply {
            dataMap.putLong("pressedAt", pressedAt)
            dataMap.putString("source", "wear_os")
        }.asPutDataRequest().setUrgent()

        return try {
            Wearable.getDataClient(app).putDataItem(request).await()
            val nodes = withTimeoutOrNull(5_000L) {
                Wearable.getNodeClient(app).connectedNodes.await()
            } ?: emptyList()
            Log.i(TAG, "SOS queued @ $pressedAt; connected nodes=${nodes.size}")
            if (nodes.isEmpty()) Result.PHONE_NOT_REACHABLE else Result.SENT
        } catch (e: Exception) {
            Log.e(TAG, "Failed to queue SOS", e)
            Result.FAILED
        }
    }
}
