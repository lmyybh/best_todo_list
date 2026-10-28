import 'dart:async';
import 'dart:io';

import 'package:best_todo_list/services/update/update_delivery.dart';
import 'package:best_todo_list/services/update/update_preferences.dart';
import 'package:best_todo_list/services/update_controller.dart';
import 'package:best_todo_list/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_update_delivery.dart';

void main() {
  test('安装前发现缓存失效时允许重新下载', () async {
    final delivery = FakeDelivery()
      ..cached = PreparedUpdate(release, File('cached.exe'))
      ..installError = const InvalidPreparedUpdate();
    final controller = UpdateController(FakeService(), delivery: delivery);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.performAvailableAction();
    expect(controller.state.ready, isFalse);
    expect(controller.state.phase, UpdatePhase.available);
    final retry = controller.performAvailableAction();
    expect(controller.state.downloading, isTrue);
    delivery.downloaded.complete(File('redownloaded.exe'));
    await retry;
    expect(controller.state.ready, isTrue);
    expect(controller.state.hasError, isFalse);
  });

  test('后台检查返回时不覆盖用户刚关闭的自动检查设置', () async {
    final service = FakeService()..pending = Completer<ReleaseInfo?>();
    final controller = UpdateController(
      service,
      preferences: _MemoryPreferences(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.setAutoCheck(true);
    final checking = controller.check(silent: true);
    await controller.setAutoCheck(false);
    service.pending!.complete(null);
    await checking;
    expect(controller.state.autoCheck, isFalse);
  });

  test('全流程：下载进度、取消、重试、校验、准备安装和失败重试', () async {
    final delivery = FakeDelivery();
    final controller = UpdateController(FakeService(), delivery: delivery);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.check();
    final first = controller.performAvailableAction();
    expect(controller.state.downloading, isTrue);
    delivery.progress(50, 100);
    expect(controller.state.progress, .5);
    controller.cancelDownload();
    await first;
    expect(controller.state.phase, UpdatePhase.available);
    expect(controller.state.hasError, isFalse);

    final second = controller.performAvailableAction();
    delivery.verifying();
    expect(controller.state.verifying, isTrue);
    delivery.downloaded.complete(File('fixture.exe'));
    await second;
    expect(controller.state.ready, isTrue);
    expect(delivery.installCount, 0);
    // Dialog initialization must never discard an active or completed download.
    await controller.initialize();
    expect(controller.state.ready, isTrue);

    delivery.installError = StateError('Cannot start helper');
    await controller.performAvailableAction();
    expect(controller.state.ready, isTrue);
    expect(controller.state.hasError, isTrue);
    delivery.installError = null;
    await controller.performAvailableAction();
    expect(delivery.installCount, 2);
    expect(controller.state.hasError, isFalse);
  });

  test('重启后恢复下载完成状态，无需重新检查或下载', () async {
    final delivery = FakeDelivery()
      ..cached = PreparedUpdate(release, File('cached.exe'));
    final service = FakeService();
    final controller = UpdateController(service, delivery: delivery);
    addTearDown(controller.dispose);
    await Future.wait([controller.initialize(), controller.initialize()]);
    expect(service.versionReads, 1);
    expect(controller.state.ready, isTrue);
    await controller.check();
    expect(service.checkCount, 0);
    await controller.performAvailableAction();
    expect(delivery.installCount, 1);
  });

  test('后台检查网络失败时保持安静，手动检查可以重试', () async {
    final service = FakeService()..error = StateError('offline');
    final controller = UpdateController(service);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.check(silent: true);
    expect(controller.state.message, isNull);
    expect(controller.state.hasError, isFalse);
    await controller.check();
    expect(controller.state.hasError, isTrue);
    service.error = null;
    await controller.check();
    expect(controller.state.hasError, isFalse);
    expect(controller.state.availableRelease, release);
  });

  testWidgets('自动检查可开启和关闭，默认不检查也不自动下载', (tester) async {
    final service = FakeService();
    final controller = UpdateController(
      service,
      preferences: _MemoryPreferences(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pump(const Duration(seconds: 30));
    expect(service.checkCount, 0);
    await controller.setAutoCheck(true);
    await tester.pump(const Duration(seconds: 21));
    expect(service.checkCount, 1);
    expect(controller.state.availableRelease, release);
    await controller.setAutoCheck(false);
    await tester.pump(const Duration(hours: 13));
    expect(service.checkCount, 1);
    expect(controller.state.autoCheck, isFalse);
  });
}

class _MemoryPreferences extends UpdatePreferences {
  _MemoryPreferences() : super(() async => Directory('unused'));
  bool enabled = false;
  @override
  Future<bool> loadAutoCheck() async => enabled;
  @override
  Future<void> saveAutoCheck(bool value) async => enabled = value;
}
