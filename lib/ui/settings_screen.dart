import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../state/app_settings.dart';
import '../state/goal_store.dart';
import 'color_picker.dart';
import 'theme.dart';
import 'widgets.dart';

/// Подписи вариантов переноса — общие для настроек и редактора цели.
const carryTitles = {
  CarryMode.shift: 'Переносить и сдвигать график',
  CarryMode.keep: 'Переносить, график не менять',
  CarryMode.skip: 'Не переносить',
};

const carryHints = {
  CarryMode.shift: 'Цель переедет на завтра, весь график и срок сдвинутся на день',
  CarryMode.keep: 'Цель переедет на завтра, следующие дни — по прежнему плану',
  CarryMode.skip: 'Пропуск засчитается, цель ждёт следующего дня по графику',
};

const carryIcons = {
  CarryMode.shift: Icons.fast_forward_rounded,
  CarryMode.keep: Icons.redo_rounded,
  CarryMode.skip: Icons.block_rounded,
};

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final GoalStore store;

  Future<void> _setIcon(BuildContext context, String key) async {
    final s = AppSettings.instance;
    if (s.icon == key) return;
    final ok = await s.setIcon(key);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok
            ? (Platform.isAndroid
                ? 'Иконка изменится через пару секунд. Иногда приложение при этом закрывается.'
                : 'Иконка изменена')
            : 'Не получилось сменить иконку'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Настройки', style: th.textTheme.displaySmall),
            ),

            // ---- Оформление ----
            const SectionTitle('Оформление'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Тема', style: th.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  _Pills<ThemeMode>(
                    value: s.themeMode,
                    options: const {
                      ThemeMode.system: 'Как в системе',
                      ThemeMode.light: 'Светлая',
                      ThemeMode.dark: 'Тёмная',
                    },
                    icons: const {
                      ThemeMode.system: Icons.brightness_auto_rounded,
                      ThemeMode.light: Icons.light_mode_rounded,
                      ThemeMode.dark: Icons.dark_mode_rounded,
                    },
                    onChanged: s.setThemeMode,
                  ),
                  const SizedBox(height: 18),
                  Text('Акцентный цвет', style: th.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  ColorRow(
                    index: s.accent,
                    custom: s.accentCustom,
                    size: 40,
                    onPreset: s.setAccent,
                    onCustom: s.setAccentCustom,
                  ),
                ],
              ),
            ),

            // ---- Иконка ----
            const SectionTitle('Иконка приложения'),
            AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final v in appIconVariants)
                    GestureDetector(
                      onTap: () => _setIcon(context, v.key),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: s.icon == v.key ? v.a : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: AppIconPreview(variant: v, size: 50),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            v.name,
                            style: th.textTheme.labelSmall?.copyWith(
                              fontWeight: s.icon == v.key ? FontWeight.w800 : FontWeight.w500,
                              color: s.icon == v.key
                                  ? th.colorScheme.onSurface
                                  : th.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ---- Цели ----
            const SectionTitle('Цели'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Выбор времени напоминания', style: th.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  _Pills<TimePickerStyle>(
                    value: s.timeStyle,
                    options: const {
                      TimePickerStyle.wheel: 'Колесо',
                      TimePickerStyle.dial: 'Циферблат',
                    },
                    icons: const {
                      TimePickerStyle.wheel: Icons.view_day_rounded,
                      TimePickerStyle.dial: Icons.access_time_rounded,
                    },
                    onChanged: s.setTimeStyle,
                  ),
                  const SizedBox(height: 18),
                  Text('Если пропустить день — для новых целей', style: th.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  CarryPicker(
                    value: s.defaultCarry,
                    palette: brandPalette(),
                    onChanged: s.setDefaultCarry,
                  ),
                ],
              ),
            ),

            // ---- Экран блокировки ----
            const SectionTitle('Экран блокировки'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: th.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Цели на экране блокировки', style: th.textTheme.bodyLarge),
                        Text(
                          Platform.isIOS
                              ? 'Dynamic Island и экран блокировки'
                              : 'Постоянное уведомление со списком целей',
                          style: th.textTheme.bodySmall
                              ?.copyWith(color: th.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.lockScreen,
                    onChanged: (v) async {
                      await s.setLockScreen(v);
                      await store.refresh();
                    },
                  ),
                ],
              ),
            ),

            if (Platform.isAndroid) ...[
              const SectionTitle('Виджет на рабочем столе'),
              _WidgetStyleCard(store: store),
            ],

            const SizedBox(height: 28),
            Center(
              child: Text(
                'Напоминатор 1.0',
                style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Выбор одного из вариантов «таблетками».
class _Pills<T> extends StatelessWidget {
  const _Pills({
    required this.value,
    required this.options,
    required this.onChanged,
    this.icons = const {},
  });

  final T value;
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final pal = brandPalette();
    return Row(
      children: [
        for (final e in options.entries) ...[
          if (e.key != options.keys.first) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 64,
                decoration: BoxDecoration(
                  gradient: e.key == value ? pal.gradient : null,
                  color: e.key == value ? null : AppColors.muted(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icons[e.key] != null)
                      Icon(icons[e.key],
                          size: 22,
                          color: e.key == value ? Colors.white : th.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: e.key == value ? Colors.white : th.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Выбор поведения при пропуске: три карточки с пояснением.
class CarryPicker extends StatelessWidget {
  const CarryPicker({
    super.key,
    required this.value,
    required this.palette,
    required this.onChanged,
  });

  final CarryMode value;
  final GoalPalette palette;
  final ValueChanged<CarryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Column(
      children: [
        for (final m in CarryMode.values) ...[
          if (m != CarryMode.values.first) const SizedBox(height: 8),
          GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: m == value
                    ? palette.a.withValues(alpha: 0.10)
                    : AppColors.muted(context).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: m == value ? palette.a : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: m == value ? palette.gradient : null,
                      color: m == value ? null : AppColors.card(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(carryIcons[m],
                        size: 20,
                        color: m == value ? Colors.white : th.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(carryTitles[m]!,
                            style: th.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(carryHints[m]!,
                            style: th.textTheme.bodySmall
                                ?.copyWith(color: th.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    m == value ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: m == value ? palette.a : th.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Превью иконки приложения: градиент + кольцо с точкой (как в tool/make_icons.py).
class AppIconPreview extends StatelessWidget {
  const AppIconPreview({super.key, required this.variant, this.size = 56});
  final AppIconVariant variant;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.225),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [variant.a, variant.b],
        ),
      ),
      child: CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.28;
    final w = size.width * 0.10;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 1.5, false, paint);
    final a = (-90 - 38) * math.pi / 180;
    canvas.drawCircle(
      c + Offset(math.cos(a) * r, math.sin(a) * r),
      w * 0.55,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}

/// Оформление Android-виджета: прозрачность, оттенок, пастельный ↔ тёмный. С живым превью.
class _WidgetStyleCard extends StatefulWidget {
  const _WidgetStyleCard({required this.store});
  final GoalStore store;

  @override
  State<_WidgetStyleCard> createState() => _WidgetStyleCardState();
}

class _WidgetStyleCardState extends State<_WidgetStyleCard> {
  final s = AppSettings.instance;
  late bool _custom = s.widgetCustom;
  late double _hue = s.widgetHue;
  late double _tone = s.widgetTone;
  late double _opacity = s.widgetOpacity;

  Future<void> _commit() async {
    await s.setWidgetStyle(custom: _custom, hue: _hue, tone: _tone, opacity: _opacity);
    await widget.store.refresh(); // перерисует виджет
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final base = _custom ? toneColor(_hue, _tone) : AppColors.card(context);
    final bg = _custom ? base.withValues(alpha: _opacity) : base;
    final dark = base.computeLuminance() < 0.45;
    final text = _custom ? (dark ? Colors.white : const Color(0xFF16161D)) : th.colorScheme.onSurface;
    final muted = text.withValues(alpha: 0.6);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Превью на «обоях»
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFFF472B6)],
                ),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Сегодня',
                              style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        Text('2 из 4',
                            style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: 0.5,
                        minHeight: 5,
                        backgroundColor: text.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final (title, done, color) in const [
                      ('Зарядка', true, Color(0xFF22C55E)),
                      ('Английский', true, Color(0xFF6366F1)),
                      ('Прочитать 20 страниц', false, Color(0xFFF97316)),
                    ])
                      SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(title,
                                  style: TextStyle(color: done ? muted : text, fontSize: 14)),
                            ),
                            Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: done ? color : muted, size: 22),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('Своё оформление', style: th.textTheme.bodyLarge)),
              Switch(
                value: _custom,
                onChanged: (v) {
                  setState(() => _custom = v);
                  _commit();
                },
              ),
            ],
          ),
          if (!_custom)
            Text('Сейчас виджет повторяет светлую или тёмную тему телефона.',
                style: th.textTheme.bodySmall?.copyWith(color: th.colorScheme.onSurfaceVariant))
          else ...[
            const SizedBox(height: 4),
            Text('Цвет', style: th.textTheme.labelLarge),
            const SizedBox(height: 6),
            GradientSlider(
              value: _hue / 360,
              colors: rainbow,
              thumbColor: toneColor(_hue, 0.5),
              onChanged: (v) => setState(() => _hue = v * 360),
              onChangeEnd: (_) => _commit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Пастельный', style: th.textTheme.labelLarge),
                const Spacer(),
                Text('Тёмный', style: th.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            GradientSlider(
              value: _tone,
              colors: toneScale(_hue),
              thumbColor: base,
              onChanged: (v) => setState(() => _tone = v),
              onChangeEnd: (_) => _commit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Прозрачность', style: th.textTheme.labelLarge),
                const Spacer(),
                Text('${((1 - _opacity) * 100).round()}%', style: th.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            GradientSlider(
              // слева непрозрачный, справа полностью прозрачный
              value: 1 - _opacity,
              colors: [base, base.withValues(alpha: 0)],
              checkerboard: true,
              thumbColor: bg,
              onChanged: (v) => setState(() => _opacity = 1 - v),
              onChangeEnd: (_) => _commit(),
            ),
          ],
        ],
      ),
    );
  }
}
