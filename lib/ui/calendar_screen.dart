import 'package:flutter/material.dart';

import '../logic/schedule.dart';
import '../models/day.dart';
import '../models/goal.dart';
import '../state/goal_store.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

enum _EvType { done, missed, planned }

class _Ev {
  _Ev(this.goal, this.type);
  final Goal goal;
  final _EvType type;
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.store, required this.onOpen});
  final GoalStore store;
  final void Function(Goal) onOpen;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final t = todayDay();
    _month = DateTime.utc(t.year, t.month, 1);
    _selected = t;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime.utc(_month.year, _month.month + delta, 1);
      final t = todayDay();
      _selected = (_month.year == t.year && _month.month == t.month) ? t : _month;
    });
  }

  void _goToday() {
    final t = todayDay();
    setState(() {
      _month = DateTime.utc(t.year, t.month, 1);
      _selected = t;
    });
  }

  Map<DateTime, List<_Ev>> _events(List<Goal> goals, DateTime first, DateTime last) {
    final t = todayDay();
    final map = <DateTime, List<_Ev>>{};
    void put(DateTime d, _Ev e) => (map[d] ??= <_Ev>[]).add(e);
    bool inRange(DateTime d) => !d.isBefore(first) && !d.isAfter(last);

    for (final g in goals) {
      for (final c in g.completions) {
        if (inRange(c)) put(c, _Ev(g, _EvType.done));
      }
      for (final m in g.missedLog) {
        if (inRange(m)) put(m, _Ev(g, _EvType.missed));
      }
      final from = first.isBefore(t) ? t : first;
      for (final p in plannedDates(g, from, last)) {
        put(p, _Ev(g, _EvType.planned));
      }
    }
    for (final list in map.values) {
      list.sort((a, b) => a.type.index.compareTo(b.type.index));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final t = todayDay();
        final first = _month;
        final last = DateTime.utc(_month.year, _month.month + 1, 0);
        final events = _events(widget.store.goals, first, last);
        final lead = first.weekday - 1;
        final cells = ((lead + last.day + 6) ~/ 7) * 7;
        final isCurrent = _month.year == t.year && _month.month == t.month;
        final dayEvents = events[_selected] ?? const <_Ev>[];

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
                          Text('Календарь', style: th.textTheme.displaySmall),
                          const SizedBox(height: 4),
                          Text(
                            '${monthsNom[_month.month - 1]} ${_month.year}',
                            style: th.textTheme.bodyLarge?.copyWith(
                                color: th.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (!isCurrent)
                      TextButton(onPressed: _goToday, child: const Text('Сегодня')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -250) _shiftMonth(1);
                  if (v > 250) _shiftMonth(-1);
                },
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => _shiftMonth(-1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              monthsNom[_month.month - 1],
                              textAlign: TextAlign.center,
                              style: th.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _shiftMonth(1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: Center(
                                child: Text(
                                  weekdayShort[i],
                                  style: th.textTheme.labelMedium?.copyWith(
                                    color: i >= 5
                                        ? th.colorScheme.primary
                                        : th.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (var row = 0; row < cells ~/ 7; row++)
                        Row(
                          children: [
                            for (var col = 0; col < 7; col++)
                              Expanded(
                                child: _dayCell(
                                  context,
                                  row * 7 + col - lead + 1,
                                  last.day,
                                  t,
                                  events,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const _Legend(),
              SectionTitle(
                _selected == t ? 'Сегодня' : formatDateLong(_selected),
              ),
              if (dayEvents.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'В этот день целей нет',
                    style: th.textTheme.bodyLarge
                        ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < dayEvents.length; i++) ...[
                        if (i > 0) const Divider(indent: 68),
                        _EventRow(
                          ev: dayEvents[i],
                          isToday: _selected == t,
                          onTap: () => widget.onOpen(dayEvents[i].goal),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _dayCell(BuildContext context, int day, int daysInMonth, DateTime today,
      Map<DateTime, List<_Ev>> events) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 52);
    final th = Theme.of(context);
    final date = DateTime.utc(_month.year, _month.month, day);
    final selected = date == _selected;
    final isToday = date == today;
    final evs = events[date] ?? const <_Ev>[];

    Color dotColor(_Ev e) {
      switch (e.type) {
        case _EvType.done:
          return AppColors.success(context);
        case _EvType.missed:
          return th.colorScheme.error;
        case _EvType.planned:
          return th.colorScheme.outline.withValues(alpha: 0.5);
      }
    }

    final fg = selected
        ? Colors.white
        : isToday
            ? th.colorScheme.primary
            : th.colorScheme.onSurface;

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: selected ? goalPalettes[0].gradient : null,
          borderRadius: BorderRadius.circular(14),
          border: isToday && !selected
              ? Border.all(color: th.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: fg,
                fontSize: 15,
                fontWeight: selected || isToday ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final e in evs.take(4))
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? Colors.white : dotColor(e),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    Widget item(Color c, String s) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(s,
                style: th.textTheme.bodySmall
                    ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
          ],
        );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 6,
      children: [
        item(AppColors.success(context), 'выполнено'),
        item(th.colorScheme.error, 'перенесено'),
        item(th.colorScheme.outline.withValues(alpha: 0.5), 'по плану'),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.ev, required this.isToday, required this.onTap});
  final _Ev ev;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final g = ev.goal;
    late final Widget status;
    switch (ev.type) {
      case _EvType.done:
        status = Pill(
          icon: Icons.check_rounded,
          text: 'Выполнено',
          color: AppColors.success(context),
        );
      case _EvType.missed:
        status = Pill(
          icon: Icons.update_rounded,
          text: 'Перенесено',
          color: th.colorScheme.error,
        );
      case _EvType.planned:
        status = Pill(
          icon: isToday ? Icons.radio_button_unchecked_rounded : Icons.schedule_rounded,
          text: isToday ? 'Нужно сделать' : 'По плану',
          color: th.colorScheme.onSurfaceVariant,
        );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            GoalBadge.of(g, size: 38),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                g.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: th.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            status,
          ],
        ),
      ),
    );
  }
}
