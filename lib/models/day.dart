/// Работа с «днями» без времени. Все дни храним как DateTime.utc(y, m, d),
/// чтобы арифметика не ломалась на переходах летнего времени.
library;

DateTime dayOf(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime todayDay() => dayOf(DateTime.now());

DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

/// Сколько дней от [a] до [b] (b - a).
int daysBetween(DateTime a, DateTime b) => b.difference(a).inDays;

DateTime maxDay(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}
