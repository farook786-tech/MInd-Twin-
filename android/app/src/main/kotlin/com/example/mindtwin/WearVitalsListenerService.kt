package com.example.mindtwin

import android.net.Uri
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

/**
 * Bound by Google Play services whenever the watch syncs a "/mindtwin/hr/..." (vitals) or
 * "/mindtwin/sos/..." (watch SOS, see WearSosHandler) DataItem,
 * including when the MindTwin UI is closed or the process was killed.
 * Callbacks run on a background thread, so blocking Firestore calls are allowed here.
 */
class WearVitalsListenerService : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        // Copy out of the buffer first: it is released when this method returns.
        val items = mutableListOf<Pair<Uri, WearVitalsUploader.Reading?>>()
        val sosList = mutableListOf<WearSosHandler.Sos>()
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            val path = item.uri.path ?: continue
            if (WearSosHandler.isSosPath(path)) { sosList.add(WearSosHandler.parse(item)); continue }
            if (!path.startsWith(WearVitalsUploader.PATH_PREFIX + "/")) continue
            items.add(item.uri to WearVitalsUploader.parse(item))
        }
        // SOS first: never queued behind vitals uploads.
        for (sos in sosList) WearSosHandler.handle(applicationContext, sos)
        // Adds the samples to the persisted 5-minute windows (immediate docs for out-of-range
        // values), then writes every window that has closed.
        WearVitalsUploader.handleBatch(applicationContext, items)
    }
}
