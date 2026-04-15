package com.example.ai_scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class DayCountdownAppWidgetProvider : AppWidgetProvider() {
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
            val componentName = ComponentName(context, DayCountdownAppWidgetProvider::class.java)
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
            val prefs = context.getSharedPreferences("ai_scheduler_day_widget", Context.MODE_PRIVATE)
            val title = prefs.getString("title", "") ?: ""
            val targetMillis = prefs.getLong("targetMillis", 0L)
            val hasActiveCountdown = title.isNotBlank() && targetMillis > System.currentTimeMillis()

            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val views = RemoteViews(context.packageName, R.layout.day_countdown_widget).apply {
                setOnClickPendingIntent(R.id.day_widget_root, pendingIntent)
                setViewVisibility(R.id.day_widget_empty, if (hasActiveCountdown) android.view.View.GONE else android.view.View.VISIBLE)
                setViewVisibility(R.id.day_widget_content, if (hasActiveCountdown) android.view.View.VISIBLE else android.view.View.GONE)

                if (hasActiveCountdown) {
                    setTextViewText(R.id.day_widget_title, title)
                    setTextViewText(
                        R.id.day_widget_time,
                        formatRemaining(targetMillis - System.currentTimeMillis())
                    )
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            scheduleNextUpdate(context)
        }

        private fun scheduleNextUpdate(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, DayCountdownAppWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                700101,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC,
                System.currentTimeMillis() + 1000L,
                pendingIntent
            )
        }

        private fun formatRemaining(millis: Long): String {
            val totalSeconds = (millis / 1000L).coerceAtLeast(0L)
            val days = totalSeconds / 86400L
            val hours = (totalSeconds % 86400L) / 3600L
            val minutes = (totalSeconds % 3600L) / 60L
            val seconds = totalSeconds % 60L
            return String.format("%02dd %02dh %02dm %02ds", days, hours, minutes, seconds)
        }
    }
}
