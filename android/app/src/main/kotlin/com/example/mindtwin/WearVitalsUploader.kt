package com.example.mindtwin

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import io.flutter.plugin.common.MethodChannel
import java.util.Date
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Data Layer contract shared with android/wear (PhoneSync.kt):
 *   path   = "/mindtwin/hr/<measuredAtMillis>"  (one DataItem per reading, never overwritten)
 *   bpm        : Double  (beats per minute, as measured)
 *   measuredAt : Long    (epoch millis UTC of the real measurement)
 *   origin     : String  ("active" | "passive")
 *
 * Each reading is written to Firestore `vitals/${patientId}_heart_rate_${measuredAt}`
 * (docs/DATA_MODEL.md) and the DataItem is deleted only after Firestore accepted the write
 * (or durably queued it offline), so readings survive the phone app being killed.
 */
object WearVitalsUploader {
    private const val TAG = "MindTwinWearVitals"
    const val PATH_PREFIX = "/mindtwin/hr"
    private const val PREFS = "mindtwin_wear_vitals"
    private const val THERAPIST_CACHE_MS = 6L * 60 * 60 * 1000
    private const val WRITE_TIMEOUT_S = 20L

    enum class Outcome { WRITTEN, DROP, RETRY }

    private val lock = Any()

    /** Live UI bridge: set by MainActivity while the Flutter engine is alive. */
    @Volatile
    var liveChannel: MethodChannel? = null

    data class Reading(val bpm: Double, val measuredAt: Long, val origin: String)

    fun parse(item: DataItem): Reading? {
        val path = item.uri.path ?: return null
        if (!path.startsWith("$PATH_PREFIX/")) return null
        return try {
            val map = DataMapItem.fromDataItem(item).dataMap
            val bpm = map.getDouble("bpm", Double.NaN)
            val measuredAt = map.getLong("measuredAt", 0L)
            Reading(bpm, measuredAt, map.getString("origin", "unknown"))
        } catch (e: Exception) {
            Log.e(TAG, "Malformed data item at $path", e)
            null
        }
    }

    /** Must be called OFF the main thread (blocks on Firestore). */
    fun handle(context: Context, uri: Uri, reading: Reading?) {
        val outcome = if (reading == null) Outcome.DROP else upload(context, reading)
        if (reading != null && outcome != Outcome.RETRY) emitLive(reading)
        if (outcome != Outcome.RETRY) {
            try {
                Tasks.await(Wearable.getDataClient(context).deleteDataItems(uri), 10, TimeUnit.SECONDS)
            } catch (e: Exception) {
                Log.w(TAG, "Could not delete data item $uri (will be deduped on retry)", e)
            }
        }
    }

    /** Uploads every reading still waiting in the Data Layer. Must be called OFF the main thread. */
    fun processPending(context: Context) {
        val uri = Uri.Builder().scheme(PutDataRequest.WEAR_URI_SCHEME).path(PATH_PREFIX).build()
        val pending = mutableListOf<Pair<Uri, Reading?>>()
        try {
            val buffer = Tasks.await(
                Wearable.getDataClient(context).getDataItems(uri, DataClient.FILTER_PREFIX),
                15, TimeUnit.SECONDS
            )
            try {
                for (item in buffer) pending.add(item.uri to parse(item))
            } finally {
                buffer.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not list pending watch readings", e)
            return
        }
        pending.sortBy { it.second?.measuredAt ?: 0L }
        for ((itemUri, reading) in pending) handle(context, itemUri, reading)
    }

    private fun upload(context: Context, r: Reading): Outcome = synchronized(lock) {
        val now = System.currentTimeMillis()
        // Validate: never store implausible values or readings with a bogus clock.
        if (r.bpm.isNaN() || r.bpm < 20.0 || r.bpm > 250.0) {
            Log.w(TAG, "Dropping implausible bpm ${r.bpm}")
            return Outcome.DROP
        }
        if (r.measuredAt <= 0L || r.measuredAt > now + 5 * 60 * 1000) {
            Log.w(TAG, "Dropping reading with invalid measuredAt ${r.measuredAt}")
            return Outcome.DROP
        }

        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            Log.i(TAG, "No signed-in patient; keeping reading for later upload")
            return Outcome.RETRY
        }
        val uid = user.uid
        val profile = patientProfile(context, uid) ?: return Outcome.RETRY
        if (profile.role != "patient") {
            Log.w(TAG, "Signed-in user is not a patient (role=${profile.role}); keeping reading")
            return Outcome.RETRY
        }

        val db = FirebaseFirestore.getInstance()
        val docId = "${uid}_heart_rate_${r.measuredAt}"
        val value = Math.round(r.bpm * 10.0) / 10.0
        val measuredAt = Timestamp(Date(r.measuredAt))
        val data = hashMapOf<String, Any?>(
            "patientId" to uid,
            "therapistId" to profile.therapistId,
            "type" to "heart_rate",
            "value" to value,
            "unit" to "bpm",
            "measuredAt" to measuredAt,
            "source" to "wear_os",
            "createdAt" to FieldValue.serverTimestamp(),
        )

        val outcome = try {
            Tasks.await(db.collection("vitals").document(docId).set(data), WRITE_TIMEOUT_S, TimeUnit.SECONDS)
            Outcome.WRITTEN
        } catch (e: TimeoutException) {
            // Offline: the write is already in Firestore's persisted local queue and will be
            // sent when connectivity returns, so it is safe to consume the DataItem.
            Log.i(TAG, "Firestore write queued offline for $docId")
            Outcome.WRITTEN
        } catch (e: ExecutionException) {
            val cause = e.cause
            if (cause is FirebaseFirestoreException &&
                cause.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
            ) {
                // vitals docs are immutable: PERMISSION_DENIED on a deterministic id almost
                // always means it was already written. Retrying cannot succeed either way.
                Log.w(TAG, "Write denied for $docId (duplicate or rules); dropping", cause)
                Outcome.DROP
            } else {
                Log.e(TAG, "Firestore write failed for $docId; will retry", cause ?: e)
                Outcome.RETRY
            }
        } catch (e: Exception) {
            Log.e(TAG, "Firestore write failed for $docId; will retry", e)
            Outcome.RETRY
        }

        if (outcome == Outcome.WRITTEN) updateLatest(context, db, uid, value, r.measuredAt)
        outcome
    }

    private fun updateLatest(context: Context, db: FirebaseFirestore, uid: String, value: Double, at: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val key = "latestHrAt_$uid"
        if (at <= prefs.getLong(key, 0L)) return
        prefs.edit().putLong(key, at).apply()
        val patch = mapOf(
            "latestVitals" to mapOf(
                "heartRate" to mapOf("value" to value, "measuredAt" to Timestamp(Date(at)))
            )
        )
        db.collection("users").document(uid).set(patch, SetOptions.merge())
            .addOnFailureListener { Log.w(TAG, "latestVitals update failed", it) }
    }

    private data class Profile(val role: String?, val therapistId: String?)

    /** users/{uid}.role / therapistId, cached in SharedPreferences (refreshed every 6 h). */
    private fun patientProfile(context: Context, uid: String): Profile? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val cachedAt = prefs.getLong("profileAt_$uid", 0L)
        val cached = if (cachedAt > 0L) {
            Profile(prefs.getString("role_$uid", null), prefs.getString("therapistId_$uid", null))
        } else null
        if (cached != null && System.currentTimeMillis() - cachedAt < THERAPIST_CACHE_MS) return cached

        return try {
            val snap = Tasks.await(
                FirebaseFirestore.getInstance().collection("users").document(uid).get(),
                WRITE_TIMEOUT_S, TimeUnit.SECONDS
            )
            if (!snap.exists()) return cached
            val fresh = Profile(snap.getString("role"), snap.getString("therapistId")?.takeIf { it.isNotBlank() })
            prefs.edit()
                .putLong("profileAt_$uid", System.currentTimeMillis())
                .putString("role_$uid", fresh.role)
                .putString("therapistId_$uid", fresh.therapistId)
                .apply()
            fresh
        } catch (e: Exception) {
            Log.w(TAG, "Could not read users/$uid; using cached profile=${cached != null}", e)
            cached
        }
    }

    private fun emitLive(r: Reading) {
        val channel = liveChannel ?: return
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod(
                "onHeartRateReceived",
                mapOf("bpm" to r.bpm, "timestamp" to r.measuredAt, "source" to "wear_os")
            )
        }
    }
}
