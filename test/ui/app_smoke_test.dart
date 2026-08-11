import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/ui/common/node_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  late MemoryNodeRepository repository;
  late AppController controller;
  var id = 0;

  setUp(() async {
    repository = MemoryNodeRepository();
    controller = AppController(
      NodeService(
        repository,
        clock: () => DateTime.utc(2026, 8, 11, 9),
        idGenerator: () => 'node-${++id}',
      ),
      clock: () => DateTime(2026, 8, 11, 9),
    );
    await controller.load();
  });

  testWidgets('空应用展示引导并可创建顶层事件', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('从一件想完成的事开始'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '新建事件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新版发布');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(find.text('新版发布'), findsWidgets);
    expect(controller.nodes, hasLength(1));
  });

  testWidgets('事件详情可快速新增并完成叶子任务', (tester) async {
    final root = await controller.create(title: '新版发布');
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final quickAdd = find.widgetWithText(TextField, '添加一个子任务…');
    expect(quickAdd, findsOneWidget);
    await tester.enterText(quickAdd, '确认最终文案');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('确认最终文案'), findsWidgets);
    expect(controller.selectedId, root!.id);
    final child = controller.tree.childrenOf(root.id).single;
    await controller.setCompleted(child.id, true);
    await tester.pumpAndSettle();
    expect(controller.tree.isComplete(root.id), isTrue);
  });

  testWidgets('时间线切换和已完成开关可用', (tester) async {
    final root = await controller.create(title: '有日期任务');
    await controller.updateDeadline(root!.id, DateTime(2026, 8, 11, 16));
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('时间线').first);
    await tester.pumpAndSettle();
    expect(find.text('把注意力留给眼前的事'), findsOneWidget);
    expect(find.text('有日期任务'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('逾期任务卡片使用明确的可见标题颜色', (tester) async {
    final task = await controller.create(title: '逾期任务');
    await controller.updateDeadline(task!.id, DateTime(2026, 8, 11, 8));
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('已逾期'), findsOneWidget);
    final titleFinder = find.descendant(
      of: find.byType(NodeTile),
      matching: find.text('逾期任务'),
    );
    expect(titleFinder, findsOneWidget);
    final title = tester.widget<Text>(titleFinder);
    expect(
      title.style?.color,
      Theme.of(tester.element(titleFinder)).colorScheme.onSurface,
    );
  });
}
