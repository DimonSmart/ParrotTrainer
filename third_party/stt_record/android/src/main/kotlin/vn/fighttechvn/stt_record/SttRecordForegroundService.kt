package vn.fighttechvn.stt_record

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * A minimal foreground service used to keep audio capture alive while the app
 * is in background.
 */
class SttRecordForegroundService : Service() {

    private var isPaused = false
    private var enableActionPause = true
    private var enableActionStop = true
    private var notificationTitle = "Recording"
    private var notificationBody = "Speech-to-text is running"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            if (intent.hasExtra("EXTRA_ENABLE_ACTION_PAUSE")) {
                enableActionPause = intent.getBooleanExtra("EXTRA_ENABLE_ACTION_PAUSE", true)
            }
            if (intent.hasExtra("EXTRA_ENABLE_ACTION_STOP")) {
                enableActionStop = intent.getBooleanExtra("EXTRA_ENABLE_ACTION_STOP", true)
            }
            if (intent.hasExtra("EXTRA_NOTIFICATION_TITLE")) {
                notificationTitle = intent.getStringExtra("EXTRA_NOTIFICATION_TITLE") ?: "Recording"
            }
            if (intent.hasExtra("EXTRA_NOTIFICATION_BODY")) {
                notificationBody = intent.getStringExtra("EXTRA_NOTIFICATION_BODY") ?: "Speech-to-text is running"
            }
        }
        val action = intent?.action
        when (action) {
            ACTION_PAUSE -> {
                isPaused = true
                sendBroadcast(Intent(BROADCAST_PAUSE))
                updateNotification()
            }
            ACTION_RESUME -> {
                isPaused = false
                sendBroadcast(Intent(BROADCAST_RESUME))
                updateNotification()
            }
            ACTION_STOP -> {
                sendBroadcast(Intent(BROADCAST_STOP))
            }
            else -> {
                startInForeground()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        runCatching {
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        }
        super.onDestroy()
    }

    private fun startInForeground() {
        ensureNotificationChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Recording in background"
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
            )
        } else {
            null
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(notificationTitle)
            .setContentText(notificationBody)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)

        // Actions
        if (enableActionPause) {
            if (isPaused) {
                builder.addAction(
                    android.R.drawable.ic_media_play,
                    "Resume",
                    createActionIntent(ACTION_RESUME)
                )
            } else {
                builder.addAction(
                    android.R.drawable.ic_media_pause,
                    "Pause",
                    createActionIntent(ACTION_PAUSE)
                )
            }
        }
        
        if (enableActionStop) {
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                createActionIntent(ACTION_STOP)
            )
        }

        return builder.build()
    }

    private fun createActionIntent(action: String): PendingIntent {
        val intent = Intent(this, SttRecordForegroundService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
    }

    companion object {
        private const val CHANNEL_ID = "stt_record"
        private const val CHANNEL_NAME = "stt_record"
        private const val NOTIFICATION_ID = 48421

        const val ACTION_PAUSE = "ACTION_PAUSE"
        const val ACTION_RESUME = "ACTION_RESUME"
        const val ACTION_STOP = "ACTION_STOP"

        const val BROADCAST_PAUSE = "vn.fighttechvn.stt_record.PAUSE"
        const val BROADCAST_RESUME = "vn.fighttechvn.stt_record.RESUME"
        const val BROADCAST_STOP = "vn.fighttechvn.stt_record.STOP"

        fun start(context: Context, enableSystemNotification: Boolean, notificationTitle: String, notificationBody: String, enableActionPause: Boolean, enableActionStop: Boolean) {
            if (!enableSystemNotification) return
            val i = Intent(context, SttRecordForegroundService::class.java).apply {
                putExtra("EXTRA_ENABLE_ACTION_PAUSE", enableActionPause)
                putExtra("EXTRA_ENABLE_ACTION_STOP", enableActionStop)
                putExtra("EXTRA_NOTIFICATION_TITLE", notificationTitle)
                putExtra("EXTRA_NOTIFICATION_BODY", notificationBody)
            }
            runCatching {
                ContextCompat.startForegroundService(context, i)
            }
        }

        fun stop(context: Context) {
            runCatching {
                context.stopService(Intent(context, SttRecordForegroundService::class.java))
            }
        }

        // Optional: helper to tell the service it was paused/resumed by the app (not via notification)
        fun notifyState(context: Context, isPaused: Boolean) {
            val i = Intent(context, SttRecordForegroundService::class.java).apply {
                action = if (isPaused) ACTION_PAUSE else ACTION_RESUME
            }
            runCatching {
                ContextCompat.startForegroundService(context, i)
            }
        }
    }
}
