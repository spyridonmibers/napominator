import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../state/goal_store.dart';
import 'edit_goal_screen.dart';
import 'format.dart';
import 'settings_screen.dart' show carryTitles;
import 'theme.dart';
import 'widgets.dart';

class GoalDetailScreen extends StatelessWidget {
  const GoalDetailScreen({super.key, required this.store, required this.goalId});
  final GoalStore store;
  final String goalId;

  Future<void> _edit(BuildContext context, Goal g) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EditGoalScreen(store: store, goal: g)),
      );

  Future<void> _delete(BuildContext context, Goal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить цель?'),
        content: Text('«${g.title}» и вся её история будут удалены без возможности восстановления.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      await store.delete(g);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.byId(goalId);
        if (g == null) {
          return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
        }
        final th = Theme.of(context);
        final pal = paletteOf(g);
        final t = todayDay();
        final dueToday = isDueToday(g, t);
        final doneToday = doneOn(g, t);
        final p = progress(g);
        final end = projectedEnd(g);

        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: 'Изменить',
                onPressed: () => _edit(context, g),
                icon: const Icon(Icons.edit_rounded),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (v) {
                  if (v == 'archive') store.setArchived(g, !g.archived);
                  if (v == 'delete') _delete(context, g);
                },
                itemBuilder: (_) => [
                  if (!g.finished)
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(g.archived ? 'Вернуть из архива' : 'Отложить в архив'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            children: [
              Center(child: GoalBadge.of(g, size: 84, dimmed: g.archived)),
              const SizedBox(height: 18),
              Text(g.title, textAlign: TextAlign.center, style: th.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                scheduleLine(g),
                textAlign: TextAlign.center,
                style: th.textTheme.bodyLarge?.copyWith(color: th.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                'При пропуске: ${carryTitles[g.carry]!.toLowerCase()}',
                textAlign: TextAlign.center,
                style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Center(child: _statusPill(context, g, dueToday, doneToday)),
              const SizedBox(height: 22),
              if (dueToday)
                _GradientButton(
                  palette: pal,
                  icon: Icons.check_rounded,
                  label: 'Отметить выполнение',
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    store.completeById(g.id);
                  },
                )
              else if (doneToday)
                OutlinedButton.icon(
                  onPressed: () => store.undo(g),
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Отменить сегодняшнюю отметку'),
                )
              else if (g.archived)
                OutlinedButton.icon(
                  onPressed: store.canAdd ? () => store.setArchived(g, false) : null,
                  icon: const Icon(Icons.unarchive_rounded),
                  label: Text(store.canAdd ? 'Вернуть из архива' : 'Достигнут лимит 50 целей'),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.local_fire_department_rounded,
                      color: const Color(0xFFF97316),
                      value: '${currentStreak(g)}',
                      label: 'текущая серия',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.military_tech_rounded,
                      color: const Color(0xFFF59E0B),
                      value: '${bestStreak(g)}',
                      label: 'лучшая серия',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success(context),
                      value: '${g.completions.length}',
                      label: 'выполнено',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.update_rounded,
                      color: th.colorScheme.error,
                      value: '${g.missedDays}',
                      label: g.carry == CarryMode.skip ? 'пропущено' : 'дней переноса',
                    ),
                  ),
                ],
              ),
              if (p != null) ...[
                const SectionTitle('Прогресс'),
                AppCard(
                  child: Row(
                    children: [
                      ProgressRing(
                        value: p,
                        size: 68,
                        stroke: 8,
                        gradient: pal.gradient,
                        child: Text('${(p * 100).round()}%',
                            style: th.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(deadlineText(g), style: th.textTheme.titleSmall),
                            if (end != null && !g.finished) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Финиш без пропусков: ${formatDate(end)}',
                                style: th.textTheme.bodySmall
                                    ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SectionTitle('История за 16 недель'),
              AppCard(child: _Heatmap(goal: g)),
            ],
          ),
        );
      },
    );
  }

  Widget _statusPill(BuildContext context, Goal g, bool dueToday, bool doneToday) {
    final th = Theme.of(context);
    if (g.finished) {
      return Pill(icon: Icons.emoji_events_rounded, text: 'Цель достигнута', color: paletteOf(g).main);
    }
    if (g.archived) {
      return Pill(icon: Icons.inventory_2_rounded, text: 'В архиве', color: th.colorScheme.onSurfaceVariant);
    }
    if (doneToday) {
      return Pill(icon: Icons.check_rounded, text: 'Сегодня выполнено', color: AppColors.success(context));
    }
    if (dueToday) {
      return g.missedDays > 0 && g.carry != CarryMode.skip
          ? Pill(icon: Icons.update_rounded, text: 'Сегодня · перенос +${g.missedDays}', color: th.colorScheme.error)
          : Pill(icon: Icons.today_rounded, text: 'Нужно сделать сегодня', color: paletteOf(g).main);
    }
    return Pill(
      icon: Icons.schedule_rounded,
      text: 'Следующий раз ${formatRelative(g.nextDue)}',
      color: th.colorScheme.onSurfaceVariant,
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final GoalPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: palette.gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: palette.a.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: th.textTheme.titleLarge),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: th.textTheme.bodySmall
                        ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Тепловая карта: столбцы — недели, строки — дни недели.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.goal});
  final Goal goal;

  static const _weeks = 16;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final g = goal;
    final pal = paletteOf(g);
    final t = todayDay();
    final startMonday = addDays(t, -(t.weekday - 1) - (_weeks - 1) * 7);
    final done = g.completions.toSet();
    final missed = g.missedLog.toSet();
    final planned = plannedDates(g, t, addDays(startMonday, _weeks * 7 - 1)).toSet();

    Color colorFor(DateTime d) {
      if (done.contains(d)) return pal.main;
      if (missed.contains(d)) return th.colorScheme.error.withValues(alpha: 0.75);
      if (planned.contains(d)) return pal.main.withValues(alpha: 0.22);
      return AppColors.muted(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 4.0;
            const labelW = 22.0;
            final cell = ((c.maxWidth - labelW - gap * (_weeks - 1)) / _weeks).clamp(6.0, 22.0).toDouble();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelW,
                  child: Column(
                    children: [
                      for (var r = 0; r < 7; r++)
                        SizedBox(
                          height: cell + gap,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: r.isEven
                                ? Text(weekdayShort[r],
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: th.colorScheme.onSurfaceVariant))
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
                for (var w = 0; w < _weeks; w++)
                  Padding(
                    padding: EdgeInsets.only(right: w == _weeks - 1 ? 0 : gap),
                    child: Column(
                      children: [
                        for (var r = 0; r < 7; r++)
                          Builder(builder: (_) {
                            final d = addDays(startMonday, w * 7 + r);
                            final isToday = d == t;
                            return Container(
                              width: cell,
                              height: cell,
                              margin: const EdgeInsets.only(bottom: gap),
                              decoration: BoxDecoration(
                                color: colorFor(d),
                                borderRadius: BorderRadius.circular(cell * 0.28),
                                border: isToday
                                    ? Border.all(color: th.colorScheme.onSurface, width: 1.5)
                                    : null,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(context, pal.main, 'выполнено'),
            _legend(context, th.colorScheme.error.withValues(alpha: 0.75), 'перенос'),
            _legend(context, pal.main.withValues(alpha: 0.22), 'по плану'),
          ],
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color c, String s) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 5),
          Text(s,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}
