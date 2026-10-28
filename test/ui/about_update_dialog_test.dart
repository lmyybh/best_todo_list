import 'package:best_todo_list/services/update_controller.dart';
import 'package:best_todo_list/services/update_service.dart';
import 'package:best_todo_list/ui/common/about_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('展示当前版本并在发现新版后打开 Release 页面', (tester) async {
    final release = ReleaseInfo(
      version: VersionNumber.parse('0.2.0'),
      name: 'Version 0.2.0',
      notes: '新增 Windows 版本。',
      pageUri: Uri.parse(
        'https://github.com/lmyybh/best_todo_list/releases/tag/v0.2.0',
      ),
    );
    final service = _FakeUpdateService(release: release);

    await _pumpDialog(tester, service);

    expect(find.text('当前版本 v0.1.0'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('check-for-updates')));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v0.2.0'), findsOneWidget);
    expect(find.text('新增 Windows 版本。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('check-for-updates')),
      findsNothing,
    );
    expect(find.widgetWithText(FilledButton, '前往下载'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('open-release-page')));
    await tester.pumpAndSettle();
    expect(service.openedUri, release.pageUri);
  });

  testWidgets('没有更高版本时提示当前已是最新版本', (tester) async {
    final service = _FakeUpdateService(
      release: ReleaseInfo(
        version: VersionNumber.parse('0.1.0'),
        name: 'Version 0.1.0',
        notes: '',
        pageUri: Uri.parse('https://github.com/lmyybh/best_todo_list/releases'),
      ),
    );

    await _pumpDialog(tester, service);
    await tester.tap(find.byKey(const ValueKey<String>('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('open-release-page')),
      findsNothing,
    );
  });

  testWidgets('Windows 发现新版后启动应用内安装', (tester) async {
    final service = _FakeUpdateService(
      release: ReleaseInfo(
        version: VersionNumber.parse('0.2.0'),
        name: 'Version 0.2.0',
        notes: '',
        pageUri: Uri.parse('https://github.com/lmyybh/best_todo_list/releases'),
      ),
    );
    var installStarted = false;

    await _pumpDialog(
      tester,
      service,
      installUpdate: () async => installStarted = true,
    );
    await tester.tap(find.byKey(const ValueKey<String>('check-for-updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('install-update')));
    await tester.pumpAndSettle();

    expect(find.text('请在更新窗口中继续下载和安装'), findsOneWidget);
    expect(find.text('重新打开更新窗口'), findsOneWidget);
    expect(installStarted, isTrue);
    expect(service.openedUri, isNull);
  });

  testWidgets('检查异常时留在弹窗并显示错误', (tester) async {
    final service = _FakeUpdateService(
      error: const UpdateCheckException('网络不可用'),
    );

    await _pumpDialog(tester, service);
    await tester.tap(find.byKey(const ValueKey<String>('check-for-updates')));
    await tester.pumpAndSettle();

    expect(find.text('暂时无法检查更新，请稍后重试'), findsOneWidget);
    expect(find.text('关于与更新'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('网络不可用').hitTestable(), findsNothing);
    await tester.tap(find.text('查看错误详情'));
    await tester.pumpAndSettle();
    expect(find.text('网络不可用').hitTestable(), findsOneWidget);
  });

  testWidgets('检查失败后可原地重试并清除错误', (tester) async {
    final service = _FakeUpdateService(
      error: const UpdateCheckException('网络不可用'),
    );
    await _pumpDialog(tester, service);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    service.error = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('尚未发布可用版本'), findsOneWidget);
    expect(find.text('查看错误详情'), findsNothing);
  });

  testWidgets('版本读取失败后可以重试', (tester) async {
    final service = _FakeUpdateService(loadError: StateError('读取失败'));
    await _pumpDialog(tester, service);
    expect(find.text('无法读取当前版本，请重试'), findsOneWidget);
    service.loadError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('当前版本 v0.1.0'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('小窗口和长更新说明仍能访问安装按钮', (tester) async {
    tester.view.physicalSize = const Size(420, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeUpdateService(
      release: ReleaseInfo(
        version: VersionNumber.parse('0.2.0'),
        name: 'Version 0.2.0',
        notes: List.filled(50, '改善更新体验，修复已知问题。').join('\n'),
        pageUri: Uri.parse('https://example.com/releases'),
      ),
    );
    await _pumpDialog(tester, service);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('前往下载').hitTestable(), findsOneWidget);
    await tester.tap(find.text('前往下载'));
    await tester.pumpAndSettle();
    expect(service.openedUri, isNotNull);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester,
  UpdateService service, {
  Future<void> Function()? installUpdate,
}) async {
  final controller = UpdateController(service, installUpdate: installUpdate);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: AboutUpdateDialog(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeUpdateService implements UpdateService {
  _FakeUpdateService({this.release, this.error, this.loadError});

  final ReleaseInfo? release;
  Object? error;
  Object? loadError;
  Uri? openedUri;

  @override
  Future<ReleaseInfo?> fetchLatestRelease() async {
    if (error != null) throw error!;
    return release;
  }

  @override
  Future<AppVersion> loadCurrentVersion() async {
    if (loadError != null) throw loadError!;
    return const AppVersion(version: '0.1.0');
  }

  @override
  Future<bool> openReleasePage(Uri uri) async {
    openedUri = uri;
    return true;
  }
}
