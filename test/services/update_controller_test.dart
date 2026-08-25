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
  });

  test('弹窗关闭后延迟返回的版本读取不再发送通知', () async {
    final service = _DelayedVersionService();
    final controller = UpdateController(service);
    final initialize = controller.initialize();

    controller.dispose();
    service.complete();

    await expectLater(initialize, completes);
  });

  test('版本读取失败时返回可展示错误', () async {
    final controller = UpdateController(
      _FakeUpdateService(loadError: StateError('版本不可用')),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.state.currentVersion, isNull);
    expect(controller.state.message, '无法读取当前版本');
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

    expect(controller.state.message, contains('网络不可用'));
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
    expect(controller.state.message, '无法打开系统浏览器');
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
    expect(controller.state.message, contains('启动更新失败'));
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
    expect(controller.state.message, '无法打开系统浏览器');
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
