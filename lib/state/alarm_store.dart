import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';
import '../services/alarm_bridge.dart';

class AlarmStore extends ChangeNotifier {
  static const _key = 'alarms_v1';
  static const maxAlarms = 50;

  List<AlarmItem> alarms = <AlarmItem>[];
  bool loaded = false;

  bool get canAdd => alarms.length < maxAlarms;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        alarms = [
          for (final e in jsonDecode(raw) as List<dynamic>)
            AlarmItem.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
      } catch (_) {
        alarms = [];
      }
    }
    alarms.sort((a, b) => a.minutes.compareTo(b.minutes));
    loaded = true;
    notifyListeners();
    await AlarmBridge.sync(alarms);
  }

  Future<void> _save() async {
    alarms.sort((a, b) => a.minutes.compareTo(b.minutes));
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode([for (final a in alarms) a.toJson()]));
    notifyListeners();
    await AlarmBridge.sync(alarms);
  }

  int nextNativeId() {
    var m = 0;
    for (final a in alarms) {
      if (a.nativeId > m) m = a.nativeId;
    }
    return m + 1;
  }

  AlarmItem? byId(String id) {
    for (final a in alarms) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> add(AlarmItem a) async {
    if (!canAdd) return;
    alarms.add(a);
    await _save();
  }

  Future<void> update(AlarmItem a) => _save();

  Future<void> delete(AlarmItem a) async {
    alarms.removeWhere((x) => x.id == a.id);
    await _save();
  }

  Future<void> setEnabled(AlarmItem a, bool v) async {
    a.enabled = v;
    await _save();
  }
}
