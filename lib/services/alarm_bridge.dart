import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../models/alarm.dart';

/// Связь с нативной частью будильника (Android: AlarmManager + свой экран,
/// iPhone: AlarmKit на iOS 26+).
class AlarmBridge {
  static const _ch = MethodChannel('napominator/alarm');

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  /// Передать все будильники — нативная часть сама перепланирует.
  static Future<void> sync(List<AlarmItem> alarms) async {
    if (!_mobile) return;
    try {
      await _ch.invokeMethod('sync', jsonEncode([for (final a in alarms) a.toJson()]));
    } catch (_) {}
  }

  /// Поддерживаются ли настоящие будильники (на iPhone — только iOS 26+).
  static Future<bool> isSupported() async {
    if (!_mobile) return false;
    try {
      return await _ch.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Чего не хватает для работы: 'fullScreen' (Android 14+), 'authorization' (iPhone).
  static Future<List<String>> missingPermissions() async {
    if (!_mobile) return const [];
    try {
      final res = await _ch.invokeMethod<List<dynamic>>('missingPermissions');
      return [for (final e in res ?? const []) e.toString()];
    } catch (_) {
      return const [];
    }
  }

  /// Запросить разрешение / открыть нужный экран настроек.
  static Future<void> requestPermission(String what) async {
    if (!_mobile) return;
    try {
      await _ch.invokeMethod('requestPermission', what);
    } catch (_) {}
  }

  static Future<void> preview(String sound) async {
    if (!_mobile) return;
    try {
      await _ch.invokeMethod('preview', sound);
    } catch (_) {}
  }

  static Future<void> stopPreview() async {
    if (!_mobile) return;
    try {
      await _ch.invokeMethod('stopPreview');
    } catch (_) {}
  }

  /// Android: выбрать системную мелодию или файл. Возвращает (sound, title).
  static Future<(String, String)?> pick(String kind) async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await _ch.invokeMethod<Map<dynamic, dynamic>>(kind);
      if (res == null) return null;
      return (res['sound'] as String, res['title'] as String);
    } catch (_) {
      return null;
    }
  }
}
