package com.example.mindtwin.wear

import android.content.Context
import android.os.SystemClock
import android.util.Log
import androidx.health.services.client.data.HeartRateAccuracy
import androidx.health.services.client.data.SampleDataPoint
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.time.Instant

/**
 * Sends heart-rate readings to the phone over the Wearable Data Layer.
 *
 * Contract (mirrored in android/app WearVitalsUploader.kt):
 *   path "/mindtwin/hr/<measuredAtMillis>", one DataItem per reading (unique path, so nothing
 *   is overwritten). DataItems are persisted and re-synced by Play services when the phone is
 *   out of range, and the phone deletes each one after writing it to Firestore.
 *
 * At most one reading per [MIN_INTERVAL_MS] bucket is sent: continuous sensors emit ~1 Hz,
 * which would be 86k Firestore docs/day. The value sent is a REAL sample from that minute.
 */
object PhoneSync {
    private const val TAG = "MindTwinWear"
    const val PATH_PREFIX = "/mindtwin/hr"
    private const val MIN_INTERVAL_MS = 60_000L
    private const val MAX_BUCKETS = 3 * 24 * 60

    private val sentBuckets = LinkedHashSet<Long>()

    @Volatile var lastSentBpm: Double? = null
        private set
    @Volatile var lastSentAt: Long? = null
        private set

    fun bootInstant(): Instant =
        Instant.ofEpochMilli(System.currentTimeMillis() - SystemClock.elapsedRealtime())

    /** Returns true if the sample is from a sensor with skin contact and usable accuracy. */
    fun isReliable(point: SampleDataPoint<Double>): Boolean {
        val acc = point.accuracy as? HeartRateAccuracy ?: return true
        return when (acc.sensorStatus) {
            HeartRateAccuracy.SensorStatus.NO_CONTACT,
            HeartRateAccuracy.SensorStatus.UNRELIABLE -> false
            else -> true
        }
    }

    fun sendHeartRatePoints(context: Context, points: List<SampleDataPoint<Double>>, origin: String) {
        if (points.isEmpty()) return
        val boot = bootInstant()
        for (p in points) {
            if (!isReliable(p)) continue
            val measuredAt = p.getTimeInstant(boot).toEpochMilli()
            sendHeartRate(context, p.value, measuredAt, origin)
        }
    }

    fun sendHeartRate(context: Context, bpm: Double, measuredAt: Long, origin: String) {
        if (bpm.isNaN() || bpm < 20.0 || bpm > 250.0) return
        if (measuredAt <= 0L || measuredAt > System.currentTimeMillis() + 60_000L) return

        val bucket = measuredAt / MIN_INTERVAL_MS
        synchronized(sentBuckets) {
            if (!sentBuckets.add(bucket)) return
            while (sentBuckets.size > MAX_BUCKETS) {
                val it = sentBuckets.iterator(); it.next(); it.remove()
            }
        }

        val request = PutDataMapRequest.create("$PATH_PREFIX/$measuredAt").apply {
            dataMap.putDouble("bpm", bpm)
            dataMap.putLong("measuredAt", measuredAt)
            dataMap.putString("origin", origin)
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(context.applicationContext).putDataItem(request)
            .addOnSuccessListener {
                lastSentBpm = bpm
                lastSentAt = measuredAt
                Log.d(TAG, "Queued $bpm BPM @ $measuredAt ($origin) for phone")
            }
            .addOnFailureListener { e ->
                synchronized(sentBuckets) { sentBuckets.remove(bucket) }
                Log.e(TAG, "Failed to queue BPM for phone", e)
            }
    }
}
