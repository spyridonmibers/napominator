import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/goal_repository.dart';
import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';

const _channelId = 'goal_reminders';
const _actionDone = 'done';
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

/// Нажатие «Выполнено» в уведомлении, когда приложение закрыто.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  if (response.actionId != _actionDone || response.payload == null) return;
  DartPluginRegistrant.ensureInitialized();
  final repo = GoalRepository();
  final goals = await repo.load();
  Goal? goal;
  for (final g in goals) {
    if (g.id == response.payload) goal = g;
  }
  if (goal == null) return;
  if (complete(goal, todayDay())) {
    await repo.save(goals);
  }
  try {
    await Notifications.instance.init();
    await Notifications.instance.cancelGoal(goal);
    await Notifications.instance.reschedule(goals);
  } catch (_) {
    // Пересчитается при следующем открытии приложения.
  }
}

class _Entry {
  _Entry(this.id, this.at, this.goal);
  final int id;
  final DateTime at;
  final Goal goal;
}

class Notifications {
  Notifications._();
  static final Notifications instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  void Function(String goalId)? _onDone;

  bool get _isIOS => Platform.isIOS;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init({void Function(String goalId)? onDone}) async {
    if (onDone != null) _onDone = onDone;
    if (_initialized) return;
    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
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
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (r) {
        if (r.actionId == _actionDone && r.payload != null) {
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

  NotificationDetails _details() => NotificationDetails(
        android: const AndroidNotificationDetails(
          _channelId,
          'Напоминания о целях',
          channelDescription: 'Висят, пока цель на сегодня не отмечена',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          category: AndroidNotificationCategory.reminder,
          actions: <AndroidNotificationAction>[
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
        if (day.isBefore(g.nextDue) || doneOn(g, day)) continue;
        final first = DateTime(day.year, day.month, day.day, h, m);
        final times = <DateTime>[first];
        if (_isIOS) {
          var x = first.add(const Duration(hours: _iosRepeatHours));
          while (x.day == first.day && x.hour < 23 && times.length < _iosMaxPerDay) {
            times.add(x);
            x = x.add(const Duration(hours: _iosRepeatHours));
          }
        }
        for (var k = 0; k < times.length; k++) {
          final id = _isIOS ? g.notifId * 100 + d * 10 + k : g.notifId * 10 + d;
          if (times[k].isAfter(now)) {
            entries.add(_Entry(id, times[k], g));
          } else if (!_isIOS && d == 0) {
            // Время уже прошло, а цель не выполнена — уведомление должно висеть.
            showNow.add(_Entry(id, times[k], g));
          }
        }
      }
    }

    final details = _details();

    if (showNow.isNotEmpty) {
      final active = <int>{};
      try {
        for (final a in await _android?.getActiveNotifications() ??
            const <ActiveNotification>[]) {
          if (a.id != null) active.add(a.id!);
        }
      } catch (_) {}
      for (final e in showNow) {
        if (active.contains(e.id)) continue;
        await _plugin.show(e.id, e.goal.title, _body(e.goal), details,
            payload: e.goal.id);
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

    for (final e in entries.take(limit)) {
      await _plugin.zonedSchedule(
        e.id,
        e.goal.title,
        _body(e.goal),
        tz.TZDateTime.from(e.at, tz.UTC),
        details,
        androidScheduleMode: mode,
        payload: e.goal.id,
      );
    }
  }

  String _body(Goal g) {
    final shift = g.missedDays > 0 ? ' (перенесено дней: ${g.missedDays})' : '';
    return 'Отметьте выполнение цели на сегодня$shift';
  }
}
