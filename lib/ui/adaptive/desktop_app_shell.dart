import 'package:flutter/material.dart';

class DesktopAppShell extends StatelessWidget {
  const DesktopAppShell({
    required this.navigation,
    required this.body,
    super.key,
  });

  final Widget navigation;
  final Widget body;

  static const double minimumSupportedWidth = 720;
  static const double navigationWidth = 54;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(width: navigationWidth, child: navigation),
      Expanded(child: body),
    ],
  );
}
