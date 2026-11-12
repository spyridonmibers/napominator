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
    widgetCustom = p.getBool(kWidgetCustom) ?? false;
    widgetHue = p.getDouble(kWidgetHue) ?? 250;
    widgetTone = p.getDouble(kWidgetTone) ?? 0.15;
    widgetOpacity = p.getDouble(kWidgetOpacity) ?? 1.0;
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
