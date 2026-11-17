package com.example.mindtwin

import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.wear.remote.interactions.RemoteActivityHelper
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

// FlutterFragmentActivity is required by the `health` plugin (Health Connect permission UI).
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "com.example.mindtwin/wearable"
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        WearVitalsUploader.liveChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isWatchConnected" -> io.execute {
                    val status = watchStatus()
                    runOnUiThread { result.success(status) }
                }
                "flushPendingWatchReadings" -> io.execute {
                    WearVitalsUploader.processPending(applicationContext)
                    runOnUiThread { result.success(true) }
                }
                // "Link your watch": the watch component ships inside the patient app's Play
                // listing (same applicationId). If the paired watch doesn't have it yet, open
                // the listing in the watch's Play Store.
                "installOnWatch" -> io.execute {
                    val outcome = openOnWatch(
                        Intent(Intent.ACTION_VIEW)
                            .addCategory(Intent.CATEGORY_BROWSABLE)
                            .setData(Uri.parse("market://details?id=$packageName")),
                        requireApp = false,
                    )
                    runOnUiThread { result.success(outcome) }
                }
                // Opens the MindTwin screen on the watch so the patient can grant the
                // heart-rate permission there (sensor permissions can only be granted on-watch).
                "openOnWatch" -> io.execute {
                    val outcome = openOnWatch(
                        Intent(Intent.ACTION_VIEW)
                            .addCategory(Intent.CATEGORY_BROWSABLE)
                            .setData(Uri.parse(WATCH_DEEP_LINK)),
                        requireApp = true,
                    )
                    runOnUiThread { result.success(outcome) }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        WearVitalsUploader.liveChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        // Upload anything the watch synced while the listener could not write (e.g. signed out).
        io.execute { WearVitalsUploader.processPending(applicationContext) }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    /**
     * Real connection status. `connected` is true only if a reachable node advertises the
     * MindTwin wear capability (declared in android/wear res/values/wear.xml), i.e. the watch
     * is paired, in range, and has the MindTwin watch app installed.
     */
    private fun watchStatus(): Map<String, Any> {
        return try {
            val nodes = Tasks.await(Wearable.getNodeClient(this).connectedNodes, 10, TimeUnit.SECONDS)
            val capability = Tasks.await(
                Wearable.getCapabilityClient(this)
                    .getCapability(WEAR_CAPABILITY, CapabilityClient.FILTER_REACHABLE),
                10, TimeUnit.SECONDS
            )
            val appNodes = capability.nodes
            mapOf(
                "connected" to appNodes.isNotEmpty(),
                "pairedNodeConnected" to nodes.isNotEmpty(),
                "appInstalled" to appNodes.isNotEmpty(),
                "nodeNames" to appNodes.map { it.displayName },
            )
        } catch (e: Exception) {
            Log.w("MindTwinWearVitals", "Watch status check failed", e)
            mapOf(
                "connected" to false,
                "pairedNodeConnected" to false,
                "appInstalled" to false,
                "nodeNames" to emptyList<String>(),
                "error" to (e.message ?: e.javaClass.simpleName),
            )
        }
    }

    /**
     * Starts [intent] on every reachable paired watch (or only those that already run the
     * MindTwin watch component when [requireApp]). Returns {sent: Int, error?: String}.
     */
    private fun openOnWatch(intent: Intent, requireApp: Boolean): Map<String, Any> {
        return try {
            val nodes = if (requireApp) {
                Tasks.await(
                    Wearable.getCapabilityClient(this)
                        .getCapability(WEAR_CAPABILITY, CapabilityClient.FILTER_REACHABLE),
                    10, TimeUnit.SECONDS
                ).nodes
            } else {
                Tasks.await(Wearable.getNodeClient(this).connectedNodes, 10, TimeUnit.SECONDS).toSet()
            }
            if (nodes.isEmpty()) return mapOf("sent" to 0, "error" to "no_watch")
            val helper = RemoteActivityHelper(applicationContext, io)
            var sent = 0
            for (node in nodes) {
                try {
                    helper.startRemoteActivity(intent, node.id).get(15, TimeUnit.SECONDS)
                    sent++
                } catch (e: Exception) {
                    Log.w("MindTwinWearVitals", "startRemoteActivity failed on ${node.displayName}", e)
                }
            }
            if (sent == 0) mapOf("sent" to 0, "error" to "remote_start_failed") else mapOf("sent" to sent)
        } catch (e: Exception) {
            Log.w("MindTwinWearVitals", "openOnWatch failed", e)
            mapOf("sent" to 0, "error" to (e.message ?: e.javaClass.simpleName))
        }
    }

    companion object {
        const val WEAR_CAPABILITY = "mindtwin_wear_vitals"
        // Must match the VIEW intent-filter on the wear MainActivity.
        const val WATCH_DEEP_LINK = "mindtwin://watch/start"
    }
}
