package com.example.mindtwin.wear

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Health Services passive registrations and our foreground service do not survive a reboot or
 * an app update, so restart both here. Starting a `health` foreground service from
 * BOOT_COMPLETED is allowed (Android 14/15 restrict only other FGS types).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d("MindTwinWear", "Restarting monitoring after ${intent.action}")
                Monitoring.startAll(context)
            }
        }
    }
}
