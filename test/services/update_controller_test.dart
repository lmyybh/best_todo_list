import 'dart:async';

import 'package:best_todo_list/services/update_controller.dart';
import 'package:best_todo_list/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('集中加载当前版本并判定可用新版本', () async {
    final release = ReleaseInfo(
      version: VersionNumber.parse('0.2.0'),
      name: 'Version 0.2.0',
      notes: '新功能',
      pageUri: Uri.parse('https://example.com/releases/v0.2.0'),
    );
    final controller = UpdateController(_FakeUpdateService(release: release));
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();

    expect(controller.state.currentVersion?.display, 'v0.1.0');
    expect(controller.state.availableRelease, release);
    expect(controller.state.message, '发现新版本 v0.2.0');
    expect(controller.state.checking, isFalse);
  });

  test('可用动作由控制器在浏览器与应用内安装之间选择', () async {
    final release = ReleaseInfo(
      version: VersionNumber.parse('0.2.0'),
      name: 'Version 0.2.0',
      notes: '',
      pageUri: Uri.parse('https://example.com/releases/v0.2.0'),
    );
    final service = _FakeUpdateService(release: release);
    var installCount = 0;
    final controller = UpdateController(
      service,
      installUpdate: () async => installCount += 1,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.performAvailableAction();

    expect(installCount, 1);
    expect(service.openedUri, isNull);
    expect(controller.usesInstaller, isTrue);
    expect(controller.state.actionOpened, isTrue);
    expect(controller.state.message, '请在更新窗口中继续下载和安装');
    expect(controller.state.acting, isFalse);
  });

  test('弹窗关闭后延迟返回的版本读取不再发送通知', () async {
    final service = _DelayedVersionService();
    final controller = UpdateController(service);
    final initialize = controller.initialize();

    controller.dispose();
    service.complete();

    await expectLater(initialize, completes);
  });

  test('启动更新时禁止重复操作和检查，失败后可以重试', () async {
    final started = Completer<void>();
    var installCount = 0;
    final controller = UpdateController(
      _FakeUpdateService(release: _release()),
      installUpdate: () {
        installCount += 1;
        return installCount == 1 ? started.future : Future<void>.value();
      },
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.check();

    final action = controller.performAvailableAction();
    await controller.performAvailableAction();
    await controller.check();
    expect(installCount, 1);
    expect(controller.state.acting, isTrue);
    expect(controller.state.checking, isFalse);

    started.completeError(StateError('启动失败'));
    await action;
    expect(controller.state.hasError, isTrue);
    expect(controller.state.actionOpened, isFalse);

    await controller.performAvailableAction();
    expect(installCount, 2);
    expect(controller.state.hasError, isFalse);
    expect(controller.state.actionOpened, isTrue);
  });

  test('版本读取失败时返回可展示错误', () async {
    final controller = UpdateController(
      _FakeUpdateService(loadError: StateError('版本不可用')),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.state.currentVersion, isNull);
    expect(controller.state.message, '无法读取当前版本，请重试');
    expect(controller.state.errorDetails, contains('版本不可用'));
  });

  test('无 Release 时结束检查并给出提示', () async {
    final controller = UpdateController(_FakeUpdateService());
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();

    expect(controller.state.message, '尚未发布可用版本');
    expect(controller.state.availableRelease, isNull);
    expect(controller.state.checking, isFalse);
  });

  test('Release 检查失败时结束检查并展示原因', () async {
    final controller = UpdateController(
      _FakeUpdateService(fetchError: StateError('网络不可用')),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();

    expect(controller.state.message, '暂时无法检查更新，请稍后重试');
    expect(controller.state.errorDetails, contains('网络不可用'));
    expect(controller.state.checking, isFalse);
  });

  test('浏览器无法打开时保留 Release 并结束动作', () async {
    final release = _release();
    final controller = UpdateController(
      _FakeUpdateService(release: release, openResult: false),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.performAvailableAction();

    expect(controller.state.availableRelease, release);
    expect(controller.state.message, '无法打开下载页面，请重试');
    expect(controller.state.hasError, isTrue);
    expect(controller.state.acting, isFalse);
  });

  test('安装器失败时保留 Release 并结束动作', () async {
    final release = _release();
    final controller = UpdateController(
      _FakeUpdateService(release: release),
      installUpdate: () => throw StateError('启动失败'),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.performAvailableAction();

    expect(controller.state.availableRelease, release);
    expect(controller.state.message, '无法启动更新，请重试');
    expect(controller.state.errorDetails, contains('启动失败'));
    expect(controller.state.acting, isFalse);
  });

  test('浏览器抛出异常时保留 Release 并结束动作', () async {
    final release = _release();
    final controller = UpdateController(
      _FakeUpdateService(release: release, openError: StateError('浏览器不可用')),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.check();
    await controller.performAvailableAction();

    expect(controller.state.availableRelease, release);
    expect(controller.state.message, '无法打开下载页面，请重试');
    expect(controller.state.hasError, isTrue);
    expect(controller.state.acting, isFalse);
  });
}

ReleaseInfo _release() => ReleaseInfo(
  version: VersionNumber.parse('0.2.0'),
  name: 'Version 0.2.0',
  notes: '',
  pageUri: Uri.parse('https://example.com/releases/v0.2.0'),
);

class _FakeUpdateService implements UpdateService {
  _FakeUpdateService({
    this.release,
    this.loadError,
    this.fetchError,
    this.openError,
    this.openResult = true,
  });

  final ReleaseInfo? release;
  final Object? loadError;
  final Object? fetchError;
  final Object? openError;
  final bool openResult;
  Uri? openedUri;

  @override
  Future<ReleaseInfo?> fetchLatestRelease() async {
    final error = fetchError;
    if (error != null) throw error;
    return release;
  }

  @override
  Future<AppVersion> loadCurrentVersion() async {
    final error = loadError;
    if (error != null) throw error;
    return const AppVersion(version: '0.1.0');
  }

  @override
  Future<bool> openReleasePage(Uri uri) async {
    openedUri = uri;
    final error = openError;
    if (error != null) throw error;
    return openResult;
  }
}

class _DelayedVersionService implements UpdateService {
  final _version = Completer<AppVersion>();

  void complete() => _version.complete(const AppVersion(version: '0.1.0'));

  @override
  Future<ReleaseInfo?> fetchLatestRelease() async => null;

  @override
  Future<AppVersion> loadCurrentVersion() => _version.future;

  @override
  Future<bool> openReleasePage(Uri uri) async => true;
}
