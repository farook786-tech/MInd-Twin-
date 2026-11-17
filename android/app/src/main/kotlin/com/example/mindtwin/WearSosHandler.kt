package com.example.mindtwin

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Watch SOS (Data Layer contract shared with android/wear SosSender.kt):
 *   path      = "/mindtwin/sos/<pressedAtMillis>"
 *   pressedAt : Long   (epoch millis UTC)
 *   source    : String ("wear_os")
 *
 * For each SOS this:
 *  1. immediately posts a high-priority phone notification that opens Safety Resources
 *     (MainActivity extra [EXTRA_ACTION] = [ACTION_SAFETY_RESOURCES], read by Flutter via the
 *     "com.example.mindtwin/sos" channel, see [SosLaunchBridge]);
 *  2. writes `crisis_events/wear_sos_<uid>_<pressedAt>` {eventType 'sos', severity 'critical',
 *     source 'wear_os'} (docs/DATA_MODEL.md) with the native Firebase SDK. Offline, the write
 *     waits in Firestore's persistent queue and is delivered on reconnect;
 *  3. deletes the DataItem.
 * The deterministic doc id makes Data Layer redelivery idempotent (create-only rule).
 */
object WearSosHandler {
    private const val TAG = "MindTwinWearSos"
    const val PATH_PREFIX = "/mindtwin/sos"
    const val EXTRA_ACTION = "mindtwin_action"
    const val ACTION_SAFETY_RESOURCES = "safety_resources"

    private const val CHANNEL_ID = "sos_watch"
    private const val PREFS = "mindtwin_wear_sos"
    private const val READ_TIMEOUT_S = 5L
    private const val WRITE_TIMEOUT_S = 10L

    data class Sos(val uri: Uri, val pressedAt: Long)

    fun isSosPath(path: String): Boolean = path.startsWith("$PATH_PREFIX/")

    /** Parse while the DataEventBuffer is still valid. */
    fun parse(item: DataItem): Sos {
        val fromPath = item.uri.lastPathSegment?.toLongOrNull() ?: 0L
        val pressedAt = try {
            DataMapItem.fromDataItem(item).dataMap.getLong("pressedAt", fromPath)
        } catch (e: Exception) {
            Log.w(TAG, "Malformed SOS item ${item.uri}; using path time", e)
            fromPath
        }
        val now = System.currentTimeMillis()
        // A bogus watch clock must never drop an SOS: fall back to "now".
        val safeAt = if (pressedAt <= 0L || pressedAt > now + 5 * 60_000L) now else pressedAt
        return Sos(item.uri, safeAt)
    }

    /** Must be called OFF the main thread (blocks on Firestore / Data Layer). */
    fun handle(context: Context, sos: Sos) {
        val user = FirebaseAuth.getInstance().currentUser
        notifyPatient(context, signedIn = user != null)
        if (user != null) writeCrisisEvent(context, user.uid, sos)
        try {
            Tasks.await(Wearable.getDataClient(context).deleteDataItems(sos.uri), 10, TimeUnit.SECONDS)
        } catch (e: Exception) {
            Log.w(TAG, "Could not delete SOS item ${sos.uri}", e)
        }
    }

    private data class Profile(val therapistId: String?, val name: String?)

    /** users/{uid}: server (short timeout) -> device cache -> last known values. */
    private fun profile(context: Context, uid: String): Profile {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ref = FirebaseFirestore.getInstance().collection("users").document(uid)
        val snap: DocumentSnapshot? = try {
            Tasks.await(ref.get(), READ_TIMEOUT_S, TimeUnit.SECONDS)
        } catch (e: Exception) {
            try {
                Tasks.await(ref.get(Source.CACHE), READ_TIMEOUT_S, TimeUnit.SECONDS)
            } catch (e2: Exception) {
                null
            }
        }
        if (snap != null && snap.exists()) {
            val p = Profile(
                snap.getString("therapistId")?.takeIf { it.isNotBlank() },
                snap.getString("name")?.trim()?.takeIf { it.isNotEmpty() },
            )
            prefs.edit()
                .putString("therapistId_$uid", p.therapistId)
                .putString("name_$uid", p.name)
                .apply()
            return p
        }
        return Profile(prefs.getString("therapistId_$uid", null), prefs.getString("name_$uid", null))
    }

    private fun writeCrisisEvent(context: Context, uid: String, sos: Sos) {
        val profile = profile(context, uid)
        val name = profile.name
            ?: FirebaseAuth.getInstance().currentUser?.displayName?.takeIf { it.isNotBlank() }
            ?: "Patient"
        val time = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(sos.pressedAt))
        val docId = "wear_sos_${uid}_${sos.pressedAt}"
        val data = hashMapOf<String, Any?>(
            "patientId" to uid,
            "therapistId" to profile.therapistId,
            "patientName" to name,
            "eventType" to "sos",
            "severity" to "critical",
            "title" to "SOS alert (watch)",
            "message" to "$name pressed the SOS button on their watch at $time and needs urgent help.",
            "acknowledged" to false,
            "timestamp" to FieldValue.serverTimestamp(),
            "clientCreatedAt" to Timestamp(Date(sos.pressedAt)),
            "source" to "wear_os",
        )
        val write = FirebaseFirestore.getInstance().collection("crisis_events").document(docId).set(data)
        try {
            Tasks.await(write, WRITE_TIMEOUT_S, TimeUnit.SECONDS)
            Log.i(TAG, "SOS crisis event $docId delivered")
        } catch (e: TimeoutException) {
            // Already in Firestore's persisted queue: delivered automatically when online.
            Log.i(TAG, "SOS crisis event $docId queued offline")
        } catch (e: ExecutionException) {
            val cause = e.cause
            if (cause is FirebaseFirestoreException &&
                cause.code == FirebaseFirestoreException.Code.PERMISSION_DENIED
            ) {
                // Create-only collection: a redelivered SOS with the same id is denied.
                Log.w(TAG, "SOS write denied for $docId (duplicate or rules)", cause)
            } else {
                Log.e(TAG, "SOS write failed for $docId", cause ?: e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "SOS write failed for $docId", e)
        }
    }

    private fun notifyPatient(context: Context, signedIn: Boolean) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "POST_NOTIFICATIONS not granted; SOS notification not shown")
            return
        }
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Watch SOS", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Shown when you press SOS on your watch"
                    enableVibration(true)
                }
            )
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_ACTION, ACTION_SAFETY_RESOURCES)
        }
        val pending = PendingIntent.getActivity(
            context, 7316, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val title: String
        val text: String
        if (signedIn) {
            title = "SOS sent from your watch"
            text = "Opening safety resources. If you are in danger, call 112 or Tele-MANAS 14416."
        } else {
            title = "SOS pressed on your watch"
            text = "You are signed out, so your therapist was NOT alerted. Call Tele-MANAS 14416 or 112."
        }
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(pending)
            // Opens Safety Resources straight away when the system allows full-screen intents.
            .setFullScreenIntent(pending, true)
            .setAutoCancel(true)
            .build()
        nm.notify(7316, notification)
    }
}
