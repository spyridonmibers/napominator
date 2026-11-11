/// Логика расписания.
///
/// Правило: у цели есть [Goal.nextDue] — день ближайшего выполнения.
/// Если день прошёл, а отметки нет, цель переносится на сегодня,
/// и весь график (а также дата окончания) сдвигается на столько же дней.
library;

import '../models/day.dart';
import '../models/goal.dart';

/// Является ли [day] днём выполнения по (сдвинутому) графику.
bool isPatternDay(Goal g, DateTime day) {
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
DateTime nextOccurrence(Goal g, DateTime from) {
  var d = maxDay(from, addDays(g.startDate, g.shift));
  for (var i = 0; i < 70; i++) {
    if (isPatternDay(g, d)) return d;
    d = addDays(d, 1);
  }
  return maxDay(from, g.startDate); // пустой набор дней недели — не должно быть
}

bool doneOn(Goal g, DateTime day) => g.completions.contains(day);

DateTime? effectiveEndDate(Goal g) =>
    g.endDate == null ? null : addDays(g.endDate!, g.missedDays);

/// Переносит просроченную цель на [today]. Возвращает true, если что-то изменилось.
bool normalize(Goal g, DateTime today) {
  if (g.finished || g.archived) return false;
  if (g.nextDue.isBefore(today)) {
    final diff = daysBetween(g.nextDue, today);
    for (var i = 0; i < diff; i++) {
      g.missedLog.add(addDays(g.nextDue, i));
    }
    g.shift += diff;
    g.missedDays += diff;
    g.nextDue = today;
    return true;
  }
  return false;
}

bool isDueToday(Goal g, DateTime today) =>
    !g.finished && !g.archived && g.nextDue == today;

bool isActive(Goal g) => !g.finished && !g.archived;

void _updateFinished(Goal g, DateTime today) {
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

/// Отметить выполнение за сегодня.
bool complete(Goal g, DateTime today) {
  normalize(g, today);
  if (g.finished || g.archived || g.nextDue != today || doneOn(g, today)) {
    return false;
  }
  g.completions.add(today);
  g.completions.sort();
  g.nextDue = nextOccurrence(g, addDays(today, 1));
  _updateFinished(g, today);
  return true;
}

/// Отменить сегодняшнюю отметку.
bool undoToday(Goal g, DateTime today) {
  if (!doneOn(g, today)) return false;
  g.completions.remove(today);
  g.nextDue = today;
  g.finished = false;
  g.finishedOn = null;
  return true;
}

/// Первичная настройка новой цели.
void initGoal(Goal g, DateTime today) {
  g.shift = 0;
  g.missedDays = 0;
  g.completions.clear();
  g.missedLog.clear();
  g.nextDue = nextOccurrence(g, maxDay(g.startDate, today));
  _updateFinished(g, today);
}

/// Пересчёт после редактирования. [patternChanged] — сменились периодичность,
/// дни недели или дата старта: тогда сдвиг графика сбрасывается
/// (но накопленные переносы по-прежнему продлевают дату окончания).
void applyEdit(Goal g, DateTime today, {required bool patternChanged}) {
  if (patternChanged) g.shift = 0;
  final from = doneOn(g, today) ? addDays(today, 1) : today;
  g.nextDue = nextOccurrence(g, from);
  _updateFinished(g, today);
}

/// Сколько выполнений ещё осталось (null — бессрочно).
int? remainingCount(Goal g) {
  if (g.finished) return 0;
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
