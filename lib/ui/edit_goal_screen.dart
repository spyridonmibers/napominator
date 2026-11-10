import 'package:flutter/material.dart';

import '../models/day.dart';
import '../models/goal.dart';
import '../state/goal_store.dart';
import 'format.dart';

class EditGoalScreen extends StatefulWidget {
  const EditGoalScreen({super.key, required this.store, this.goal});
  final GoalStore store;
  final Goal? goal;

  @override
  State<EditGoalScreen> createState() => _EditGoalScreenState();
}

class _EditGoalScreenState extends State<EditGoalScreen> {
  late final TextEditingController _title;
  late final TextEditingController _count;
  late RepeatType _repeat;
  late Set<int> _weekdays;
  late DateTime _start;
  late DeadlineType _deadline;
  DateTime? _end;
  int? _reminder;
  String? _error;

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
  }

  @override
  void dispose() {
    _title.dispose();
    _count.dispose();
    super.dispose();
  }

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
    if (picked != null) setState(() => _start = dayOf(picked));
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end!.isBefore(_start) ? _start : _end!,
      firstDate: _start,
      lastDate: addDays(_start, 3650),
      helpText: 'Дата окончания',
    );
    if (picked != null) setState(() => _end = dayOf(picked));
  }

  Future<void> _pickTime() async {
    final m = _reminder ?? 9 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: 'Время напоминания',
    );
    if (picked != null) setState(() => _reminder = picked.hour * 60 + picked.minute);
  }

  void _fail(String msg) => setState(() => _error = msg);

  Future<void> _save() async {
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
    if (_deadline == DeadlineType.date && _end!.isBefore(_start)) {
      return _fail('Дата окончания раньше даты начала');
    }

    final store = widget.store;
    final old = widget.goal;
    if (old == null) {
      if (!store.canAdd) {
        return _fail('Можно не больше ${GoalStore.maxGoals} целей');
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
      );
      await store.add(g);
    } else {
      final patternChanged = old.repeat != _repeat ||
          old.startDate != _start ||
          (_repeat == RepeatType.weekdays &&
              (old.weekdays.length != _weekdays.length ||
                  !old.weekdays.containsAll(_weekdays)));
      old
        ..title = title
        ..repeat = _repeat
        ..weekdays = {..._weekdays}
        ..startDate = _start
        ..deadlineType = _deadline
        ..endDate = _deadline == DeadlineType.date ? _end : null
        ..targetCount = count
        ..reminderMinutes = _reminder;
      await store.update(old, patternChanged: patternChanged);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить цель?'),
        content: Text('«${widget.goal!.title}» и вся её история будут удалены.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) {
      await widget.store.delete(widget.goal!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новая цель' : 'Цель'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            autofocus: _isNew,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Например: 20 минут английского',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text('Периодичность', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<RepeatType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: RepeatType.daily, label: Text('Каждый день')),
              ButtonSegment(value: RepeatType.everyOtherDay, label: Text('Через день')),
              ButtonSegment(value: RepeatType.weekdays, label: Text('Дни недели')),
            ],
            selected: {_repeat},
            onSelectionChanged: (s) => setState(() => _repeat = s.first),
          ),
          if (_repeat == RepeatType.weekdays) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var w = 1; w <= 7; w++)
                  FilterChip(
                    label: Text(weekdayShort[w - 1]),
                    selected: _weekdays.contains(w),
                    onSelected: (v) => setState(() {
                      v ? _weekdays.add(w) : _weekdays.remove(w);
                    }),
                  ),
              ],
            ),
            if (!_isNew && widget.goal!.shift > 0 && widget.goal!.repeat == RepeatType.weekdays)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Из-за переносов сейчас график сдвинут на '
                  '${daysWord(widget.goal!.shift)}. Если поменять дни, сдвиг сбросится.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_arrow_outlined),
            title: const Text('Начало'),
            subtitle: Text(formatRelative(_start)),
            onTap: _pickStart,
          ),
          const Divider(),
          Text('Срок', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<DeadlineType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: DeadlineType.none, label: Text('Без срока')),
              ButtonSegment(value: DeadlineType.date, label: Text('До даты')),
              ButtonSegment(value: DeadlineType.count, label: Text('N раз')),
            ],
            selected: {_deadline},
            onSelectionChanged: (s) => setState(() => _deadline = s.first),
          ),
          const SizedBox(height: 8),
          if (_deadline == DeadlineType.date)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Дата окончания'),
              subtitle: Text(
                  '${formatDate(_end!)} — при пропуске дня сдвигается на день'),
              onTap: _pickEnd,
            ),
          if (_deadline == DeadlineType.count)
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Сколько раз выполнить',
                border: OutlineInputBorder(),
              ),
            ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Напоминание'),
            subtitle: const Text('Висит в уведомлениях, пока цель не отмечена'),
            value: _reminder != null,
            onChanged: (v) => setState(() => _reminder = v ? 9 * 60 : null),
          ),
          if (_reminder != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Время'),
              subtitle: Text(formatTime(_reminder!)),
              onTap: _pickTime,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (!_isNew) ...[
            const SizedBox(height: 16),
            Text(
              'Выполнено раз: ${widget.goal!.completions.length} · '
              'перенесено дней: ${widget.goal!.missedDays}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
