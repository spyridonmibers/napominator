import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/day.dart';
import '../models/goal.dart';

/// Хранение целей на устройстве (JSON в SharedPreferences).
class GoalRepository {
  static const _key = 'goals_v1';

  Future<List<Goal>> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Данные могли поменяться из фонового обработчика уведомлений.
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Goal>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Goal.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> save(List<Goal> goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(goals.map((g) => g.toJson()).toList()));
  }

  /// Отметки, сделанные кнопками Live Activity на iPhone (пишет Swift).
  /// Возвращает их и очищает очередь.
  Future<List<(String, DateTime)>> takePendingToggles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('pending_toggles');
    if (raw == null || raw.isEmpty) return const [];
    await prefs.remove('pending_toggles');
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map && e['id'] is String && e['date'] is String)
            (e['id'] as String, parseDay(e['date'] as String)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> getFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? false;
  }

  Future<void> setFlag(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}
