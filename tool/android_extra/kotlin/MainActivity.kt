package ru.napominator.napominator

import android.content.ComponentName
import android.content.pm.PackageManager
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "napominator/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> result.success(setIcon(call.arguments as? String ?: "indigo"))
                    else -> result.notImplemented()
                }
            }
    }

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
}
