import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../state/goal_store.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.store,
    required this.onAdd,
    required this.onOpen,
  });

  final GoalStore store;
  final VoidCallback onAdd;
  final void Function(Goal) onOpen;

  /// Последняя показанная плашка «Выполнено · Отменить».
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _snack;

  Future<void> _toggle(BuildContext context, Goal g, bool done) async {
    HapticFeedback.mediumImpact();
    if (done) {
      await store.undo(g);
      return;
    }
    final ok = await store.completeById(g.id);
    if (!ok || !context.mounted) return;
    final u = store.byId(g.id);
    final finished = u != null && u.finished;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final controller = messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            Icon(
              finished ? Icons.emoji_events_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(finished
                  ? 'Цель «${g.title}» достигнута!'
                  : '«${g.title}» — выполнено'),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () {
            final x = store.byId(g.id);
            if (x != null) store.undo(x);
          },
        ),
      ));
    // В новых версиях Flutter плашка с кнопкой сама не исчезает — закрываем через 5 секунд.
    // Закрываем только свою плашку: если за это время показали новую, её не трогаем.
    _snack = controller;
    var closed = false;
    controller.closed.then((_) => closed = true);
    Timer(const Duration(seconds: 5), () {
      if (!closed && identical(_snack, controller)) controller.close();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final t = todayDay();
        final tomorrow = addDays(t, 1);
        final due = <Goal>[];
        final done = <Goal>[];
        final next = <Goal>[];
        for (final g in store.goals) {
          if (!isActive(g) && !(g.finished && doneOn(g, t))) continue;
          if (isDueToday(g, t)) {
            due.add(g);
          } else if (doneOn(g, t)) {
            done.add(g);
          } else if (g.nextDue == tomorrow) {
            next.add(g);
          }
        }
        due.sort((a, b) {
          final m = b.missedDays.compareTo(a.missedDays);
          if (m != 0) return m;
          return (a.reminderMinutes ?? 9999).compareTo(b.reminderMinutes ?? 9999);
        });
        final total = due.length + done.length;
        final hasActive = store.activeCount > 0;

        return CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: _Header(done: done.length, total: total, today: t),
              ),
            ),
            if (!store.loaded)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!hasActive && done.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.track_changes_rounded,
                  title: 'Поставьте первую цель',
                  text: 'Отмечайте выполнение каждый день. '
                      'Пропустили — цель переедет на завтра, '
                      'а график сдвинется на день.',
                  action: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Создать цель'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.list(
                  children: [
                    SectionTitle(
                      'Нужно сделать',
                      trailing: AddGoalButton(
                        onTap: store.canAdd ? onAdd : null,
                      ),
                    ),
                    if (total == 0)
                      const _RestCard()
                    else if (due.isEmpty)
                      const _AllDoneCard(),
                    if (due.isNotEmpty) ...[
                      for (final g in due)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TodayCard(
                            goal: g,
                            done: false,
                            onCheck: () => _toggle(context, g, false),
                            onTap: () => onOpen(g),
                          ),
                        ),
                    ],
                    if (done.isNotEmpty) ...[
                      const SectionTitle('Выполнено'),
                      for (final g in done)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TodayCard(
                            goal: g,
                            done: true,
                            onCheck: () => _toggle(context, g, true),
                            onTap: () => onOpen(g),
                          ),
                        ),
                    ],
                    if (next.isNotEmpty) ...[
                      const SectionTitle('Завтра'),
                      AppCard(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (var i = 0; i < next.length; i++) ...[
                              if (i > 0) const Divider(indent: 68),
                              _CompactRow(goal: next[i], onTap: () => onOpen(next[i])),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.done, required this.total, required this.today});
  final int done;
  final int total;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final left = total - done;
    final subtitle = total == 0
        ? 'На сегодня ничего не запланировано'
        : left == 0
            ? 'Все цели выполнены'
            : 'Осталось $left из $total';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateLong(today),
                  style: th.textTheme.titleSmall?.copyWith(
                    color: th.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Сегодня', style: th.textTheme.displaySmall),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: th.textTheme.bodyLarge
                      ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (total > 0)
            ProgressRing(
              value: done / total,
              size: 76,
              stroke: 9,
              gradient: brandPalette().gradient,
              child: Text(
                '$done/$total',
                style: th.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.goal,
    required this.done,
    required this.onCheck,
    required this.onTap,
  });

  final Goal goal;
  final bool done;
  final VoidCallback onCheck;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final g = goal;
    final pal = paletteOf(g);
    final streak = currentStreak(g);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        children: [
          GoalBadge.of(g, size: 50, dimmed: done),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: th.textTheme.titleMedium!.copyWith(
                    color: done
                        ? th.colorScheme.onSurfaceVariant
                        : th.colorScheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                  child: Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (g.reminderMinutes != null)
                      Pill(
                        icon: Icons.notifications_rounded,
                        text: formatTime(g.reminderMinutes!),
                        color: th.colorScheme.onSurfaceVariant,
                      ),
                    if (!done && g.missedDays > 0 && g.carry != CarryMode.skip)
                      Pill(
                        icon: Icons.update_rounded,
                        text: 'перенос +${g.missedDays}',
                        color: th.colorScheme.error,
                      ),
                    if (streak >= 2)
                      Pill(
                        icon: Icons.local_fire_department_rounded,
                        text: '$streak',
                        color: const Color(0xFFF97316),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CheckButton(done: done, palette: pal, onTap: onCheck),
        ],
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.goal, required this.onTap});
  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GoalBadge.of(goal, size: 38),
            const SizedBox(width: 14),
            Expanded(
              child: Text(goal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: th.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500)),
            ),
            if (goal.reminderMinutes != null)
              Text(formatTime(goal.reminderMinutes!),
                  style: th.textTheme.bodyMedium
                      ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _AllDoneCard extends StatelessWidget {
  const _AllDoneCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: AppCard(
        gradient: brandPalette().gradient,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('День закрыт',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Все цели на сегодня выполнены. Так держать!',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestCard extends StatelessWidget {
  const _RestCard();

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            GoalBadge(palette: goalPalettes[6], icon: Icons.spa_rounded, size: 52),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('День отдыха', style: th.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text('Сегодня по графику целей нет.',
                      style: th.textTheme.bodyMedium
                          ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
