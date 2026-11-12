/// Расписание будильников: те же графики, что у целей, но без переносов.
library;

import '../models/alarm.dart';
import '../models/day.dart';
import '../models/goal.dart' show RepeatType;

/// Звонит ли будильник в [day].
bool alarmRingsOn(AlarmItem a, DateTime day) {
  if (day.isBefore(a.startDate)) return false;
  switch (a.repeat) {
    case RepeatType.daily:
      return true;
    case RepeatType.everyOtherDay:
      return daysBetween(a.startDate, day) % 2 == 0;
    case RepeatType.weekdays:
      return a.weekdays.contains(day.weekday);
    case RepeatType.cycle:
      final on = a.cycleOn < 1 ? 1 : a.cycleOn;
      final off = a.cycleOff < 0 ? 0 : a.cycleOff;
      return daysBetween(a.startDate, day) % (on + off) < on;
  }
}

/// Ближайшее срабатывание после [now] (null — выключен или нет дней).
DateTime? nextAlarmTime(AlarmItem a, DateTime now) {
  if (!a.enabled) return null;
  var d = dayOf(now);
  for (var i = 0; i < 400; i++) {
    if (alarmRingsOn(a, d)) {
      final at = DateTime(d.year, d.month, d.day, a.minutes ~/ 60, a.minutes % 60);
      if (at.isAfter(now)) return at;
    }
    d = addDays(d, 1);
  }
  return null;
}

/// Дни срабатывания в диапазоне.
List<DateTime> alarmDays(AlarmItem a, DateTime from, DateTime to) {
  if (!a.enabled) return const [];
  final res = <DateTime>[];
  var d = from;
  while (!d.isAfter(to)) {
    if (alarmRingsOn(a, d)) res.add(d);
    d = addDays(d, 1);
  }
  return res;
}
