package com.example.ai_scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object AlarmScheduler {
    const val extraAlarmId = "alarm_id"
    const val extraTitle = "alarm_title"
    const val extraBody = "alarm_body"
    const val extraTriggerAtMillis = "trigger_at_millis"
    const val extraMode = "alarm_mode"
    const val actionRing = "com.example.ai_scheduler.action.RING"
    const val actionDismiss = "com.example.ai_scheduler.action.DISMISS"
    const val actionSnooze = "com.example.ai_scheduler.action.SNOOZE"

    fun alarmManager(context: Context): AlarmManager {
        return context.getSystemService(AlarmManager::class.java)
    }

    fun scheduleAlarm(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long,
        mode: String = "alarm",
    ) {
        val manager = alarmManager(context)
        val pendingIntent = createAlarmPendingIntent(
            context = context,
            id = id,
            title = title,
            body = body,
            triggerAtMillis = triggerAtMillis,
            mode = mode,
        )
        manager.cancel(pendingIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) {
            manager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            manager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        }
    }

    fun cancelAlarm(context: Context, id: Int) {
        val pendingIntent = findExistingAlarmPendingIntent(
            context = context,
            id = id,
        )
        if (pendingIntent != null) {
            alarmManager(context).cancel(pendingIntent)
            pendingIntent.cancel()
        }
        stopAlarm(context, id)
    }

    fun stopAlarm(context: Context, id: Int?) {
        val stopIntent = Intent(context, AlarmSoundService::class.java).apply {
            action = actionDismiss
            if (id != null) {
                putExtra(extraAlarmId, id)
            }
        }
        context.startService(stopIntent)
    }

    fun snoozeAlarm(
        context: Context,
        id: Int,
        title: String,
        body: String,
        mode: String,
        minutes: Int = 5,
    ) {
        stopAlarm(context, id)
        scheduleAlarm(
            context = context,
            id = id,
            title = title,
            body = body,
            triggerAtMillis = System.currentTimeMillis() + minutes * 60_000L,
            mode = mode,
        )
    }

    private fun createAlarmPendingIntent(
        context: Context,
        id: Int,
        title: String,
        body: String,
        triggerAtMillis: Long,
        mode: String,
    ): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = actionRing
            putExtra(extraAlarmId, id)
            putExtra(extraTitle, title)
            putExtra(extraBody, body)
            putExtra(extraTriggerAtMillis, triggerAtMillis)
            putExtra(extraMode, mode)
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun findExistingAlarmPendingIntent(
        context: Context,
        id: Int,
    ): PendingIntent? {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = actionRing
            putExtra(extraAlarmId, id)
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
