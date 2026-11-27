package com.bokachoda.mobai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receives Pause / Resume / Cancel PendingIntent broadcasts from download notifications.
 */
class DownloadNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val action = when (intent.action) {
            DownloadForegroundService.ACTION_PAUSE -> "pause"
            DownloadForegroundService.ACTION_RESUME -> "resume"
            DownloadForegroundService.ACTION_CANCEL -> "cancel"
            else -> intent.getStringExtra(DownloadForegroundService.EXTRA_ACTION)
        } ?: return

        val modelId = intent.getStringExtra(DownloadForegroundService.EXTRA_MODEL_ID)
        if (modelId.isNullOrBlank()) return

        when (action) {
            "cancel" -> {
                // Dismiss notification immediately even if the Dart engine was killed.
                DownloadForegroundService.cancelDownload(context.applicationContext, modelId)
            }
            "resume" -> {
                // Only start/promote the foreground service when an active Dart engine
                // can actually execute the download; avoid a stuck 0% service if dead.
                if (DownloadNotificationBridge.hasEventSink()) {
                    DownloadForegroundService.requestForegroundResume(context.applicationContext, modelId)
                }
            }
        }

        DownloadNotificationBridge.emit(action, modelId)
    }
}
