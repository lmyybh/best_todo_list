import 'package:flutter/material.dart';

import '../../services/update_service.dart';

class AboutUpdateDialog extends StatefulWidget {
  const AboutUpdateDialog({
    required this.service,
    this.installUpdate,
    super.key,
  });

  final UpdateService service;
  final Future<void> Function()? installUpdate;

  @override
  State<AboutUpdateDialog> createState() => _AboutUpdateDialogState();
}

class _AboutUpdateDialogState extends State<AboutUpdateDialog> {
  AppVersion? _currentVersion;
  ReleaseInfo? _availableRelease;
  String? _message;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final version = await widget.service.loadCurrentVersion();
      if (mounted) setState(() => _currentVersion = version);
    } catch (_) {
      if (mounted) setState(() => _message = '无法读取当前版本');
    }
  }

  Future<void> _checkForUpdates() async {
    final currentVersion = _currentVersion;
    if (currentVersion == null) return;
    setState(() {
      _checking = true;
      _message = null;
      _availableRelease = null;
    });

    try {
      final release = await widget.service.fetchLatestRelease();
      if (!mounted) return;
      setState(() {
        if (release == null) {
          _message = '尚未发布可用版本';
        } else if (release.isNewerThan(currentVersion)) {
          _availableRelease = release;
          _message = '发现新版本 ${release.version}';
        } else {
          _message = '当前已是最新版本';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _message = '检查失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openReleasePage() async {
    final release = _availableRelease;
    if (release == null) return;
    try {
      final opened = await widget.service.openReleasePage(release.pageUri);
      if (mounted && !opened) {
        setState(() => _message = '无法打开系统浏览器');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '无法打开系统浏览器');
    }
  }

  Future<void> _installUpdate() async {
    try {
      await widget.installUpdate!();
    } catch (error) {
      if (mounted) setState(() => _message = '启动更新失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _availableRelease;
    return AlertDialog(
      title: const Text('关于 todo'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _currentVersion == null
                  ? '正在读取版本…'
                  : '当前版本 ${_currentVersion!.display}',
              key: const ValueKey<String>('current-app-version'),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(_message!, key: const ValueKey<String>('update-message')),
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
              widget.installUpdate == null
                  ? 'open-release-page'
                  : 'install-update',
            ),
            onPressed: widget.installUpdate == null
                ? _openReleasePage
                : _installUpdate,
            child: Text(widget.installUpdate == null ? '前往下载' : '下载并安装'),
          ),
        FilledButton(
          key: const ValueKey<String>('check-for-updates'),
          onPressed: _currentVersion == null || _checking
              ? null
              : _checkForUpdates,
          child: _checking
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
