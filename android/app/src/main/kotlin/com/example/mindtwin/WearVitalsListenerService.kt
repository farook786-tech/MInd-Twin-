package com.example.mindtwin

import android.net.Uri
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

/**
 * Bound by Google Play services whenever the watch syncs a "/mindtwin/hr/..." DataItem,
 * including when the MindTwin UI is closed or the process was killed.
 * Callbacks run on a background thread, so blocking Firestore calls are allowed here.
 */
class WearVitalsListenerService : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        // Copy out of the buffer first: it is released when this method returns.
        val items = mutableListOf<Pair<Uri, WearVitalsUploader.Reading?>>()
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            val path = item.uri.path ?: continue
            if (!path.startsWith(WearVitalsUploader.PATH_PREFIX + "/")) continue
            items.add(item.uri to WearVitalsUploader.parse(item))
        }
        items.sortBy { it.second?.measuredAt ?: 0L }
        for ((uri, reading) in items) {
            WearVitalsUploader.handle(applicationContext, uri, reading)
        }
    }
}
