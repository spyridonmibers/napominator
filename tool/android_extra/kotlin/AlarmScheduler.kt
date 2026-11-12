package ru.napominator.napominator

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Планирование будильников через AlarmManager.setAlarmClock — так же, как это делает
 * системное приложение «Часы»: срабатывает точно и даже в режиме экономии.
 * Будильники присылает Dart (lib/services/alarm_bridge.dart) в виде JSON.
 */
object AlarmScheduler {
    private const val PREFS = "NapominatorAlarms"
    private const val KEY_ALARMS = "alarms"
    private const val KEY_SCHEDULED = "scheduled"
    const val ACTION_FIRE = "ru.napominator.napominator.ALARM_FIRE"
    const val EXTRA_ID = "alarm_id"
    private const val SNOOZE_OFFSET = 500000

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(ctx: Context, json: String) {
        prefs(ctx).edit().putString(KEY_ALARMS, json).apply()
    }

    fun load(ctx: Context): JSONArray = try {
        JSONArray(prefs(ctx).getString(KEY_ALARMS, "[]"))
    } catch (e: Exception) {
        JSONArray()
    }

    fun find(ctx: Context, id: String): JSONObject? {
        val all = load(ctx)
        for (i in 0 until all.length()) {
            val a = all.optJSONObject(i) ?: continue
            if (a.optString("id") == id) return a
        }
        return null
    }

    // ---------- Расписание (то же, что lib/logic/alarm_schedule.dart) ----------

    private fun ringsOn(a: JSONObject, day: LocalDate): Boolean {
        val start = try {
            LocalDate.parse(a.optString("startDate"))
        } catch (e: Exception) {
            day
        }
        if (day.isBefore(start)) return false
        val diff = ChronoUnit.DAYS.between(start, day)
        return when (a.optString("repeat")) {
            "everyOtherDay" -> diff % 2 == 0L
            "weekdays" -> {
                val days = a.optJSONArray("weekdays") ?: JSONArray()
                var found = false
                for (i in 0 until days.length()) {
                    if (days.optInt(i) == day.dayOfWeek.value) found = true
                }
                found
            }
            "cycle" -> {
                val on = maxOf(1, a.optInt("cycleOn", 2))
                val off = maxOf(0, a.optInt("cycleOff", 2))
                diff % (on + off) < on
            }
            else -> true
        }
    }

    fun nextTrigger(a: JSONObject, now: LocalDateTime = LocalDateTime.now()): Long? {
        if (!a.optBoolean("enabled", true)) return null
        val minutes = a.optInt("minutes", 420)
        var day = now.toLocalDate()
        repeat(400) {
            if (ringsOn(a, day)) {
                val at = day.atTime(minutes / 60, minutes % 60)
                if (at.isAfter(now)) {
                    return at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                }
            }
            day = day.plusDays(1)
        }
        return null
    }

    // ---------- Постановка в систему ----------

    private fun firePending(ctx: Context, requestCode: Int, id: String, flags: Int): PendingIntent? {
        val intent = Intent(ctx, AlarmReceiver::class.java)
            .setAction(ACTION_FIRE)
            .putExtra(EXTRA_ID, id)
        return PendingIntent.getBroadcast(ctx, requestCode, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun setClock(ctx: Context, triggerAt: Long, operation: PendingIntent) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val show = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAt, show), operation)
        } catch (e: SecurityException) {
            // Нет разрешения на точные будильники — ставим как получится.
            if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            }
        }
    }

    /** Снять все запланированные и поставить заново ближайшие срабатывания. */
    fun rescheduleAll(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val p = prefs(ctx)
        // Снимаем старые
        val old = p.getString(KEY_SCHEDULED, "") ?: ""
        for (part in old.split(",")) {
            val code = part.toIntOrNull() ?: continue
            val pi = firePending(ctx, code, "", PendingIntent.FLAG_NO_CREATE)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
            }
        }
        // Ставим новые
        val scheduled = mutableListOf<Int>()
        val all = load(ctx)
        for (i in 0 until all.length()) {
            val a = all.optJSONObject(i) ?: continue
            val at = nextTrigger(a) ?: continue
            val code = a.optInt("nativeId")
            val pi = firePending(ctx, code, a.optString("id"), PendingIntent.FLAG_UPDATE_CURRENT) ?: continue
            setClock(ctx, at, pi)
            scheduled.add(code)
        }
        p.edit().putString(KEY_SCHEDULED, scheduled.joinToString(",")).apply()
    }

    fun scheduleSnooze(ctx: Context, a: JSONObject) {
        val minutes = maxOf(1, a.optInt("snoozeMinutes", 10))
        val at = System.currentTimeMillis() + minutes * 60_000L
        val pi = firePending(
            ctx, a.optInt("nativeId") + SNOOZE_OFFSET, a.optString("id"),
            PendingIntent.FLAG_UPDATE_CURRENT
        ) ?: return
        setClock(ctx, at, pi)
    }

    // ---------- Мелодия ----------

    fun soundUri(ctx: Context, sound: String?): Uri {
        val s = sound ?: ""
        if (s.startsWith("builtin:")) {
            val res = ctx.resources.getIdentifier("alarm_" + s.removePrefix("builtin:"), "raw", ctx.packageName)
            if (res != 0) return Uri.parse("android.resource://${ctx.packageName}/$res")
        } else if (s.startsWith("uri:")) {
            return Uri.parse(s.removePrefix("uri:"))
        }
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    }
}
