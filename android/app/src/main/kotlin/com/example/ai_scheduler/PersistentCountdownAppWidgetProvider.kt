package com.example.ai_scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class PersistentCountdownAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val manager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, PersistentCountdownAppWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(componentName)
            ids.forEach { updateWidget(context, manager, it) }
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences("ai_scheduler_persistent_widget", Context.MODE_PRIVATE)
            val title = prefs.getString("title", "") ?: ""
            val status = prefs.getString("status", "idle") ?: "idle"
            val remainingMillis = prefs.getLong("remainingMillis", 0L)
            val targetMillis = prefs.getLong("targetMillis", 0L)
            val hasTimer = title.isNotBlank()

            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val views = RemoteViews(context.packageName, R.layout.persistent_countdown_widget).apply {
                setOnClickPendingIntent(R.id.persistent_widget_root, pendingIntent)
                setViewVisibility(R.id.persistent_widget_empty, if (hasTimer) android.view.View.GONE else android.view.View.VISIBLE)
                setViewVisibility(R.id.persistent_widget_content, if (hasTimer) android.view.View.VISIBLE else android.view.View.GONE)

                if (hasTimer) {
                    setTextViewText(R.id.persistent_widget_title, title)
                    setTextViewText(R.id.persistent_widget_status, formatStatus(status))
                    setTextViewText(
                        R.id.persistent_widget_time,
                        formatRemaining(status, remainingMillis, targetMillis)
                    )
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            if (hasTimer) {
                scheduleNextUpdate(context)
            }
        }

        private fun scheduleNextUpdate(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, PersistentCountdownAppWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                700201,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC,
                System.currentTimeMillis() + 1000L,
                pendingIntent
            )
        }

        private fun formatStatus(status: String): String {
            return when (status) {
                "running" -> "Running"
                "paused" -> "Paused"
                "finished" -> "Finished"
                else -> "Ready"
            }
        }

        private fun formatRemaining(status: String, remainingMillis: Long, targetMillis: Long): String {
            val effectiveMillis = if (status == "running" && targetMillis > 0L) {
                (targetMillis - System.currentTimeMillis()).coerceAtLeast(0L)
            } else {
                remainingMillis.coerceAtLeast(0L)
            }
            val totalSeconds = effectiveMillis / 1000L
            val hours = totalSeconds / 3600L
            val minutes = (totalSeconds % 3600L) / 60L
            val seconds = totalSeconds % 60L
            return String.format("%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
}
