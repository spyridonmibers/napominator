import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/notifications.dart';
import 'state/goal_store.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GoalStore();
  try {
    await Notifications.instance.init(onDone: (id) => store.completeById(id));
  } catch (_) {
    // Приложение работает и без уведомлений.
  }
  runApp(NapominatorApp(store: store));
  store.refresh();
}

class NapominatorApp extends StatelessWidget {
  const NapominatorApp({super.key, required this.store});
  final GoalStore store;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D6B);
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
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(store: store),
    );
  }
}
