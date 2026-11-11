#!/usr/bin/env python3
"""Правки сгенерированных android/ и ios/ для flutter_local_notifications.

Скрипт идемпотентный: повторный запуск ничего не ломает.
"""
import pathlib
import re
import shutil
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_NAME = "Напоминатор"
errors = []


def read(p):
    return p.read_text(encoding="utf-8")


def write(p, s):
    p.write_text(s, encoding="utf-8")


# ---------------- Android: манифест ----------------
manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
m = read(manifest)

PERMS = """
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
"""
RECEIVERS = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "POST_NOTIFICATIONS" not in m:
    m = re.sub(r"(<manifest[^>]*>)", lambda x: x.group(1) + PERMS, m, count=1)
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", RECEIVERS + "    </application>", 1)

WIDGET = """
        <receiver android:name=".TodayWidgetProvider" android:exported="true"
            android:label="@string/widget_label">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider"
                android:resource="@xml/today_widget_info" />
        </receiver>
        <receiver android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="es.antonborri.home_widget.action.BACKGROUND" />
            </intent-filter>
        </receiver>
        <service android:name="es.antonborri.home_widget.HomeWidgetBackgroundService"
            android:permission="android.permission.BIND_JOB_SERVICE"
            android:exported="true" />
"""
if "TodayWidgetProvider" not in m:
    m = m.replace("</application>", WIDGET + "    </application>", 1)
m = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', m, count=1)
write(manifest, m)

# ---------------- Android: виджет, ресурсы, иконка ----------------
main_dir = ROOT / "android/app/src/main"
extra = ROOT / "tool/android_extra"
shutil.copytree(extra / "res", main_dir / "res", dirs_exist_ok=True)
activity = list((main_dir / "kotlin").rglob("MainActivity.kt"))
if activity:
    shutil.copy(extra / "kotlin/TodayWidgetProvider.kt", activity[0].parent / "TodayWidgetProvider.kt")
else:
    errors.append("не найден MainActivity.kt — некуда положить виджет")
shutil.copytree(ROOT / "tool/icons/android", main_dir / "res", dirs_exist_ok=True)

# ---------------- Android: desugaring ----------------
kts = ROOT / "android/app/build.gradle.kts"
groovy = ROOT / "android/app/build.gradle"
DESUGAR = "com.android.tools:desugar_jdk_libs:2.1.4"
if kts.exists():
    g = read(kts)
    if "isCoreLibraryDesugaringEnabled" not in g:
        g, n = re.subn(r"compileOptions\s*\{",
                       "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
        if n == 0:
            errors.append("build.gradle.kts: не найден compileOptions")
        g += f'\ndependencies {{\n    coreLibraryDesugaring("{DESUGAR}")\n}}\n'
    write(kts, g)
elif groovy.exists():
    g = read(groovy)
    if "coreLibraryDesugaringEnabled" not in g:
        g, n = re.subn(r"compileOptions\s*\{",
                       "compileOptions {\n        coreLibraryDesugaringEnabled true", g, count=1)
        if n == 0:
            errors.append("build.gradle: не найден compileOptions")
        g += f"\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR}'\n}}\n"
    write(groovy, g)
else:
    errors.append("не найден android/app/build.gradle(.kts)")

# ---------------- iOS: AppDelegate ----------------
delegate = ROOT / "ios/Runner/AppDelegate.swift"
d = read(delegate)
if "flutter_local_notifications" not in d:
    d = d.replace("import UIKit", "import UIKit\nimport UserNotifications\nimport flutter_local_notifications", 1)
    SNIPPET = """
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
"""
    d, n = re.subn(r"(didFinishLaunchingWithOptions[^{]*\{)", lambda x: x.group(1) + SNIPPET, d, count=1)
    if n == 0:
        errors.append("AppDelegate.swift: не найден didFinishLaunchingWithOptions")
    write(delegate, d)

# ---------------- iOS: имя приложения ----------------
plist = ROOT / "ios/Runner/Info.plist"
p = read(plist)
p = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
           lambda x: x.group(1) + APP_NAME + x.group(2), p, count=1)
write(plist, p)

# ---------------- iOS: иконка ----------------
def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])

appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
ios_icons = ROOT / "tool/icons/ios"
for png in appicon.glob("*.png"):
    w, _ = png_size(png)
    src = ios_icons / f"{w}.png"
    if src.exists():
        shutil.copy(src, png)
    else:
        print(f"нет иконки {w}px для {png.name} — оставлена стандартная")

if errors:
    print("ОШИБКИ ПАТЧА:\n  " + "\n  ".join(errors))
    sys.exit(1)
print("Платформы пропатчены.")
