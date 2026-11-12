import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/day.dart';
import '../state/app_settings.dart';
import 'format.dart';
import 'theme.dart';

/// Выбор времени: колесо или циферблат — как выбрано в настройках.
/// Возвращает минуты от полуночи или null, если пользователь закрыл окно.
Future<int?> pickTimeMinutes(
  BuildContext context, {
  required int current,
  String title = 'Время напоминания',
  int minuteInterval = 5,
}) async {
  if (AppSettings.instance.timeStyle == TimePickerStyle.dial) {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: title,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }
  final m = (current ~/ minuteInterval) * minuteInterval;
  var selected = m;
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card(context),
    builder: (c) {
      final th = Theme.of(c);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: th.textTheme.titleLarge),
              const SizedBox(height: 8),
              SizedBox(
                height: 216,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: th.brightness,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: th.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    minuteInterval: minuteInterval,
                    initialDateTime: DateTime(2000, 1, 1, m ~/ 60, m % 60),
                    onDateTimeChanged: (d) => selected = d.hour * 60 + d.minute,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, selected),
                  child: const Text('Готово'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Выбор одного варианта из нескольких — «таблетки» в цвете цели.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    required this.value,
    required this.options,
    required this.onChanged,
    required this.palette,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final GoalPalette palette;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Row(
      children: [
        for (final e in options.entries) ...[
          if (e.key != options.keys.first) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: e.key == value ? palette.gradient : null,
                  color: e.key == value ? null : AppColors.muted(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: e.key == value ? Colors.white : th.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class DayToggle extends StatelessWidget {
  const DayToggle({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final GoalPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: selected ? palette.gradient : null,
          color: selected ? null : AppColors.muted(context),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class SettingTile extends StatelessWidget {
  const SettingTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: th.colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: th.textTheme.bodyLarge)),
            Text(value,
                style: th.textTheme.bodyLarge?.copyWith(
                    color: th.colorScheme.primary, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: th.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class TimePreset extends StatelessWidget {
  const TimePreset({
    required this.label,
    required this.time,
    required this.selected,
    required this.palette,
    required this.onTap,
  });
  final String label;
  final String time;
  final bool selected;
  final GoalPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final fg = selected ? Colors.white : th.colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          gradient: selected ? palette.gradient : null,
          color: selected ? null : AppColors.muted(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
            ),
            const SizedBox(height: 2),
            Text(time,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Редактор своего графика «N через M»: пресеты, счётчики и превью на 14 дней.
class CycleEditor extends StatelessWidget {
  const CycleEditor({
    required this.on,
    required this.off,
    required this.start,
    required this.palette,
    required this.onChanged,
  });

  final int on;
  final int off;
  final DateTime start;
  final GoalPalette palette;
  final void Function(int on, int off) onChanged;

  static const _presets = <(int, int)>[(2, 2), (3, 1), (1, 2), (5, 2), (3, 3), (1, 3)];
  static const _max = 30;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final t = todayDay();
    final from = start.isAfter(t) ? start : t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              GestureDetector(
                onTap: () => onChanged(p.$1, p.$2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: p.$1 == on && p.$2 == off ? palette.gradient : null,
                    color: p.$1 == on && p.$2 == off ? null : AppColors.muted(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${p.$1}/${p.$2}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: p.$1 == on && p.$2 == off
                          ? Colors.white
                          : th.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        StepperRow(
          label: 'Выполнять',
          value: on,
          palette: palette,
          onMinus: on > 1 ? () => onChanged(on - 1, off) : null,
          onPlus: on < _max ? () => onChanged(on + 1, off) : null,
        ),
        const SizedBox(height: 8),
        StepperRow(
          label: 'Отдыхать',
          value: off,
          palette: palette,
          onMinus: off > 1 ? () => onChanged(on, off - 1) : null,
          onPlus: off < _max ? () => onChanged(on, off + 1) : null,
        ),
        const SizedBox(height: 14),
        Text(
          'Ближайшие 14 дней',
          style: th.textTheme.labelMedium?.copyWith(color: th.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 14; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: Builder(builder: (_) {
                  final d = addDays(from, i);
                  final work = daysBetween(start, d) % (on + off) < on;
                  return Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 0.7,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: work ? palette.gradient : null,
                            color: work ? null : AppColors.muted(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: d == t ? FontWeight.w800 : FontWeight.w500,
                          color: d == t ? palette.a : th.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class StepperRow extends StatelessWidget {
  const StepperRow({
    required this.label,
    required this.value,
    required this.palette,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final GoalPalette palette;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    Widget btn(IconData icon, VoidCallback? onTap) => Material(
          color: AppColors.muted(context),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon,
                  size: 20,
                  color: onTap == null
                      ? th.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                      : th.colorScheme.onSurface),
            ),
          ),
        );
    return Row(
      children: [
        Expanded(child: Text(label, style: th.textTheme.bodyLarge)),
        btn(Icons.remove_rounded, onMinus),
        SizedBox(
          width: 76,
          child: Text(
            daysWord(value),
            textAlign: TextAlign.center,
            style: th.textTheme.titleMedium?.copyWith(color: palette.a, fontWeight: FontWeight.w800),
          ),
        ),
        btn(Icons.add_rounded, onPlus),
      ],
    );
  }
}
