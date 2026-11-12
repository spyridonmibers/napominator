package ru.napominator.napominator

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Срабатывание будильника и перепланирование после перезагрузки / смены времени. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            AlarmScheduler.ACTION_FIRE -> {
                val id = intent.getStringExtra(AlarmScheduler.EXTRA_ID) ?: return
                val service = Intent(context, AlarmService::class.java)
                    .setAction(AlarmService.ACTION_START)
                    .putExtra(AlarmScheduler.EXTRA_ID, id)
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(service)
                } else {
                    context.startService(service)
                }
            }
            else -> AlarmScheduler.rescheduleAll(context)
        }
    }
}
