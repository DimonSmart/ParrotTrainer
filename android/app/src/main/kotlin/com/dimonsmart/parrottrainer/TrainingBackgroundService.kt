package com.dimonsmart.parrottrainer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class TrainingBackgroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundWithNotification()
        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:training")
                .apply { acquire() }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundWithNotification() {
        val channelId = "training_background"
        val language = currentLanguage()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                when (language) {
                    "ru" -> "Обучение попугая"
                    "es" -> "Entrenamiento del loro"
                    else -> "Parrot training"
                },
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            android.app.Notification.Builder(this)
        }
        val notification = notificationBuilder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(
                when (language) {
                    "ru" -> "Parrot Trainer работает"
                    "es" -> "Parrot Trainer está activo"
                    else -> "Parrot Trainer is running"
                },
            )
            .setContentText(
                when (language) {
                    "ru" -> "Обучение продолжается при выключенном экране"
                    "es" -> "El entrenamiento continúa con la pantalla apagada"
                    else -> "Training continues while the screen is off"
                },
            )
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(101, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun currentLanguage(): String {
        val language = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            resources.configuration.locales[0].language
        } else {
            resources.configuration.locale.language
        }
        return when (language.lowercase()) {
            "ru", "es" -> language.lowercase()
            else -> "en"
        }
    }

    companion object {
        fun setEnabled(context: Context, enabled: Boolean) {
            val intent = Intent(context, TrainingBackgroundService::class.java)
            if (enabled) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } else {
                context.stopService(intent)
            }
        }
    }
}
