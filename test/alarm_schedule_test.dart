import 'package:flutter_test/flutter_test.dart';
import 'package:napominator/logic/alarm_schedule.dart';
import 'package:napominator/models/alarm.dart';
import 'package:napominator/models/day.dart';
import 'package:napominator/models/goal.dart' show RepeatType;

// 2026-11-09 — понедельник.
final mon = DateTime.utc(2026, 11, 9);

AlarmItem make(RepeatType r, {Set<int>? days, int on = 2, int off = 2}) => AlarmItem(
      id: 'a',
      nativeId: 1,
      minutes: 7 * 60,
      repeat: r,
      weekdays: days,
      cycleOn: on,
      cycleOff: off,
      startDate: mon,
    );

void main() {
  test('будни', () {
    final a = make(RepeatType.weekdays, days: {1, 2, 3, 4, 5});
    expect(alarmDays(a, mon, addDays(mon, 6)).length, 5);
    // пятница 8:00 → следующий понедельник 7:00
    expect(nextAlarmTime(a, DateTime(2026, 11, 13, 8)), DateTime(2026, 11, 16, 7));
  });

  test('сегодня, если время ещё не наступило', () {
    final a = make(RepeatType.daily);
    expect(nextAlarmTime(a, DateTime(2026, 11, 10, 6, 59)), DateTime(2026, 11, 10, 7));
    expect(nextAlarmTime(a, DateTime(2026, 11, 10, 7, 0)), DateTime(2026, 11, 11, 7));
  });

  test('график 2/2', () {
    final a = make(RepeatType.cycle, on: 2, off: 2);
    expect(alarmDays(a, mon, addDays(mon, 7)),
        [mon, addDays(mon, 1), addDays(mon, 4), addDays(mon, 5)]);
  });

  test('выключенный не звонит', () {
    final a = make(RepeatType.daily)..enabled = false;
    expect(nextAlarmTime(a, DateTime(2026, 11, 10)), isNull);
  });

  test('json', () {
    final a = make(RepeatType.cycle, on: 3, off: 1);
    expect(AlarmItem.fromJson(a.toJson()).toJson(), a.toJson());
  });
}
