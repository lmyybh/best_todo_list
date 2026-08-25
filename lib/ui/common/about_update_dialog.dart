import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/update_controller.dart';

class AboutUpdateDialog extends StatefulWidget {
  const AboutUpdateDialog({required this.controller, super.key});

  final UpdateController controller;

  @override
  State<AboutUpdateDialog> createState() => _AboutUpdateDialogState();
}

class _AboutUpdateDialogState extends State<AboutUpdateDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChanged);
    unawaited(widget.controller.initialize());
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AboutUpdateDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_handleChanged);
    widget.controller.addListener(_handleChanged);
    unawaited(widget.controller.initialize());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final release = state.availableRelease;
    return AlertDialog(
      title: const Text('关于 todo'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              state.currentVersion == null
                  ? '正在读取版本…'
                  : '当前版本 ${state.currentVersion!.display}',
              key: const ValueKey<String>('current-app-version'),
            ),
            if (state.message != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                state.message!,
                key: const ValueKey<String>('update-message'),
              ),
            ],
            if (release != null && release.notes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(release.name, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(child: Text(release.notes.trim())),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (release != null)
          OutlinedButton(
            key: ValueKey<String>(
              widget.controller.usesInstaller
                  ? 'install-update'
                  : 'open-release-page',
            ),
            onPressed: state.acting
                ? null
                : widget.controller.performAvailableAction,
            child: Text(widget.controller.usesInstaller ? '下载并安装' : '前往下载'),
          ),
        FilledButton(
          key: const ValueKey<String>('check-for-updates'),
          onPressed: state.currentVersion == null || state.checking
              ? null
              : widget.controller.check,
          child: state.checking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('检查更新'),
        ),
      ],
    );
  }
}
