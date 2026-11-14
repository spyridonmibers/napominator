import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/day.dart';
import '../models/goal.dart';
import '../state/goal_store.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Карточка «цель не выполнена в срок»: перенести, перенести с графиком или отменить.
class MissChoiceCard extends StatelessWidget {
  const MissChoiceCard({super.key, required this.store, required this.goal, this.onTap});
  final GoalStore store;
  final Goal goal;
  final VoidCallback? onTap;

  void _choose(CarryMode mode) {
    HapticFeedback.selectionClick();
    store.resolve(goal.id, mode);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final g = goal;
    final pal = paletteOf(g);
    final today = todayDay();
    final when = g.nextDue == today
        ? 'Не выполнена сегодня${g.dueMinutes == null ? '' : ' к ${formatTime(g.dueMinutes!)}'}'
        : 'Не выполнена ${formatDate(g.nextDue)}';
    final linked = g.parentId != null;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GoalBadge.of(g, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: th.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      linked ? '$when · ${linkText(g)}' : when,
                      style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ChoiceButton(
                  icon: Icons.redo_rounded,
                  label: 'Перенести',
                  palette: pal,
                  filled: true,
                  onTap: () => _choose(CarryMode.keep),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoiceButton(
                  icon: Icons.fast_forward_rounded,
                  label: 'С графиком',
                  palette: pal,
                  onTap: () => _choose(CarryMode.shift),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoiceButton(
                  icon: Icons.close_rounded,
                  label: 'Отменить',
                  palette: pal,
                  danger: true,
                  onTap: () => _choose(CarryMode.skip),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            linked
                ? '«С графиком» — вместе с этой целью на столько же сдвинется главная и всё, что к ней привязано.'
                : '«С графиком» — вместе с целью сдвинутся все следующие дни и срок.',
            style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.filled = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final GoalPalette palette;
  final VoidCallback onTap;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final fg = filled
        ? Colors.white
        : danger
            ? th.colorScheme.error
            : th.colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled ? palette.gradient : null,
          color: filled
              ? null
              : danger
                  ? th.colorScheme.error.withValues(alpha: 0.10)
                  : AppColors.muted(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
