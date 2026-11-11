import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';

import 'services/notifications.dart';
import 'services/widget_sync.dart';
import 'state/goal_store.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(NapominatorApp(store: store));
  store.refresh();
}

class NapominatorApp extends StatelessWidget {
  const NapominatorApp({super.key, required this.store});
  final GoalStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Напоминатор',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeScreen(store: store),
    );
  }
}
