import 'package:flutter/material.dart';

import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../state/goal_store.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.store,
    required this.onAdd,
    required this.onOpen,
  });

  final GoalStore store;
  final VoidCallback onAdd;
  final void Function(Goal) onOpen;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  int _tab = 0; // 0 — актуальные, 1 — архив

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final active = store.active
          ..sort((a, b) {
            final c = a.nextDue.compareTo(b.nextDue);
            return c != 0 ? c : a.title.compareTo(b.title);
          });
        final archive = store.archive
          ..sort((a, b) {
            final da = a.finishedOn ?? a.nextDue;
            final db = b.finishedOn ?? b.nextDue;
            return db.compareTo(da);
          });
        final list = _tab == 0 ? active : archive;

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Все цели', style: th.textTheme.displaySmall),
                          const SizedBox(height: 4),
                          Text(
                            'Активных ${store.activeCount} из ${GoalStore.maxGoals}',
                            style: th.textTheme.bodyLarge
                                ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    AddGoalButton(onTap: store.canAdd ? widget.onAdd : null, size: 44),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _Segmented(
                index: _tab,
                labels: ['Актуальные · ${active.length}', 'Архив · ${archive.length}'],
                onChanged: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 16),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: _tab == 0
                      ? EmptyState(
                          icon: Icons.flag_rounded,
                          title: 'Нет активных целей',
                          text: 'Создайте цель — она появится здесь и на экране «Сегодня».',
                          action: FilledButton.icon(
                            onPressed: store.canAdd ? widget.onAdd : null,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Создать цель'),
                          ),
                        )
                      : const EmptyState(
                          icon: Icons.inventory_2_rounded,
                          title: 'Архив пуст',
                          text: 'Сюда попадают достигнутые цели и те, '
                              'что вы отложили.',
                        ),
                )
              else
                for (final g in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalCard(goal: g, onTap: () => widget.onOpen(g)),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Переключатель-«таблетка» на две позиции.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.index, required this.labels, required this.onChanged});
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.muted(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppColors.shadow(context),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: Text(
                            labels[i],
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: i == index
                                  ? th.colorScheme.onSurface
                                  : th.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});
  final Goal goal;
  final VoidCallback onTap;

  String _status(Goal g) {
    if (g.finished) {
      return g.finishedOn == null ? 'Достигнута' : 'Достигнута ${formatDate(g.finishedOn!)}';
    }
    if (g.archived) return 'Отложена';
    final t = todayDay();
    if (doneOn(g, t)) return 'Сегодня выполнено · далее ${formatRelative(g.nextDue)}';
    if (g.nextDue == t) return 'Нужно сделать сегодня';
    return 'Следующий раз ${formatRelative(g.nextDue)}';
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final g = goal;
    final pal = paletteOf(g);
    final p = progress(g);
    final streak = currentStreak(g);
    final inactive = !isActive(g);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GoalBadge.of(g, size: 46, dimmed: g.archived),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: th.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      scheduleLine(g),
                      style: th.textTheme.bodySmall
                          ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (g.finished)
                Icon(Icons.emoji_events_rounded, color: pal.main)
              else if (!inactive && streak >= 2)
                Pill(
                  icon: Icons.local_fire_department_rounded,
                  text: '$streak',
                  color: const Color(0xFFF97316),
                ),
            ],
          ),
          if (p != null) ...[
            const SizedBox(height: 14),
            GoalProgressBar(value: p, palette: pal),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _status(g),
                  style: th.textTheme.bodySmall?.copyWith(
                    color: !inactive && g.nextDue == todayDay() && !doneOn(g, todayDay())
                        ? pal.main
                        : th.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (g.deadlineType != DeadlineType.none)
                Text(
                  _deadlineShort(g),
                  style: th.textTheme.bodySmall
                      ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _deadlineShort(Goal g) {
    switch (g.deadlineType) {
      case DeadlineType.none:
        return '';
      case DeadlineType.count:
        return '${g.completions.length}/${g.targetCount}';
      case DeadlineType.date:
        return 'до ${formatDate(effectiveEndDate(g)!)}';
    }
  }
}
