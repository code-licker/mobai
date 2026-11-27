package com.example.mobai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import java.util.Locale

data class DownloadNotificationItem(
    val modelId: String,
    val title: String,
    val fileName: String?,
    val progress: Double,
    val receivedBytes: Long,
    val totalBytes: Long,
    val speedBytesPerSec: Double,
    val isDownloading: Boolean,
    val isPaused: Boolean,
    val errorMessage: String?
)

/**
 * Keeps model downloads alive in the background with a dataSync foreground service,
 * partial WakeLock + WifiLock, and per-model notification controls.
 */
class DownloadForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "mobai_downloads"
        private const val CHANNEL_NAME = "Model Downloads"

        const val ACTION_OPEN_DOWNLOADS = "com.example.mobai.ACTION_OPEN_DOWNLOADS"
        const val ACTION_PAUSE = "com.example.mobai.ACTION_PAUSE"
        const val ACTION_RESUME = "com.example.mobai.ACTION_RESUME"
        const val ACTION_CANCEL = "com.example.mobai.ACTION_CANCEL"
        private const val ACTION_SYNC = "com.example.mobai.ACTION_SYNC"
        private const val ACTION_RESUME_FOREGROUND = "com.example.mobai.ACTION_RESUME_FOREGROUND"

        const val EXTRA_ACTION = "mobai_action"
        const val EXTRA_MODEL_ID = "mobai_model_id"
        private const val EXTRA_STARTED_AS_FOREGROUND = "mobai_started_as_foreground"

        private const val TRANSIENT_FOREGROUND_ID = 999
        private const val WAKELOCK_TIMEOUT_MS = 4 * 60 * 60 * 1000L

        private val stateLock = Any()
        private var currentDownloads = LinkedHashMap<String, DownloadNotificationItem>()
        private val shownNotificationIds = HashMap<String, Int>()

        @Volatile
        private var activeInstance: DownloadForegroundService? = null

        fun syncDownloads(context: Context, items: List<DownloadNotificationItem>) {
            val appContext = context.applicationContext
            ensureNotificationChannel(appContext)

            val hasActive: Boolean
            synchronized(stateLock) {
                val updated = LinkedHashMap<String, DownloadNotificationItem>(items.size)
                for (item in items) {
                    if (item.isDownloading || item.isPaused) {
                        updated[item.modelId] = item
                    }
                }
                currentDownloads = updated
                hasActive = updated.values.any { it.isDownloading }
            }

            val instance = activeInstance
            if (instance != null) {
                instance.applyState()
                return
            }

            if (hasActive) {
                startServiceCompat(appContext, Intent(appContext, DownloadForegroundService::class.java).apply {
                    action = ACTION_SYNC
                })
            } else {
                // No active downloads and service is not running: update/detach paused notifications
                // directly without launching a foreground service.
                renderNotificationsWithoutService(appContext)
            }
        }

        fun cancelDownload(context: Context, modelId: String) {
            val appContext = context.applicationContext
            val hasActive: Boolean
            synchronized(stateLock) {
                currentDownloads.remove(modelId)
                hasActive = currentDownloads.values.any { it.isDownloading }
            }

            val instance = activeInstance
            if (instance != null) {
                instance.applyState()
            } else if (hasActive) {
                startServiceCompat(appContext, Intent(appContext, DownloadForegroundService::class.java).apply {
                    action = ACTION_SYNC
                })
            } else {
                renderNotificationsWithoutService(appContext)
            }

            // Also cancel directly by deterministic ID in case the notification was
            // left detached from a previous process before this process started.
            val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            try {
                manager?.cancel(notificationIdFor(modelId))
            } catch (_: Throwable) {
            }
        }

        fun requestForegroundResume(context: Context, modelId: String) {
            val appContext = context.applicationContext
            ensureNotificationChannel(appContext)

            synchronized(stateLock) {
                val existing = currentDownloads[modelId]
                currentDownloads[modelId] = existing?.copy(
                    isDownloading = true,
                    isPaused = false,
                    errorMessage = null
                ) ?: DownloadNotificationItem(
                    modelId = modelId,
                    title = modelId.substringAfterLast('/'),
                    fileName = null,
                    progress = 0.0,
                    receivedBytes = 0L,
                    totalBytes = 0L,
                    speedBytesPerSec = 0.0,
                    isDownloading = true,
                    isPaused = false,
                    errorMessage = null
                )
            }

            val instance = activeInstance
            if (instance != null) {
                instance.applyState()
            } else {
                startServiceCompat(appContext, Intent(appContext, DownloadForegroundService::class.java).apply {
                    action = ACTION_RESUME_FOREGROUND
                    putExtra(EXTRA_MODEL_ID, modelId)
                })
            }
        }

        private fun startServiceCompat(context: Context, intent: Intent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    intent.putExtra(EXTRA_STARTED_AS_FOREGROUND, true)
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Throwable) {
                // Ignore background foreground-service restrictions cleanly if OS blocks launch.
            }
        }

        private fun ensureNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing != null) return

            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            manager.createNotificationChannel(channel)
        }

        private fun renderNotificationsWithoutService(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
            ensureNotificationChannel(context)

            val pausedItems: List<DownloadNotificationItem>
            val toCancelIds = ArrayList<Int>()
            synchronized(stateLock) {
                pausedItems = currentDownloads.values.filter { it.isPaused && !it.isDownloading }
                val activeModelIds = pausedItems.map { it.modelId }.toHashSet()
                val iterator = shownNotificationIds.entries.iterator()
                while (iterator.hasNext()) {
                    val entry = iterator.next()
                    if (!activeModelIds.contains(entry.key)) {
                        toCancelIds.add(entry.value)
                        iterator.remove()
                    }
                }
                for (item in pausedItems) {
                    shownNotificationIds[item.modelId] = notificationIdFor(item.modelId)
                }
            }

            for (id in toCancelIds) {
                try {
                    manager.cancel(id)
                } catch (_: Throwable) {
                }
            }
            for (item in pausedItems) {
                val id = notificationIdFor(item.modelId)
                val notification = buildNotification(context, item)
                try {
                    manager.notify(id, notification)
                } catch (_: SecurityException) {
                }
            }
        }

        private fun notificationIdFor(modelId: String): Int {
            return 1000 + (modelId.hashCode() and 0x0FFFFFFF)
        }

        private fun buildTransientForegroundNotification(context: Context): Notification {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
            }
            return builder
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(CHANNEL_NAME)
                .setContentText("Updating downloads...")
                .setOnlyAlertOnce(true)
                .build()
        }

        private fun buildNotification(
            context: Context,
            item: DownloadNotificationItem
        ): Notification {
            val fraction = when {
                item.progress > 0.0 -> item.progress.coerceIn(0.0, 1.0)
                item.totalBytes > 0L -> (item.receivedBytes.toDouble() / item.totalBytes.toDouble()).coerceIn(0.0, 1.0)
                else -> 0.0
            }
            val progressThousandths = (fraction * 1000.0).toInt().coerceIn(0, 1000)
            val pctInt = (fraction * 100.0).toInt().coerceIn(0, 100)

            val openIntent = Intent(context, MainActivity::class.java).apply {
                action = ACTION_OPEN_DOWNLOADS
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_ACTION, "open_downloads")
                putExtra(EXTRA_MODEL_ID, item.modelId)
            }
            val openPendingIntent = PendingIntent.getActivity(
                context,
                ("open:" + item.modelId).hashCode(),
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
            }

            val iconRes = if (item.isDownloading) {
                android.R.drawable.stat_sys_download
            } else {
                android.R.drawable.ic_media_pause
            }

            val contentText = if (item.isDownloading) {
                buildDownloadingSubtext(item, pctInt)
            } else {
                buildPausedSubtext(item, pctInt)
            }

            builder
                .setSmallIcon(iconRes)
                .setContentTitle(item.title)
                .setContentText(contentText)
                .setOngoing(item.isDownloading)
                .setOnlyAlertOnce(true)
                .setAutoCancel(false)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setContentIntent(openPendingIntent)
                .setProgress(
                    1000,
                    progressThousandths,
                    item.isDownloading && item.totalBytes <= 0L
                )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }

            if (item.isDownloading) {
                builder.addAction(
                    createAction(
                        context = context,
                        iconRes = android.R.drawable.ic_media_pause,
                        title = "Pause",
                        broadcastAction = ACTION_PAUSE,
                        actionName = "pause",
                        modelId = item.modelId
                    )
                )
            } else {
                builder.addAction(
                    createAction(
                        context = context,
                        iconRes = android.R.drawable.ic_media_play,
                        title = "Resume",
                        broadcastAction = ACTION_RESUME,
                        actionName = "resume",
                        modelId = item.modelId
                    )
                )
            }

            builder.addAction(
                createAction(
                    context = context,
                    iconRes = android.R.drawable.ic_menu_close_clear_cancel,
                    title = "Cancel",
                    broadcastAction = ACTION_CANCEL,
                    actionName = "cancel",
                    modelId = item.modelId
                )
            )

            return builder.build()
        }

        private fun createAction(
            context: Context,
            iconRes: Int,
            title: String,
            broadcastAction: String,
            actionName: String,
            modelId: String
        ): Notification.Action {
            val intent = Intent(context, DownloadNotificationReceiver::class.java).apply {
                action = broadcastAction
                data = Uri.parse("mobai://download/$actionName/${Uri.encode(modelId)}")
                putExtra(EXTRA_ACTION, actionName)
                putExtra(EXTRA_MODEL_ID, modelId)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                ("$actionName:$modelId").hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            return Notification.Action.Builder(
                Icon.createWithResource(context, iconRes),
                title,
                pendingIntent
            ).build()
        }

        private fun buildDownloadingSubtext(item: DownloadNotificationItem, pctInt: Int): String {
            val speed = formatSpeed(item.speedBytesPerSec)
            val progressPart = if (item.totalBytes > 0L) {
                "$pctInt% • ${formatBytes(item.receivedBytes)} / ${formatBytes(item.totalBytes)}"
            } else if (item.receivedBytes > 0L) {
                formatBytes(item.receivedBytes)
            } else {
                "Starting..."
            }
            return if (speed != null) "$progressPart • $speed" else progressPart
        }

        private fun buildPausedSubtext(item: DownloadNotificationItem, pctInt: Int): String {
            return if (item.totalBytes > 0L) {
                "Paused • $pctInt% • ${formatBytes(item.receivedBytes)} / ${formatBytes(item.totalBytes)}"
            } else {
                "Paused • ${formatBytes(item.receivedBytes)}"
            }
        }

        private fun formatBytes(bytes: Long): String {
            if (bytes <= 0L) return "0 B"
            val kb = 1024.0
            val mb = kb * 1024.0
            val gb = mb * 1024.0
            return when {
                bytes < kb -> "$bytes B"
                bytes < mb -> String.format(Locale.US, "%.1f KB", bytes / kb)
                bytes < gb -> String.format(Locale.US, "%.1f MB", bytes / mb)
                else -> String.format(Locale.US, "%.2f GB", bytes / gb)
            }
        }

        private fun formatSpeed(speedBytesPerSec: Double): String? {
            if (speedBytesPerSec <= 0.0) return null
            val kb = 1024.0
            val mb = kb * 1024.0
            return when {
                speedBytesPerSec < kb -> "${speedBytesPerSec.toInt()} B/s"
                speedBytesPerSec < mb -> String.format(Locale.US, "%.1f KB/s", speedBytesPerSec / kb)
                else -> String.format(Locale.US, "%.1f MB/s", speedBytesPerSec / mb)
            }
        }
    }

    private val lockGuard = Any()
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var isForeground = false
    private var foregroundNotificationId: Int? = null
    private var foregroundModelId: String? = null

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        ensureNotificationChannel(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel(applicationContext)
        val startedAsForeground =
            intent?.getBooleanExtra(EXTRA_STARTED_AS_FOREGROUND, false) == true &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        applyState(startedAsForeground = startedAsForeground)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        DownloadNotificationBridge.emit("force_close", null)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        val idsToCancel = ArrayList<Int>()
        synchronized(stateLock) {
            val activeKeys = currentDownloads.values
                .filter { it.isDownloading }
                .map { it.modelId }
            for (modelId in activeKeys) {
                currentDownloads.remove(modelId)
                shownNotificationIds.remove(modelId)?.let { idsToCancel.add(it) }
            }
        }

        releaseLocks()

        if (isForeground) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            isForeground = false
            foregroundNotificationId = null
            foregroundModelId = null
        }

        if (manager != null) {
            for (id in idsToCancel) {
                try {
                    manager.cancel(id)
                } catch (_: Throwable) {
                }
            }
        }

        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseLocks()
        if (activeInstance === this) {
            activeInstance = null
        }
        super.onDestroy()
    }

    private fun applyState(startedAsForeground: Boolean = false) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return

        val activeItems: List<DownloadNotificationItem>
        val pausedItems: List<DownloadNotificationItem>
        val toCancelIds = ArrayList<Int>()

        synchronized(stateLock) {
            val allItems = currentDownloads.values.toList()
            activeItems = allItems.filter { it.isDownloading }
            pausedItems = allItems.filter { !it.isDownloading && it.isPaused }

            val retainedIds = HashSet<String>(activeItems.size + pausedItems.size)
            for (item in activeItems) retainedIds.add(item.modelId)
            for (item in pausedItems) retainedIds.add(item.modelId)

            val iterator = shownNotificationIds.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next()
                if (!retainedIds.contains(entry.key)) {
                    toCancelIds.add(entry.value)
                    iterator.remove()
                }
            }
            for (item in activeItems) {
                shownNotificationIds[item.modelId] = notificationIdFor(item.modelId)
            }
            for (item in pausedItems) {
                shownNotificationIds[item.modelId] = notificationIdFor(item.modelId)
            }
        }

        if (activeItems.isNotEmpty()) {
            acquireLocks()

            val targetForegroundItem = activeItems.firstOrNull { it.modelId == foregroundModelId }
                ?: activeItems.first()
            val targetForegroundId = notificationIdFor(targetForegroundItem.modelId)
            val targetForegroundNotification = buildNotification(applicationContext, targetForegroundItem)

            startForegroundCompat(targetForegroundId, targetForegroundNotification)
            isForeground = true
            foregroundNotificationId = targetForegroundId
            foregroundModelId = targetForegroundItem.modelId

            for (item in activeItems) {
                if (item.modelId == targetForegroundItem.modelId) continue
                val id = notificationIdFor(item.modelId)
                try {
                    manager.notify(id, buildNotification(applicationContext, item))
                } catch (_: SecurityException) {
                }
            }

            for (item in pausedItems) {
                val id = notificationIdFor(item.modelId)
                try {
                    manager.notify(id, buildNotification(applicationContext, item))
                } catch (_: SecurityException) {
                }
            }

            for (id in toCancelIds) {
                if (id != targetForegroundId) {
                    try {
                        manager.cancel(id)
                    } catch (_: Throwable) {
                    }
                }
            }
            return
        }

        // Zero active downloads remain.
        releaseLocks()

        // If started via startForegroundService() and active downloads became empty
        // before onStartCommand ran, satisfy Android's startForeground() contract
        // before stopping so ForegroundServiceDidNotStartInTimeException never occurs.
        if (!isForeground && startedAsForeground) {
            startForegroundCompat(
                TRANSIENT_FOREGROUND_ID,
                buildTransientForegroundNotification(applicationContext)
            )
            isForeground = true
            foregroundNotificationId = TRANSIENT_FOREGROUND_ID
            foregroundModelId = null
        }

        if (pausedItems.isNotEmpty()) {
            val previousForegroundId = foregroundNotificationId
            if (isForeground) {
                val stopFlags = if (previousForegroundId == TRANSIENT_FOREGROUND_ID) {
                    STOP_FOREGROUND_REMOVE
                } else {
                    STOP_FOREGROUND_DETACH
                }
                stopForeground(stopFlags)
                isForeground = false
                foregroundNotificationId = null
                foregroundModelId = null
            }

            for (id in toCancelIds) {
                try {
                    manager.cancel(id)
                } catch (_: Throwable) {
                }
            }

            val pausedIds = HashSet<Int>(pausedItems.size)
            for (item in pausedItems) {
                val id = notificationIdFor(item.modelId)
                pausedIds.add(id)
                try {
                    manager.notify(id, buildNotification(applicationContext, item))
                } catch (_: SecurityException) {
                }
            }

            if (previousForegroundId != null && !pausedIds.contains(previousForegroundId)) {
                try {
                    manager.cancel(previousForegroundId)
                } catch (_: Throwable) {
                }
            }

            stopSelf()
        } else {
            if (isForeground) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                isForeground = false
                foregroundNotificationId = null
                foregroundModelId = null
            }
            for (id in toCancelIds) {
                try {
                    manager.cancel(id)
                } catch (_: Throwable) {
                }
            }
            stopSelf()
        }
    }

    private fun startForegroundCompat(notificationId: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(notificationId, notification)
        }
    }

    private fun acquireLocks() {
        synchronized(lockGuard) {
            if (wakeLock == null) {
                val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "mobai:DownloadWakeLock"
                )?.apply {
                    setReferenceCounted(false)
                }
            }
            try {
                // Renew safety timeout while active downloads are running.
                wakeLock?.acquire(WAKELOCK_TIMEOUT_MS)
            } catch (_: Throwable) {
            }

            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm?.createWifiLock(mode, "mobai:DownloadWifiLock")?.apply {
                    setReferenceCounted(false)
                }
            }
            try {
                if (wifiLock?.isHeld == false) {
                    wifiLock?.acquire()
                }
            } catch (_: Throwable) {
            }
        }
    }

    private fun releaseLocks() {
        synchronized(lockGuard) {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
            } catch (_: Throwable) {
            }
            try {
                if (wifiLock?.isHeld == true) {
                    wifiLock?.release()
                }
            } catch (_: Throwable) {
            }
        }
    }
}
