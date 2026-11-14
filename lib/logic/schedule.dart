/// Логика расписания.
///
/// У цели есть [Goal.nextDue] — день ближайшего выполнения. Срок дня истекает
/// в полночь либо в [Goal.dueMinutes], если задано «выполнить до». Если срок истёк,
/// а отметки нет, дальше всё зависит от [Goal.carry]:
/// - shift: цель переносится на следующий день, весь график и срок сдвигаются;
/// - keep: цель переносится, график остаётся прежним;
/// - skip: пропуск засчитывается, цель ждёт следующего дня по графику;
/// - ask: цель ждёт решения пользователя ([resolveGoal]).
///
/// Привязанная цель ([Goal.parent]) своего графика не имеет: её дни — это дни
/// главной цели со смещением [Goal.offsetDays].
library;

import '../models/day.dart';
import '../models/goal.dart';

final DateTime _never = DateTime.utc(9999);

int _minutesOf(DateTime now) => now.hour * 60 + now.minute;

/// Истёк ли к моменту [now] срок выполнения за день [day].
/// [now] может быть и «днём» (полночь) — тогда учитываются только даты.
bool deadlinePassed(Goal g, DateTime day, DateTime now) {
  final today = dayOf(now);
  if (day.isBefore(today)) return true;
  if (day.isAfter(today)) return false;
  final m = g.dueMinutes;
  return m != null && _minutesOf(now) >= m;
}

/// Первый день, срок которого ещё не истёк.
DateTime openDay(Goal g, DateTime now) {
  final today = dayOf(now);
  return deadlinePassed(g, today, now) ? addDays(today, 1) : today;
}

/// Проставляет ссылки [Goal.parent] по [Goal.parentId]. Вложенность — один уровень.
void linkGoals(List<Goal> goals) {
  final byId = {for (final g in goals) g.id: g};
  for (final g in goals) {
    final p = g.parentId == null ? null : byId[g.parentId];
    if (p == null || identical(p, g) || p.parentId != null) {
      g.parent = null;
      g.parentId = null; // главная удалена или связь некорректна — цель становится обычной
    } else {
      g.parent = p;
    }
  }
}

List<Goal> childrenOf(Goal parent, List<Goal> goals) =>
    [for (final g in goals) if (g.parentId == parent.id) g];

/// Есть ли у главной цели выполнение в день [day] (с учётом её срока).
bool _parentOccurs(Goal p, DateTime day) {
  if (!isPatternDay(p, day)) return false;
  if (p.finished) return p.finishedOn != null && !day.isAfter(p.finishedOn!);
  if (p.deadlineType == DeadlineType.date) return !day.isAfter(effectiveEndDate(p)!);
  return true;
}

/// Является ли [day] днём выполнения по (сдвинутому) графику.
bool isPatternDay(Goal g, DateTime day) {
  final p = g.parent;
  if (p != null) return _parentOccurs(p, addDays(day, -g.offsetDays));
  final base = addDays(day, -g.shift);
  if (base.isBefore(g.startDate)) return false;
  switch (g.repeat) {
    case RepeatType.daily:
      return true;
    case RepeatType.everyOtherDay:
      return daysBetween(g.startDate, base) % 2 == 0;
    case RepeatType.weekdays:
      return g.weekdays.contains(base.weekday);
    case RepeatType.cycle:
      final on = g.cycleOn < 1 ? 1 : g.cycleOn;
      final off = g.cycleOff < 0 ? 0 : g.cycleOff;
      return daysBetween(g.startDate, base) % (on + off) < on;
  }
}

/// Первый день графика, начиная с [from] (включительно).
/// Для привязанной цели, у которой дней больше нет, возвращает 9999 год.
DateTime nextOccurrence(Goal g, DateTime from) {
  if (g.parent != null) {
    var d = from;
    for (var i = 0; i < 400; i++) {
      if (isPatternDay(g, d)) return d;
      d = addDays(d, 1);
    }
    return _never;
  }
  var d = maxDay(from, addDays(g.startDate, g.shift));
  for (var i = 0; i < 70; i++) {
    if (isPatternDay(g, d)) return d;
    d = addDays(d, 1);
  }
  return maxDay(from, g.startDate); // пустой набор дней недели — не должно быть
}

bool doneOn(Goal g, DateTime day) => g.completions.contains(day);

DateTime? effectiveEndDate(Goal g) =>
    g.endDate == null ? null : addDays(g.endDate!, g.endShift);

bool isDueToday(Goal g, DateTime today) =>
    !g.finished && !g.archived && !g.awaiting && g.nextDue == today;

bool isActive(Goal g) => !g.finished && !g.archived;

void _updateFinished(Goal g, DateTime today) {
  if (g.parent != null) return; // у привязанной цели срок определяет главная
  bool fin;
  switch (g.deadlineType) {
    case DeadlineType.none:
      fin = false;
    case DeadlineType.count:
      fin = g.completions.length >= (g.targetCount ?? 1);
    case DeadlineType.date:
      fin = g.nextDue.isAfter(effectiveEndDate(g)!);
  }
  g.finished = fin;
  g.finishedOn = fin ? (g.completions.isEmpty ? today : g.completions.last) : null;
}

/// Назначить следующее выполнение, начиная с [from].
void _advance(Goal g, DateTime from, DateTime today) {
  final d = nextOccurrence(g, from);
  if (g.parent != null) {
    if (d.year >= 9999) {
      g.finished = true;
      g.finishedOn = g.completions.isEmpty ? today : g.completions.last;
      return;
    }
    g.linkDay = addDays(d, -g.offsetDays);
  }
  g.nextDue = d;
  _updateFinished(g, today);
}

/// Обрабатывает истёкший срок одной цели. Возвращает true, если что-то изменилось.
///
/// [force] — применить этот вариант вместо [Goal.carry] (ответ пользователя).
/// В [cancelled] добавляются дни, которые были отменены (для связанных целей).
/// Для списка целей со связями используйте [normalizeAll].
bool normalize(Goal g, DateTime now, {CarryMode? force, List<DateTime>? cancelled}) {
  if (g.finished || g.archived) return false;
  if (!deadlinePassed(g, g.nextDue, now)) {
    if (g.awaiting) {
      g.awaiting = false; // срок изменили — решать больше нечего
      return true;
    }
    return false;
  }
  final today = dayOf(now);
  final mode = force ?? g.carry;
  switch (mode) {
    case CarryMode.ask:
      if (g.awaiting) return false;
      g.awaiting = true;
      return true;
    case CarryMode.shift:
    case CarryMode.keep:
      final open = openDay(g, now);
      final diff = daysBetween(g.nextDue, open);
      for (var i = 0; i < diff; i++) {
        g.missedLog.add(addDays(g.nextDue, i));
      }
      g.missedDays += diff;
      if (mode == CarryMode.shift) {
        if (g.parent == null) {
          g.shift += diff;
          g.endShift += diff;
        } else {
          g.pendingParentShift += diff; // сдвинуть главную и её график
        }
      }
      g.nextDue = open;
    case CarryMode.skip:
      var d = g.nextDue;
      var guard = 0;
      while (d.year < 9999 && deadlinePassed(g, d, now) && guard < 5000) {
        g.missedLog.add(d);
        g.missedDays++;
        cancelled?.add(d);
        d = nextOccurrence(g, addDays(d, 1));
        guard++;
      }
      _advance(g, d, today);
  }
  g.awaiting = false;
  return true;
}

/// Сдвинуть привязанные цели вслед за главной на [days] дней.
void _shiftChildren(Goal parent, List<Goal> goals, int days, {Goal? except}) {
  for (final c in childrenOf(parent, goals)) {
    if (identical(c, except) || c.finished) continue;
    final link = c.linkDay ?? addDays(c.nextDue, -c.offsetDays);
    final carried = c.nextDue != addDays(link, c.offsetDays);
    c.linkDay = addDays(link, days);
    if (!carried) c.nextDue = addDays(c.nextDue, days);
  }
}

/// Отменить у привязанных целей выполнения, относящиеся к отменённым дням главной.
void _cancelChildren(Goal parent, List<Goal> goals, List<DateTime> cancelled, DateTime today) {
  if (cancelled.isEmpty) return;
  for (final c in childrenOf(parent, goals)) {
    var guard = 0;
    while (!c.finished && c.linkDay != null && cancelled.contains(c.linkDay) && guard < 400) {
      c.awaiting = false;
      _advance(c, addDays(addDays(c.linkDay!, c.offsetDays), 1), today);
      guard++;
    }
  }
}

/// Выполнить действие над целью и разнести последствия по связанным целям:
/// сдвиг графика главной и разовые отмены.
bool _withCascade(Goal g, List<Goal> goals, DateTime now, bool Function(List<DateTime> cancelled) action) {
  final today = dayOf(now);
  final cancelled = <DateTime>[];
  final p = g.parent;
  if (p == null) {
    final before = g.shift;
    final changed = action(cancelled);
    if (g.shift != before) _shiftChildren(g, goals, g.shift - before);
    _cancelChildren(g, goals, cancelled, today);
    return changed;
  }
  g.pendingParentShift = 0;
  final changed = action(cancelled);
  final d = g.pendingParentShift;
  g.pendingParentShift = 0;
  if (d > 0) {
    p.shift += d;
    p.endShift += d;
    if (!p.finished) p.nextDue = addDays(p.nextDue, d);
    if (p.awaiting && !deadlinePassed(p, p.nextDue, now)) p.awaiting = false;
    g.linkDay = addDays(g.linkDay ?? addDays(g.nextDue, -g.offsetDays), d);
    _shiftChildren(p, goals, d, except: g);
  }
  return changed;
}

/// Привести состояние привязанной цели в соответствие с главной (архив, завершение).
bool _syncChild(Goal c, DateTime today) {
  final p = c.parent!;
  var changed = false;
  if (c.archived != p.archived) {
    c.archived = p.archived;
    changed = true;
    if (!c.archived && !c.finished) {
      c.awaiting = false;
      _advance(c, doneOn(c, today) ? addDays(today, 1) : today, today);
    }
  }
  if (c.linkDay == null && !c.finished) {
    c.linkDay = addDays(c.nextDue, -c.offsetDays);
    changed = true;
  }
  final over = p.finished && (p.finishedOn == null || c.linkDay == null || c.linkDay!.isAfter(p.finishedOn!));
  if (over && !c.finished) {
    c.finished = true;
    c.finishedOn = c.completions.isEmpty ? (p.finishedOn ?? today) : c.completions.last;
    c.awaiting = false;
    changed = true;
  } else if (!p.finished && c.finished) {
    // главная снова активна (отменили отметку или изменили срок) — проверяем,
    // появились ли у привязанной цели новые дни
    final was = c.finishedOn;
    c.finished = false;
    _advance(c, doneOn(c, today) ? addDays(today, 1) : today, today);
    if (c.finished) {
      c.finishedOn = was;
    } else {
      c.finishedOn = null;
      changed = true;
    }
  }
  return changed;
}

/// Обработать истёкшие сроки у всех целей с учётом связей.
bool normalizeAll(List<Goal> goals, DateTime now) {
  linkGoals(goals);
  final today = dayOf(now);
  var changed = false;
  for (final g in goals) {
    if (g.parent != null) continue;
    if (_withCascade(g, goals, now, (c) => normalize(g, now, cancelled: c))) changed = true;
  }
  for (final g in goals) {
    if (g.parent == null) continue;
    if (_syncChild(g, today)) changed = true;
    if (_withCascade(g, goals, now, (c) => normalize(g, now, cancelled: c))) changed = true;
  }
  return changed;
}

/// Ответ пользователя на «цель не выполнена»: [choice] — skip (отменить),
/// keep (перенести) или shift (перенести вместе с графиком).
bool resolveGoal(List<Goal> goals, Goal g, DateTime now, CarryMode choice) {
  if (!g.awaiting || choice == CarryMode.ask) return false;
  g.awaiting = false;
  if (!deadlinePassed(g, g.nextDue, now)) return true;
  _withCascade(g, goals, now, (c) => normalize(g, now, force: choice, cancelled: c));
  return true;
}

/// Отменить ближайшее выполнение цели («пропустить этот раз»).
/// У главной цели вместе с ним отменяются связанные.
bool skipGoalOnce(List<Goal> goals, Goal g, DateTime now) {
  if (!isActive(g)) return false;
  if (g.awaiting) return resolveGoal(goals, g, now, CarryMode.skip);
  final today = dayOf(now);
  if (doneOn(g, g.nextDue)) return false;
  return _withCascade(g, goals, now, (cancelled) {
    final day = g.nextDue;
    g.missedLog.add(day);
    g.missedDays++;
    cancelled.add(day);
    _advance(g, addDays(day, 1), today);
    return true;
  });
}

/// Будет ли цель назначена на [day], если до него её не отмечать.
bool wouldBeDue(Goal g, DateTime day) {
  if (!isActive(g) || g.awaiting || day.isBefore(g.nextDue)) return false;
  if (day == g.nextDue) return true;
  return (g.carry == CarryMode.skip || g.carry == CarryMode.ask) ? isPatternDay(g, day) : true;
}

/// Отметить выполнение за сегодня. [now] — момент или день.
bool complete(Goal g, DateTime now) {
  final today = dayOf(now);
  normalize(g, now);
  if (g.finished || g.archived || g.awaiting || g.nextDue != today || doneOn(g, today)) {
    return false;
  }
  g.completions.add(today);
  g.completions.sort();
  _advance(g, addDays(today, 1), today);
  return true;
}

/// Отменить сегодняшнюю отметку.
bool undoToday(Goal g, DateTime today) {
  if (!doneOn(g, today)) return false;
  g.completions.remove(today);
  g.nextDue = today;
  if (g.parent != null) g.linkDay = addDays(today, -g.offsetDays);
  g.finished = false;
  g.finishedOn = null;
  return true;
}

/// Первичная настройка новой цели.
void initGoal(Goal g, DateTime today) {
  g.shift = 0;
  g.missedDays = 0;
  g.endShift = 0;
  g.awaiting = false;
  g.completions.clear();
  g.missedLog.clear();
  if (g.parent != null) {
    g.nextDue = today;
    _advance(g, today, today);
  } else {
    g.nextDue = nextOccurrence(g, maxDay(g.startDate, today));
    _updateFinished(g, today);
  }
}

/// Пересчёт после редактирования. [patternChanged] — сменились периодичность,
/// дни недели, дата старта или привязка: тогда сдвиг графика сбрасывается
/// (но накопленные переносы по-прежнему продлевают дату окончания).
void applyEdit(Goal g, DateTime today, {required bool patternChanged}) {
  if (patternChanged) {
    g.shift = 0;
    g.awaiting = false;
  }
  final carriedToday =
      !patternChanged && g.nextDue == today && !doneOn(g, today) && !g.archived;
  if (g.parent != null) {
    if (!carriedToday && !g.awaiting) {
      g.finished = false;
      g.finishedOn = null;
      _advance(g, doneOn(g, today) ? addDays(today, 1) : today, today);
    }
    return;
  }
  if (!carriedToday && !g.awaiting) {
    final from = doneOn(g, today) ? addDays(today, 1) : today;
    g.nextDue = nextOccurrence(g, from);
  }
  _updateFinished(g, today);
}

/// После правки главной цели пересчитать привязанные.
void relinkChildren(Goal parent, List<Goal> goals, DateTime today) {
  for (final c in childrenOf(parent, goals)) {
    c.parent = parent;
    applyEdit(c, today, patternChanged: true);
  }
}

/// Сколько выполнений ещё осталось (null — бессрочно).
int? remainingCount(Goal g) {
  if (g.finished) return 0;
  if (g.parent != null) return null; // срок задаёт главная цель
  switch (g.deadlineType) {
    case DeadlineType.none:
      return null;
    case DeadlineType.count:
      final left = (g.targetCount ?? 1) - g.completions.length;
      return left < 0 ? 0 : left;
    case DeadlineType.date:
      final end = effectiveEndDate(g)!;
      var n = 0;
      var d = g.nextDue;
      var guard = 0;
      while (!d.isAfter(end) && guard < 20000) {
        n++;
        d = nextOccurrence(g, addDays(d, 1));
        guard++;
      }
      return n;
  }
}

/// Ожидаемая дата последнего выполнения (если не будет пропусков).
DateTime? projectedEnd(Goal g) {
  if (g.finished) return g.finishedOn;
  if (g.parent != null) return null;
  switch (g.deadlineType) {
    case DeadlineType.none:
      return null;
    case DeadlineType.date:
      return effectiveEndDate(g);
    case DeadlineType.count:
      var left = (g.targetCount ?? 1) - g.completions.length;
      var d = g.nextDue;
      while (left > 1) {
        d = nextOccurrence(g, addDays(d, 1));
        left--;
      }
      return d;
  }
}

/// Текущие (с учётом сдвига) дни недели.
Set<int> shiftedWeekdays(Goal g) =>
    g.weekdays.map((w) => ((w - 1 + g.shift) % 7) + 1).toSet();

/// Сколько выполнений подряд с последнего пропуска.
int currentStreak(Goal g) {
  if (g.missedLog.isEmpty) return g.completions.length;
  var lastMiss = g.missedLog.first;
  for (final m in g.missedLog) {
    if (m.isAfter(lastMiss)) lastMiss = m;
  }
  return g.completions.where((c) => c.isAfter(lastMiss)).length;
}

/// Лучшая серия выполнений без пропусков.
int bestStreak(Goal g) {
  final events = <MapEntry<DateTime, bool>>[
    for (final c in g.completions) MapEntry(c, true),
    for (final m in g.missedLog) MapEntry(m, false),
  ]..sort((a, b) => a.key.compareTo(b.key));
  var best = 0, cur = 0;
  for (final e in events) {
    if (e.value) {
      cur++;
      if (cur > best) best = cur;
    } else {
      cur = 0;
    }
  }
  return best;
}

/// Плановые дни выполнения в диапазоне [from]..[to] (если не будет пропусков).
List<DateTime> plannedDates(Goal g, DateTime from, DateTime to) {
  if (!isActive(g)) return const <DateTime>[];
  final res = <DateTime>[];
  var left = remainingCount(g);
  var d = g.nextDue;
  var guard = 0;
  while (!d.isAfter(to) && guard < 2000) {
    if (left != null && left <= 0) break;
    if (!d.isBefore(from)) res.add(d);
    if (left != null) left--;
    d = nextOccurrence(g, addDays(d, 1));
    guard++;
  }
  return res;
}
