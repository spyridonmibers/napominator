import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:home_widget/home_widget.dart';

import '../data/goal_repository.dart';
import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../ui/theme.dart';
import 'notifications.dart';

const _androidProvider = 'ru.napominator.napominator.TodayWidgetProvider';

/// Нажатие на кружок в виджете (выполняется в фоне, даже если приложение закрыто).
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null || uri.host != 'toggle') return;
  final id = uri.queryParameters['id'];
  if (id == null) return;
  DartPluginRegistrant.ensureInitialized();
  final repo = GoalRepository();
  final goals = await repo.load();
  final t = todayDay();
  for (final g in goals) {
    normalize(g, t);
  }
  Goal? goal;
  for (final g in goals) {
    if (g.id == id) goal = g;
  }
  if (goal != null) {
    if (doneOn(goal, t)) {
      undoToday(goal, t);
    } else {
      complete(goal, t);
    }
  }
  await repo.save(goals);
  await WidgetSync.update(goals);
  try {
    await Notifications.instance.init();
    if (goal != null) await Notifications.instance.cancelGoal(goal);
    await Notifications.instance.reschedule(goals);
  } catch (_) {}
}

class WidgetSync {
  static Map<String, dynamic> _item(Goal g, bool done) => {
        'id': g.id,
        'title': g.title,
        'done': done,
        'color': '#${paletteOf(g).main.toARGB32().toRadixString(16).padLeft(8, '0')}',
      };

  /// Сохранить данные для виджета и перерисовать его (только Android).
  static Future<void> update(List<Goal> goals) async {
    if (!Platform.isAndroid) return;
    try {
      final t = todayDay();
      final tomorrow = addDays(t, 1);
      final today = <Goal>[];
      final next = <Goal>[];
      for (final g in goals) {
        final done = doneOn(g, t);
        final active = isActive(g);
        if ((active && !g.nextDue.isAfter(t)) || (done && (active || g.finished))) {
          today.add(g);
        }
        if (active && !g.nextDue.isAfter(tomorrow)) next.add(g);
      }
      int byTime(Goal a, Goal b) =>
          (a.reminderMinutes ?? 9999).compareTo(b.reminderMinutes ?? 9999);
      today.sort((a, b) {
        final da = doneOn(a, t) ? 1 : 0, db = doneOn(b, t) ? 1 : 0;
        return da != db ? da - db : byTime(a, b);
      });
      next.sort(byTime);

      final data = {
        'date': dayKey(t),
        'today': [for (final g in today) _item(g, doneOn(g, t))],
        'next': [for (final g in next) _item(g, false)],
      };
      await HomeWidget.saveWidgetData<String>('today_json', jsonEncode(data));
      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
    } catch (_) {
      // Виджет не добавлен или недоступен — не страшно.
    }
  }
}
