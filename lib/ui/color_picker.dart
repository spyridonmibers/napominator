import 'package:flutter/material.dart';

import 'theme.dart';

/// Все оттенки радуги — для ползунка цвета.
const rainbow = <Color>[
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF00C7BE),
  Color(0xFF007AFF),
  Color(0xFF5856D6),
  Color(0xFFAF52DE),
  Color(0xFFFF2D55),
  Color(0xFFFF3B30),
];

/// Ползунок с градиентной дорожкой.
class GradientSlider extends StatelessWidget {
  const GradientSlider({
    super.key,
    required this.value,
    required this.colors,
    required this.onChanged,
    this.onChangeEnd,
    this.thumbColor,
    this.checkerboard = false,
  });

  /// 0..1
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? thumbColor;

  /// Шахматный фон под дорожкой — для ползунка прозрачности.
  final bool checkerboard;

  static const _height = 30.0;
  static const _track = 14.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      const pad = _height / 2;
      double toValue(double dx) => ((dx - pad) / (w - 2 * pad)).clamp(0.0, 1.0);
      final x = pad + (w - 2 * pad) * value.clamp(0.0, 1.0);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onChanged(toValue(d.localPosition.dx)),
        onTapUp: (d) => onChangeEnd?.call(toValue(d.localPosition.dx)),
        onHorizontalDragUpdate: (d) => onChanged(toValue(d.localPosition.dx)),
        onHorizontalDragEnd: (_) => onChangeEnd?.call(value),
        child: SizedBox(
          height: _height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: pad - _track / 2,
                right: pad - _track / 2,
                top: (_height - _track) / 2,
                height: _track,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_track),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (checkerboard) const CustomPaint(painter: _CheckerPainter()),
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: x - _height / 2,
                top: 0,
                width: _height,
                height: _height,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: thumbColor ?? Colors.white,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 6.0;
    final a = Paint()..color = const Color(0xFFDDDDDD);
    final b = Paint()..color = Colors.white;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final odd = ((x / cell).floor() + (y / cell).floor()).isOdd;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), odd ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter oldDelegate) => false;
}

/// Цвета для ползунка «пастельный → тёмный» при данном оттенке.
List<Color> toneScale(double hue) => [
      for (var i = 0; i <= 6; i++) toneColor(hue, i / 6),
    ];

/// Окно выбора любого цвета: оттенок + тон. Возвращает ARGB или null.
Future<int?> showColorPickerSheet(BuildContext context, {Color? initial}) {
  final start = initial ?? brandPalette().a;
  var hue = HSLColor.fromColor(start).hue;
  var tone = toneOf(start);
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.card(context),
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final th = Theme.of(c);
        final color = toneColor(hue, tone);
        final pal = paletteFromColor(color);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Свой цвет', style: th.textTheme.titleLarge),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: pal.gradient,
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: [
                        BoxShadow(
                          color: pal.a.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Оттенок', style: th.textTheme.labelLarge),
                const SizedBox(height: 6),
                GradientSlider(
                  value: hue / 360,
                  colors: rainbow,
                  thumbColor: toneColor(hue, 0.5),
                  onChanged: (v) => setState(() => hue = v * 360),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('Пастельный', style: th.textTheme.labelLarge),
                    const Spacer(),
                    Text('Тёмный', style: th.textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 6),
                GradientSlider(
                  value: tone,
                  colors: toneScale(hue),
                  thumbColor: color,
                  onChanged: (v) => setState(() => tone = v),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(c, color.toARGB32()),
                    child: const Text('Готово'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Ряд выбора цвета: 10 готовых + «свой» (радужный кружок).
class ColorRow extends StatelessWidget {
  const ColorRow({
    super.key,
    required this.index,
    required this.custom,
    required this.onPreset,
    required this.onCustom,
    this.size = 36,
  });

  final int index;
  final int? custom;
  final ValueChanged<int> onPreset;
  final ValueChanged<int> onCustom;
  final double size;

  Widget _ring({required bool selected, required Color ringColor, required Widget child}) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? ringColor : Colors.transparent, width: 2),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final customSelected = custom != null;
    final customColor = custom != null ? Color(custom!) : null;
    return SizedBox(
      height: size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < goalPalettes.length; i++) ...[
            GestureDetector(
              onTap: () => onPreset(i),
              child: _ring(
                selected: !customSelected && i == index,
                ringColor: goalPalettes[i].a,
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: goalPalettes[i].gradient),
                  child: !customSelected && i == index
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          GestureDetector(
            onTap: () async {
              final c = await showColorPickerSheet(context, initial: customColor);
              if (c != null) onCustom(c);
            },
            child: _ring(
              selected: customSelected,
              ringColor: customColor ?? Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: customColor != null
                      ? paletteFromColor(customColor).gradient
                      : const SweepGradient(colors: rainbow),
                ),
                child: Icon(
                  customSelected ? Icons.check_rounded : Icons.add_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
