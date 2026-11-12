import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../models/day.dart';
import '../models/goal.dart' show RepeatType;
import '../services/alarm_bridge.dart';
import '../state/alarm_store.dart';
import 'format.dart';
import 'schedule_picker.dart';
import 'theme.dart';
import 'widgets.dart';

class EditAlarmScreen extends StatefulWidget {
  const EditAlarmScreen({super.key, required this.store, this.alarm});
  final AlarmStore store;
  final AlarmItem? alarm;

  @override
  State<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends State<EditAlarmScreen> {
  late int _minutes;
  late final TextEditingController _label;
  late RepeatType _repeat;
  late Set<int> _weekdays;
  late int _cycleOn;
  late int _cycleOff;
  late DateTime _start;
  late String _sound;
  late String _soundTitle;
  late bool _vibrate;
  late bool _ramp;
  late int _snooze;
  late int _color;
  String? _error;

  bool get _isNew => widget.alarm == null;
  GoalPalette get _pal => goalPalettes[_color % goalPalettes.length];

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    final t = todayDay();
    _minutes = a?.minutes ?? 7 * 60;
    _label = TextEditingController(text: a?.label ?? '');
    _repeat = a?.repeat ?? RepeatType.weekdays;
    _weekdays = {...?a?.weekdays};
    if (_weekdays.isEmpty) _weekdays = {1, 2, 3, 4, 5};
    _cycleOn = a?.cycleOn ?? 2;
    _cycleOff = a?.cycleOff ?? 2;
    _start = a?.startDate ?? t;
    _sound = a?.sound ?? 'builtin:soft';
    _soundTitle = a?.soundTitle ?? builtinAlarmSounds['soft']!;
    _vibrate = a?.vibrate ?? true;
    _ramp = a?.ramp ?? true;
    _snooze = a?.snoozeMinutes ?? 10;
    _color = a?.colorIndex ?? (widget.store.alarms.length % goalPalettes.length);
  }

  @override
  void dispose() {
    _label.dispose();
    AlarmBridge.stopPreview();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final r = await pickTimeMinutes(context,
        current: _minutes, title: 'Время будильника', minuteInterval: 1);
    if (r != null) setState(() => _minutes = r);
  }

  Future<void> _pickStart() async {
    final t = todayDay();
    final first = _start.isBefore(t) ? _start : t;
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: first,
      lastDate: addDays(t, 3650),
      helpText: 'Начало графика',
    );
    if (picked != null) setState(() => _start = dayOf(picked));
  }

  Future<void> _pickSound() async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card(context),
      builder: (c) => _SoundSheet(current: _sound, palette: _pal),
    );
    await AlarmBridge.stopPreview();
    if (result != null) {
      setState(() {
        _sound = result.$1;
        _soundTitle = result.$2;
      });
    }
  }

  Future<void> _save() async {
    if (_repeat == RepeatType.weekdays && _weekdays.isEmpty) {
      setState(() => _error = 'Выберите хотя бы один день недели');
      return;
    }
    final store = widget.store;
    final old = widget.alarm;
    if (old == null) {
      await store.add(AlarmItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        nativeId: store.nextNativeId(),
        minutes: _minutes,
        label: _label.text.trim(),
        repeat: _repeat,
        weekdays: {..._weekdays},
        cycleOn: _cycleOn,
        cycleOff: _cycleOff,
        startDate: _start,
        sound: _sound,
        soundTitle: _soundTitle,
        vibrate: _vibrate,
        ramp: _ramp,
        snoozeMinutes: _snooze,
        colorIndex: _color,
      ));
    } else {
      old
        ..minutes = _minutes
        ..label = _label.text.trim()
        ..repeat = _repeat
        ..weekdays = {..._weekdays}
        ..cycleOn = _cycleOn
        ..cycleOff = _cycleOff
        ..startDate = _start
        ..sound = _sound
        ..soundTitle = _soundTitle
        ..vibrate = _vibrate
        ..ramp = _ramp
        ..snoozeMinutes = _snooze
        ..colorIndex = _color
        ..enabled = true;
      await store.update(old);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить будильник?'),
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
    if (ok == true) {
      await widget.store.delete(widget.alarm!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _switchRow(IconData icon, String title, String? hint, bool value, ValueChanged<bool> onChanged) {
    final th = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: th.colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: th.textTheme.bodyLarge),
              if (hint != null)
                Text(hint,
                    style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final pal = _pal;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новый будильник' : 'Будильник'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          // ---- Время ----
          AppCard(
            gradient: pal.gradient,
            onTap: _pickTime,
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Column(
              children: [
                Text(
                  formatTime(_minutes),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Нажмите, чтобы изменить время',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _label,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Название (необязательно), например «Подъём»',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: goalPalettes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        width: 36,
                        height: 36,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == _color ? goalPalettes[i].a : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: goalPalettes[i].gradient,
                          ),
                          child: i == _color
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ---- График ----
          const SectionTitle('Когда звонить'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChoiceRow<RepeatType>(
                  value: _repeat,
                  palette: pal,
                  options: const {
                    RepeatType.daily: 'Каждый день',
                    RepeatType.everyOtherDay: 'Через день',
                  },
                  onChanged: (v) => setState(() => _repeat = v),
                ),
                const SizedBox(height: 8),
                ChoiceRow<RepeatType>(
                  value: _repeat,
                  palette: pal,
                  options: const {
                    RepeatType.weekdays: 'Дни недели',
                    RepeatType.cycle: 'Свой график',
                  },
                  onChanged: (v) => setState(() => _repeat = v),
                ),
                if (_repeat == RepeatType.weekdays)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var w = 1; w <= 7; w++)
                          DayToggle(
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
                if (_repeat == RepeatType.cycle)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: CycleEditor(
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
                if (_repeat == RepeatType.everyOtherDay || _repeat == RepeatType.cycle) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  SettingTile(
                    icon: Icons.event_rounded,
                    title: 'Начало графика',
                    value: formatRelative(_start),
                    onTap: _pickStart,
                  ),
                ],
              ],
            ),
          ),

          // ---- Звук ----
          const SectionTitle('Звук'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SettingTile(
                    icon: Icons.music_note_rounded,
                    title: 'Мелодия',
                    value: _soundTitle,
                    onTap: _pickSound,
                  ),
                ),
                const Divider(),
                _switchRow(Icons.trending_up_rounded, 'Нарастающая громкость',
                    'Начинает тихо и за 30 секунд доходит до максимума', _ramp,
                    (v) => setState(() => _ramp = v)),
                const Divider(),
                _switchRow(Icons.vibration_rounded, 'Вибрация', null, _vibrate,
                    (v) => setState(() => _vibrate = v)),
              ],
            ),
          ),

          const SectionTitle('Отложить на'),
          AppCard(
            child: ChoiceRow<int>(
              value: _snooze,
              palette: pal,
              options: const {5: '5 мин', 10: '10 мин', 15: '15 мин', 20: '20 мин'},
              onChanged: (v) => setState(() => _snooze = v),
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
            child: Text(_isNew ? 'Поставить будильник' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

/// Выбор мелодии с прослушиванием.
class _SoundSheet extends StatefulWidget {
  const _SoundSheet({required this.current, required this.palette});
  final String current;
  final GoalPalette palette;

  @override
  State<_SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<_SoundSheet> {
  String? _playing;

  Future<void> _toggle(String sound) async {
    if (_playing == sound) {
      await AlarmBridge.stopPreview();
      setState(() => _playing = null);
    } else {
      await AlarmBridge.preview(sound);
      setState(() => _playing = sound);
    }
  }

  Future<void> _pickNative(String kind) async {
    await AlarmBridge.stopPreview();
    final res = await AlarmBridge.pick(kind);
    if (res != null && mounted) Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final pal = widget.palette;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Мелодия', style: th.textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          for (final e in builtinAlarmSounds.entries)
            Builder(builder: (_) {
              final sound = 'builtin:${e.key}';
              final selected = widget.current == sound;
              final playing = _playing == sound;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected ? pal.a.withValues(alpha: 0.10) : AppColors.muted(context).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(context, (sound, e.value)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => _toggle(sound),
                            icon: Icon(
                              playing ? Icons.stop_circle_rounded : Icons.play_circle_rounded,
                              size: 34,
                              color: pal.a,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.value,
                                    style: th.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                Text(builtinAlarmHints[e.key] ?? '',
                                    style: th.textTheme.bodySmall
                                        ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (selected) Icon(Icons.check_circle_rounded, color: pal.a),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.library_music_rounded),
              title: const Text('Системная мелодия…'),
              onTap: () => _pickNative('pickSystem'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Свой файл…'),
              onTap: () => _pickNative('pickFile'),
            ),
          ],
        ],
      ),
    );
  }
}
