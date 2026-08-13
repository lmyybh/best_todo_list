import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_theme.dart';
import '../common/create_node_dialog.dart';

class AppRail extends StatelessWidget {
  const AppRail({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.sidebar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.borderSoft)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          child: Column(
            children: <Widget>[
              _RailButton(
                key: const ValueKey<String>('events-navigation'),
                label: '事件',
                icon: Icons.format_list_bulleted,
                selected: controller.view == AppView.events,
                onPressed: () => controller.setView(AppView.events),
              ),
              const SizedBox(height: 6),
              _RailButton(
                key: const ValueKey<String>('timeline-navigation'),
                label: '时间线',
                icon: Icons.timeline_outlined,
                selected: controller.view == AppView.timeline,
                onPressed: () => controller.setView(AppView.timeline),
              ),
              const Spacer(),
              Divider(
                height: 13,
                indent: 5,
                endIndent: 5,
                color: colors.borderSoft,
              ),
              _RailButton(
                key: const ValueKey<String>('create-event-navigation'),
                label: '新建事件',
                icon: Icons.add,
                onPressed: () => _createEvent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createEvent(BuildContext context) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const CreateNodeDialog(),
    );
    if (title == null || title.trim().isEmpty) return;
    await controller.create(title: title);
    controller.setView(AppView.events);
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onPressed,
          mouseCursor: SystemMouseCursors.click,
          visualDensity: VisualDensity.compact,
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(Size.square(38)),
            minimumSize: const WidgetStatePropertyAll(Size.square(38)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected) return AppTheme.accent;
              if (states.contains(WidgetState.hovered)) {
                return Theme.of(context).colorScheme.onSurface;
              }
              return colors.muted;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected) return colors.accentSoft;
              if (states.contains(WidgetState.hovered)) {
                return colors.surfaceHover;
              }
              return Colors.transparent;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          icon: Icon(icon, size: 18),
        ),
      ),
    );
  }
}
