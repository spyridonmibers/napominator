package ru.napominator.napominator

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Звонящий будильник: мелодия по каналу «Будильник», вибрация, экран поверх блокировки. */
class AlarmService : Service() {

    companion object {
        const val ACTION_START = "ru.napominator.napominator.ALARM_START"
        const val ACTION_SNOOZE = "ru.napominator.napominator.ALARM_SNOOZE"
        const val ACTION_DISMISS = "ru.napominator.napominator.ALARM_DISMISS"
        private const val CHANNEL = "alarm_ring"
        private const val NOTIF_ID = 9100
        private const val RAMP_MS = 30_000L
        private const val AUTO_STOP_MS = 10 * 60_000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var current: JSONObject? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(AlarmScheduler.EXTRA_ID)
                val alarm = if (id == null) null else AlarmScheduler.find(this, id)
                if (alarm == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                start(alarm)
            }
            ACTION_SNOOZE -> {
                current?.let { AlarmScheduler.scheduleSnooze(this, it) }
                stopRinging()
            }
            ACTION_DISMISS -> stopRinging()
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun start(alarm: JSONObject) {
        stopSound()
        current = alarm
        val notification = buildNotification(alarm)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, notification)
        }

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "napominator:alarm").apply {
            acquire(AUTO_STOP_MS + 60_000L)
        }

        playSound(alarm)
        if (alarm.optBoolean("vibrate", true)) vibrate()

        // Следующее срабатывание по графику
        AlarmScheduler.rescheduleAll(this)
        // Через 10 минут без ответа замолкаем
        handler.postDelayed({ stopRinging() }, AUTO_STOP_MS)
    }

    private fun playSound(alarm: JSONObject) {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val uris = listOf(
            AlarmScheduler.soundUri(this, alarm.optString("sound")),
            AlarmScheduler.soundUri(this, null)
        )
        for (uri in uris) {
            try {
                val mp = MediaPlayer()
                mp.setAudioAttributes(attrs)
                mp.setDataSource(this, uri)
                mp.isLooping = true
                mp.prepare()
                val ramp = alarm.optBoolean("ramp", true)
                mp.setVolume(if (ramp) 0.1f else 1f, if (ramp) 0.1f else 1f)
                mp.start()
                player = mp
                if (ramp) rampVolume(System.currentTimeMillis())
                return
            } catch (e: Exception) {
                // пробуем мелодию по умолчанию
            }
        }
    }

    private fun rampVolume(startedAt: Long) {
        handler.postDelayed(object : Runnable {
            override fun run() {
                val mp = player ?: return
                val p = ((System.currentTimeMillis() - startedAt).toFloat() / RAMP_MS).coerceIn(0f, 1f)
                val v = 0.1f + 0.9f * p
                try {
                    mp.setVolume(v, v)
                } catch (e: Exception) {
                    return
                }
                if (p < 1f) handler.postDelayed(this, 1000)
            }
        }, 1000)
    }

    @Suppress("DEPRECATION")
    private fun vibrate() {
        val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator ?: return
        vibrator = v
        val pattern = longArrayOf(0, 700, 500)
        if (Build.VERSION.SDK_INT >= 26) {
            val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
            v.vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
        } else {
            v.vibrate(pattern, 0)
        }
    }

    private fun buildNotification(alarm: JSONObject): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CHANNEL, "Будильник", NotificationManager.IMPORTANCE_HIGH)
            ch.description = "Звонящий будильник"
            ch.setSound(null, null) // мелодию играем сами
            ch.enableVibration(false)
            ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            ch.setBypassDnd(true)
            nm.createNotificationChannel(ch)
        }
        val label = alarm.optString("label").ifEmpty { "Будильник" }
        val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        val snooze = alarm.optInt("snoozeMinutes", 10)

        val full = Intent(this, AlarmActivity::class.java)
            .putExtra(AlarmActivity.EXTRA_LABEL, label)
            .putExtra(AlarmActivity.EXTRA_SNOOZE, snooze)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION)
        val fullPi = PendingIntent.getActivity(
            this, 9101, full, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        fun servicePi(action: String, code: Int) = PendingIntent.getService(
            this, code, Intent(this, AlarmService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        @Suppress("DEPRECATION")
        b.setSmallIcon(R.drawable.ic_stat_goal)
            .setContentTitle("$time · $label")
            .setContentText("Будильник звонит")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullPi, true)
            .setContentIntent(fullPi)
            .addAction(R.drawable.ic_stat_goal, "Отложить на $snooze мин", servicePi(ACTION_SNOOZE, 9102))
            .addAction(R.drawable.ic_stat_goal, "Выключить", servicePi(ACTION_DISMISS, 9103))
        return b.build()
    }

    private fun stopSound() {
        handler.removeCallbacksAndMessages(null)
        try {
            player?.stop()
        } catch (e: Exception) {
        }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun stopRinging() {
        stopSound()
        AlarmActivity.closeAll()
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
        }
        wakeLock = null
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        stopSound()
        super.onDestroy()
    }
}
