package ru.napominator.napominator

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        /** Ключи иконок → activity-alias из AndroidManifest (tool/patch_platforms.py). */
        val ICONS = mapOf(
            "indigo" to "IconIndigo",
            "sunset" to "IconSunset",
            "mint" to "IconMint",
            "ocean" to "IconOcean",
            "graphite" to "IconGraphite",
        )
        private const val REQ_RINGTONE = 4101
        private const val REQ_FILE = 4102
    }

    private var preview: MediaPlayer? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "napominator/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> result.success(setIcon(call.arguments as? String ?: "indigo"))
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "napominator/alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    AlarmScheduler.save(this, call.arguments as? String ?: "[]")
                    AlarmScheduler.rescheduleAll(this)
                    result.success(true)
                }
                "isSupported" -> result.success(true)
                "missingPermissions" -> result.success(missingPermissions())
                "requestPermission" -> {
                    requestPermission(call.arguments as? String ?: "")
                    result.success(true)
                }
                "preview" -> {
                    playPreview(call.arguments as? String)
                    result.success(true)
                }
                "stopPreview" -> {
                    stopPreview()
                    result.success(true)
                }
                "pickSystem" -> pickRingtone(result)
                "pickFile" -> pickFile(result)
                else -> result.notImplemented()
            }
        }
    }

    // ---------- Иконка ----------

    private fun setIcon(key: String): Boolean {
        val target = ICONS[key] ?: return false
        return try {
            val pm = packageManager
            // Сначала включаем нужную, потом выключаем остальные — чтобы иконка не пропала совсем.
            pm.setComponentEnabledSetting(
                ComponentName(packageName, "$packageName.$target"),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            for ((_, alias) in ICONS) {
                if (alias == target) continue
                pm.setComponentEnabledSetting(
                    ComponentName(packageName, "$packageName.$alias"),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    // ---------- Разрешения для будильника ----------

    private fun missingPermissions(): List<String> {
        val res = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (!am.canScheduleExactAlarms()) res.add("exact")
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!nm.canUseFullScreenIntent()) res.add("fullScreen")
        }
        return res
    }

    private fun requestPermission(what: String) {
        try {
            val intent = when {
                what == "exact" && Build.VERSION.SDK_INT >= 31 ->
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                what == "fullScreen" && Build.VERSION.SDK_INT >= 34 ->
                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
                else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            }
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
    }

    // ---------- Прослушивание мелодии ----------

    private fun playPreview(sound: String?) {
        stopPreview()
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            mp.setDataSource(this, AlarmScheduler.soundUri(this, sound))
            mp.isLooping = false
            mp.prepare()
            mp.start()
            preview = mp
        } catch (e: Exception) {
            preview = null
        }
    }

    private fun stopPreview() {
        try {
            preview?.stop()
        } catch (e: Exception) {
        }
        preview?.release()
        preview = null
    }

    // ---------- Выбор системной мелодии / файла ----------

    private fun pickRingtone(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Мелодия будильника")
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            .putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_RINGTONE)
        } catch (e: Exception) {
            pendingPick = null
            result.success(null)
        }
    }

    private fun pickFile(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("audio/*")
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_FILE)
        } catch (e: Exception) {
            pendingPick = null
            result.success(null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_RINGTONE && requestCode != REQ_FILE) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != RESULT_OK || data == null) {
            result.success(null)
            return
        }
        try {
            if (requestCode == REQ_RINGTONE) {
                val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
                } else {
                    data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                }
                if (uri == null) {
                    result.success(null)
                    return
                }
                val title = RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "Системная мелодия"
                result.success(mapOf("sound" to "uri:$uri", "title" to title))
            } else {
                val uri = data.data
                if (uri == null) {
                    result.success(null)
                    return
                }
                try {
                    contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } catch (e: Exception) {
                }
                var title = "Свой файл"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) title = it.getString(0)?.substringBeforeLast('.') ?: title
                }
                result.success(mapOf("sound" to "uri:$uri", "title" to title))
            }
        } catch (e: Exception) {
            result.success(null)
        }
    }

    override fun onDestroy() {
        stopPreview()
        super.onDestroy()
    }
}
