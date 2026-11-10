import 'package:flutter/foundation.dart';

import '../data/goal_repository.dart';
import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../services/notifications.dart';

class GoalStore extends ChangeNotifier {
  static const maxGoals = 50;

  final _repo = GoalRepository();
  List<Goal> goals = <Goal>[];
  bool loaded = false;

  bool get canAdd => goals.length < maxGoals;

  int nextNotifId() {
    var m = 0;
    for (final g in goals) {
      if (g.notifId > m) m = g.notifId;
    }
    return m + 1;
  }

  /// Перечитать данные, перенести просроченные цели, обновить уведомления.
  Future<void> refresh() async {
    goals = await _repo.load();
    final t = todayDay();
    var changed = false;
    for (final g in goals) {
      if (normalize(g, t)) changed = true;
    }
    if (changed) await _repo.save(goals);
    loaded = true;
    notifyListeners();
    await Notifications.instance.reschedule(goals);
  }

  Future<void> _persist() async {
    await _repo.save(goals);
    notifyListeners();
    await Notifications.instance.reschedule(goals);
  }

  Goal? byId(String id) {
    for (final g in goals) {
      if (g.id == id) return g;
    }
    return null;
  }

  Future<void> add(Goal g) async {
    if (!canAdd) return;
    initGoal(g, todayDay());
    goals.add(g);
    await _persist();
  }

  Future<void> update(Goal g, {required bool patternChanged}) async {
    applyEdit(g, todayDay(), patternChanged: patternChanged);
    await Notifications.instance.cancelGoal(g);
    await _persist();
  }

  Future<void> delete(Goal g) async {
    goals.removeWhere((x) => x.id == g.id);
    await Notifications.instance.cancelGoal(g);
    await _persist();
  }

  Future<bool> completeById(String id) async {
    // Перечитываем, чтобы не затереть отметку из фонового обработчика.
    goals = await _repo.load();
    final g = byId(id);
    if (g == null) return false;
    final ok = complete(g, todayDay());
    if (ok) await Notifications.instance.cancelGoal(g);
    await _persist();
    return ok;
  }

  Future<void> undo(Goal g) async {
    if (undoToday(g, todayDay())) await _persist();
  }
}
