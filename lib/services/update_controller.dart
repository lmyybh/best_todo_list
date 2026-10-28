import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'update/update_delivery.dart';
import 'update/update_preferences.dart';
import 'update_service.dart';

enum UpdatePhase {
  idle,
  checking,
  available,
  opening,
  downloading,
  verifying,
  ready,
  installing,
}

class UpdateState {
  const UpdateState({
    this.currentVersion,
    this.availableRelease,
    this.message,
    this.phase = UpdatePhase.idle,
    this.errorDetails,
    this.actionOpened = false,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.autoCheck = false,
    this.savingPreferences = false,
  });

  final AppVersion? currentVersion;
  final ReleaseInfo? availableRelease;
  final String? message;
  final UpdatePhase phase;
  final String? errorDetails;
  final bool actionOpened;
  final int receivedBytes;
  final int totalBytes;
  final bool autoCheck;
  final bool savingPreferences;

  bool get hasError => errorDetails != null;
  bool get checking => phase == UpdatePhase.checking;
  bool get downloading => phase == UpdatePhase.downloading;
  bool get verifying => phase == UpdatePhase.verifying;
  bool get ready => phase == UpdatePhase.ready;
  bool get installing => phase == UpdatePhase.installing;
  bool get acting =>
      phase == UpdatePhase.opening || downloading || verifying || installing;
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0, 1) : null;

  UpdateState copyWith({
    AppVersion? currentVersion,
    ReleaseInfo? availableRelease,
    String? message,
    UpdatePhase? phase,
    String? errorDetails,
    bool clearError = false,
    bool? actionOpened,
    int? receivedBytes,
    int? totalBytes,
    bool? autoCheck,
    bool? savingPreferences,
  }) => UpdateState(
    currentVersion: currentVersion ?? this.currentVersion,
    availableRelease: availableRelease ?? this.availableRelease,
    message: message ?? this.message,
    phase: phase ?? this.phase,
    errorDetails: clearError ? null : errorDetails ?? this.errorDetails,
    actionOpened: actionOpened ?? this.actionOpened,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    autoCheck: autoCheck ?? this.autoCheck,
    savingPreferences: savingPreferences ?? this.savingPreferences,
  );
}

class UpdateController extends ChangeNotifier {
  UpdateController(
    this.service, {
    this.installUpdate,
    this.delivery,
    this.preferences,
  });

  final UpdateService service;
  final Future<void> Function()? installUpdate;
  final UpdateDelivery? delivery;
  final UpdatePreferences? preferences;

  UpdateState _state = const UpdateState();
  bool _disposed = false;
  Future<void>? _initializing;
  Timer? _automaticCheck;
  PreparedUpdate? _prepared;

  UpdateState get state => _state;
  bool get usesInstaller => installUpdate != null || canDownload;
  bool get canDownload =>
      delivery?.supported == true &&
      _state.availableRelease?.manifestUri != null;
  bool get supportsPreferences => preferences != null;

  Future<void> initialize() async {
    if (_disposed || _state.currentVersion != null) return;
    if (_initializing != null) return _initializing;
    _initializing = _initialize();
    await _initializing;
    _initializing = null;
  }

  Future<void> _initialize() async {
    _setState(const UpdateState());
    AppVersion? current;
    try {
      current = await service.loadCurrentVersion();
      final autoCheck = await preferences?.loadAutoCheck() ?? false;
      _prepared = await delivery?.restore(current);
      _setState(UpdateState(currentVersion: current, autoCheck: autoCheck));
      if (_prepared != null) {
        _setState(
          _state.copyWith(
            availableRelease: _prepared!.release,
            phase: UpdatePhase.ready,
            message: _prepared!.installationError == null
                ? '更新已准备好，重启即可完成安装'
                : '上次更新未完成，可重试或手动下载',
            errorDetails: _prepared!.installationError,
          ),
        );
      }
      if (autoCheck) _scheduleCheck(const Duration(seconds: 20));
    } catch (error) {
      _setState(
        _state.copyWith(
          currentVersion: current,
          message: current == null ? '无法读取当前版本，请重试' : '无法恢复更新状态，请重新检查',
          errorDetails: '$error',
        ),
      );
    }
  }

  Future<void> setAutoCheck(bool enabled) async {
    if (_disposed || preferences == null || _state.savingPreferences) return;
    _setState(_state.copyWith(savingPreferences: true));
    try {
      await preferences!.saveAutoCheck(enabled);
      _setState(_state.copyWith(autoCheck: enabled, savingPreferences: false));
      _automaticCheck?.cancel();
      if (enabled) _scheduleCheck(const Duration(seconds: 20));
    } catch (error) {
      _setState(
        _state.copyWith(
          savingPreferences: false,
          message: '无法保存更新设置，请重试',
          errorDetails: '$error',
        ),
      );
    }
  }

  void _scheduleCheck(Duration delay) {
    if (_disposed) return;
    _automaticCheck?.cancel();
    _automaticCheck = Timer(delay, () async {
      await check(silent: true);
      if (!_disposed && _state.autoCheck) {
        _scheduleCheck(const Duration(hours: 12));
      }
    });
  }

  Future<void> check({bool silent = false}) async {
    final current = _state.currentVersion;
    if (_disposed ||
        current == null ||
        _state.checking ||
        _state.acting ||
        _state.ready) {
      return;
    }
    final previous = _state;
    // Quiet checks do not replace an existing notification or failure.
    if (silent && _state.availableRelease != null) return;
    _setState(_state.copyWith(phase: UpdatePhase.checking, clearError: true));
    try {
      final release = await service.fetchLatestRelease();
      if (release != null && release.isNewerThan(current)) {
        _setState(
          _state.copyWith(
            availableRelease: release,
            phase: UpdatePhase.available,
            message: '发现新版本 ${release.version}',
            clearError: true,
          ),
        );
      } else if (silent) {
        _setState(
          previous.copyWith(
            autoCheck: _state.autoCheck,
            savingPreferences: _state.savingPreferences,
          ),
        );
      } else {
        _setState(
          UpdateState(
            currentVersion: current,
            autoCheck: _state.autoCheck,
            message: release == null ? '尚未发布可用版本' : '当前已是最新版本',
          ),
        );
      }
    } catch (error) {
      _setState(
        silent
            ? previous.copyWith(
                autoCheck: _state.autoCheck,
                savingPreferences: _state.savingPreferences,
              )
            : _state.copyWith(
                phase: UpdatePhase.idle,
                message: '暂时无法检查更新，请稍后重试',
                errorDetails: '$error',
              ),
      );
    }
  }

  Future<void> performAvailableAction() async {
    final release = _state.availableRelease;
    if (_disposed || release == null || _state.acting || _state.checking) {
      return;
    }
    if (_state.ready) return _install();
    if (canDownload) return _download(release);
    _setState(
      _state.copyWith(
        phase: UpdatePhase.opening,
        clearError: true,
        actionOpened: false,
        message: usesInstaller ? '正在打开更新窗口…' : '正在打开下载页面…',
      ),
    );
    try {
      if (installUpdate != null) {
        await installUpdate!();
      } else if (!await service.openReleasePage(release.pageUri)) {
        throw const UpdateCheckException('系统浏览器未能打开下载地址');
      }
      _setState(
        _state.copyWith(
          phase: UpdatePhase.available,
          actionOpened: true,
          message: usesInstaller ? '请在更新窗口中继续下载和安装' : '下载页面已在浏览器中打开',
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          phase: UpdatePhase.available,
          message: usesInstaller ? '无法启动更新，请重试' : '无法打开下载页面，请重试',
          errorDetails: '$error',
        ),
      );
    }
  }

  Future<void> _download(ReleaseInfo release) async {
    _setState(
      _state.copyWith(
        phase: UpdatePhase.downloading,
        clearError: true,
        receivedBytes: 0,
        totalBytes: 0,
        message: '正在下载更新，可关闭此窗口继续使用',
      ),
    );
    try {
      final File file = await delivery!.download(
        release,
        onProgress: (received, total) => _setState(
          _state.copyWith(receivedBytes: received, totalBytes: total),
        ),
        onVerifying: () => _setState(
          _state.copyWith(phase: UpdatePhase.verifying, message: '正在校验更新包…'),
        ),
      );
      _prepared = PreparedUpdate(release, file);
      _setState(
        _state.copyWith(phase: UpdatePhase.ready, message: '更新已准备好，重启即可完成安装'),
      );
    } on DownloadCancelled {
      _setState(
        _state.copyWith(
          phase: UpdatePhase.available,
          message: '下载已取消，可随时重新下载',
          receivedBytes: 0,
          totalBytes: 0,
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          phase: UpdatePhase.available,
          message: '下载失败，请重试',
          errorDetails: '$error',
        ),
      );
    }
  }

  void cancelDownload() {
    if (_state.downloading || _state.verifying) delivery?.cancel();
  }

  Future<void> _install() async {
    if (_prepared == null) return;
    _setState(
      _state.copyWith(
        phase: UpdatePhase.installing,
        clearError: true,
        message: '正在保存数据并准备重启…',
      ),
    );
    try {
      await delivery!.install(_prepared!);
      // Production exits in the installer. A returning implementation can retry.
      _setState(_state.copyWith(phase: UpdatePhase.ready));
    } on InvalidPreparedUpdate catch (error) {
      _prepared = null;
      _setState(
        _state.copyWith(
          phase: UpdatePhase.available,
          message: '更新包已失效，请重新下载',
          errorDetails: '$error',
        ),
      );
    } catch (error) {
      _setState(
        _state.copyWith(
          phase: UpdatePhase.ready,
          message: '无法安装更新，请重试或手动下载',
          errorDetails: '$error',
        ),
      );
    }
  }

  Future<void> openDownloadPage() async {
    final release = _state.availableRelease;
    if (release == null || _state.installing) return;
    try {
      if (!await service.openReleasePage(release.pageUri)) {
        throw StateError('系统浏览器未能打开下载地址');
      }
    } catch (error) {
      _setState(
        _state.copyWith(message: '无法打开下载页面，请重试', errorDetails: '$error'),
      );
    }
  }

  void _setState(UpdateState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _automaticCheck?.cancel();
    delivery?.cancel();
    super.dispose();
  }
}
