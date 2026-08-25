import 'package:flutter/foundation.dart';

import 'update_service.dart';

class UpdateState {
  const UpdateState({
    this.currentVersion,
    this.availableRelease,
    this.message,
    this.checking = false,
    this.acting = false,
  });

  final AppVersion? currentVersion;
  final ReleaseInfo? availableRelease;
  final String? message;
  final bool checking;
  final bool acting;
}

class UpdateController extends ChangeNotifier {
  UpdateController(this.service, {this.installUpdate});

  final UpdateService service;
  final Future<void> Function()? installUpdate;

  UpdateState _state = const UpdateState();
  bool _disposed = false;

  UpdateState get state => _state;
  bool get usesInstaller => installUpdate != null;

  Future<void> initialize() async {
    try {
      final currentVersion = await service.loadCurrentVersion();
      _setState(UpdateState(currentVersion: currentVersion));
    } catch (_) {
      _setState(const UpdateState(message: '无法读取当前版本'));
    }
  }

  Future<void> check() async {
    final currentVersion = _state.currentVersion;
    if (currentVersion == null || _state.checking) return;
    _setState(UpdateState(currentVersion: currentVersion, checking: true));
    try {
      final release = await service.fetchLatestRelease();
      if (release == null) {
        _setState(
          UpdateState(currentVersion: currentVersion, message: '尚未发布可用版本'),
        );
      } else if (release.isNewerThan(currentVersion)) {
        _setState(
          UpdateState(
            currentVersion: currentVersion,
            availableRelease: release,
            message: '发现新版本 ${release.version}',
          ),
        );
      } else {
        _setState(
          UpdateState(currentVersion: currentVersion, message: '当前已是最新版本'),
        );
      }
    } catch (error) {
      _setState(
        UpdateState(currentVersion: currentVersion, message: '检查失败：$error'),
      );
    }
  }

  Future<void> performAvailableAction() async {
    final release = _state.availableRelease;
    if (release == null || _state.acting) return;
    _setState(
      UpdateState(
        currentVersion: _state.currentVersion,
        availableRelease: release,
        message: _state.message,
        acting: true,
      ),
    );
    try {
      final installer = installUpdate;
      if (installer != null) {
        await installer();
      } else if (!await service.openReleasePage(release.pageUri)) {
        _setActionError('无法打开系统浏览器');
        return;
      }
      _finishAction();
    } catch (error) {
      _setActionError(installUpdate == null ? '无法打开系统浏览器' : '启动更新失败：$error');
    }
  }

  void _finishAction() {
    _setState(
      UpdateState(
        currentVersion: _state.currentVersion,
        availableRelease: _state.availableRelease,
        message: _state.message,
      ),
    );
  }

  void _setActionError(String message) {
    _setState(
      UpdateState(
        currentVersion: _state.currentVersion,
        availableRelease: _state.availableRelease,
        message: message,
      ),
    );
  }

  void _setState(UpdateState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
