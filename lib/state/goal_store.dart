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
    linkGoals(goals);
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
    if (normalizeAll(goals, DateTime.now())) changed = true;
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

  /// Цели, привязанные к [parent].
  List<Goal> children(Goal parent) => childrenOf(parent, goals);

  /// Цели, которые можно выбрать главной для [self] (null — для новой цели):
  /// активные, сами ни к кому не привязанные. Цель, у которой есть привязанные,
  /// сама привязанной стать не может.
  List<Goal> parentCandidates(Goal? self) {
    if (self != null && children(self).isNotEmpty) return const [];
    return [
      for (final g in goals)
        if (isActive(g) && g.parentId == null && g.id != self?.id) g,
    ];
  }

  /// Цели, срок которых прошёл и которые ждут решения пользователя.
  List<Goal> get awaiting => [for (final g in goals) if (isActive(g) && g.awaiting) g];

  Future<void> add(Goal g) async {
    if (!canAdd) return;
    goals.add(g);
    linkGoals(goals);
    initGoal(g, todayDay());
    normalizeAll(goals, DateTime.now());
    await _persist();
  }

  /// Актуальный объект цели (после перечитывания данных объекты пересоздаются).
  Goal _live(Goal g) => byId(g.id) ?? g;

  Future<void> update(Goal g, {required bool patternChanged}) async {
    // Экран правки мог держать объект, созданный до перечитывания данных.
    final idx = goals.indexWhere((x) => x.id == g.id);
    if (idx >= 0) goals[idx] = g;
    linkGoals(goals);
    final today = todayDay();
    applyEdit(g, today, patternChanged: patternChanged);
    if (patternChanged) relinkChildren(g, goals, today);
    normalizeAll(goals, DateTime.now());
    await Notifications.instance.cancelGoal(g);
    await _persist();
  }

  /// Удаляет цель. Вместе с главной удаляются и привязанные к ней.
  Future<void> delete(Goal g) async {
    g = _live(g);
    final gone = [g, ...children(g)];
    goals.removeWhere((x) => gone.any((y) => y.id == x.id));
    for (final x in gone) {
      await Notifications.instance.cancelGoal(x);
    }
    await _persist();
  }

  /// Архив. Привязанные цели уходят в архив и возвращаются вместе с главной.
  Future<void> setArchived(Goal g, bool value) async {
    g = _live(g);
    final kids = children(g);
    if (!value && !g.finished && activeCount + 1 + kids.length > maxGoals) return;
    g.archived = value;
    if (!value) {
      applyEdit(g, todayDay(), patternChanged: false);
    }
    normalizeAll(goals, DateTime.now()); // привязанные повторят состояние главной
    for (final x in [g, ...kids]) {
      await Notifications.instance.cancelGoal(x);
    }
    await _persist();
  }

  /// Ответ на «цель не выполнена»: skip — отменить, keep — перенести,
  /// shift — перенести вместе с графиком.
  Future<void> resolve(String id, CarryMode choice) => _serial(() async {
        goals = await _repo.load();
        final now = DateTime.now();
        normalizeAll(goals, now);
        final g = byId(id);
        if (g != null && resolveGoal(goals, g, now, choice)) {
          normalizeAll(goals, now);
          await Notifications.instance.cancelGoal(g);
        }
        await _persist();
      });

  /// Отменить ближайшее выполнение («пропустить этот раз»).
  Future<void> skipOnce(Goal g) async {
    g = _live(g);
    final now = DateTime.now();
    if (skipGoalOnce(goals, g, now)) {
      normalizeAll(goals, now);
      await Notifications.instance.cancelGoal(g);
      await _persist();
    }
  }

  /// Раз в минуту: не истёк ли у какой-нибудь цели срок «выполнить до».
  void tick() {
    final now = DateTime.now();
    for (final g in goals) {
      if (isActive(g) && !g.awaiting && deadlinePassed(g, g.nextDue, now)) {
        refresh();
        return;
      }
    }
  }

  Future<bool> completeById(String id) => _serial(() => _completeById(id));

  Future<bool> _completeById(String id) async {
    // Перечитываем, чтобы не затереть отметку из фонового обработчика.
    goals = await _repo.load();
    final now = DateTime.now();
    normalizeAll(goals, now);
    final g = byId(id);
    if (g == null) return false;
    final ok = complete(g, now);
    if (ok) normalizeAll(goals, now); // главная завершилась — завершаем привязанные
    if (ok) await Notifications.instance.cancelGoal(g);
    await _persist();
    return ok;
  }

  Future<void> undo(Goal g) async {
    g = _live(g);
    if (undoToday(g, todayDay())) {
      normalizeAll(goals, DateTime.now());
      await _persist();
    }
  }
}
