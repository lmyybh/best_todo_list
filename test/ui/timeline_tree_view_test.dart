import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  testWidgets('时间线铺开顶层事件并可展开当天任务的嵌套事件', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'timeline-tree-${++id}',
      ),
      clock: () => DateTime(2026, 9, 11, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = await expectWriteSuccess(
      controller.create(title: '工作项目', selectCreated: false),
    );
    final phase = await expectWriteSuccess(
      controller.create(parentId: root.id, title: '发布准备', selectCreated: false),
    );
    final task = await expectWriteSuccess(
      controller.create(
        parentId: phase.id,
        title: '检查安装包',
        deadline: TimedDeadline(DateTime(2026, 9, 11, 11)),
        selectCreated: false,
      ),
    );
    await controller.create(
      parentId: phase.id,
      title: '明天发布',
      deadline: TimedDeadline(DateTime(2026, 9, 12, 10)),
      selectCreated: false,
    );
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('工作项目'), findsOneWidget);
    expect(find.text('发布准备'), findsOneWidget);
    expect(find.text('检查安装包'), findsNothing);
    expect(find.text('明天发布'), findsNothing);
    expect(find.textContaining('上下文'), findsNothing);
    expect(find.text('1 项相关 · 0/2 已完成'), findsNWidgets(2));
    expect(find.byIcon(Icons.account_tree_outlined), findsNothing);

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-expand-${phase.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('检查安装包'), findsOneWidget);
    expect(find.text('明天发布'), findsNothing);

    final rootTitle = find.descendant(
      of: find.byKey(ValueKey<String>('timeline-row-${root.id}')),
      matching: find.text('工作项目'),
    );
    final phaseTitle = find.descendant(
      of: find.byKey(ValueKey<String>('timeline-row-${phase.id}')),
      matching: find.text('发布准备'),
    );
    final taskTitle = find.descendant(
      of: find.byKey(ValueKey<String>('timeline-row-${task.id}')),
      matching: find.text('检查安装包'),
    );
    final colors = AppColors.of(tester.element(phaseTitle));
    expect(tester.widget<Text>(rootTitle).style?.fontSize, 10);
    expect(tester.widget<Text>(phaseTitle).style?.fontSize, 13);
    expect(tester.widget<Text>(phaseTitle).style?.color, colors.muted);
    expect(tester.widget<Text>(taskTitle).style?.fontSize, 14);

    await controller.updateDeadline(
      phase.id,
      TimedDeadline(DateTime(2026, 9, 11, 11)),
    );
    await tester.pumpAndSettle();
    final phaseDeadline = find.descendant(
      of: find.byKey(ValueKey<String>('timeline-row-${phase.id}')),
      matching: find.text('9 月 11 日，11:00'),
    );
    final taskDeadline = find.descendant(
      of: find.byKey(ValueKey<String>('timeline-row-${task.id}')),
      matching: find.text('9 月 11 日，11:00'),
    );
    expect(
      tester.getTopRight(phaseDeadline).dx,
      closeTo(tester.getTopRight(taskDeadline).dx, 0.1),
    );

    await tester.tap(
      find.byKey(ValueKey<String>('timeline-expand-${phase.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('检查安装包'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('timeline-toggle-all')));
    await tester.pumpAndSettle();
    expect(find.text('检查安装包'), findsOneWidget);
    expect(find.text('折叠全部'), findsOneWidget);
  });

  testWidgets('已完成区域突出实际结果并将祖先降为路径', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        clock: () => DateTime(2026, 9, 11, 10, 24),
        idGenerator: () => 'timeline-result-${++id}',
      ),
      clock: () => DateTime(2026, 9, 11, 12),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final root = await expectWriteSuccess(
      controller.create(title: '工作项目', selectCreated: false),
    );
    final phase = await expectWriteSuccess(
      controller.create(parentId: root.id, title: '发布准备', selectCreated: false),
    );
    final task = await expectWriteSuccess(
      controller.create(
        parentId: phase.id,
        title: '检查安装包',
        deadline: TimedDeadline(DateTime(2026, 9, 7, 21)),
        selectCreated: false,
      ),
    );
    await controller.setTaskStatus(task.id, TodoNodeStatus.completed);
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('timeline-activity-${task.id}')),
      findsOneWidget,
    );
    expect(find.text('检查安装包'), findsOneWidget);
    expect(find.text('工作项目 / 发布准备'), findsOneWidget);
    expect(find.text('10:24 完成'), findsOneWidget);
    expect(find.text('原定 9 月 7 日，21:00'), findsOneWidget);
    expect(find.text('0待办 · 1完成'), findsOneWidget);
    expect(find.text('今天的待办已全部完成'), findsOneWidget);
    expect(find.textContaining('上下文'), findsNothing);
    expect(
      find.byKey(ValueKey<String>('timeline-expand-${root.id}')),
      findsNothing,
    );

    await tester.tap(find.byTooltip('取消完成'));
    await tester.pumpAndSettle();
    expect(controller.tree.nodes[task.id]!.status, TodoNodeStatus.active);
  });
}
