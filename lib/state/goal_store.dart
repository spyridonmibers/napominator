import 'package:flutter/foundation.dart';

import '../data/goal_repository.dart';
import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../services/notifications.dart';
import '../services/widget_sync.dart';

class GoalStore extends ChangeNotifier {
  /// Максимум активных целей.
  static const maxGoals = 50;

  final _repo = GoalRepository();
  List<Goal> goals = <Goal>[];
  bool loaded = false;

  List<Goal> get active => goals.where(isActive).toList();
  List<Goal> get archive => goals.where((g) => !isActive(g)).toList();
  int get activeCount => goals.where(isActive).length;
  bool get canAdd => activeCount < maxGoals;

  /// Последовательное выполнение операций, которые перечитывают и сохраняют данные,
  /// чтобы два параллельных обновления не затёрли друг друга.
  Future<void> _queue = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  int nextNotifId() {
    var m = 0;
    for (final g in goals) {
      if (g.notifId > m) m = g.notifId;
    }
    return m + 1;
  }

  /// Перечитать данные, перенести просроченные цели, обновить уведомления.
  Future<void> refresh() => _serial(_refresh);

  Future<void> _refresh() async {
    goals = await _repo.load();
    final t = todayDay();
    var changed = false;
    // Отметки из Dynamic Island / экрана блокировки iPhone.
    for (final (id, day) in await _repo.takePendingToggles()) {
      final g = byId(id);
      if (g == null) continue;
      if (doneOn(g, day) ? undoToday(g, day) : complete(g, day)) {
        changed = true;
        await Notifications.instance.cancelGoal(g);
      }
    }
    for (final g in goals) {
      if (normalize(g, t)) changed = true;
    }
    if (changed) await _repo.save(goals);
    loaded = true;
    notifyListeners();
    await WidgetSync.update(goals);
    await Notifications.instance.reschedule(goals);
  }

  Future<void> _persist() async {
    await _repo.save(goals);
    notifyListeners();
    await WidgetSync.update(goals);
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

  Future<void> setArchived(Goal g, bool value) async {
    if (!value && !g.finished && !canAdd) return;
    g.archived = value;
    if (!value) {
      applyEdit(g, todayDay(), patternChanged: false);
    }
    await Notifications.instance.cancelGoal(g);
    await _persist();
  }

  Future<bool> completeById(String id) => _serial(() => _completeById(id));

  Future<bool> _completeById(String id) async {
    // Перечитываем, чтобы не затереть отметку из фонового обработчика.
    goals = await _repo.load();
    final t = todayDay();
    for (final g in goals) {
      normalize(g, t);
    }
    final g = byId(id);
    if (g == null) return false;
    final ok = complete(g, t);
    if (ok) await Notifications.instance.cancelGoal(g);
    await _persist();
    return ok;
  }

  Future<void> undo(Goal g) async {
    if (undoToday(g, todayDay())) await _persist();
  }
}
