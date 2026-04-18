package com.example.ai_scheduler

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai_scheduler/widget"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateHomeWidget" -> {
                    val rawEntries = call.argument<List<Map<String, Any?>>>("entries") ?: emptyList()
                    updateHomeWidget(applicationContext, rawEntries)
                    result.success(null)
                }

                "updateDayCountdownWidget" -> {
                    val title = call.argument<String>("title") ?: ""
                    val targetMillis = (call.argument<Number>("targetMillis"))?.toLong() ?: 0L
                    updateDayCountdownWidget(applicationContext, title, targetMillis)
                    result.success(null)
                }

                "clearDayCountdownWidget" -> {
                    clearDayCountdownWidget(applicationContext)
                    result.success(null)
                }

                "updatePersistentCountdownWidget" -> {
                    val title = call.argument<String>("title") ?: ""
                    val status = call.argument<String>("status") ?: "idle"
                    val remainingMillis = (call.argument<Number>("remainingMillis"))?.toLong() ?: 0L
                    val targetMillis = (call.argument<Number>("targetMillis"))?.toLong() ?: 0L
                    updatePersistentCountdownWidget(
                        applicationContext,
                        title,
                        status,
                        remainingMillis,
                        targetMillis
                    )
                    result.success(null)
                }

                "clearPersistentCountdownWidget" -> {
                    clearPersistentCountdownWidget(applicationContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai_scheduler/alarm"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val id = call.argument<Int>("id")
                    val title = call.argument<String>("title") ?: "Alarm"
                    val body = call.argument<String>("body") ?: ""
                    val triggerAtMillis = (call.argument<Number>("triggerAtMillis"))?.toLong()
                    val mode = call.argument<String>("mode") ?: "alarm"
                    if (id == null || triggerAtMillis == null) {
                        result.error("invalid_args", "Missing alarm arguments", null)
                        return@setMethodCallHandler
                    }
                    AlarmScheduler.scheduleAlarm(
                        context = applicationContext,
                        id = id,
                        title = title,
                        body = body,
                        triggerAtMillis = triggerAtMillis,
                        mode = mode,
                    )
                    result.success(null)
                }

                "cancelAlarm" -> {
                    val id = call.argument<Int>("id")
                    if (id == null) {
                        result.error("invalid_args", "Missing alarm id", null)
                        return@setMethodCallHandler
                    }
                    AlarmScheduler.cancelAlarm(applicationContext, id)
                    result.success(null)
                }

                "stopAlarm" -> {
                    val id = call.argument<Int>("id")
                    AlarmScheduler.stopAlarm(applicationContext, id)
                    result.success(null)
                }

                "canScheduleExactAlarms" -> {
                    val alarmManager = AlarmScheduler.alarmManager(applicationContext)
                    val canSchedule = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        alarmManager.canScheduleExactAlarms()
                    } else {
                        true
                    }
                    result.success(canSchedule)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun updateHomeWidget(context: Context, entries: List<Map<String, Any?>>) {
        val prefs = context.getSharedPreferences("ai_scheduler_widget", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putInt("entryCount", entries.size.coerceAtMost(3))
            repeat(3) { index ->
                val entry = entries.getOrNull(index)
                putString("title_$index", entry?.get("title") as? String ?: "")
                putLong("targetMillis_$index", (entry?.get("targetMillis") as? Number)?.toLong() ?: 0L)
            }
            apply()
        }

        val manager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, SchedulerAppWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(componentName)
        val intent = Intent(context, SchedulerAppWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        }
        context.sendBroadcast(intent)
    }

    private fun updateDayCountdownWidget(context: Context, title: String, targetMillis: Long) {
        val prefs = context.getSharedPreferences("ai_scheduler_day_widget", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("title", title)
            .putLong("targetMillis", targetMillis)
            .apply()

        val manager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, DayCountdownAppWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(componentName)
        val intent = Intent(context, DayCountdownAppWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        }
        context.sendBroadcast(intent)
    }

    private fun clearDayCountdownWidget(context: Context) {
        val prefs = context.getSharedPreferences("ai_scheduler_day_widget", Context.MODE_PRIVATE)
        prefs.edit()
            .remove("title")
            .remove("targetMillis")
            .apply()

        val manager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, DayCountdownAppWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(componentName)
        val intent = Intent(context, DayCountdownAppWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        }
        context.sendBroadcast(intent)
    }

    private fun updatePersistentCountdownWidget(
        context: Context,
        title: String,
        status: String,
        remainingMillis: Long,
        targetMillis: Long,
    ) {
        val prefs = context.getSharedPreferences("ai_scheduler_persistent_widget", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("title", title)
            .putString("status", status)
            .putLong("remainingMillis", remainingMillis)
            .putLong("targetMillis", targetMillis)
            .apply()

        val manager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, PersistentCountdownAppWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(componentName)
        val intent = Intent(context, PersistentCountdownAppWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        }
        context.sendBroadcast(intent)
    }

    private fun clearPersistentCountdownWidget(context: Context) {
        val prefs = context.getSharedPreferences("ai_scheduler_persistent_widget", Context.MODE_PRIVATE)
        prefs.edit()
            .remove("title")
            .remove("status")
            .remove("remainingMillis")
            .remove("targetMillis")
            .apply()

        val manager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, PersistentCountdownAppWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(componentName)
        val intent = Intent(context, PersistentCountdownAppWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        }
        context.sendBroadcast(intent)
    }
}
