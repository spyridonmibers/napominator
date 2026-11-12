package ru.napominator.napominator

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.TextView
import java.lang.ref.WeakReference
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Экран звонящего будильника — поверх экрана блокировки. */
class AlarmActivity : Activity() {

    companion object {
        const val EXTRA_LABEL = "label"
        const val EXTRA_SNOOZE = "snooze"
        private var current: WeakReference<AlarmActivity>? = null

        fun closeAll() {
            current?.get()?.finish()
            current = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.alarm_activity)
        bind(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        bind(intent)
    }

    private fun bind(intent: Intent?) {
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Будильник"
        val snooze = intent?.getIntExtra(EXTRA_SNOOZE, 10) ?: 10
        findViewById<TextView>(R.id.alarm_time).text =
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        findViewById<TextView>(R.id.alarm_label).text = label
        findViewById<TextView>(R.id.alarm_snooze).apply {
            text = "Отложить на $snooze мин"
            setOnClickListener { send(AlarmService.ACTION_SNOOZE) }
        }
        findViewById<TextView>(R.id.alarm_dismiss).setOnClickListener {
            send(AlarmService.ACTION_DISMISS)
        }
    }

    private fun send(action: String) {
        startService(Intent(this, AlarmService::class.java).setAction(action))
        finish()
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    @Deprecated("Кнопка «Назад» не выключает будильник")
    override fun onBackPressed() {
        // Будильник выключается только кнопками
    }
}
