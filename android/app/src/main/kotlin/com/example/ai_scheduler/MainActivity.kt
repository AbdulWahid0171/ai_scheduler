package com.example.ai_scheduler

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
                    val title = call.argument<String>("title") ?: "Countdown Timers"
                    val subtitle = call.argument<String>("subtitle") ?: "No active countdowns"
                    val targetMillis = call.argument<Long>("targetMillis") ?: 0L
                    updateHomeWidget(applicationContext, title, subtitle, targetMillis)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun updateHomeWidget(context: Context, title: String, subtitle: String, targetMillis: Long) {
        val prefs = context.getSharedPreferences("ai_scheduler_widget", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("title", title)
            .putString("subtitle", subtitle)
            .putLong("targetMillis", targetMillis)
            .apply()

        val manager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, SchedulerAppWidgetProvider::class.java)
        val widgetIds = manager.getAppWidgetIds(componentName)
        val intent = Intent(context, SchedulerAppWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        }
        context.sendBroadcast(intent)
    }
}
