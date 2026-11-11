import 'day.dart';

/// cycle — свой график «N дней выполнять / M дней отдыха» (2/2, 3/1, 1/2...).
enum RepeatType { daily, everyOtherDay, weekdays, cycle }

enum DeadlineType { none, date, count }

/// Что делать, если день пропущен:
/// shift — перенести цель на завтра и сдвинуть весь график (и срок) на день;
/// keep  — перенести цель на завтра, но дальше идти по прежнему графику;
/// skip  — не переносить: пропуск засчитывается, цель ждёт следующего дня по графику.
enum CarryMode { shift, keep, skip }

class Goal {
  Goal({
    required this.id,
    required this.notifId,
    required this.title,
    required this.repeat,
    required this.weekdays,
    required this.startDate,
    required this.deadlineType,
    this.endDate,
    this.targetCount,
    this.reminderMinutes,
    this.shift = 0,
    this.missedDays = 0,
    required this.nextDue,
    List<DateTime>? completions,
    this.finished = false,
    this.finishedOn,
    this.colorIndex = 0,
    this.icon = 'target',
    this.archived = false,
    this.cycleOn = 2,
    this.cycleOff = 2,
    this.carry = CarryMode.shift,
    this.endShift = 0,
    List<DateTime>? missedLog,
  })  : completions = completions ?? <DateTime>[],
        missedLog = missedLog ?? <DateTime>[];

  final String id;

  /// Числовой номер для идентификаторов уведомлений.
  final int notifId;

  String title;
  RepeatType repeat;

  /// Дни недели 1..7 (Пн..Вс) — для [RepeatType.weekdays].
  Set<int> weekdays;

  DateTime startDate;
  DeadlineType deadlineType;

  /// Исходная дата окончания (без учёта переносов).
  DateTime? endDate;

  /// Сколько раз нужно выполнить цель.
  int? targetCount;

  /// Время напоминания в минутах от полуночи, null — без напоминания.
  int? reminderMinutes;

  /// На сколько дней сдвинут график (сбрасывается при смене расписания).
  int shift;

  /// Сколько всего дней перенесено (продлевает дату окончания).
  int missedDays;

  /// День, на который назначено ближайшее выполнение.
  DateTime nextDue;

  /// Дни, в которые цель отмечена выполненной.
  List<DateTime> completions;

  bool finished;
  DateTime? finishedOn;

  /// Индекс цвета из палитры (см. ui/theme.dart).
  int colorIndex;

  /// Ключ иконки (см. ui/theme.dart).
  String icon;

  /// Отложена пользователем (в архиве, без напоминаний и переносов).
  bool archived;

  /// Дни, когда цель была назначена, но не выполнена.
  List<DateTime> missedLog;

  /// Свой график: сколько дней подряд выполнять и сколько отдыхать.
  int cycleOn;
  int cycleOff;

  /// Поведение при пропуске дня.
  CarryMode carry;

  /// На сколько дней продлена дата окончания (только в режиме [CarryMode.shift]).
  int endShift;

  Map<String, dynamic> toJson() => {
        'id': id,
        'notifId': notifId,
        'title': title,
        'repeat': repeat.name,
        'weekdays': weekdays.toList()..sort(),
        'startDate': dayKey(startDate),
        'deadlineType': deadlineType.name,
        'endDate': endDate == null ? null : dayKey(endDate!),
        'targetCount': targetCount,
        'reminderMinutes': reminderMinutes,
        'shift': shift,
        'missedDays': missedDays,
        'nextDue': dayKey(nextDue),
        'completions': completions.map(dayKey).toList(),
        'finished': finished,
        'finishedOn': finishedOn == null ? null : dayKey(finishedOn!),
        'colorIndex': colorIndex,
        'icon': icon,
        'archived': archived,
        'cycleOn': cycleOn,
        'cycleOff': cycleOff,
        'carry': carry.name,
        'endShift': endShift,
        'missedLog': missedLog.map(dayKey).toList(),
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        notifId: (j['notifId'] as num).toInt(),
        title: j['title'] as String,
        repeat: RepeatType.values.byName(j['repeat'] as String),
        weekdays: ((j['weekdays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toSet(),
        startDate: parseDay(j['startDate'] as String),
        deadlineType: DeadlineType.values.byName(j['deadlineType'] as String),
        endDate: j['endDate'] == null ? null : parseDay(j['endDate'] as String),
        targetCount: (j['targetCount'] as num?)?.toInt(),
        reminderMinutes: (j['reminderMinutes'] as num?)?.toInt(),
        shift: (j['shift'] as num?)?.toInt() ?? 0,
        missedDays: (j['missedDays'] as num?)?.toInt() ?? 0,
        nextDue: parseDay(j['nextDue'] as String),
        completions: ((j['completions'] as List?) ?? const [])
            .map((e) => parseDay(e as String))
            .toList(),
        finished: j['finished'] as bool? ?? false,
        finishedOn:
            j['finishedOn'] == null ? null : parseDay(j['finishedOn'] as String),
        colorIndex: (j['colorIndex'] as num?)?.toInt() ?? 0,
        icon: j['icon'] as String? ?? 'target',
        archived: j['archived'] as bool? ?? false,
        cycleOn: (j['cycleOn'] as num?)?.toInt() ?? 2,
        cycleOff: (j['cycleOff'] as num?)?.toInt() ?? 2,
        carry: CarryMode.values.asNameMap()[j['carry']] ?? CarryMode.shift,
        // Старые цели всегда сдвигали график — продление срока равно числу переносов.
        endShift: (j['endShift'] as num?)?.toInt() ??
            (j['missedDays'] as num?)?.toInt() ??
            0,
        missedLog: ((j['missedLog'] as List?) ?? const [])
            .map((e) => parseDay(e as String))
            .toList(),
      );
}
