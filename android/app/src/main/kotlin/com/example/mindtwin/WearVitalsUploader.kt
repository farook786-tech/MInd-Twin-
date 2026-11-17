package com.example.mindtwin

import android.content.Context
import android.content.SharedPreferences
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
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.util.Date
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.math.ceil
import kotlin.math.roundToLong

/**
 * Data Layer contract shared with android/wear (PhoneSync.kt):
 *   path   = "/mindtwin/hr/<measuredAtMillis>"  (one DataItem per reading, never overwritten)
 *   bpm        : Double  (beats per minute, as measured)
 *   measuredAt : Long    (epoch millis UTC of the real measurement)
 *   origin     : String  ("active" | "passive")
 *
 * Firestore output (docs/DATA_MODEL.md, "Free-tier budget"):
 *  - ONE `vitals` doc per 5-minute window: id `${uid}_heart_rate_${windowStartMillis}`,
 *    {value: rounded mean, min, max, sampleCount, windowStart, measuredAt = window end}.
 *    (Was one doc per ~1/min sample: ~1,440 writes/patient/day.)
 *  - Out-of-range samples (vs users/{uid}.vitalThresholds, defaults 120/45) are ALSO written
 *    immediately as `immediate: true` docs (`${uid}_heart_rate_imm_${measuredAt}`) so server
 *    threshold alerts are not delayed; at most one per direction per window (+1 if it turns
 *    critical). Mirrors lib/services/vitals_aggregation.dart.
 *  - `users/{uid}.latestVitals.heartRate`: at most every 15 min.
 *  - `vitals_daily/{uid}_{yyyy-MM-dd}` hr* fields (local date): at most every 3 h for today,
 *    once more when a past day still has unsent windows.
 *
 * Durability: a sample is added to the window accumulator, which is persisted with commit()
 * BEFORE the DataItem is deleted, so readings survive the process being killed. Open windows
 * are flushed when closed (+ grace) on the next batch, on app resume and on Flutter's
 * `flushPendingWatchReadings`.
 */
object WearVitalsUploader {
    private const val TAG = "MindTwinWearVitals"
    const val PATH_PREFIX = "/mindtwin/hr"
    private const val PREFS = "mindtwin_wear_vitals"
    private const val PROFILE_CACHE_MS = 60L * 60 * 1000
    private const val WRITE_TIMEOUT_S = 20L

    const val WINDOW_MS = 5L * 60 * 1000
    private const val WINDOW_GRACE_MS = 2L * 60 * 1000
    private const val FLUSHED_KEEP_MS = 48L * 60 * 60 * 1000
    private const val LATEST_EVERY_MS = 15L * 60 * 1000
    private const val DAILY_EVERY_MS = 3L * 60 * 60 * 1000
    private const val DAILY_KEEP_DAYS = 3
    private const val MIN_WINDOWS_FOR_RESTING = 12
    private const val MAX_WINDOW_TRIES = 3

    private const val DEFAULT_HR_HIGH = 120.0
    private const val DEFAULT_HR_LOW = 45.0
    private const val CRITICAL_HIGH = 150.0
    private const val CRITICAL_LOW = 40.0

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

    /** Processes one batch (oldest first), then flushes closed windows. OFF the main thread. */
    fun handleBatch(context: Context, items: List<Pair<Uri, Reading?>>) {
        for ((uri, reading) in items.sortedBy { it.second?.measuredAt ?: 0L }) {
            handle(context, uri, reading)
        }
        flush(context)
    }

    private fun handle(context: Context, uri: Uri, reading: Reading?) {
        val outcome = if (reading == null) Outcome.DROP else accept(context, reading)
        if (reading != null && outcome != Outcome.RETRY) emitLive(reading)
        if (outcome != Outcome.RETRY) {
            try {
                Tasks.await(Wearable.getDataClient(context).deleteDataItems(uri), 10, TimeUnit.SECONDS)
            } catch (e: Exception) {
                Log.w(TAG, "Could not delete data item $uri (deduped by sample time on retry)", e)
            }
        }
    }

    /** Uploads every reading still waiting in the Data Layer and flushes closed windows. OFF the main thread. */
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
            flush(context)
            return
        }
        handleBatch(context, pending)
    }

    // ------------------------------------------------------------------ per-sample

    private fun accept(context: Context, r: Reading): Outcome = synchronized(lock) {
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
        val prefs = prefs(context)
        val start = r.measuredAt - r.measuredAt % WINDOW_MS

        // 1) Out of range -> immediate doc (server alerts on it without waiting for the window).
        val dir = when {
            r.bpm > profile.hrHigh -> "high"
            r.bpm < profile.hrLow -> "low"
            else -> null
        }
        if (dir != null) {
            val critical = r.bpm >= CRITICAL_HIGH || r.bpm <= CRITICAL_LOW
            val imm = jsonObj(prefs.getString("imm_$uid", null))
            val last = imm.optJSONObject(dir)
            val sameWindow = last != null && last.optLong("w") == start
            val lastCritical = sameWindow && last!!.optBoolean("c")
            if (!sameWindow || (critical && !lastCritical)) {
                val docId = "${uid}_heart_rate_imm_${r.measuredAt}"
                val data = hashMapOf<String, Any?>(
                    "patientId" to uid,
                    "therapistId" to profile.therapistId,
                    "type" to "heart_rate",
                    "value" to round1(r.bpm),
                    "unit" to "bpm",
                    "measuredAt" to Timestamp(Date(r.measuredAt)),
                    "source" to "wear_os",
                    "immediate" to true,
                    "createdAt" to FieldValue.serverTimestamp(),
                )
                val out = write(FirebaseFirestore.getInstance().collection("vitals").document(docId), data, merge = false)
                if (out == Outcome.RETRY) return Outcome.RETRY
                if (out == Outcome.DROP) invalidateProfile(prefs, uid)
                imm.put(dir, JSONObject().put("w", start).put("c", critical || lastCritical))
                prefs.edit().putString("imm_$uid", imm.toString()).commit()
            }
        }

        // 2) Add to the 5-minute window (persisted before the DataItem is deleted).
        val flushed = jsonArr(prefs.getString("flushed_$uid", null))
        for (i in 0 until flushed.length()) {
            if (flushed.optLong(i) == start) {
                // Window doc already written (immutable): the late sample is not added.
                Log.i(TAG, "Late sample for already-written window $start; not aggregated")
                return Outcome.WRITTEN
            }
        }
        val windows = jsonObj(prefs.getString("win_$uid", null))
        val key = start.toString()
        val w = windows.optJSONObject(key) ?: JSONObject()
            .put("sum", 0.0).put("n", 0).put("min", r.bpm).put("max", r.bpm).put("ts", JSONArray())
        val ts = w.getJSONArray("ts")
        for (i in 0 until ts.length()) {
            if (ts.optLong(i) == r.measuredAt) return Outcome.WRITTEN // already counted
        }
        ts.put(r.measuredAt)
        w.put("sum", w.getDouble("sum") + r.bpm)
        w.put("n", w.getInt("n") + 1)
        w.put("min", minOf(w.getDouble("min"), r.bpm))
        w.put("max", maxOf(w.getDouble("max"), r.bpm))
        windows.put(key, w)
        if (!prefs.edit().putString("win_$uid", windows.toString()).commit()) {
            Log.e(TAG, "Could not persist window $start; keeping reading")
            return Outcome.RETRY
        }
        Outcome.WRITTEN
    }

    // ------------------------------------------------------------------ flushing

    /** Writes every closed window, then (throttled) latestVitals and vitals_daily. OFF the main thread. */
    fun flush(context: Context) {
        synchronized(lock) { flushLocked(context) }
    }

    private fun flushLocked(context: Context) {
        val user = FirebaseAuth.getInstance().currentUser ?: return
        val uid = user.uid
        val prefs = prefs(context)
        val windows = jsonObj(prefs.getString("win_$uid", null))
        val now = System.currentTimeMillis()
        val closed = windows.keys().asSequence().mapNotNull { it.toLongOrNull() }
            .filter { it + WINDOW_MS + WINDOW_GRACE_MS <= now }.sorted().toList()
        if (closed.isNotEmpty()) {
            val profile = patientProfile(context, uid)
            if (profile == null || profile.role != "patient") return
            val db = FirebaseFirestore.getInstance()
            val flushed = jsonArr(prefs.getString("flushed_$uid", null))
            val daily = jsonObj(prefs.getString("daily_$uid", null))
            var newestEnd = 0L
            var newestValue = 0L
            for (start in closed) {
                val w = windows.getJSONObject(start.toString())
                val n = w.optInt("n", 0)
                if (n <= 0) {
                    windows.remove(start.toString())
                    continue
                }
                val avg = w.getDouble("sum") / n
                val data = hashMapOf<String, Any?>(
                    "patientId" to uid,
                    "therapistId" to profile.therapistId,
                    "type" to "heart_rate",
                    "value" to avg.roundToLong(),
                    "min" to round1(w.getDouble("min")),
                    "max" to round1(w.getDouble("max")),
                    "sampleCount" to n,
                    "windowStart" to Timestamp(Date(start)),
                    "unit" to "bpm",
                    "measuredAt" to Timestamp(Date(start + WINDOW_MS)),
                    "source" to "wear_os",
                    "createdAt" to FieldValue.serverTimestamp(),
                )
                val out = write(db.collection("vitals").document("${uid}_heart_rate_$start"), data, merge = false)
                if (out == Outcome.RETRY) break // keep this and later windows; retried next flush
                if (out == Outcome.DROP) {
                    // Usually "already written"; can also be a stale therapistId stamp, so
                    // refresh the profile and retry a few times before giving up.
                    invalidateProfile(prefs, uid)
                    val tries = w.optInt("tries", 0) + 1
                    if (tries < MAX_WINDOW_TRIES) {
                        w.put("tries", tries)
                        break
                    }
                    Log.w(TAG, "Window $start denied $tries times; dropping")
                }
                windows.remove(start.toString())
                flushed.put(start)
                addDailyWindow(daily, start, avg, w.getDouble("min"), w.getDouble("max"))
                if (start + WINDOW_MS > newestEnd) {
                    newestEnd = start + WINDOW_MS
                    newestValue = avg.roundToLong()
                }
            }
            val keep = JSONArray()
            for (i in 0 until flushed.length()) {
                val s = flushed.optLong(i)
                if (s >= now - FLUSHED_KEEP_MS) keep.put(s)
            }
            prefs.edit()
                .putString("win_$uid", windows.toString())
                .putString("flushed_$uid", keep.toString())
                .putString("daily_$uid", daily.toString())
                .commit()
            if (newestEnd > 0L) updateLatest(prefs, db, uid, newestValue, newestEnd, now)
        }
        flushDaily(context, uid, now)
    }

    /**
     * Heart-rate windows computed by the Dart Health Connect path (on Android this uploader
     * owns the hr* fields of vitals_daily). Deduplicated by window start. OFF the main thread.
     */
    fun recordExternalWindows(context: Context, list: List<*>) {
        synchronized(lock) {
            val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
            val prefs = prefs(context)
            val daily = jsonObj(prefs.getString("daily_$uid", null))
            var added = false
            for (item in list) {
                val m = item as? Map<*, *> ?: continue
                val start = (m["start"] as? Number)?.toLong() ?: continue
                val avg = (m["avg"] as? Number)?.toDouble() ?: continue
                if (avg.isNaN() || avg < 20.0 || avg > 250.0) continue
                val min = (m["min"] as? Number)?.toDouble() ?: avg
                val max = (m["max"] as? Number)?.toDouble() ?: avg
                if (addDailyWindow(daily, start, avg, min, max)) added = true
            }
            if (added) prefs.edit().putString("daily_$uid", daily.toString()).commit()
            flushDaily(context, uid, System.currentTimeMillis())
        }
    }

    private fun localDate(millis: Long): String =
        Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate().toString()

    /** Returns true if the window was new for its day. */
    private fun addDailyWindow(daily: JSONObject, start: Long, avg: Double, min: Double, max: Double): Boolean {
        val date = localDate(start)
        val day = daily.optJSONObject(date)
            ?: JSONObject().put("w", JSONObject()).put("dirty", false).put("at", 0L)
        val w = day.getJSONObject("w")
        if (w.has(start.toString())) return false
        w.put(start.toString(), JSONArray().put(avg).put(min).put(max))
        day.put("dirty", true)
        daily.put(date, day)
        // Keep only the most recent days.
        val dates = daily.keys().asSequence().toList().sorted()
        if (dates.size > DAILY_KEEP_DAYS) dates.take(dates.size - DAILY_KEEP_DAYS).forEach { daily.remove(it) }
        return true
    }

    /** Caller holds [lock]. */
    private fun flushDaily(context: Context, uid: String, now: Long) {
        val prefs = prefs(context)
        val daily = jsonObj(prefs.getString("daily_$uid", null))
        val today = localDate(now)
        var changed = false
        for (date in daily.keys().asSequence().toList().sorted()) {
            val day = daily.getJSONObject(date)
            if (!day.optBoolean("dirty")) continue
            val at = day.optLong("at", 0L)
            if (date == today && at > 0L && now - at < DAILY_EVERY_MS) continue
            val w = day.getJSONObject("w")
            val avgs = mutableListOf<Double>()
            var lo = Double.MAX_VALUE
            var hi = -Double.MAX_VALUE
            for (k in w.keys()) {
                val a = w.getJSONArray(k)
                avgs.add(a.getDouble(0))
                lo = minOf(lo, a.getDouble(1))
                hi = maxOf(hi, a.getDouble(2))
            }
            if (avgs.isEmpty()) continue
            val profile = patientProfile(context, uid) ?: return
            if (profile.role != "patient") return
            avgs.sort()
            val resting = if (avgs.size >= MIN_WINDOWS_FOR_RESTING) {
                // Nearest-rank 10th percentile of the 5-min means (same as vitals_aggregation.dart).
                val rank = ceil(0.10 * avgs.size).toInt().coerceIn(1, avgs.size)
                avgs[rank - 1].roundToLong()
            } else {
                null
            }
            val data = hashMapOf<String, Any?>(
                "patientId" to uid,
                "therapistId" to profile.therapistId,
                "date" to date,
                "hrRestingEstimate" to resting,
                "hrAvg" to (avgs.sum() / avgs.size).roundToLong(),
                "hrMin" to lo.roundToLong(),
                "hrMax" to hi.roundToLong(),
                "hrWindows" to avgs.size,
                "updatedAt" to FieldValue.serverTimestamp(),
            )
            val ref = FirebaseFirestore.getInstance().collection("vitals_daily").document("${uid}_$date")
            when (write(ref, data, merge = true)) {
                Outcome.WRITTEN -> {
                    day.put("dirty", false).put("at", now)
                    changed = true
                }
                Outcome.DROP -> invalidateProfile(prefs, uid) // stale therapistId? retried next flush
                Outcome.RETRY -> {}
            }
        }
        if (changed) prefs.edit().putString("daily_$uid", daily.toString()).commit()
    }

    private fun updateLatest(prefs: SharedPreferences, db: FirebaseFirestore, uid: String, value: Long, at: Long, now: Long) {
        val lastAt = prefs.getLong("latestHrAt_$uid", 0L)
        val lastWrite = prefs.getLong("latestHrWriteAt_$uid", 0L)
        if (at <= lastAt || now - lastWrite < LATEST_EVERY_MS) return
        prefs.edit().putLong("latestHrAt_$uid", at).putLong("latestHrWriteAt_$uid", now).apply()
        val patch = mapOf(
            "latestVitals" to mapOf(
                "heartRate" to mapOf("value" to value.toDouble(), "measuredAt" to Timestamp(Date(at)))
            )
        )
        db.collection("users").document(uid).set(patch, SetOptions.merge())
            .addOnFailureListener { Log.w(TAG, "latestVitals update failed", it) }
    }

    /** Blocking write with the shared outcome mapping. */
    private fun write(ref: DocumentReference, data: Map<String, Any?>, merge: Boolean): Outcome {
        return try {
            val task = if (merge) ref.set(data, SetOptions.merge()) else ref.set(data)
            Tasks.await(task, WRITE_TIMEOUT_S, TimeUnit.SECONDS)
            Outcome.WRITTEN
        } catch (e: TimeoutException) {
            // Offline: the write is already in Firestore's persisted local queue.
            Log.i(TAG, "Firestore write queued offline for ${ref.path}")
            Outcome.WRITTEN
        } catch (e: ExecutionException) {
            val cause = e.cause
            if (cause is FirebaseFirestoreException &&
                cause.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
            ) {
                // vitals docs are immutable: PERMISSION_DENIED on a deterministic id almost
                // always means it was already written (or the therapist stamp is stale).
                Log.w(TAG, "Write denied for ${ref.path} (duplicate, stale stamp or rules)", cause)
                Outcome.DROP
            } else {
                Log.e(TAG, "Firestore write failed for ${ref.path}; will retry", cause ?: e)
                Outcome.RETRY
            }
        } catch (e: Exception) {
            Log.e(TAG, "Firestore write failed for ${ref.path}; will retry", e)
            Outcome.RETRY
        }
    }

    // ------------------------------------------------------------------ profile

    private data class Profile(val role: String?, val therapistId: String?, val hrHigh: Double, val hrLow: Double)

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Keeps the cached values (offline fallback) but forces a refresh on next use. */
    private fun invalidateProfile(prefs: SharedPreferences, uid: String) {
        prefs.edit().putLong("profileAt_$uid", 1L).apply()
    }

    /**
     * users/{uid}.role / therapistId / vitalThresholds, cached in SharedPreferences (refreshed
     * every hour, so a therapist's threshold change reaches the phone within ~1 h).
     * Threshold validation mirrors functions/src/logic/vitals.js resolveThresholds.
     */
    private fun patientProfile(context: Context, uid: String): Profile? {
        val prefs = prefs(context)
        val cachedAt = prefs.getLong("profileAt_$uid", 0L)
        val cached = if (cachedAt > 0L) {
            Profile(
                prefs.getString("role_$uid", null),
                prefs.getString("therapistId_$uid", null),
                prefs.getFloat("hrHigh_$uid", DEFAULT_HR_HIGH.toFloat()).toDouble(),
                prefs.getFloat("hrLow_$uid", DEFAULT_HR_LOW.toFloat()).toDouble(),
            )
        } else {
            null
        }
        if (cached != null && System.currentTimeMillis() - cachedAt < PROFILE_CACHE_MS) return cached

        return try {
            val snap = Tasks.await(
                FirebaseFirestore.getInstance().collection("users").document(uid).get(),
                WRITE_TIMEOUT_S, TimeUnit.SECONDS
            )
            if (!snap.exists()) return cached
            val t = snap.get("vitalThresholds") as? Map<*, *>
            fun pick(k: String, d: Double, lo: Double, hi: Double): Double {
                val v = (t?.get(k) as? Number)?.toDouble() ?: return d
                return if (!v.isNaN() && v >= lo && v <= hi) v else d
            }
            var high = pick("heartRateHigh", DEFAULT_HR_HIGH, 80.0, 220.0)
            var low = pick("heartRateLow", DEFAULT_HR_LOW, 25.0, 80.0)
            if (low >= high) {
                high = DEFAULT_HR_HIGH
                low = DEFAULT_HR_LOW
            }
            val fresh = Profile(
                snap.getString("role"),
                snap.getString("therapistId")?.takeIf { it.isNotBlank() },
                high,
                low,
            )
            prefs.edit()
                .putLong("profileAt_$uid", System.currentTimeMillis())
                .putString("role_$uid", fresh.role)
                .putString("therapistId_$uid", fresh.therapistId)
                .putFloat("hrHigh_$uid", high.toFloat())
                .putFloat("hrLow_$uid", low.toFloat())
                .apply()
            fresh
        } catch (e: Exception) {
            Log.w(TAG, "Could not read users/$uid; using cached profile=${cached != null}", e)
            cached
        }
    }

    // ------------------------------------------------------------------ helpers

    private fun round1(v: Double): Double = Math.round(v * 10.0) / 10.0

    private fun jsonObj(s: String?): JSONObject = try {
        if (s.isNullOrEmpty()) JSONObject() else JSONObject(s)
    } catch (e: Exception) {
        Log.w(TAG, "Corrupt state JSON; resetting", e)
        JSONObject()
    }

    private fun jsonArr(s: String?): JSONArray = try {
        if (s.isNullOrEmpty()) JSONArray() else JSONArray(s)
    } catch (e: Exception) {
        JSONArray()
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
