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
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
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
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
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
ALARM = """
        <receiver android:name=".AlarmReceiver" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
            </intent-filter>
        </receiver>
        <service android:name=".AlarmService" android:exported="false"
            android:foregroundServiceType="mediaPlayback" />
        <activity android:name=".AlarmActivity" android:exported="false"
            android:showWhenLocked="true" android:turnScreenOn="true"
            android:excludeFromRecents="true" android:launchMode="singleInstance"
            android:taskAffinity="" android:screenOrientation="portrait"
            android:theme="@android:style/Theme.Material.NoActionBar.Fullscreen" />
"""
if "AlarmReceiver" not in m:
    m = m.replace("</application>", ALARM + "    </application>", 1)
if "TodayWidgetProvider" not in m:
    m = m.replace("</application>", WIDGET + "    </application>", 1)
m = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', m, count=1)

# Смена иконки: значок на рабочем столе даёт не MainActivity, а одна из activity-alias.
ICON_ALIASES = [("IconIndigo", "@mipmap/ic_launcher", True)] + [
    (f"Icon{k.capitalize()}", f"@mipmap/ic_launcher_{k}", False)
    for k in ["sunset", "mint", "ocean", "graphite"]
]
if "IconIndigo" not in m:
    m, n = re.subn(
        r'\s*<intent-filter>\s*<action android:name="android\.intent\.action\.MAIN"\s*/>\s*'
        r'<category android:name="android\.intent\.category\.LAUNCHER"\s*/>\s*</intent-filter>',
        "", m, count=1)
    if n == 0:
        errors.append("AndroidManifest: не найден LAUNCHER intent-filter у MainActivity")
    aliases = ""
    for name, icon, enabled in ICON_ALIASES:
        aliases += f"""
        <activity-alias android:name=".{name}" android:targetActivity=".MainActivity"
            android:enabled="{'true' if enabled else 'false'}" android:exported="true"
            android:icon="{icon}" android:label="{APP_NAME}">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
"""
    m = m.replace("</application>", aliases + "    </application>", 1)
write(manifest, m)

# ---------------- Android: виджет, ресурсы, иконка ----------------
main_dir = ROOT / "android/app/src/main"
extra = ROOT / "tool/android_extra"
shutil.copytree(extra / "res", main_dir / "res", dirs_exist_ok=True)
activity = list((main_dir / "kotlin").rglob("MainActivity.kt"))
if activity:
    # MainActivity заменяем своей, остальные классы (виджет, будильник) кладём рядом
    for kt in (extra / "kotlin").glob("*.kt"):
        shutil.copy(kt, activity[0].parent / kt.name)
else:
    errors.append("не найден MainActivity.kt — некуда положить виджет")
shutil.copytree(ROOT / "tool/icons/android", main_dir / "res", dirs_exist_ok=True)
# Мелодии будильника
(main_dir / "res/raw").mkdir(parents=True, exist_ok=True)
for snd in (ROOT / "tool/sounds/android").glob("*.ogg"):
    shutil.copy(snd, main_dir / "res/raw" / snd.name)

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

# ---------------- iOS: Live Activity ----------------
d = read(delegate)
if "LiveGoalsPlugin" not in d:
    patterns = [
        (r"GeneratedPluginRegistrant\.register\(with: self\)",
         'LiveGoalsPlugin.register(with: self.registrar(forPlugin: "LiveGoalsPlugin")!)'),
        (r"GeneratedPluginRegistrant\.register\(with: engineBridge\.pluginRegistry\)",
         'LiveGoalsPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "LiveGoalsPlugin")!)'),
    ]
    for pat, line in patterns:
        d, n = re.subn(pat, lambda x, line=line: x.group(0) + "\n    " + line, d, count=1)
        if n:
            break
    else:
        errors.append("AppDelegate.swift: не найдено место для LiveGoalsPlugin")
    write(delegate, d)

# ---------------- iOS: имя приложения ----------------
plist = ROOT / "ios/Runner/Info.plist"
p = read(plist)
p = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
           lambda x: x.group(1) + APP_NAME + x.group(2), p, count=1)
if "NSSupportsLiveActivities" not in p:
    idx = p.rfind("</dict>")
    p = p[:idx] + "\t<key>NSSupportsLiveActivities</key>\n\t<true/>\n" + p[idx:]
if "NSAlarmKitUsageDescription" not in p:
    idx = p.rfind("</dict>")
    p = (p[:idx] + "\t<key>NSAlarmKitUsageDescription</key>\n"
         "\t<string>Чтобы будильники звонили по вашему графику, даже в беззвучном режиме.</string>\n" + p[idx:])
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

# Альтернативные иконки iPhone (подключаются к сборке в tool/ios_extra/add_live_activity.rb)
assets = ROOT / "ios/Runner/Assets.xcassets"
for d in (ROOT / "tool/icons/ios_alt").glob("AppIcon-*.appiconset"):
    shutil.copytree(d, assets / d.name, dirs_exist_ok=True)

if errors:
    print("ОШИБКИ ПАТЧА:\n  " + "\n  ".join(errors))
    sys.exit(1)
print("Платформы пропатчены.")
