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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = state.checking || state.acting;
    final loadingVersion = state.currentVersion == null && !state.hasError;
    final statusColor = state.hasError ? colors.error : colors.primary;
    final title = switch (state.phase) {
      UpdatePhase.downloading => '正在下载更新',
      UpdatePhase.verifying => '正在校验更新',
      UpdatePhase.ready => '${release?.version} 已准备好',
      UpdatePhase.installing => '正在准备重启',
      _ => release != null ? '发现新版本 ${release.version}' : '软件更新',
    };
    final actionLabel = state.installing
        ? '正在重启…'
        : state.ready
        ? '重启并更新'
        : widget.controller.canDownload
        ? (state.hasError ? '重新下载' : '下载更新')
        : state.acting
        ? '正在打开…'
        : state.hasError
        ? '重试'
        : state.actionOpened
        ? (widget.controller.usesInstaller ? '重新打开更新窗口' : '重新打开下载页面')
        : (widget.controller.usesInstaller ? '下载并安装' : '前往下载');

    return PopScope(
      canPop: !state.installing,
      child: AlertDialog(
        title: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.system_update_alt,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Text('关于与更新')),
          ],
        ),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('todo', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                state.currentVersion == null
                    ? (state.hasError ? '当前版本暂不可用' : '正在读取版本…')
                    : '当前版本 ${state.currentVersion!.display}',
                key: const ValueKey<String>('current-app-version'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: state.hasError
                      ? colors.errorContainer
                      : colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          state.hasError
                              ? Icons.error_outline
                              : release != null
                              ? Icons.new_releases_outlined
                              : Icons.info_outline,
                          size: 20,
                          color: statusColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            state.checking ? '正在检查更新…' : title,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      release != null &&
                              state.phase == UpdatePhase.available &&
                              !widget.controller.canDownload &&
                              !state.hasError &&
                              !state.actionOpened &&
                              !state.acting
                          ? (widget.controller.usesInstaller
                                ? '更新将在独立窗口中下载和安装，安装时可能需要退出应用。'
                                : '将在浏览器中打开下载页面，请下载适用于当前系统的安装包。')
                          : state.message ?? '手动检查新版本，更新前由你决定。',
                      key: const ValueKey<String>('update-message'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (busy || loadingVersion) ...<Widget>[
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: state.downloading ? state.progress : null,
                      ),
                      if (state.downloading &&
                          state.totalBytes > 0) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          '${(state.progress! * 100).floor()}% · '
                          '${(state.receivedBytes / 1048576).toStringAsFixed(1)} / '
                          '${(state.totalBytes / 1048576).toStringAsFixed(1)} MB',
                        ),
                      ],
                    ],
                    if (state.errorDetails != null)
                      Material(
                        color: Colors.transparent,
                        child: ExpansionTile(
                          key: ValueKey<String>(state.errorDetails!),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          title: const Text('查看错误详情'),
                          children: <Widget>[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                state.errorDetails!,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.controller.supportsPreferences) ...<Widget>[
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动检查更新'),
                  subtitle: const Text('启动后及每 12 小时检查，仅提醒，不自动安装'),
                  value: state.autoCheck,
                  onChanged: state.savingPreferences || state.installing
                      ? null
                      : widget.controller.setAutoCheck,
                ),
              ],
              if (release != null) ...<Widget>[
                const SizedBox(height: 24),
                Text('更新内容', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                if (release.name != release.version.toString()) ...<Widget>[
                  Text(release.name, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                ],
                SelectableText(
                  release.notes.trim().isEmpty
                      ? '此版本暂无更新说明。'
                      : release.notes.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        actions: <Widget>[
          TextButton(
            onPressed: state.installing
                ? null
                : () => Navigator.of(context).pop(),
            child: Text(
              state.downloading || state.verifying
                  ? '后台下载'
                  : release != null && !state.actionOpened
                  ? '稍后'
                  : '关闭',
            ),
          ),
          if (state.downloading || state.verifying)
            TextButton(
              onPressed: widget.controller.cancelDownload,
              child: const Text('取消下载'),
            ),
          if (release != null &&
              widget.controller.canDownload &&
              state.hasError)
            TextButton(
              onPressed: state.installing
                  ? null
                  : widget.controller.openDownloadPage,
              child: const Text('手动下载'),
            ),
          if (release != null && !state.downloading && !state.verifying)
            FilledButton(
              key: ValueKey<String>(
                widget.controller.usesInstaller
                    ? 'install-update'
                    : 'open-release-page',
              ),
              onPressed: busy ? null : widget.controller.performAvailableAction,
              child: Text(actionLabel),
            )
          else if (release == null)
            FilledButton(
              key: const ValueKey<String>('check-for-updates'),
              onPressed: busy || loadingVersion
                  ? null
                  : state.currentVersion == null
                  ? widget.controller.initialize
                  : widget.controller.check,
              child: Text(
                state.checking
                    ? '正在检查…'
                    : state.hasError
                    ? '重试'
                    : '检查更新',
              ),
            ),
        ],
      ),
    );
  }
}
