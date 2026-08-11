import 'package:flutter/material.dart';

class DesktopAppShell extends StatelessWidget {
  const DesktopAppShell({
    required this.sidebarBuilder,
    required this.body,
    super.key,
  });

  final Widget Function(BuildContext context, double width) sidebarBuilder;
  final Widget body;

  static const double minimumSupportedWidth = 720;
  static const double _minimumSidebarWidth = 220;
  static const double _maximumSidebarWidth = 258;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : minimumSupportedWidth;
      final sidebarWidth = (availableWidth * 0.24).clamp(
        _minimumSidebarWidth,
        _maximumSidebarWidth,
      );
      return Row(
        children: <Widget>[
          sidebarBuilder(context, sidebarWidth),
          Expanded(child: body),
        ],
      );
    },
  );
}
