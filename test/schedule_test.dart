import 'package:flutter_test/flutter_test.dart';
import 'package:napominator/logic/schedule.dart';
import 'package:napominator/models/day.dart';
import 'package:napominator/models/goal.dart';

// 2026-11-09 — понедельник.
final mon = DateTime.utc(2026, 11, 9);
DateTime d(int offset) => addDays(mon, offset);

Goal make({
  RepeatType repeat = RepeatType.daily,
  Set<int> weekdays = const {},
  DeadlineType deadline = DeadlineType.none,
  DateTime? end,
  int? count,
}) {
  final g = Goal(
    id: 't',
    notifId: 1,
    title: 'Тест',
    repeat: repeat,
    weekdays: {...weekdays},
    startDate: mon,
    deadlineType: deadline,
    endDate: end,
    targetCount: count,
    nextDue: mon,
  );
  initGoal(g, mon);
  return g;
}

void main() {
  test('каждый день: выполнение и перенос', () {
    final g = make();
    expect(g.nextDue, d(0));
    expect(complete(g, d(0)), isTrue);
    expect(g.nextDue, d(1));
    // Вторник пропущен, в среду цель висит на среде, сдвиг +1.
    normalize(g, d(2));
    expect(g.nextDue, d(2));
    expect(g.shift, 1);
    expect(g.missedDays, 1);
  });

  test('через день: пропуск сдвигает график на день', () {
    final g = make(repeat: RepeatType.everyOtherDay);
    complete(g, d(0));
    expect(g.nextDue, d(2));
    normalize(g, d(3)); // среду пропустили
    expect(g.nextDue, d(3));
    complete(g, d(3));
    expect(g.nextDue, d(5));
  });

  test('по дням недели: Пн/Ср/Пт → после пропуска Вт/Чт/Сб', () {
    final g = make(repeat: RepeatType.weekdays, weekdays: {1, 3, 5});
    complete(g, d(0)); // Пн
    expect(g.nextDue, d(2)); // Ср
    normalize(g, d(3)); // Ср пропущена, сегодня Чт
    expect(g.nextDue, d(3));
    complete(g, d(3));
    expect(g.nextDue, d(5)); // Сб
    expect(shiftedWeekdays(g), {2, 4, 6});
  });

  test('несколько пропущенных дней подряд', () {
    final g = make();
    normalize(g, d(4));
    expect(g.nextDue, d(4));
    expect(g.missedDays, 4);
  });

  test('срок по количеству', () {
    final g = make(deadline: DeadlineType.count, count: 3);
    expect(projectedEnd(g), d(2));
    complete(g, d(0));
    complete(g, d(1));
    expect(g.finished, isFalse);
    expect(remainingCount(g), 1);
    complete(g, d(2));
    expect(g.finished, isTrue);
    expect(normalize(g, d(10)), isFalse);
  });

  test('срок по дате продлевается при пропуске', () {
    final g = make(deadline: DeadlineType.date, end: d(2));
    expect(remainingCount(g), 3);
    complete(g, d(0));
    normalize(g, d(2)); // пропустили вторник
    expect(effectiveEndDate(g), d(3));
    complete(g, d(2));
    expect(g.finished, isFalse);
    complete(g, d(3));
    expect(g.finished, isTrue);
  });

  test('отмена отметки', () {
    final g = make(deadline: DeadlineType.count, count: 1);
    complete(g, d(0));
    expect(g.finished, isTrue);
    expect(undoToday(g, d(0)), isTrue);
    expect(g.finished, isFalse);
    expect(g.nextDue, d(0));
  });

  test('нельзя отметить не в свой день', () {
    final g = make(repeat: RepeatType.everyOtherDay);
    complete(g, d(0));
    expect(complete(g, d(1)), isFalse);
  });

  test('смена расписания сбрасывает сдвиг', () {
    final g = make(repeat: RepeatType.weekdays, weekdays: {1});
    normalize(g, d(2));
    expect(g.shift, 2);
    g.weekdays = {5};
    applyEdit(g, d(2), patternChanged: true);
    expect(g.shift, 0);
    expect(g.nextDue, d(4)); // пятница
    expect(g.missedDays, 2);
  });

  test('json туда-обратно', () {
    final g = make(repeat: RepeatType.weekdays, weekdays: {2, 4});
    final g2 = Goal.fromJson(g.toJson());
    expect(g2.toJson(), g.toJson());
  });
}
