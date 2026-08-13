import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import 'adaptive/desktop_app_shell.dart';
import 'events/event_view.dart';
import 'navigation/app_rail.dart';
import 'timeline/timeline_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({required this.controller, super.key});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  Timer? _clockTimer;

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
              navigation: AppRail(controller: controller),
              body: controller.view == AppView.events
                  ? EventView(controller: controller)
                  : TimelineView(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}
