import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/goal_repository.dart';
import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import 'widget_sync.dart';

const _channelId = 'goal_reminders';
const _summaryChannelId = 'daily_summary';

/// Постоянная сводка «Сегодня: осталось N из M».
const summaryId = 1;

/// Если целей больше — в сводке только количество.
const _summaryMaxLines = 5;
const _actionDone = 'done';
const _actionMissSkip = 'miss_skip';
const _actionMissKeep = 'miss_keep';
const _actionMissShift = 'miss_shift';
const _iosMissCategory = 'miss';
const _missChannelId = 'goal_missed';
const _iosCategory = 'goal';
const _exactAskedFlag = 'exact_alarm_asked';

/// Сколько дней вперёд планируем напоминания.
const _daysAhead = 7;

/// iOS разрешает не больше 64 запланированных уведомлений.
const _iosLimit = 60;
const _androidLimit = 400;

/// Повторы на iOS (там нельзя сделать «неснимаемое» уведомление):
/// каждые 2 часа после основного времени, но не позже 22:59.
const _iosRepeatHours = 2;
const _iosMaxPerDay = 9;

/// Ответ из уведомления «цель не выполнена» → вариант переноса.
CarryMode? missChoice(String? actionId) => switch (actionId) {
      _actionMissSkip => CarryMode.skip,
      _actionMissKeep => CarryMode.keep,
      _actionMissShift => CarryMode.shift,
      _ => null,
    };

/// Нажатие кнопки в уведомлении, когда приложение закрыто:
/// «Выполнено» либо выбор для невыполненной цели.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  final choice = missChoice(response.actionId);
  if ((response.actionId != _actionDone && choice == null) || response.payload == null) return;
  DartPluginRegistrant.ensureInitialized();
  final repo = GoalRepository();
  final goals = await repo.load();
  final now = DateTime.now();
  normalizeAll(goals, now);
  Goal? goal;
  for (final g in goals) {
    if (g.id == response.payload) goal = g;
  }
  if (goal == null) return;
  if (choice != null) {
    resolveGoal(goals, goal, now, choice);
  } else {
    complete(goal, now);
  }
  normalizeAll(goals, now);
  await repo.save(goals);
  await WidgetSync.update(goals);
  try {
    await Notifications.instance.init();
    await Notifications.instance.cancelGoal(goal);
    await Notifications.instance.reschedule(goals);
  } catch (_) {
    // Пересчитается при следующем открытии приложения.
  }
}

class _Entry {
  _Entry(this.id, this.at, this.goal, {this.until});
  final int id;
  final DateTime at;
  final Goal goal;

  /// Срок «выполнить до»: в этот момент напоминание само исчезает (Android).
  final DateTime? until;
}

class Notifications {
  Notifications._();
  static final Notifications instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Показывать сводку через этот плагин. На Android её заменяет нативная панель,
  /// на iPhone — Live Activity (если она доступна).
  bool useSummary = true;
  void Function(String goalId)? _onDone;
  void Function(String goalId, CarryMode choice)? _onMiss;

  bool get _isIOS => Platform.isIOS;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init({
    void Function(String goalId)? onDone,
    void Function(String goalId, CarryMode choice)? onMiss,
  }) async {
    if (onDone != null) _onDone = onDone;
    if (onMiss != null) _onMiss = onMiss;
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('ic_stat_goal');
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          _iosCategory,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(_actionDone, 'Выполнено'),
          ],
        ),
        DarwinNotificationCategory(
          _iosMissCategory,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(_actionMissKeep, 'Перенести'),
            DarwinNotificationAction.plain(_actionMissShift, 'Перенести вместе с графиком'),
            DarwinNotificationAction.plain(_actionMissSkip, 'Отменить',
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.destructive,
                }),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload == null) return;
        final choice = missChoice(r.actionId);
        if (choice != null) {
          _onMiss?.call(r.payload!, choice);
        } else if (r.actionId == _actionDone) {
          _onDone?.call(r.payload!);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    if (!_initialized) return;
    if (Platform.isAndroid) {
      final a = _android;
      await a?.requestNotificationsPermission();
      final canExact = await a?.canScheduleExactNotifications() ?? true;
      final repo = GoalRepository();
      if (!canExact && !await repo.getFlag(_exactAskedFlag)) {
        await repo.setFlag(_exactAskedFlag);
        await a?.requestExactAlarmsPermission();
      }
    } else if (_isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// [timeoutMs] — через сколько напоминание само исчезнет (срок «выполнить до»).
  NotificationDetails _details([int? timeoutMs]) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Напоминания о целях',
          channelDescription: 'Висят, пока цель на сегодня не отмечена',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          category: AndroidNotificationCategory.reminder,
          timeoutAfter: timeoutMs,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              _actionDone,
              'Выполнено',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _iosCategory,
          threadIdentifier: 'goals',
        ),
      );

  /// Уведомление «цель не выполнена» с выбором: перенести / со сдвигом / отменить.
  NotificationDetails _missDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          _missChannelId,
          'Невыполненные цели',
          channelDescription: 'Выбор, что делать с целью, которую не успели выполнить',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: false,
          category: AndroidNotificationCategory.reminder,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(_actionMissKeep, 'Перенести',
                showsUserInterface: false, cancelNotification: true),
            AndroidNotificationAction(_actionMissShift, 'С графиком',
                showsUserInterface: false, cancelNotification: true),
            AndroidNotificationAction(_actionMissSkip, 'Отменить',
                showsUserInterface: false, cancelNotification: true),
          ],
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: _iosMissCategory,
          threadIdentifier: 'miss',
        ),
      );

  static int _missId(Goal g) => 1500000000 + g.notifId;

  /// Момент, когда истекает срок выполнения за день [day].
  static DateTime _deadlineOf(Goal g, DateTime day) {
    final m = g.dueMinutes;
    return m == null
        ? DateTime(day.year, day.month, day.day + 1)
        : DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
  }

  String _missBody(Goal g) {
    final p = g.parent;
    if (p != null && g.offsetDays < 0) {
      return 'Это подготовка к цели «${p.title}». Перенести или отменить?';
    }
    return 'Перенести на следующий день или отменить?';
  }

  List<int> _allIds(Goal g) {
    final ids = <int>[];
    for (var d = 0; d < _daysAhead; d++) {
      if (_isIOS) {
        for (var k = 0; k < _iosMaxPerDay; k++) {
          ids.add(g.notifId * 100 + d * 10 + k);
        }
      } else {
        ids.add(g.notifId * 10 + d);
      }
    }
    ids.add(_missId(g));
    return ids;
  }

  /// Убрать все уведомления цели (и показанные, и запланированные).
  Future<void> cancelGoal(Goal g) async {
    if (!_initialized) return;
    for (final id in _allIds(g)) {
      await _plugin.cancel(id);
    }
  }

  /// Полностью пересобрать расписание напоминаний.
  Future<void> reschedule(List<Goal> goals) async {
    if (!_initialized) return;

    // Снимаем только запланированные: показанные «висящие» не трогаем,
    // чтобы они не звенели заново при каждом открытии приложения.
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id == summaryId) continue; // перезапишется ниже
      await _plugin.cancel(p.id);
    }

    final now = DateTime.now();
    final t = dayOf(now);
    final entries = <_Entry>[];
    final showNow = <_Entry>[];

    for (final g in goals) {
      final minutes = g.reminderMinutes;
      if (!isActive(g) || minutes == null) continue;
      final h = minutes ~/ 60, m = minutes % 60;
      for (var d = 0; d < _daysAhead; d++) {
        final day = addDays(t, d);
        if (!wouldBeDue(g, day) || doneOn(g, day)) continue;
        final first = DateTime(day.year, day.month, day.day, h, m);
        // Напоминать после срока «выполнить до» уже незачем.
        final until = g.dueMinutes == null ? null : _deadlineOf(g, day);
        if (until != null && !first.isBefore(until)) continue;
        final times = <DateTime>[first];
        if (_isIOS) {
          var x = first.add(const Duration(hours: _iosRepeatHours));
          while (x.day == first.day &&
              x.hour < 23 &&
              times.length < _iosMaxPerDay &&
              (until == null || x.isBefore(until))) {
            times.add(x);
            x = x.add(const Duration(hours: _iosRepeatHours));
          }
        }
        for (var k = 0; k < times.length; k++) {
          final id = _isIOS ? g.notifId * 100 + d * 10 + k : g.notifId * 10 + d;
          if (times[k].isAfter(now)) {
            entries.add(_Entry(id, times[k], g, until: until));
          } else if (!_isIOS && d == 0 && (until == null || until.isAfter(now))) {
            // Время уже прошло, а цель не выполнена — уведомление должно висеть.
            showNow.add(_Entry(id, times[k], g, until: until));
          }
        }
      }
    }

    int? timeout(_Entry e, DateTime from) =>
        e.until == null ? null : e.until!.difference(from).inMilliseconds;

    final active = <int>{};
    try {
      for (final a in await _plugin.getActiveNotifications()) {
        if (a.id != null) active.add(a.id!);
      }
    } catch (_) {}

    for (final e in showNow) {
      if (active.contains(e.id)) continue;
      await _plugin.show(e.id, e.goal.title, _body(e.goal), _details(timeout(e, now)),
          payload: e.goal.id);
    }

    // «Цель не выполнена — что делать?» для целей с вариантом «спрашивать».
    final missLater = <_Entry>[];
    for (final g in goals) {
      if (!isActive(g) || g.carry != CarryMode.ask) continue;
      final id = _missId(g);
      if (g.awaiting) {
        if (!active.contains(id)) {
          await _plugin.show(id, 'Не выполнено: ${g.title}', _missBody(g), _missDetails(),
              payload: g.id);
        }
        continue;
      }
      if (doneOn(g, g.nextDue)) continue;
      // Без срока «выполнить до» спрашиваем не в полночь, а утром следующего дня.
      final at = g.dueMinutes == null
          ? DateTime(g.nextDue.year, g.nextDue.month, g.nextDue.day + 1, 9)
          : _deadlineOf(g, g.nextDue);
      if (at.isAfter(now) && at.difference(now).inDays < _daysAhead) {
        missLater.add(_Entry(id, at, g));
      }
    }

    entries.sort((a, b) => a.at.compareTo(b.at));
    final limit = _isIOS ? _iosLimit : _androidLimit;

    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (Platform.isAndroid) {
      try {
        if (await _android?.canScheduleExactNotifications() ?? false) {
          mode = AndroidScheduleMode.exactAllowWhileIdle;
        }
      } catch (_) {}
    }

    try {
      await _updateSummary(goals, mode);
    } catch (_) {}

    missLater.sort((a, b) => a.at.compareTo(b.at));
    final missCount = missLater.length > 15 ? 15 : missLater.length;
    for (final e in missLater.take(missCount)) {
      await _plugin.zonedSchedule(
        e.id,
        'Не выполнено: ${e.goal.title}',
        _missBody(e.goal),
        tz.TZDateTime.from(e.at, tz.UTC),
        _missDetails(),
        androidScheduleMode: mode,
        payload: e.goal.id,
      );
    }

    for (final e in entries.take(limit - 1 - missCount)) {
      await _plugin.zonedSchedule(
        e.id,
        e.goal.title,
        _body(e.goal),
        tz.TZDateTime.from(e.at, tz.UTC),
        _details(timeout(e, e.at)),
        androidScheduleMode: mode,
        payload: e.goal.id,
      );
    }
  }

  NotificationDetails _summaryDetails(String title, List<String> lines) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _summaryChannelId,
          'Сводка на сегодня',
          channelDescription: 'Постоянное уведомление со списком целей на день',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          silent: true,
          category: AndroidNotificationCategory.status,
          styleInformation: lines.isEmpty
              ? null
              : InboxStyleInformation(lines, contentTitle: title),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentBanner: false,
          presentSound: false,
          presentBadge: false,
          presentList: true,
          interruptionLevel: InterruptionLevel.passive,
          threadIdentifier: 'summary',
        ),
      );

  /// Текст сводки по списку «осталось» и количеству выполненных.
  (String, String, List<String>) _summaryText(List<Goal> left, int done) {
    final total = left.length + done;
    final title = left.isEmpty
        ? 'Сегодня всё выполнено · $done из $total'
        : 'Сегодня: осталось ${left.length} из $total';
    if (left.isEmpty) return (title, 'Отличная работа!', const <String>[]);
    if (left.length > _summaryMaxLines) {
      return (title, 'Целей на сегодня: ${left.length}', const <String>[]);
    }
    final lines = [for (final g in left) '○  ${g.title}'];
    return (title, left.map((g) => g.title).join(', '), lines);
  }

  /// Показать/обновить постоянную сводку и запланировать сводку на завтра.
  Future<void> _updateSummary(List<Goal> goals, AndroidScheduleMode mode) async {
    if (!useSummary) {
      await _plugin.cancel(summaryId);
      return;
    }
    final now = DateTime.now();
    final t = dayOf(now);
    final tomorrow = addDays(t, 1);
    int byTime(Goal a, Goal b) =>
        (a.reminderMinutes ?? 9999).compareTo(b.reminderMinutes ?? 9999);

    final left = <Goal>[];
    var done = 0;
    for (final g in goals) {
      if (doneOn(g, t) && (isActive(g) || g.finished)) {
        done++;
      } else if (isActive(g) && !g.awaiting && !g.nextDue.isAfter(t)) {
        left.add(g);
      }
    }
    left.sort(byTime);

    final next = goals
        .where((g) => wouldBeDue(g, tomorrow))
        .toList()
      ..sort(byTime);

    // Снимаем старую запланированную сводку на завтра, если планировать нечего.
    // cancel убирает и показанную — она сразу же покажется заново ниже.
    if (next.isEmpty) await _plugin.cancel(summaryId);

    if (left.isEmpty && done == 0) {
      await _plugin.cancel(summaryId);
    } else {
      final (title, body, lines) = _summaryText(left, done);
      await _plugin.show(summaryId, title, body, _summaryDetails(title, lines));
    }
    if (next.isEmpty) return;

    // Если приложение не откроют, в 00:01 сводка обновится сама.
    final (nTitle, nBody, nLines) = _summaryText(next, 0);
    await _plugin.zonedSchedule(
      summaryId,
      nTitle,
      nBody,
      tz.TZDateTime.from(
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 0, 1), tz.UTC),
      _summaryDetails(nTitle, nLines),
      androidScheduleMode: mode,
    );
  }

  String _body(Goal g) {
    final shift = g.missedDays > 0 && g.carry != CarryMode.skip
        ? ' (перенесено дней: ${g.missedDays})'
        : '';
    return 'Отметьте выполнение цели на сегодня$shift';
  }
}
