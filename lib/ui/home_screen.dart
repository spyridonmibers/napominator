import 'dart:async';

import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/notifications.dart';
import '../state/goal_store.dart';
import 'calendar_screen.dart';
import 'edit_goal_screen.dart';
import 'goal_detail_screen.dart';
import 'goals_screen.dart';
import 'today_screen.dart';

/// Главный экран с нижним меню: Сегодня / Календарь / Все цели.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final GoalStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _midnight;

  GoalStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Notifications.instance.requestPermissions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.refresh();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      store.refresh();
      _scheduleMidnight();
    });
  }

  Future<void> _add() async {
    if (!store.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Можно вести не больше 50 активных целей')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => EditGoalScreen(store: store),
    ));
  }

  Future<void> _open(Goal g) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GoalDetailScreen(store: store, goalId: g.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TodayScreen(store: store, onAdd: _add, onOpen: _open),
          CalendarScreen(store: store, onOpen: _open),
          GoalsScreen(store: store, onAdd: _add, onOpen: _open),
        ],
      ),
      floatingActionButton: _tab == 1
          ? null
          : FloatingActionButton(
              onPressed: _add,
              tooltip: 'Новая цель',
              child: const Icon(Icons.add_rounded, size: 30),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny_rounded),
            label: 'Сегодня',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Календарь',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Все цели',
          ),
        ],
      ),
    );
  }
}
