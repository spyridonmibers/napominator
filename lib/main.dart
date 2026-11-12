import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';

import 'services/notifications.dart';
import 'services/widget_sync.dart';
import 'state/alarm_store.dart';
import 'state/app_settings.dart';
import 'state/goal_store.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppSettings.instance.load();
  } catch (_) {}
  final store = GoalStore();
  try {
    await Notifications.instance.init(onDone: (id) => store.completeById(id));
  } catch (_) {
    // Приложение работает и без уведомлений.
  }
  if (Platform.isAndroid) {
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    } catch (_) {}
  }
  LiveSync.init(store.refresh);
  final alarms = AlarmStore();
  runApp(NapominatorApp(store: store, alarms: alarms));
  store.refresh();
  alarms.load();
}

class NapominatorApp extends StatelessWidget {
  const NapominatorApp({super.key, required this.store, required this.alarms});
  final GoalStore store;
  final AlarmStore alarms;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
      title: 'Напоминатор',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: settings.themeMode,
      theme: buildTheme(Brightness.light,
          accent: settings.accent, accentCustom: settings.accentCustom),
      darkTheme: buildTheme(Brightness.dark,
          accent: settings.accent, accentCustom: settings.accentCustom),
      home: HomeScreen(store: store, alarms: alarms),
      ),
    );
  }
}
