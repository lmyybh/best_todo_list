import 'package:flutter/material.dart';

class DesktopContextMenu extends StatelessWidget {
  const DesktopContextMenu({
    required this.menuChildren,
    required this.child,
    this.onOpen,
    super.key,
  });

  final List<Widget> menuChildren;
  final Widget child;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    useRootOverlay: true,
    menuChildren: menuChildren,
    builder: (context, controller, child) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        onOpen?.call();
        if (controller.isOpen) controller.close();
        controller.open(position: details.localPosition);
      },
      child: child,
    ),
    child: child,
  );
}
