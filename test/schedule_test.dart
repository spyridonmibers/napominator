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
  int on = 2,
  int off = 2,
  CarryMode carry = CarryMode.shift,
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
    cycleOn: on,
    cycleOff: off,
    carry: carry,
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

  test('журнал пропусков и серии', () {
    final g = make();
    complete(g, d(0));
    complete(g, d(1));
    normalize(g, d(4)); // пропущены d2, d3
    expect(g.missedLog, [d(2), d(3)]);
    expect(currentStreak(g), 0);
    complete(g, d(4));
    expect(currentStreak(g), 1);
    expect(bestStreak(g), 2);
  });

  test('архив: нет переносов и отметок', () {
    final g = make();
    g.archived = true;
    expect(normalize(g, d(5)), isFalse);
    expect(complete(g, d(0)), isFalse);
    g.archived = false;
    applyEdit(g, d(5), patternChanged: false);
    expect(g.nextDue, d(5));
    expect(g.missedDays, 0);
  });

  test('плановые даты учитывают срок', () {
    final g = make(deadline: DeadlineType.count, count: 3);
    expect(plannedDates(g, d(0), d(10)), [d(0), d(1), d(2)]);
    final w = make(repeat: RepeatType.everyOtherDay);
    expect(plannedDates(w, d(1), d(6)), [d(2), d(4), d(6)]);
  });

  test('свой график 2/2 и сдвиг при пропуске', () {
    final g = make(repeat: RepeatType.cycle, on: 2, off: 2);
    expect(plannedDates(g, d(0), d(7)), [d(0), d(1), d(4), d(5)]);
    complete(g, d(0));
    expect(g.nextDue, d(1));
    normalize(g, d(2)); // d1 пропущен
    expect(g.nextDue, d(2));
    complete(g, d(2));
    expect(g.nextDue, d(5)); // весь график сдвинулся на день
  });

  test('свой график 3/1 и 1/2', () {
    final a = make(repeat: RepeatType.cycle, on: 3, off: 1);
    expect(plannedDates(a, d(0), d(7)), [d(0), d(1), d(2), d(4), d(5), d(6)]);
    final b = make(repeat: RepeatType.cycle, on: 1, off: 2);
    expect(plannedDates(b, d(0), d(7)), [d(0), d(3), d(6)]);
  });

  test('перенос без сдвига графика', () {
    final g = make(repeat: RepeatType.everyOtherDay, carry: CarryMode.keep);
    normalize(g, d(1)); // d0 пропущен — цель висит на d1
    expect(g.nextDue, d(1));
    expect(g.shift, 0);
    complete(g, d(1));
    expect(g.nextDue, d(2)); // дальше по прежнему графику
    expect(g.missedDays, 1);
  });

  test('без переноса: пропуск засчитывается', () {
    final g = make(repeat: RepeatType.everyOtherDay, carry: CarryMode.skip);
    normalize(g, d(1));
    expect(g.nextDue, d(2));
    expect(g.missedLog, [d(0)]);
    normalize(g, d(5)); // пропущены d2 и d4
    expect(g.nextDue, d(6));
    expect(g.missedDays, 3);
    expect(wouldBeDue(g, d(7)), isFalse);
    expect(wouldBeDue(g, d(8)), isTrue);
  });

  test('без переноса: срок по дате не продлевается', () {
    final g = make(
        repeat: RepeatType.everyOtherDay,
        carry: CarryMode.skip,
        deadline: DeadlineType.date,
        end: d(2));
    normalize(g, d(3));
    expect(g.finished, isTrue);
  });

  test('перенос со сдвигом продлевает срок, без сдвига — нет', () {
    final a = make(deadline: DeadlineType.date, end: d(5));
    normalize(a, d(2));
    expect(effectiveEndDate(a), d(7));
    final b = make(deadline: DeadlineType.date, end: d(5), carry: CarryMode.keep);
    normalize(b, d(2));
    expect(effectiveEndDate(b), d(5));
  });

  test('правка цели не теряет перенесённую на сегодня', () {
    final g = make(repeat: RepeatType.everyOtherDay, carry: CarryMode.keep);
    normalize(g, d(1));
    g.title = 'Новое имя';
    applyEdit(g, d(1), patternChanged: false);
    expect(g.nextDue, d(1));
  });

  // ---------- срок в течение дня ----------

  test('выполнить до времени: перенос на завтра сразу после срока', () {
    final g = make(carry: CarryMode.keep)..dueMinutes = 18 * 60;
    expect(normalize(g, DateTime(2026, 11, 9, 17, 59)), isFalse);
    expect(normalize(g, DateTime(2026, 11, 9, 18, 0)), isTrue);
    expect(g.nextDue, d(1));
    expect(g.missedLog, [d(0)]);
    // сегодня её уже не отметить
    expect(complete(g, DateTime(2026, 11, 9, 19, 0)), isFalse);
    expect(complete(g, DateTime(2026, 11, 10, 9, 0)), isTrue);
  });

  test('выполнить до времени: без переноса', () {
    final g = make(repeat: RepeatType.everyOtherDay, carry: CarryMode.skip)..dueMinutes = 12 * 60;
    normalize(g, DateTime(2026, 11, 9, 12, 30));
    expect(g.nextDue, d(2));
    expect(g.missedDays, 1);
  });

  // ---------- «спрашивать» ----------

  test('спросить: цель ждёт решения, потом перенос со сдвигом', () {
    final g = make(repeat: RepeatType.everyOtherDay, carry: CarryMode.ask);
    final all = [g];
    expect(normalizeAll(all, d(1)), isTrue);
    expect(g.awaiting, isTrue);
    expect(isDueToday(g, d(1)), isFalse);
    expect(complete(g, d(1)), isFalse);
    expect(resolveGoal(all, g, d(1), CarryMode.shift), isTrue);
    expect(g.awaiting, isFalse);
    expect(g.nextDue, d(1));
    expect(g.shift, 1);
    complete(g, d(1));
    expect(g.nextDue, d(3));
  });

  test('спросить: отмена', () {
    final g = make(repeat: RepeatType.everyOtherDay, carry: CarryMode.ask);
    final all = [g];
    normalizeAll(all, d(1));
    resolveGoal(all, g, d(1), CarryMode.skip);
    expect(g.nextDue, d(2));
    expect(g.missedLog, [d(0)]);
  });

  // ---------- связанные цели ----------

  Goal child(Goal parent, int offset, {CarryMode carry = CarryMode.keep, String id = 'c'}) {
    final c = Goal(
      id: id,
      notifId: 2,
      title: 'Подготовка',
      repeat: RepeatType.daily,
      weekdays: {},
      startDate: mon,
      deadlineType: DeadlineType.none,
      nextDue: mon,
      carry: carry,
      parentId: parent.id,
      offsetDays: offset,
    )..parent = parent;
    initGoal(c, mon);
    return c;
  }

  test('привязанная цель идёт за днями главной со смещением', () {
    final p = make(repeat: RepeatType.weekdays, weekdays: {3, 5}); // Ср, Пт
    final c = child(p, -1);
    expect(c.nextDue, d(1)); // вторник — за день до среды
    expect(c.linkDay, d(2));
    complete(c, d(1));
    expect(c.nextDue, d(3)); // четверг — за день до пятницы
    final after = child(p, 2, id: 'a');
    expect(after.nextDue, d(4)); // через 2 дня после среды
  });

  test('сдвиг главной сдвигает привязанные', () {
    final p = make(repeat: RepeatType.weekdays, weekdays: {3, 5});
    final c = child(p, -1);
    final all = [p, c];
    complete(c, d(1)); // подготовка к среде сделана, следующая — чт (к пятнице)
    normalizeAll(all, d(3)); // среду главная пропустила → переехала на четверг, график +1
    expect(p.nextDue, d(3));
    expect(p.shift, 1);
    expect(c.nextDue, d(4)); // подготовка к субботе — в пятницу
    expect(c.linkDay, d(5));
  });

  test('разовая отмена главной отменяет привязанные', () {
    final p = make(repeat: RepeatType.weekdays, weekdays: {3, 5}, carry: CarryMode.skip);
    final c = child(p, 0);
    final all = [p, c];
    expect(c.nextDue, d(2));
    normalizeAll(all, d(3)); // среда пропущена и не переносится
    expect(p.nextDue, d(4));
    expect(c.nextDue, d(4));
    expect(c.missedLog, isEmpty); // отменена вместе с главной, а не пропущена
  });

  test('«пропустить этот раз» у главной', () {
    final p = make(repeat: RepeatType.weekdays, weekdays: {3, 5});
    final c = child(p, -1);
    final all = [p, c];
    expect(skipGoalOnce(all, p, d(0)), isTrue);
    expect(p.nextDue, d(4));
    expect(c.nextDue, d(3));
  });

  test('привязанная не выполнена: выбор «перенести с графиком» сдвигает главную', () {
    final p = make(repeat: RepeatType.weekdays, weekdays: {3, 5});
    final c = child(p, -1, carry: CarryMode.ask);
    final all = [p, c];
    normalizeAll(all, d(2)); // вторник прошёл
    expect(c.awaiting, isTrue);
    expect(p.nextDue, d(2));
    resolveGoal(all, c, d(2), CarryMode.shift);
    expect(c.nextDue, d(2)); // делаем сегодня
    expect(p.nextDue, d(3)); // главная переехала на четверг
    expect(p.shift, 1);
  });

  test('привязанная не выполнена: «перенести» без графика и «отменить»', () {
    final p = make(repeat: RepeatType.weekdays, weekdays: {3, 5});
    final c = child(p, -1, carry: CarryMode.ask);
    final all = [p, c];
    normalizeAll(all, d(2));
    resolveGoal(all, c, d(2), CarryMode.keep);
    expect(c.nextDue, d(2));
    expect(p.nextDue, d(2));
    expect(p.shift, 0);

    final c2 = child(p, -1, carry: CarryMode.ask, id: 'c2');
    final all2 = [p, c2];
    normalizeAll(all2, d(2));
    resolveGoal(all2, c2, d(2), CarryMode.skip);
    expect(c2.nextDue, d(3)); // следующая — к пятнице
  });

  test('главная завершена — привязанные завершаются', () {
    final p = make(deadline: DeadlineType.count, count: 1);
    final c = child(p, 0);
    final all = [p, c];
    complete(c, d(0));
    complete(p, d(0));
    normalizeAll(all, d(1));
    expect(p.finished, isTrue);
    expect(c.finished, isTrue);
  });

  test('архив главной уводит привязанные', () {
    final p = make();
    final c = child(p, 0);
    final all = [p, c];
    p.archived = true;
    normalizeAll(all, d(0));
    expect(c.archived, isTrue);
  });
}
