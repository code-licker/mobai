package com.bokachoda.mobai

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Thread-safe bridge connecting Android Service/Receiver notification actions
 * to Dart's EventChannel and pending-action queue when the UI is detached.
 */
object DownloadNotificationBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private var eventSink: EventChannel.EventSink? = null
    private var pendingAction: Map<String, Any?>? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        synchronized(lock) {
            eventSink = sink
        }
    }

    fun hasEventSink(): Boolean {
        synchronized(lock) {
            return eventSink != null
        }
    }

    fun emit(action: String, modelId: String?) {
        val payload = hashMapOf<String, Any?>(
            "action" to action,
            "modelId" to modelId
        )
        val sinkSnapshot: EventChannel.EventSink?
        synchronized(lock) {
            sinkSnapshot = eventSink
            if (sinkSnapshot == null) {
                pendingAction = payload
                return
            }
        }
        mainHandler.post {
            val activeSink = synchronized(lock) { eventSink }
            if (activeSink != null) {
                try {
                    activeSink.success(payload)
                } catch (_: Throwable) {
                    synchronized(lock) {
                        pendingAction = payload
                    }
                }
            } else {
                synchronized(lock) {
                    pendingAction = payload
                }
            }
        }
    }

    fun consumePendingAction(): Map<String, Any?>? {
        synchronized(lock) {
            val action = pendingAction
            pendingAction = null
            return action
        }
    }
}

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.bokachoda.mobai/download_notifications"
        private const val EVENT_CHANNEL = "com.bokachoda.mobai/download_notification_events"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            handleNotificationIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).apply {
            setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    DownloadNotificationBridge.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    DownloadNotificationBridge.setEventSink(null)
                }
            })
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        DownloadNotificationBridge.setEventSink(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "syncDownloadNotifications" -> {
                val rawList = call.argument<List<*>>("downloads")
                val items = parseDownloadItems(rawList)
                DownloadForegroundService.syncDownloads(applicationContext, items)
                result.success(null)
            }
            "cancelDownloadNotification" -> {
                val modelId = call.argument<String>("modelId")
                if (!modelId.isNullOrBlank()) {
                    DownloadForegroundService.cancelDownload(applicationContext, modelId)
                }
                result.success(null)
            }
            "moveToBackground" -> {
                moveTaskToBack(true)
                result.success(null)
            }
            "consumePendingAction" -> {
                result.success(DownloadNotificationBridge.consumePendingAction())
            }
            "getDeviceRamMb" -> {
                val activityManager =
                    getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val memInfo = android.app.ActivityManager.MemoryInfo()
                activityManager.getMemoryInfo(memInfo)
                val totalMb = (memInfo.totalMem / (1024L * 1024L)).toInt()
                result.success(totalMb)
            }
            "openUrl" -> {
                val rawUrl = call.argument<String>("url")?.trim()
                val uri = rawUrl?.let { Uri.parse(it) }
                val scheme = uri?.scheme?.lowercase()
                if (uri == null || (scheme != "http" && scheme != "https")) {
                    result.success(false)
                } else {
                    try {
                        val viewIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(viewIntent)
                        result.success(true)
                    } catch (_: Throwable) {
                        result.success(false)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun parseDownloadItems(rawList: List<*>?): List<DownloadNotificationItem> {
        if (rawList == null) return emptyList()
        val parsed = ArrayList<DownloadNotificationItem>(rawList.size)
        for (entry in rawList) {
            val map = entry as? Map<*, *> ?: continue
            val modelId = map["modelId"] as? String ?: continue
            if (modelId.isBlank()) continue
            val fileName = map["fileName"] as? String
            val title = (map["title"] as? String)?.takeIf { it.isNotBlank() }
                ?: fileName?.takeIf { it.isNotBlank() }
                ?: modelId
            val progress = (map["progress"] as? Number)?.toDouble() ?: 0.0
            val receivedBytes = (map["receivedBytes"] as? Number)?.toLong() ?: 0L
            val totalBytes = (map["totalBytes"] as? Number)?.toLong() ?: 0L
            val speedBytesPerSec = (map["speedBytesPerSec"] as? Number)?.toDouble() ?: 0.0
            val isDownloading = map["isDownloading"] as? Boolean ?: false
            val isPaused = map["isPaused"] as? Boolean ?: false
            val errorMessage = map["errorMessage"] as? String

            parsed.add(
                DownloadNotificationItem(
                    modelId = modelId,
                    title = title,
                    fileName = fileName,
                    progress = progress,
                    receivedBytes = receivedBytes,
                    totalBytes = totalBytes,
                    speedBytesPerSec = speedBytesPerSec,
                    isDownloading = isDownloading,
                    isPaused = isPaused,
                    errorMessage = errorMessage
                )
            )
        }
        return parsed
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val isOpenDownloads =
            intent.action == DownloadForegroundService.ACTION_OPEN_DOWNLOADS ||
                intent.getStringExtra(DownloadForegroundService.EXTRA_ACTION) == "open_downloads"
        if (!isOpenDownloads) return

        // Clear flag so configuration changes do not re-emit the navigation event.
        intent.action = null
        intent.removeExtra(DownloadForegroundService.EXTRA_ACTION)
        DownloadNotificationBridge.emit("open_downloads", null)
    }
}
