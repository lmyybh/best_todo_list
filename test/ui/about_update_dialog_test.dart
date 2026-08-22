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

    expect(find.text('当前版本 0.1.0+1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('check-for-updates')));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 0.2.0'), findsOneWidget);
    expect(find.text('新增 Windows 版本。'), findsOneWidget);

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

    expect(find.text('下载并安装'), findsOneWidget);
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

    expect(find.text('检查失败：网络不可用'), findsOneWidget);
    expect(find.text('关于 todo'), findsOneWidget);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester,
  UpdateService service, {
  Future<void> Function()? installUpdate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: AboutUpdateDialog(
            service: service,
            installUpdate: installUpdate,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeUpdateService implements UpdateService {
  _FakeUpdateService({this.release, this.error});

  final ReleaseInfo? release;
  final Object? error;
  Uri? openedUri;

  @override
  Future<ReleaseInfo?> fetchLatestRelease() async {
    if (error != null) throw error!;
    return release;
  }

  @override
  Future<AppVersion> loadCurrentVersion() async {
    return const AppVersion(version: '0.1.0', buildNumber: '1');
  }

  @override
  Future<bool> openReleasePage(Uri uri) async {
    openedUri = uri;
    return true;
  }
}
