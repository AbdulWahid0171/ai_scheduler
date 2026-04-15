package com.example.ai_scheduler

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

class AlarmRingingActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockscreen()
        setContentView(R.layout.activity_alarm_ringing)

        val alarmId = intent.getIntExtra(AlarmScheduler.extraAlarmId, 0)
        val title = intent.getStringExtra(AlarmScheduler.extraTitle) ?: "Alarm"
        val body = intent.getStringExtra(AlarmScheduler.extraBody) ?: ""
        val mode = intent.getStringExtra(AlarmScheduler.extraMode) ?: "alarm"

        findViewById<TextView>(R.id.modeLabel).text = if (mode == "timer") "TIMER" else "ALARM"
        findViewById<TextView>(R.id.alarmTitle).text = title
        findViewById<TextView>(R.id.alarmBody).text =
            if (body.isBlank()) {
                if (mode == "timer") "Timer finished" else "Alarm is ringing"
            } else {
                body
            }

        findViewById<Button>(R.id.dismissButton).setOnClickListener {
            AlarmScheduler.stopAlarm(this, alarmId)
            finish()
        }

        findViewById<Button>(R.id.snoozeButton).text = if (mode == "timer") "Add 5 Minutes" else "Snooze 5 Minutes"
        findViewById<Button>(R.id.snoozeButton).setOnClickListener {
            AlarmScheduler.snoozeAlarm(this, alarmId, title, body, mode)
            finish()
        }
    }

    override fun onNewIntent(intent: android.content.Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun showOverLockscreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
