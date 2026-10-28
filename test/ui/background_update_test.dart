import 'dart:io';

import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/services/update_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_update_delivery.dart';
import '../helpers/memory_node_repository.dart';

void main() {
  testWidgets('关闭弹窗继续下载，重新打开保留进度，完成后可重启更新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController(NodePersistenceWorkspace(MemoryNodeRepository()));
    final delivery = FakeDelivery();
    final updates = UpdateController(FakeService(), delivery: delivery);
    addTearDown(app.dispose);
    addTearDown(updates.dispose);
    await app.load();
    await updates.initialize();
    await updates.check();
    await tester.pumpWidget(TodoApp(controller: app, updates: updates));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('about-update-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载更新'));
    await tester.pump();
    delivery.progress(50, 100);
    await tester.pump();
    expect(find.text('50% · 0.0 / 0.0 MB'), findsOneWidget);
    await tester.tap(find.text('后台下载'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(updates.state.downloading, isTrue);
    expect(find.byTooltip('更新下载中 · 50%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about-update-navigation')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('50% · 0.0 / 0.0 MB'), findsOneWidget);
    delivery.downloaded.complete(File('fixture.exe'));
    await tester.pumpAndSettle();
    expect(find.text('重启并更新'), findsOneWidget);
    expect(delivery.installCount, 0);
    await tester.tap(find.text('重启并更新'));
    await tester.pumpAndSettle();
    expect(delivery.installCount, 1);
  });
}
