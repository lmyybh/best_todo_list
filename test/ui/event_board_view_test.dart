import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/ui/events/event_board_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  testWidgets('事件卡片随桌面宽度分列并在同行保持等高', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'node-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final roots = <String>[];
    for (var index = 0; index < 8; index++) {
      final root = await controller.create(
        title: '事件 $index',
        selectCreated: false,
      );
      roots.add(root!.id);
    }
    for (var index = 0; index < 8; index++) {
      await controller.create(
        parentId: roots.first,
        title: '任务 $index',
        selectCreated: false,
      );
    }
    controller.showEventOverview();

    Future<void> expectColumns(double width, int expectedColumns) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(TodoApp(controller: controller));
      await tester.pumpAndSettle();
      final cards = <Finder>[
        for (final root in roots)
          find.byKey(ValueKey<String>('event-card-$root')),
      ];
      final firstRowY = tester.getTopLeft(cards.first).dy;
      final firstRowCount = cards
          .where((card) => (tester.getTopLeft(card).dy - firstRowY).abs() < 1)
          .length;
      expect(firstRowCount, expectedColumns);
    }

    await expectColumns(720, 1);
    await expectColumns(1100, 2);
    await expectColumns(1440, 3);

    final firstCard = find.byKey(ValueKey<String>('event-card-${roots.first}'));
    final firstRowPeer = find.byKey(ValueKey<String>('event-card-${roots[1]}'));
    final secondRowCard = find.byKey(
      ValueKey<String>('event-card-${roots[3]}'),
    );
    final lastRowCard = find.byKey(ValueKey<String>('event-card-${roots[6]}'));
    final newEventCard = find.byKey(const ValueKey<String>('new-event-card'));
    expect(
      tester.getSize(firstCard).height,
      tester.getSize(firstRowPeer).height,
    );
    expect(
      tester.getSize(firstCard).height,
      inInclusiveRange(
        EventBoardView.minimumCardHeight,
        EventBoardView.maximumCardHeight,
      ),
    );
    expect(
      tester.getSize(secondRowCard).height,
      lessThan(tester.getSize(firstCard).height),
    );
    expect(
      tester.getSize(lastRowCard).height,
      tester.getSize(newEventCard).height,
    );
    expect(
      find.byKey(ValueKey<String>('event-more-${roots.first}')),
      findsOneWidget,
    );
    expect(find.text('还有 3 项任务'), findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('event-tree-scroll-${roots.first}')),
      findsNothing,
    );
  });

  testWidgets('卡片内新增完成展开和菜单互不触发详情跳转', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'interaction-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await controller.create(title: 'sglang', selectCreated: false);
    final branch = await controller.create(
      parentId: root!.id,
      title: '论文阅读',
      selectCreated: false,
    );
    final task = await controller.create(
      parentId: branch!.id,
      title: '阅读 v4',
      selectCreated: false,
    );
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey<String>('event-row-${task!.id}'));
    final surface = find.byKey(
      ValueKey<String>('event-row-surface-${task.id}'),
    );
    final title = find.descendant(of: row, matching: find.text('阅读 v4'));
    expect(tester.getSize(row).width, tester.getSize(surface).width);
    expect(
      (tester.getCenter(title).dy - tester.getCenter(row).dy).abs(),
      lessThanOrEqualTo(1),
    );
    await tester.tapAt(tester.getTopRight(row) - const Offset(2, -18));
    await tester.pumpAndSettle();
    expect(controller.eventDetailOpen, isFalse);

    final quickAdd = find.byKey(ValueKey<String>('event-quick-add-${root.id}'));
    await tester.enterText(quickAdd, '本地实验');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('本地实验'), findsOneWidget);
    expect(controller.eventDetailOpen, isFalse);

    await tester.tap(find.byKey(ValueKey<String>('event-complete-${task.id}')));
    await tester.pumpAndSettle();
    expect(controller.tree.isComplete(task.id), isTrue);
    expect(find.text('阅读 v4'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('阅读 v4')).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(controller.eventDetailOpen, isFalse);

    await tester.tap(find.byKey(ValueKey<String>('event-expand-${branch.id}')));
    await tester.pumpAndSettle();
    expect(find.text('阅读 v4'), findsNothing);
    await tester.tap(find.byKey(ValueKey<String>('event-expand-${branch.id}')));
    await tester.pumpAndSettle();
    expect(find.text('阅读 v4'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey<String>('event-menu-${root.id}')));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.byType(MenuItemButton), findsNWidgets(2));
  });

  testWidgets('事件总览进入详情修改后可以返回并同步状态', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'detail-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final task = await controller.create(
      parentId: root!.id,
      title: '确认文案',
      selectCreated: false,
    );
    controller.showEventOverview();
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey<String>('event-row-title-${task!.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('event-detail-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('event-card-${root.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('detail-notes-field')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('detail-completion-toggle')),
    );
    await tester.pumpAndSettle();
    expect(controller.tree.isComplete(task.id), isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('back-to-event-board')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('event-card-${root.id}')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('确认文案')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('事件卡片最多预览两级任务结构', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'depth-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final first = await controller.create(
      parentId: root!.id,
      title: '准备阶段',
      selectCreated: false,
    );
    final second = await controller.create(
      parentId: first!.id,
      title: '内容检查',
      selectCreated: false,
    );
    await controller.create(
      parentId: second!.id,
      title: '检查错别字',
      selectCreated: false,
    );
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('准备阶段'), findsOneWidget);
    expect(find.text('内容检查'), findsOneWidget);
    expect(find.text('检查错别字'), findsNothing);
    expect(
      find.byKey(ValueKey<String>('event-nested-count-${second.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('event-expand-${second.id}')),
      findsNothing,
    );
  });
}
