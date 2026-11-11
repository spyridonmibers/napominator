import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'theme.dart';

/// Белая (в тёмной теме — графитовая) карточка со скруглением и мягкой тенью.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.gradient,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? AppColors.card(context)) : null,
        gradient: gradient,
        borderRadius: br,
        boxShadow: AppColors.shadow(context),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: br,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Иконка цели на градиентной плитке.
class GoalBadge extends StatelessWidget {
  const GoalBadge({
    super.key,
    required this.palette,
    required this.icon,
    this.size = 48,
    this.dimmed = false,
  });

  GoalBadge.of(Goal g, {super.key, this.size = 48, this.dimmed = false})
      : palette = paletteOf(g),
        icon = iconOf(g);

  final GoalPalette palette;
  final IconData icon;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: dimmed ? 0.45 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: palette.gradient,
          borderRadius: BorderRadius.circular(size * 0.32),
          boxShadow: [
            BoxShadow(
              color: palette.a.withValues(alpha: 0.35),
              blurRadius: size * 0.3,
              offset: Offset(0, size * 0.12),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.52),
      ),
    );
  }
}

/// Кольцо прогресса.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 72,
    this.stroke = 8,
    this.gradient,
    this.color,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final Gradient? gradient;
  final Color? color;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0).toDouble()),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
            value: v,
            stroke: stroke,
            track: AppColors.muted(context),
            color: c,
            gradient: gradient,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.track,
    required this.color,
    this.gradient,
  });

  final double value;
  final double stroke;
  final Color track;
  final Color color;
  final Gradient? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (gradient != null) {
      p.shader = gradient!.createShader(rect);
    } else {
      p.color = color;
    }
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Круглая кнопка отметки.
class CheckButton extends StatelessWidget {
  const CheckButton({
    super.key,
    required this.done,
    required this.palette,
    required this.onTap,
    this.size = 44,
  });

  final bool done;
  final GoalPalette palette;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: done ? 'Отменить отметку' : 'Отметить выполнение',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: done ? palette.gradient : null,
            border: done
                ? null
                : Border.all(
                    color: palette.a.withValues(alpha: 0.45), width: 2.5),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: done
                ? Icon(Icons.check_rounded,
                    key: const ValueKey('on'),
                    color: Colors.white,
                    size: size * 0.6)
                : const SizedBox.shrink(key: ValueKey('off')),
          ),
        ),
      ),
    );
  }
}

/// Заголовок секции.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: t.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Небольшая плашка с иконкой и текстом.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.icon,
    required this.color,
    this.filled = false,
  });

  final String text;
  final IconData? icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Пустое состояние экрана.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GoalBadge(palette: brandPalette(), icon: icon, size: 88),
            const SizedBox(height: 28),
            Text(title,
                textAlign: TextAlign.center,
                style: t.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: t.textTheme.bodyLarge
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant, height: 1.4),
            ),
            if (action != null) ...[
              const SizedBox(height: 28),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Тонкая полоска прогресса в цвете цели.
class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({super.key, required this.value, required this.palette});
  final double value;
  final GoalPalette palette;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Container(
        height: 6,
        decoration: BoxDecoration(
          color: AppColors.muted(context),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          width: c.maxWidth * value.clamp(0.0, 1.0),
          decoration: BoxDecoration(
            gradient: palette.gradient,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка «+» в цвете приложения — рядом с заголовком секции.
class AddGoalButton extends StatelessWidget {
  const AddGoalButton({super.key, required this.onTap, this.size = 36});
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = brandPalette();
    return Semantics(
      button: true,
      label: 'Новая цель',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: pal.gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: pal.a.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.add_rounded, color: Colors.white, size: size * 0.62),
          ),
        ),
      ),
    );
  }
}
