import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import '../services/update_controller.dart';
import 'adaptive/desktop_app_shell.dart';
import 'events/event_view.dart';
import 'events/event_board_view.dart';
import 'navigation/app_rail.dart';
import 'timeline/calendar_timeline_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.controller, this.updates, super.key});

  final AppController controller;
  final UpdateController? updates;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  Timer? _clockTimer;
  bool _calendarVisited = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => controller.refreshTime(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.refreshTime();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    _calendarVisited = _calendarVisited || controller.view == AppView.timeline;
    return Scaffold(
      body: Column(
        children: <Widget>[
          if (controller.error != null)
            MaterialBanner(
              content: Text(controller.error.toString()),
              leading: Icon(
                Icons.error_outline,
                color: AppColors.of(context).danger,
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: controller.clearError,
                  child: const Text('关闭'),
                ),
              ],
            ),
          Expanded(
            child: DesktopAppShell(
              navigation: AppRail(
                controller: controller,
                updates: widget.updates,
              ),
              body: EventView(
                controller: controller,
                child: IndexedStack(
                  index: controller.view == AppView.events ? 0 : 1,
                  children: [
                    EventBoardView(controller: controller),
                    if (_calendarVisited)
                      CalendarTimelineView(controller: controller)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
