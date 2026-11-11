import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../state/app_settings.dart';
import '../state/goal_store.dart';
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
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < goalPalettes.length; i++)
                        GestureDetector(
                          onTap: () => s.setAccent(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 40,
                            height: 40,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: s.accent == i ? goalPalettes[i].a : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: goalPalettes[i].gradient,
                              ),
                              child: s.accent == i
                                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                  : null,
                            ),
                          ),
                        ),
                    ],
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
