package com.example.ai_scheduler

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var activeAlarmId: Int? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            AlarmScheduler.actionDismiss -> {
                stopRinging()
                stopSelf()
                return START_NOT_STICKY
            }

            AlarmScheduler.actionRing -> {
                val alarmId = intent.getIntExtra(AlarmScheduler.extraAlarmId, 0)
                val title = intent.getStringExtra(AlarmScheduler.extraTitle) ?: "Alarm"
                val body = intent.getStringExtra(AlarmScheduler.extraBody) ?: ""
                val mode = intent.getStringExtra(AlarmScheduler.extraMode) ?: "alarm"
                activeAlarmId = alarmId
                startForeground(notificationId, buildNotification(alarmId, title, body, mode))
                startRinging()
                return START_STICKY
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    private fun startRinging() {
        if (mediaPlayer?.isPlaying == true) {
            return
        }

        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        mediaPlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(applicationContext, alarmUri)
            isLooping = true
            prepare()
            start()
        }

        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(longArrayOf(0, 600, 400), 0)
        }
    }

    private fun stopRinging() {
        mediaPlayer?.runCatching {
            if (isPlaying) stop()
            release()
        }
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun buildNotification(alarmId: Int, title: String, body: String, mode: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Alarm Ringing",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Foreground service while an alarm is ringing"
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }

        val fullScreenIntent = PendingIntent.getActivity(
            this,
            alarmId,
            Intent(this, AlarmRingingActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(AlarmScheduler.extraAlarmId, alarmId)
                putExtra(AlarmScheduler.extraTitle, title)
                putExtra(AlarmScheduler.extraBody, body)
                putExtra(AlarmScheduler.extraMode, mode)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val dismissIntent = PendingIntent.getService(
            this,
            alarmId + 10_000,
            Intent(this, AlarmSoundService::class.java).apply {
                action = AlarmScheduler.actionDismiss
                putExtra(AlarmScheduler.extraAlarmId, alarmId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(
                if (body.isBlank()) {
                    if (mode == "timer") "Timer is ringing" else "Alarm is ringing"
                } else {
                    body
                }
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(if (mode == "timer") NotificationCompat.CATEGORY_STOPWATCH else NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(0, "Dismiss", dismissIntent)
            .build()
    }

    companion object {
        private const val channelId = "alarm_ringing"
        private const val notificationId = 4041
    }
}
