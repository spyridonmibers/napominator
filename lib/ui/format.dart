import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';

const weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

const weekdayFull = [
  'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье',
];

const monthsNom = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];

const _monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return few;
  return many;
}

String daysWord(int n) => '$n ${plural(n, 'день', 'дня', 'дней')}';

String formatDate(DateTime d) {
  final now = todayDay();
  final base = '${d.day} ${_monthsGen[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

String formatRelative(DateTime d) {
  final diff = daysBetween(todayDay(), d);
  if (diff == 0) return 'сегодня';
  if (diff == 1) return 'завтра';
  if (diff == 2) return 'послезавтра';
  return formatDate(d);
}

String formatTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

String weekdaysText(Set<int> days) {
  final list = days.toList()..sort();
  return list.map((w) => weekdayShort[w - 1]).join(', ');
}

String repeatText(Goal g) {
  switch (g.repeat) {
    case RepeatType.daily:
      return 'Каждый день';
    case RepeatType.everyOtherDay:
      return 'Через день';
    case RepeatType.weekdays:
      return weekdaysText(shiftedWeekdays(g));
  }
}

String deadlineText(Goal g) {
  switch (g.deadlineType) {
    case DeadlineType.none:
      return 'Без срока · выполнено ${g.completions.length}';
    case DeadlineType.count:
      final end = projectedEnd(g);
      final tail = g.finished || end == null ? '' : ' · до ≈ ${formatDate(end)}';
      return '${g.completions.length} из ${g.targetCount}$tail';
    case DeadlineType.date:
      final left = remainingCount(g) ?? 0;
      return 'До ${formatDate(effectiveEndDate(g)!)} · '
          'осталось $left ${plural(left, 'раз', 'раза', 'раз')}';
  }
}

/// Прогресс 0..1 для полосы (null — бессрочная цель).
double? progress(Goal g) {
  if (g.finished) return 1;
  final done = g.completions.length;
  final left = remainingCount(g);
  if (left == null) return null;
  final total = done + left;
  return total == 0 ? 0 : done / total;
}

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// «Среда, 11 ноября»
String formatDateLong(DateTime d) =>
    '${capitalize(weekdayFull[d.weekday - 1])}, ${d.day} ${_monthsGen[d.month - 1]}';

/// Строка «Каждый день · 09:00».
String scheduleLine(Goal g) {
  final r = repeatText(g);
  final m = g.reminderMinutes;
  return m == null ? r : '$r · ${formatTime(m)}';
}
