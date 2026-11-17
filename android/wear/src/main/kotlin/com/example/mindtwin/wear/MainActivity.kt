package com.example.mindtwin.wear

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var statusText by mutableStateOf("Checking permissions…")
    private var needsPermission by mutableStateOf(false)

    private val foregroundLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        Log.d(TAG, "Foreground permission result: $result")
        if (Monitoring.hasSensorPermission(this)) {
            Monitoring.startAll(this)
            requestBackgroundIfNeeded()
        }
        refreshStatus()
    }

    // Background sensor permission must be requested on its own, after the foreground one.
    private val backgroundLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        Log.d(TAG, "Background sensor permission granted=$granted")
        if (granted) Monitoring.startAll(this)
        refreshStatus()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { WearAppScreen() }
        checkPermissionsAndStart()
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
    }

    private fun checkPermissionsAndStart() {
        if (Monitoring.hasSensorPermission(this)) {
            Monitoring.startAll(this)
            requestBackgroundIfNeeded()
        } else {
            foregroundLauncher.launch(Monitoring.foregroundPermissions())
        }
        refreshStatus()
    }

    private fun requestBackgroundIfNeeded() {
        val bg = Monitoring.backgroundPermission ?: return
        if (!Monitoring.granted(this, bg)) backgroundLauncher.launch(bg)
    }

    private fun refreshStatus() {
        needsPermission = !Monitoring.hasSensorPermission(this)
        statusText = when {
            needsPermission -> "Heart-rate permission needed"
            !Monitoring.hasBackgroundPermission(this) ->
                "Monitoring while open.\nAllow \"all the time\" for continuous monitoring."
            else -> {
                val at = PhoneSync.lastSentAt
                val bpm = PhoneSync.lastSentBpm
                if (at != null && bpm != null) {
                    "Monitoring\nLast: ${bpm.toInt()} BPM at " +
                        DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(at))
                } else {
                    "Monitoring heart rate"
                }
            }
        }
    }

    private var sosText by mutableStateOf<String?>(null)
    private var sosSending by mutableStateOf(false)

    /** Opens the dialer on LTE watches; tells the patient to use their phone otherwise. */
    private fun dial(number: String) {
        try {
            startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))
        } catch (e: ActivityNotFoundException) {
            sosText = "Call $number from your phone."
        }
    }

    private suspend fun sendSos() {
        if (sosSending) return
        sosSending = true
        sosText = "Sending help request..."
        sosText = when (SosSender.send(this)) {
            SosSender.Result.SENT ->
                "Help request sent to your phone.\nIf you are in danger, call 112."
            SosSender.Result.PHONE_NOT_REACHABLE ->
                "Phone not reachable - call 14416 / 112.\nYour request will send when the phone reconnects."
            SosSender.Result.FAILED ->
                "Could not send. Call 14416 (Tele-MANAS) or 112."
        }
        sosSending = false
    }

    /**
     * SOS button: press and HOLD for [SOS_HOLD_MS] (ring fills) to send, so a brush against the
     * screen never triggers it. Releasing early cancels.
     */
    @Composable
    fun SosHoldButton() {
        val scope = rememberCoroutineScope()
        val haptics = LocalHapticFeedback.current
        var progress by remember { mutableFloatStateOf(0f) }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(72.dp)
                .semantics {
                    contentDescription = "SOS. Press and hold for 2 seconds to send a help request."
                }
                .pointerInput(Unit) {
                    detectTapGestures(onPress = {
                        if (sosSending) return@detectTapGestures
                        val hold = scope.launch {
                            val start = System.currentTimeMillis()
                            while (true) {
                                val p = (System.currentTimeMillis() - start) / SOS_HOLD_MS
                                progress = p.coerceAtMost(1f)
                                if (p >= 1f) break
                                delay(16)
                            }
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            sendSos()
                            progress = 0f
                        }
                        tryAwaitRelease()
                        if (progress < 1f && hold.isActive) {
                            hold.cancel()
                            progress = 0f
                            if (!sosSending) sosText = "Hold for 2 seconds to send SOS"
                        }
                    })
                }
        ) {
            Box(
                modifier = Modifier
                    .size(60.dp)
                    .clip(CircleShape)
                    .background(Color(0xFFD32F2F)),
                contentAlignment = Alignment.Center,
            ) {
                Text("SOS", color = Color.White, fontWeight = FontWeight.Bold)
            }
            CircularProgressIndicator(
                progress = progress,
                modifier = Modifier.fillMaxSize(),
                indicatorColor = Color.White,
                trackColor = Color.Transparent,
                strokeWidth = 4.dp,
            )
        }
    }

    @Composable
    fun WearAppScreen() {
        MaterialTheme {
            ScalingLazyColumn(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                item {
                    Text(
                        text = "MindTwin",
                        style = MaterialTheme.typography.caption1,
                        color = MaterialTheme.colors.secondary
                    )
                }
                item {
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.caption2,
                        textAlign = TextAlign.Center
                    )
                }
                if (needsPermission) {
                    item {
                        Chip(
                            onClick = { checkPermissionsAndStart() },
                            label = { Text("Grant") }
                        )
                    }
                }
                item { SosHoldButton() }
                item {
                    Text(
                        text = sosText ?: "Hold SOS for 2 s if you need help",
                        style = MaterialTheme.typography.caption2,
                        textAlign = TextAlign.Center,
                    )
                }
                item {
                    Chip(
                        onClick = { dial("14416") },
                        label = { Text("Call 14416") },
                        secondaryLabel = { Text("Tele-MANAS 24x7") },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                item {
                    Chip(
                        onClick = { dial("112") },
                        label = { Text("Call 112") },
                        secondaryLabel = { Text("Emergency") },
                        colors = ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }
    }

    companion object {
        private const val TAG = "MindTwinWear"
        private const val SOS_HOLD_MS = 2000f
    }
}
