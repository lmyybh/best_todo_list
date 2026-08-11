import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_theme.dart';
import 'events/event_view.dart';
import 'sidebar.dart';
import 'timeline/timeline_view.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            child: Row(
              children: <Widget>[
                AppSidebar(controller: controller),
                Expanded(
                  child: controller.view == AppView.events
                      ? EventView(controller: controller)
                      : TimelineView(controller: controller),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
