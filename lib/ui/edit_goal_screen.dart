import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/day.dart';
import '../models/goal.dart';
import '../state/app_settings.dart';
import '../state/goal_store.dart';
import 'format.dart';
import 'settings_screen.dart' show CarryPicker;
import 'theme.dart';
import 'widgets.dart';

class EditGoalScreen extends StatefulWidget {
  const EditGoalScreen({super.key, required this.store, this.goal});
  final GoalStore store;
  final Goal? goal;

  @override
  State<EditGoalScreen> createState() => _EditGoalScreenState();
}

class _EditGoalScreenState extends State<EditGoalScreen> {
  static const _timePresets = <(String, int)>[
    ('Утро', 8 * 60),
    ('День', 13 * 60),
    ('Вечер', 19 * 60),
    ('Перед сном', 22 * 60),
  ];

  late final TextEditingController _title;
  late final TextEditingController _count;
  late RepeatType _repeat;
  late Set<int> _weekdays;
  late DateTime _start;
  late DeadlineType _deadline;
  late DateTime _end;
  int? _reminder;
  late int _color;
  late String _icon;
  late int _cycleOn;
  late int _cycleOff;
  late CarryMode _carry;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.goal == null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    final t = todayDay();
    _title = TextEditingController(text: g?.title ?? '');
    _count = TextEditingController(text: (g?.targetCount ?? 30).toString());
    _repeat = g?.repeat ?? RepeatType.daily;
    _weekdays = {...?g?.weekdays};
    if (_weekdays.isEmpty) _weekdays = {t.weekday};
    _start = g?.startDate ?? t;
    _deadline = g?.deadlineType ?? DeadlineType.none;
    _end = g?.endDate ?? addDays(t, 29);
    _reminder = g == null ? 9 * 60 : g.reminderMinutes;
    _color = g?.colorIndex ?? (widget.store.goals.length % goalPalettes.length);
    _icon = g?.icon ?? 'target';
    _cycleOn = g?.cycleOn ?? 2;
    _cycleOff = g?.cycleOff ?? 2;
    _carry = g?.carry ?? AppSettings.instance.defaultCarry;
  }

  @override
  void dispose() {
    _title.dispose();
    _count.dispose();
    super.dispose();
  }

  GoalPalette get _palette => goalPalettes[_color % goalPalettes.length];

  Future<void> _pickStart() async {
    final t = todayDay();
    final first = _start.isBefore(t) ? _start : t;
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: first,
      lastDate: addDays(t, 3650),
      helpText: 'Дата начала',
    );
    if (picked != null) {
      setState(() {
        _start = dayOf(picked);
        if (_end.isBefore(_start)) _end = _start;
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end.isBefore(_start) ? _start : _end,
      firstDate: _start,
      lastDate: addDays(_start, 3650),
      helpText: 'Дата окончания',
    );
    if (picked != null) setState(() => _end = dayOf(picked));
  }

  /// Выбор времени: колесо или циферблат — как выбрано в настройках.
  Future<void> _pickTime() async {
    if (AppSettings.instance.timeStyle == TimePickerStyle.dial) {
      final cur = _reminder ?? 9 * 60;
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
        helpText: 'Время напоминания',
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked != null) {
        setState(() => _reminder = picked.hour * 60 + picked.minute);
      }
      return;
    }
    final m = ((_reminder ?? 9 * 60) ~/ 5) * 5;
    var selected = m;
    final result = await showModalBottomSheet<int>(
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
                Text('Время напоминания', style: th.textTheme.titleLarge),
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
                      minuteInterval: 5,
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
    if (result != null) setState(() => _reminder = result);
  }

  Future<void> _pickIcon() async {
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card(context),
      builder: (c) {
        final th = Theme.of(c);
        return SizedBox(
          height: MediaQuery.sizeOf(c).height * 0.6,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(c).bottom),
            children: [
              Text('Иконка', style: th.textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in goalIcons.entries)
                    GestureDetector(
                      onTap: () => Navigator.pop(c, e.key),
                      child: e.key == _icon
                          ? GoalBadge(palette: _palette, icon: e.value, size: 50)
                          : Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.muted(c),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(e.value, color: th.colorScheme.onSurfaceVariant),
                            ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (key != null) setState(() => _icon = key);
  }

  void _fail(String msg) => setState(() => _error = msg);

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) return _fail('Введите название цели');
    if (_repeat == RepeatType.weekdays && _weekdays.isEmpty) {
      return _fail('Выберите хотя бы один день недели');
    }
    int? count;
    if (_deadline == DeadlineType.count) {
      count = int.tryParse(_count.text.trim());
      if (count == null || count < 1 || count > 10000) {
        return _fail('Количество раз — число от 1 до 10000');
      }
    }
    if (_deadline == DeadlineType.date && _end.isBefore(_start)) {
      return _fail('Дата окончания раньше даты начала');
    }

    final store = widget.store;
    final old = widget.goal;
    _saving = true;
    if (old == null) {
      if (!store.canAdd) {
        _saving = false;
        return _fail('Можно не больше ${GoalStore.maxGoals} активных целей');
      }
      final g = Goal(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        notifId: store.nextNotifId(),
        title: title,
        repeat: _repeat,
        weekdays: {..._weekdays},
        startDate: _start,
        deadlineType: _deadline,
        endDate: _deadline == DeadlineType.date ? _end : null,
        targetCount: count,
        reminderMinutes: _reminder,
        nextDue: _start,
        colorIndex: _color,
        icon: _icon,
        cycleOn: _cycleOn,
        cycleOff: _cycleOff,
        carry: _carry,
      );
      await store.add(g);
    } else {
      final patternChanged = old.repeat != _repeat ||
          old.startDate != _start ||
          (_repeat == RepeatType.weekdays &&
              (old.weekdays.length != _weekdays.length ||
                  !old.weekdays.containsAll(_weekdays))) ||
          (_repeat == RepeatType.cycle &&
              (old.cycleOn != _cycleOn || old.cycleOff != _cycleOff));
      old
        ..title = title
        ..repeat = _repeat
        ..weekdays = {..._weekdays}
        ..startDate = _start
        ..deadlineType = _deadline
        ..endDate = _deadline == DeadlineType.date ? _end : null
        ..targetCount = count
        ..reminderMinutes = _reminder
        ..colorIndex = _color
        ..icon = _icon
        ..cycleOn = _cycleOn
        ..cycleOff = _cycleOff
        ..carry = _carry;
      await store.update(old, patternChanged: patternChanged);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final pal = _palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новая цель' : 'Изменить цель'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        // Снизу — отступ под системную панель навигации, чтобы кнопка не обрезалась.
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          // ---- Внешний вид и название ----
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickIcon,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GoalBadge(palette: pal, icon: goalIcons[_icon] ?? Icons.track_changes_rounded, size: 76),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.card(context),
                            shape: BoxShape.circle,
                            boxShadow: AppColors.shadow(context),
                          ),
                          child: Icon(Icons.edit_rounded, size: 15, color: th.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _title,
                  autofocus: _isNew,
                  maxLength: 60,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.sentences,
                  style: th.textTheme.titleLarge,
                  decoration: const InputDecoration(
                    hintText: 'Название цели',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: goalPalettes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final selected = i == _color;
                      return GestureDetector(
                        onTap: () => setState(() => _color = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? goalPalettes[i].a : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: goalPalettes[i].gradient,
                            ),
                            child: selected
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ---- Периодичность ----
          const SectionTitle('Периодичность'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChoiceRow<RepeatType>(
                  value: _repeat,
                  palette: pal,
                  options: const {
                    RepeatType.daily: 'Каждый день',
                    RepeatType.everyOtherDay: 'Через день',
                  },
                  onChanged: (v) => setState(() => _repeat = v),
                ),
                const SizedBox(height: 8),
                _ChoiceRow<RepeatType>(
                  value: _repeat,
                  palette: pal,
                  options: const {
                    RepeatType.weekdays: 'Дни недели',
                    RepeatType.cycle: 'Свой график',
                  },
                  onChanged: (v) => setState(() => _repeat = v),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: switch (_repeat) {
                    RepeatType.weekdays => Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (var w = 1; w <= 7; w++)
                              _DayToggle(
                                label: weekdayShort[w - 1],
                                selected: _weekdays.contains(w),
                                palette: pal,
                                onTap: () => setState(() {
                                  if (!_weekdays.remove(w)) _weekdays.add(w);
                                }),
                              ),
                          ],
                        ),
                      ),
                    RepeatType.cycle => Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _CycleEditor(
                          on: _cycleOn,
                          off: _cycleOff,
                          start: _start,
                          palette: pal,
                          onChanged: (on, off) => setState(() {
                            _cycleOn = on;
                            _cycleOff = off;
                          }),
                        ),
                      ),
                    _ => const SizedBox(width: double.infinity),
                  },
                ),
                if (!_isNew &&
                    widget.goal!.shift > 0 &&
                    (widget.goal!.repeat == RepeatType.weekdays ||
                        widget.goal!.repeat == RepeatType.cycle))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Из-за переносов график сейчас сдвинут на ${daysWord(widget.goal!.shift)}. '
                      'Если поменять расписание, сдвиг сбросится.',
                      style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 8),
                const Divider(),
                _SettingTile(
                  icon: Icons.event_rounded,
                  title: 'Начало',
                  value: formatRelative(_start),
                  onTap: _pickStart,
                ),
              ],
            ),
          ),

          // ---- Срок ----
          const SectionTitle('Срок'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChoiceRow<DeadlineType>(
                  value: _deadline,
                  palette: pal,
                  options: const {
                    DeadlineType.none: 'Без срока',
                    DeadlineType.date: 'До даты',
                    DeadlineType.count: 'N раз',
                  },
                  onChanged: (v) => setState(() => _deadline = v),
                ),
                if (_deadline == DeadlineType.date) ...[
                  const SizedBox(height: 8),
                  _SettingTile(
                    icon: Icons.flag_rounded,
                    title: 'Дата окончания',
                    value: formatDate(_end),
                    onTap: _pickEnd,
                  ),
                  Text(
                    'Каждый пропущенный день сдвигает окончание на день.',
                    style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant),
                  ),
                ],
                if (_deadline == DeadlineType.count) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Сколько раз выполнить',
                      suffixText: 'раз',
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ---- Пропуск ----
          const SectionTitle('Если пропустить день'),
          AppCard(
            child: CarryPicker(
              value: _carry,
              palette: pal,
              onChanged: (v) => setState(() => _carry = v),
            ),
          ),

          // ---- Напоминание ----
          const SectionTitle('Напоминание'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_rounded, color: th.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Напоминать', style: th.textTheme.bodyLarge),
                          Text('Висит, пока цель не отмечена',
                              style: th.textTheme.bodySmall
                                  ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _reminder != null,
                      onChanged: (v) => setState(() => _reminder = v ? 9 * 60 : null),
                    ),
                  ],
                ),
                if (_reminder != null) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.schedule_rounded, color: th.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 14),
                            Expanded(child: Text('Время', style: th.textTheme.bodyLarge)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: pal.a.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                formatTime(_reminder!),
                                style: th.textTheme.titleLarge?.copyWith(color: pal.a),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 8, 12),
                    child: Row(
                      children: [
                        for (final p in _timePresets) ...[
                          if (p != _timePresets.first) const SizedBox(width: 8),
                          Expanded(
                            child: _TimePreset(
                              label: p.$1,
                              time: formatTime(p.$2),
                              selected: _reminder == p.$2,
                              palette: pal,
                              onTap: () => setState(() => _reminder = p.$2),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: th.colorScheme.error, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: Text(_isNew ? 'Создать цель' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

/// Выбор одного варианта из нескольких — «таблетки» в цвете цели.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
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

class _DayToggle extends StatelessWidget {
  const _DayToggle({
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

class _SettingTile extends StatelessWidget {
  const _SettingTile({
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

class _TimePreset extends StatelessWidget {
  const _TimePreset({
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
class _CycleEditor extends StatelessWidget {
  const _CycleEditor({
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
        _Stepper(
          label: 'Выполнять',
          value: on,
          palette: palette,
          onMinus: on > 1 ? () => onChanged(on - 1, off) : null,
          onPlus: on < _max ? () => onChanged(on + 1, off) : null,
        ),
        const SizedBox(height: 8),
        _Stepper(
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

class _Stepper extends StatelessWidget {
  const _Stepper({
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
