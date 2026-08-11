import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import 'adaptive/desktop_app_shell.dart';
import 'events/event_view.dart';
import 'sidebar.dart';
import 'timeline/timeline_view.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({required this.controller, super.key});

  final AppController controller;

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
              sidebarBuilder: (context, width) =>
                  AppSidebar(controller: controller, width: width),
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
