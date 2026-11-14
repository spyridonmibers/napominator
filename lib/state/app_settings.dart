import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';

enum TimePickerStyle { wheel, dial }

/// Варианты иконки приложения. Ключи совпадают с tool/make_icons.py,
/// activity-alias на Android и AppIcon-* на iPhone.
class AppIconVariant {
  const AppIconVariant(this.key, this.name, this.a, this.b);
  final String key;
  final String name;
  final Color a;
  final Color b;
}

const appIconVariants = <AppIconVariant>[
  AppIconVariant('indigo', 'Индиго', Color(0xFF4338CA), Color(0xFFA855F7)),
  AppIconVariant('sunset', 'Закат', Color(0xFFF97316), Color(0xFFEF4444)),
  AppIconVariant('mint', 'Мята', Color(0xFF10B981), Color(0xFF06B6D4)),
  AppIconVariant('ocean', 'Океан', Color(0xFF3B82F6), Color(0xFF0EA5E9)),
  AppIconVariant('graphite', 'Графит', Color(0xFF334155), Color(0xFF0F172A)),
];

/// Настройки приложения (хранятся в SharedPreferences).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kTheme = 'settings_theme';
  static const _kAccent = 'settings_accent';
  static const _kIcon = 'settings_icon';
  static const _kTime = 'settings_time';
  static const _kCarry = 'settings_carry';
  static const kLockScreen = 'settings_lock'; // читается и в фоне (widget_sync)
  static const _kAccentCustom = 'settings_accent_custom';
  // Оформление виджета — читается и в фоне (widget_sync)
  static const kWidgetCustom = 'settings_widget_custom';
  static const kWidgetHue = 'settings_widget_hue';
  static const kWidgetTone = 'settings_widget_tone';
  static const kWidgetOpacity = 'settings_widget_opacity';

  static const _channel = MethodChannel('napominator/app');

  ThemeMode themeMode = ThemeMode.system;
  int accent = 0;
  String icon = 'indigo';
  TimePickerStyle timeStyle = TimePickerStyle.wheel;
  CarryMode defaultCarry = CarryMode.shift;
  bool lockScreen = true;

  /// Свой акцентный цвет (ARGB) вместо одного из 10.
  int? accentCustom;

  // ---- По умолчанию для новых целей ----
  bool defaultReminderOn = true;
  int defaultReminderMinutes = 9 * 60;
  bool defaultDueOn = false;
  int defaultDueMinutes = 21 * 60;
  RepeatType defaultRepeat = RepeatType.daily;

  // ---- По умолчанию для новых будильников ----
  String alarmSound = 'builtin:soft';
  String alarmSoundTitle = 'Мягкое утро';
  int alarmSnooze = 10;
  bool alarmRamp = true;
  bool alarmVibrate = true;

  bool widgetCustom = false;
  double widgetHue = 250;
  double widgetTone = 0.15;
  double widgetOpacity = 1.0;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values.asNameMap()[p.getString(_kTheme)] ?? ThemeMode.system;
    accent = p.getInt(_kAccent) ?? 0;
    icon = p.getString(_kIcon) ?? 'indigo';
    timeStyle = TimePickerStyle.values.asNameMap()[p.getString(_kTime)] ?? TimePickerStyle.wheel;
    defaultCarry = CarryMode.values.asNameMap()[p.getString(_kCarry)] ?? CarryMode.shift;
    lockScreen = p.getBool(kLockScreen) ?? true;
    accentCustom = p.getInt(_kAccentCustom);
    defaultReminderOn = p.getBool('def_reminder_on') ?? true;
    defaultReminderMinutes = p.getInt('def_reminder_min') ?? 9 * 60;
    defaultDueOn = p.getBool('def_due_on') ?? false;
    defaultDueMinutes = p.getInt('def_due_min') ?? 21 * 60;
    defaultRepeat = RepeatType.values.asNameMap()[p.getString('def_repeat')] ?? RepeatType.daily;
    alarmSound = p.getString('def_alarm_sound') ?? 'builtin:soft';
    alarmSoundTitle = p.getString('def_alarm_sound_title') ?? 'Мягкое утро';
    alarmSnooze = p.getInt('def_alarm_snooze') ?? 10;
    alarmRamp = p.getBool('def_alarm_ramp') ?? true;
    alarmVibrate = p.getBool('def_alarm_vibrate') ?? true;
    widgetCustom = p.getBool(kWidgetCustom) ?? false;
    widgetHue = p.getDouble(kWidgetHue) ?? 250;
    widgetTone = p.getDouble(kWidgetTone) ?? 0.15;
    widgetOpacity = p.getDouble(kWidgetOpacity) ?? 1.0;
  }

  /// Значения по умолчанию для новых целей.
  Future<void> setGoalDefaults({
    bool? reminderOn,
    int? reminderMinutes,
    bool? dueOn,
    int? dueMinutes,
    RepeatType? repeat,
  }) async {
    if (reminderOn != null) defaultReminderOn = reminderOn;
    if (reminderMinutes != null) defaultReminderMinutes = reminderMinutes;
    if (dueOn != null) defaultDueOn = dueOn;
    if (dueMinutes != null) defaultDueMinutes = dueMinutes;
    if (repeat != null) defaultRepeat = repeat;
    notifyListeners();
    final p = await _prefs;
    await p.setBool('def_reminder_on', defaultReminderOn);
    await p.setInt('def_reminder_min', defaultReminderMinutes);
    await p.setBool('def_due_on', defaultDueOn);
    await p.setInt('def_due_min', defaultDueMinutes);
    await p.setString('def_repeat', defaultRepeat.name);
  }

  /// Значения по умолчанию для новых будильников.
  Future<void> setAlarmDefaults({
    String? sound,
    String? soundTitle,
    int? snooze,
    bool? ramp,
    bool? vibrate,
  }) async {
    if (sound != null) alarmSound = sound;
    if (soundTitle != null) alarmSoundTitle = soundTitle;
    if (snooze != null) alarmSnooze = snooze;
    if (ramp != null) alarmRamp = ramp;
    if (vibrate != null) alarmVibrate = vibrate;
    notifyListeners();
    final p = await _prefs;
    await p.setString('def_alarm_sound', alarmSound);
    await p.setString('def_alarm_sound_title', alarmSoundTitle);
    await p.setInt('def_alarm_snooze', alarmSnooze);
    await p.setBool('def_alarm_ramp', alarmRamp);
    await p.setBool('def_alarm_vibrate', alarmVibrate);
  }

  Future<void> setAccentCustom(int argb) async {
    accentCustom = argb;
    notifyListeners();
    await (await _prefs).setInt(_kAccentCustom, argb);
  }

  /// Оформление виджета (сохраняется, когда пользователь отпускает ползунок).
  Future<void> setWidgetStyle({bool? custom, double? hue, double? tone, double? opacity}) async {
    if (custom != null) widgetCustom = custom;
    if (hue != null) widgetHue = hue;
    if (tone != null) widgetTone = tone;
    if (opacity != null) widgetOpacity = opacity;
    notifyListeners();
    final p = await _prefs;
    await p.setBool(kWidgetCustom, widgetCustom);
    await p.setDouble(kWidgetHue, widgetHue);
    await p.setDouble(kWidgetTone, widgetTone);
    await p.setDouble(kWidgetOpacity, widgetOpacity);
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> setThemeMode(ThemeMode v) async {
    themeMode = v;
    notifyListeners();
    await (await _prefs).setString(_kTheme, v.name);
  }

  Future<void> setAccent(int v) async {
    accent = v;
    accentCustom = null;
    notifyListeners();
    final p = await _prefs;
    await p.setInt(_kAccent, v);
    await p.remove(_kAccentCustom);
  }

  Future<void> setTimeStyle(TimePickerStyle v) async {
    timeStyle = v;
    notifyListeners();
    await (await _prefs).setString(_kTime, v.name);
  }

  Future<void> setDefaultCarry(CarryMode v) async {
    defaultCarry = v;
    notifyListeners();
    await (await _prefs).setString(_kCarry, v.name);
  }

  Future<void> setLockScreen(bool v) async {
    lockScreen = v;
    notifyListeners();
    await (await _prefs).setBool(kLockScreen, v);
  }

  /// Сменить иконку на рабочем столе. Возвращает false, если система не позволила.
  Future<bool> setIcon(String key) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setIcon', key) ?? false;
      if (ok) {
        icon = key;
        notifyListeners();
        await (await _prefs).setString(_kIcon, key);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}
