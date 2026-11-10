import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../services/notifications.dart';
import '../state/goal_store.dart';
import 'edit_goal_screen.dart';
import 'format.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final GoalStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _midnight;

  GoalStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Notifications.instance.requestPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.refresh();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      store.refresh();
      _scheduleMidnight();
    });
  }

  Future<void> _openEditor([Goal? goal]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EditGoalScreen(store: store, goal: goal),
    ));
  }

  Future<void> _complete(Goal g) async {
    final ok = await store.completeById(g.id);
    if (!mounted || !ok) return;
    final updated = store.byId(g.id);
    final msg = updated != null && updated.finished
        ? 'Цель «${g.title}» достигнута!'
        : 'Отмечено: ${g.title}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () {
            final x = store.byId(g.id);
            if (x != null) store.undo(x);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = todayDay();
        final due = <Goal>[];
        final doneToday = <Goal>[];
        final upcoming = <Goal>[];
        final finished = <Goal>[];
        for (final g in store.goals) {
          if (g.finished) {
            finished.add(g);
          } else if (isDueToday(g, t)) {
            due.add(g);
          } else if (doneOn(g, t)) {
            doneToday.add(g);
          } else {
            upcoming.add(g);
          }
        }
        // Сначала самые «перенесённые».
        due.sort((a, b) => b.missedDays.compareTo(a.missedDays));
        upcoming.sort((a, b) => a.nextDue.compareTo(b.nextDue));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Напоминатор'),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('${store.goals.length}/${GoalStore.maxGoals}'),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: store.canAdd ? () => _openEditor() : null,
            backgroundColor: store.canAdd
                ? null
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            icon: const Icon(Icons.add),
            label: Text(store.canAdd ? 'Цель' : 'Максимум 50'),
          ),
          body: !store.loaded
              ? const Center(child: CircularProgressIndicator())
              : store.goals.isEmpty
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      children: [
                        if (due.isNotEmpty) ...[
                          _Header('Сегодня — осталось ${due.length}'),
                          ...due.map((g) => _GoalCard(
                                goal: g,
                                state: _CardState.due,
                                onCheck: () => _complete(g),
                                onTap: () => _openEditor(g),
                              )),
                        ],
                        if (due.isEmpty && doneToday.isNotEmpty)
                          const _Header('На сегодня всё выполнено 🎉'),
                        if (doneToday.isNotEmpty) ...[
                          if (due.isNotEmpty) const _Header('Выполнено сегодня'),
                          ...doneToday.map((g) => _GoalCard(
                                goal: g,
                                state: _CardState.done,
                                onCheck: () => store.undo(g),
                                onTap: () => _openEditor(g),
                              )),
                        ],
                        if (upcoming.isNotEmpty) ...[
                          const _Header('Предстоящие'),
                          ...upcoming.map((g) => _GoalCard(
                                goal: g,
                                state: _CardState.upcoming,
                                onTap: () => _openEditor(g),
                              )),
                        ],
                        if (finished.isNotEmpty) ...[
                          const _Header('Завершённые'),
                          ...finished.map((g) => _GoalCard(
                                goal: g,
                                state: _CardState.finished,
                                onTap: () => _openEditor(g),
                              )),
                        ],
                      ],
                    ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Пока нет целей.\nНажмите «Цель», чтобы добавить первую (до 50).\n\n'
          'Если цель не отмечена за день, она переносится на следующий, '
          'а весь график сдвигается на день вперёд.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

enum _CardState { due, done, upcoming, finished }

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.state,
    required this.onTap,
    this.onCheck,
  });

  final Goal goal;
  final _CardState state;
  final VoidCallback onTap;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = goal;
    final p = progress(g);

    final lines = <String>[repeatText(g)];
    if (g.reminderMinutes != null && !g.finished) {
      lines[0] = '${lines[0]} · 🔔 ${formatTime(g.reminderMinutes!)}';
    }
    switch (state) {
      case _CardState.due:
        if (g.missedDays > 0) {
          lines.add('Перенесено: ${daysWord(g.missedDays)} всего');
        }
      case _CardState.done:
        lines.add('Следующий раз: ${formatRelative(g.nextDue)}');
      case _CardState.upcoming:
        lines.add('Следующий раз: ${formatRelative(g.nextDue)}');
      case _CardState.finished:
        if (g.finishedOn != null) lines.add('Завершена ${formatDate(g.finishedOn!)}');
    }
    lines.add(deadlineText(g));

    Widget leading;
    switch (state) {
      case _CardState.due:
        leading = IconButton.outlined(
          iconSize: 28,
          tooltip: 'Выполнено',
          onPressed: onCheck,
          icon: const Icon(Icons.check),
        );
      case _CardState.done:
        leading = IconButton.filled(
          iconSize: 28,
          tooltip: 'Отменить отметку',
          onPressed: onCheck,
          icon: const Icon(Icons.check),
        );
      case _CardState.upcoming:
        leading = Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.schedule, color: scheme.outline),
        );
      case _CardState.finished:
        leading = Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(Icons.emoji_events, color: scheme.tertiary),
        );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            decoration: state == _CardState.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    for (final l in lines)
                      Text(l,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (p != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: p,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
