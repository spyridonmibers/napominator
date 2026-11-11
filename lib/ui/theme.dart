import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../state/app_settings.dart';

/// Градиент цвета цели.
class GoalPalette {
  const GoalPalette(this.name, this.a, this.b);
  final String name;
  final Color a;
  final Color b;

  Color get main => a;
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, b],
      );
}

const goalPalettes = <GoalPalette>[
  GoalPalette('Индиго', Color(0xFF6366F1), Color(0xFF8B5CF6)),
  GoalPalette('Фиалка', Color(0xFF8B5CF6), Color(0xFFD946EF)),
  GoalPalette('Роза', Color(0xFFEC4899), Color(0xFFF43F5E)),
  GoalPalette('Закат', Color(0xFFF97316), Color(0xFFEF4444)),
  GoalPalette('Янтарь', Color(0xFFF59E0B), Color(0xFFF97316)),
  GoalPalette('Мята', Color(0xFF22C55E), Color(0xFF10B981)),
  GoalPalette('Лагуна', Color(0xFF14B8A6), Color(0xFF06B6D4)),
  GoalPalette('Небо', Color(0xFF0EA5E9), Color(0xFF6366F1)),
  GoalPalette('Океан', Color(0xFF3B82F6), Color(0xFF0EA5E9)),
  GoalPalette('Графит', Color(0xFF64748B), Color(0xFF334155)),
];

GoalPalette paletteOf(Goal g) =>
    goalPalettes[g.colorIndex.abs() % goalPalettes.length];

/// Набор иконок для целей.
const goalIcons = <String, IconData>{
  'target': Icons.track_changes_rounded,
  'bolt': Icons.bolt_rounded,
  'star': Icons.star_rounded,
  'fitness': Icons.fitness_center_rounded,
  'run': Icons.directions_run_rounded,
  'walk': Icons.directions_walk_rounded,
  'bike': Icons.directions_bike_rounded,
  'pool': Icons.pool_rounded,
  'yoga': Icons.self_improvement_rounded,
  'book': Icons.menu_book_rounded,
  'school': Icons.school_rounded,
  'language': Icons.translate_rounded,
  'code': Icons.code_rounded,
  'work': Icons.work_outline_rounded,
  'write': Icons.edit_note_rounded,
  'music': Icons.music_note_rounded,
  'art': Icons.palette_rounded,
  'camera': Icons.photo_camera_rounded,
  'water': Icons.water_drop_rounded,
  'food': Icons.restaurant_rounded,
  'eco': Icons.eco_rounded,
  'sleep': Icons.bedtime_rounded,
  'sun': Icons.wb_sunny_rounded,
  'meds': Icons.medication_rounded,
  'heart': Icons.favorite_rounded,
  'mind': Icons.psychology_rounded,
  'money': Icons.savings_rounded,
  'home': Icons.home_rounded,
  'clean': Icons.cleaning_services_rounded,
  'plant': Icons.local_florist_rounded,
  'pets': Icons.pets_rounded,
  'call': Icons.call_rounded,
  'nophone': Icons.phonelink_erase_rounded,
  'nosmoke': Icons.smoke_free_rounded,
  'fish': Icons.set_meal_rounded,
  'health': Icons.health_and_safety_rounded,
  'soccer': Icons.sports_soccer_rounded,
  'movie': Icons.movie_rounded,
  'games': Icons.sports_esports_rounded,
  'payments': Icons.payments_rounded,
};

IconData iconOf(Goal g) => goalIcons[g.icon] ?? Icons.track_changes_rounded;

/// Акцентный цвет приложения (выбирается в настройках).
GoalPalette brandPalette() =>
    goalPalettes[AppSettings.instance.accent.abs() % goalPalettes.length];

/// Цвета поверхностей, которых нет в стандартной схеме.
class AppColors {
  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color card(BuildContext c) =>
      _dark(c) ? const Color(0xFF1C1C24) : Colors.white;

  static Color background(BuildContext c) =>
      _dark(c) ? const Color(0xFF111117) : const Color(0xFFF3F4F9);

  static Color muted(BuildContext c) =>
      _dark(c) ? const Color(0xFF2A2A35) : const Color(0xFFE9EAF2);

  static Color success(BuildContext c) => const Color(0xFF10B981);

  static List<BoxShadow> shadow(BuildContext c) => _dark(c)
      ? const <BoxShadow>[]
      : const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F1E1B4B),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ];
}

ThemeData buildTheme(Brightness brightness, {int accent = 0}) {
  final dark = brightness == Brightness.dark;
  final seed = goalPalettes[accent.abs() % goalPalettes.length].a;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  ).copyWith(primary: dark ? Color.lerp(seed, Colors.white, 0.3) : seed);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final text = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor:
        dark ? const Color(0xFF111117) : const Color(0xFFF3F4F9),
    textTheme: text.copyWith(
      displaySmall: text.displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      headlineLarge: text.headlineLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineMedium: text.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: text.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: text.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      foregroundColor: scheme.onSurface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: dark ? const Color(0xFF17171E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF22222C) : const Color(0xFFF3F4F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.4),
      space: 1,
    ),
  );
}
