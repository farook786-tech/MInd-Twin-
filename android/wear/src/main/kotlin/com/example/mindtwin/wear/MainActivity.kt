package com.example.mindtwin.wear

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import java.text.DateFormat
import java.util.Date

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

    @Composable
    fun WearAppScreen() {
        MaterialTheme {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                    modifier = Modifier.padding(12.dp)
                ) {
                    Text(
                        text = "MindTwin",
                        style = MaterialTheme.typography.caption1,
                        color = MaterialTheme.colors.secondary
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.caption2,
                        textAlign = TextAlign.Center
                    )
                    if (needsPermission) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Chip(
                            onClick = { checkPermissionsAndStart() },
                            label = { Text("Grant") }
                        )
                    }
                }
            }
        }
    }

    companion object {
        private const val TAG = "MindTwinWear"
    }
}
