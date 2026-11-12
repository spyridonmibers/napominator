import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/alarm_schedule.dart';
import '../models/alarm.dart';
import '../models/day.dart';
import '../models/goal.dart' show RepeatType;
import '../services/alarm_bridge.dart';
import '../state/alarm_store.dart';
import 'edit_alarm_screen.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// Текст графика будильника: «Будни», «Каждый день», «График 2/2»…
String alarmRepeatText(AlarmItem a) {
  switch (a.repeat) {
    case RepeatType.daily:
      return 'Каждый день';
    case RepeatType.everyOtherDay:
      return 'Через день';
    case RepeatType.weekdays:
      final d = a.weekdays;
      if (d.length == 5 && d.containsAll({1, 2, 3, 4, 5})) return 'Будни';
      if (d.length == 2 && d.containsAll({6, 7})) return 'Выходные';
      if (d.length == 7) return 'Каждый день';
      return weekdaysText(d);
    case RepeatType.cycle:
      return 'График ${a.cycleOn}/${a.cycleOff}';
  }
}

/// «через 8 ч 15 мин»
String untilText(DateTime at, DateTime now) {
  final diff = at.difference(now);
  final d = diff.inDays;
  final h = diff.inHours % 24;
  final m = diff.inMinutes % 60;
  if (d > 0) return 'через $d дн. $h ч';
  if (h > 0) return 'через $h ч $m мин';
  return 'через ${m < 1 ? 1 : m} мин';
}

GoalPalette alarmPalette(AlarmItem a) => a.customColor != null
    ? paletteFromColor(Color(a.customColor!))
    : goalPalettes[a.colorIndex.abs() % goalPalettes.length];

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key, required this.store});
  final AlarmStore store;

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen> {
  late DateTime _month;
  late DateTime _selected;
  Timer? _tick;
  bool _supported = true;
  List<String> _missing = const [];

  AlarmStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final t = todayDay();
    _month = DateTime.utc(t.year, t.month, 1);
    _selected = t;
    // Раз в минуту обновляем «через N минут».
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _checkPlatform();
  }

  Future<void> _checkPlatform() async {
    final ok = await AlarmBridge.isSupported();
    final missing = ok ? await AlarmBridge.missingPermissions() : const <String>[];
    if (mounted) {
      setState(() {
        _supported = ok;
        _missing = missing;
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _open([AlarmItem? a]) async {
    if (a == null && !store.canAdd) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: a == null,
      builder: (_) => EditAlarmScreen(store: store, alarm: a),
    ));
    _checkPlatform();
  }

  void _shiftMonth(int delta) => setState(() {
        _month = DateTime.utc(_month.year, _month.month + delta, 1);
        final t = todayDay();
        _selected = (_month.year == t.year && _month.month == t.month) ? t : _month;
      });

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        AlarmItem? nextAlarm;
        DateTime? nextAt;
        for (final a in store.alarms) {
          final at = nextAlarmTime(a, now);
          if (at != null && (nextAt == null || at.isBefore(nextAt))) {
            nextAt = at;
            nextAlarm = a;
          }
        }
        final first = _month;
        final last = DateTime.utc(_month.year, _month.month + 1, 0);
        final byDay = <DateTime, List<AlarmItem>>{};
        for (final a in store.alarms) {
          for (final d in alarmDays(a, first, last)) {
            (byDay[d] ??= <AlarmItem>[]).add(a);
          }
        }
        final dayAlarms = (byDay[_selected] ?? const <AlarmItem>[]).toList()
          ..sort((a, b) => a.minutes.compareTo(b.minutes));

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Будильник', style: th.textTheme.displaySmall)),
                    AddGoalButton(onTap: store.canAdd ? () => _open() : null, size: 44),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!_supported)
                const _InfoCard(
                  icon: Icons.info_outline_rounded,
                  text: 'Настоящий будильник на iPhone работает с iOS 26. '
                      'На этой версии iOS будильники сохранятся, но звонить не будут.',
                )
              else
                for (final m in _missing)
                  _InfoCard(
                    icon: Icons.warning_amber_rounded,
                    text: m == 'fullScreen'
                        ? 'Разрешите показ на весь экран — иначе будильник на заблокированном '
                            'телефоне придёт обычным уведомлением.'
                        : m == 'exact'
                            ? 'Разрешите «Будильники и напоминания», чтобы будильник звонил точно.'
                            : 'Разрешите приложению ставить будильники.',
                    action: 'Разрешить',
                    onAction: () async {
                      await AlarmBridge.requestPermission(m);
                      await Future<void>.delayed(const Duration(seconds: 1));
                      _checkPlatform();
                    },
                  ),
              _NextCard(alarm: nextAlarm, at: nextAt, now: now),

              const SectionTitle('Календарь'),
              AppCard(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
                child: GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -250) _shiftMonth(1);
                    if (v > 250) _shiftMonth(-1);
                  },
                  child: _MonthGrid(
                    month: _month,
                    selected: _selected,
                    byDay: byDay,
                    onShift: _shiftMonth,
                    onSelect: (d) => setState(() => _selected = d),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (dayAlarms.isEmpty)
                Text(
                  '${capitalize(formatRelative(_selected))}: будильников нет',
                  textAlign: TextAlign.center,
                  style: th.textTheme.bodyMedium?.copyWith(color: th.colorScheme.onSurfaceVariant),
                )
              else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in dayAlarms)
                      Pill(
                        icon: Icons.alarm_rounded,
                        text: '${formatTime(a.minutes)}${a.label.isEmpty ? '' : ' · ${a.label}'}',
                        color: alarmPalette(a).main,
                      ),
                  ],
                ),

              const SectionTitle('Все будильники'),
              if (store.alarms.isEmpty)
                AppCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text('Будильников пока нет', style: th.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Нажмите «+», чтобы поставить первый.',
                        style: th.textTheme.bodyMedium
                            ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                for (final a in store.alarms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AlarmCard(
                      alarm: a,
                      now: now,
                      onTap: () => _open(a),
                      onToggle: (v) => store.setEnabled(a, v),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text, this.action, this.onAction});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: th.colorScheme.errorContainer.withValues(alpha: 0.5),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: th.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: th.textTheme.bodyMedium)),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.alarm, required this.at, required this.now});
  final AlarmItem? alarm;
  final DateTime? at;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = alarm;
    final when = at;
    if (a == null || when == null) {
      return AppCard(
        gradient: brandPalette().gradient,
        padding: const EdgeInsets.all(20),
        child: const Row(
          children: [
            Icon(Icons.alarm_off_rounded, color: Colors.white, size: 30),
            SizedBox(width: 14),
            Expanded(
              child: Text('Нет включённых будильников',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    final day = dayOf(when);
    return AppCard(
      gradient: alarmPalette(a).gradient,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Следующий · ${formatRelative(day)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(formatTime(a.minutes),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, height: 1.1)),
                Text(
                  [untilText(when, now), if (a.label.isNotEmpty) a.label].join(' · '),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.alarm_rounded, color: Colors.white, size: 30),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.byDay,
    required this.onShift,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Map<DateTime, List<AlarmItem>> byDay;
  final void Function(int) onShift;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final t = todayDay();
    final last = DateTime.utc(month.year, month.month + 1, 0);
    final lead = month.weekday - 1;
    final cells = ((lead + last.day + 6) ~/ 7) * 7;
    final brand = brandPalette();

    Widget cell(int day) {
      if (day < 1 || day > last.day) return const SizedBox(height: 48);
      final d = DateTime.utc(month.year, month.month, day);
      final isSel = d == selected;
      final isToday = d == t;
      final list = byDay[d] ?? const <AlarmItem>[];
      return GestureDetector(
        onTap: () => onSelect(d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 48,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            gradient: isSel ? brand.gradient : null,
            borderRadius: BorderRadius.circular(14),
            border: isToday && !isSel ? Border.all(color: th.colorScheme.primary, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSel || isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isSel
                        ? Colors.white
                        : d.isBefore(t)
                            ? th.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                            : th.colorScheme.onSurface,
                  )),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final a in list.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSel ? Colors.white : alarmPalette(a).main,
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

    return Column(
      children: [
        Row(
          children: [
            IconButton(onPressed: () => onShift(-1), icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
              child: Text('${monthsNom[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center, style: th.textTheme.titleMedium),
            ),
            IconButton(onPressed: () => onShift(1), icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(weekdayShort[i],
                      style: th.textTheme.labelMedium?.copyWith(
                        color: i >= 5 ? th.colorScheme.primary : th.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < cells ~/ 7; row++)
          Row(children: [
            for (var col = 0; col < 7; col++) Expanded(child: cell(row * 7 + col - lead + 1)),
          ]),
      ],
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.now,
    required this.onTap,
    required this.onToggle,
  });

  final AlarmItem alarm;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final a = alarm;
    final pal = alarmPalette(a);
    final next = nextAlarmTime(a, now);
    final muted = th.colorScheme.onSurfaceVariant;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 54,
            decoration: BoxDecoration(
              gradient: a.enabled ? pal.gradient : null,
              color: a.enabled ? null : AppColors.muted(context),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatTime(a.minutes),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: a.enabled ? th.colorScheme.onSurface : muted,
                  ),
                ),
                Text(
                  [
                    if (a.label.isNotEmpty) a.label,
                    alarmRepeatText(a),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: th.textTheme.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.music_note_rounded, size: 14, color: muted),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        a.enabled && next != null
                            ? '${a.soundTitle} · ${untilText(next, now)}'
                            : a.soundTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: th.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: a.enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}
