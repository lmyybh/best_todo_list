import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/ui/events/event_board_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final firstCardSurface = find.byKey(
      ValueKey<String>('event-card-surface-${roots.first}'),
    );
    final cardSizeBeforeHover = tester.getSize(firstCard);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(firstCard));
    await mouse.moveTo(tester.getCenter(firstCard));
    await tester.pump(const Duration(milliseconds: 150));
    final hoveredCard = tester.widget<AnimatedContainer>(firstCardSurface);
    final hoveredDecoration = hoveredCard.decoration as BoxDecoration;
    expect(hoveredDecoration.boxShadow, isNotEmpty);
    expect(tester.getSize(firstCard), cardSizeBeforeHover);
    final dragHandle = find.byKey(
      ValueKey<String>('event-drag-${roots.first}'),
    );
    final firstTitle = find.byKey(
      ValueKey<String>('event-title-${roots.first}'),
    );
    expect(
      tester.getCenter(dragHandle).dx,
      lessThan(tester.getCenter(firstTitle).dx),
    );
    final thirdCard = find.byKey(ValueKey<String>('event-card-${roots[2]}'));
    final firstPosition = tester.getTopLeft(firstCard);
    final secondPosition = tester.getTopLeft(firstRowPeer);
    final thirdPosition = tester.getTopLeft(thirdCard);
    final cardDrag = await tester.startGesture(tester.getCenter(dragHandle));
    await cardDrag.moveBy(const Offset(5, 0));
    await cardDrag.moveTo(
      tester.getCenter(thirdCard) +
          Offset(tester.getSize(thirdCard).width / 4, 0),
    );
    await cardDrag.moveBy(const Offset(1, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(ValueKey<String>('event-drag-source-${roots.first}')),
          )
          .opacity,
      0.16,
    );
    expect(tester.getTopLeft(firstRowPeer), firstPosition);
    expect(tester.getTopLeft(thirdCard), secondPosition);
    expect(tester.getTopLeft(firstCard), thirdPosition);
    await cardDrag.up();
    await tester.pumpAndSettle();
    expect(
      controller.tree.childrenOf(null).take(3).map((node) => node.id),
      <String>[roots[1], roots[2], roots.first],
    );
    expect(
      find.byKey(ValueKey<String>('event-more-${roots.first}')),
      findsNothing,
    );
    expect(find.text('还有 3 项任务'), findsNothing);
    final taskScroll = find.byKey(
      ValueKey<String>('event-tree-scroll-${roots.first}'),
    );
    expect(taskScroll, findsOneWidget);
    expect(
      find.byKey(ValueKey<String>('event-tree-scrollbar-${roots.first}')),
      findsOneWidget,
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: taskScroll, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(taskScroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('任务 7'), findsOneWidget);
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
    expect(controller.eventDetailOpen, isTrue);
    expect(controller.selectedId, task.id);
    controller.showEventOverview();
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(row));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 150));
    final hoveredSurface = tester.widget<DecoratedBox>(surface);
    final hoveredDecoration = hoveredSurface.decoration as BoxDecoration;
    expect(
      hoveredDecoration.color,
      AppColors.of(tester.element(row)).surfaceHover,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(ValueKey<String>('event-row-actions-${task.id}')),
          )
          .opacity,
      1,
    );
    expect(tester.getSize(row).width, tester.getSize(surface).width);
    final branchRow = find.byKey(ValueKey<String>('event-row-${branch.id}'));
    final branchSurface = find.byKey(
      ValueKey<String>('event-row-surface-${branch.id}'),
    );
    await mouse.moveTo(tester.getCenter(branchRow));
    await tester.pump();
    expect(
      (tester.widget<DecoratedBox>(surface).decoration as BoxDecoration).color,
      Colors.transparent,
    );
    expect(
      (tester.widget<DecoratedBox>(branchSurface).decoration as BoxDecoration)
          .color,
      AppColors.of(tester.element(branchRow)).surfaceHover,
    );
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey<String>('event-row-menu-${task.id}')));
    await tester.pumpAndSettle();
    expect(controller.eventDetailOpen, isFalse);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tapAt(const Offset(900, 700));
    await tester.pumpAndSettle();

    final quickAdd = find.byKey(ValueKey<String>('event-quick-add-${root.id}'));
    expect(quickAdd, findsNothing);
    await tester.tap(
      find.byKey(ValueKey<String>('event-quick-add-trigger-${root.id}')),
    );
    await tester.pumpAndSettle();
    expect(quickAdd, findsOneWidget);
    await tester.enterText(quickAdd, '本地实验');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('本地实验'), findsOneWidget);
    expect(controller.eventDetailOpen, isFalse);
    final created = controller.tree.childrenOf(root.id).last;
    final createdSurface = find.byKey(
      ValueKey<String>('event-row-surface-${created.id}'),
    );
    expect(
      (tester.widget<DecoratedBox>(createdSurface).decoration as BoxDecoration)
          .color,
      AppColors.of(tester.element(createdSurface)).accentSoft,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(quickAdd, findsNothing);

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

    await tester.tap(find.byKey(ValueKey<String>('event-row-${task!.id}')));
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
    expect(
      find.byKey(const ValueKey<String>('event-detail-panel')),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(300, 700));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('event-detail-panel')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey<String>('event-card-${root.id}')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('确认文案')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('卡片内子任务可以在同一父任务下拖拽排序', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'reorder-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final first = await controller.create(
      parentId: root!.id,
      title: '第一步',
      selectCreated: false,
    );
    final second = await controller.create(
      parentId: root.id,
      title: '第二步',
      selectCreated: false,
    );
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final firstRow = find.byKey(ValueKey<String>('event-row-${first!.id}'));
    final secondRow = find.byKey(ValueKey<String>('event-row-${second!.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(secondRow));
    await mouse.moveTo(tester.getCenter(secondRow));
    await tester.pump(const Duration(milliseconds: 150));
    final handle = find.byKey(ValueKey<String>('event-task-drag-${second.id}'));
    final completion = find.byKey(
      ValueKey<String>('event-complete-${second.id}'),
    );
    expect(
      tester.getCenter(handle).dx,
      lessThan(tester.getCenter(completion).dx),
    );
    final taskDrag = await tester.startGesture(tester.getCenter(handle));
    await taskDrag.moveBy(const Offset(5, 0));
    await taskDrag.moveTo(tester.getCenter(firstRow));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(ValueKey<String>('event-task-drag-source-${second.id}')),
          )
          .opacity,
      0.38,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(ValueKey<String>('event-task-drop-${first.id}')),
          )
          .opacity,
      1,
    );
    await taskDrag.up();
    await tester.pumpAndSettle();

    expect(controller.tree.childrenOf(root.id).map((node) => node.id), <String>[
      second.id,
      first.id,
    ]);
    expect(controller.eventDetailOpen, isFalse);
  });

  testWidgets('子任务 hover 后可以直接新建它的子任务', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'child-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final task = await controller.create(
      parentId: root!.id,
      title: '检查文案',
      selectCreated: false,
    );
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey<String>('event-row-${task!.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(row));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(
      find.byKey(ValueKey<String>('event-add-child-${task.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('新建子任务'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '检查链接');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      controller.tree.childrenOf(task.id).map((node) => node.title),
      <String>['检查链接'],
    );
    expect(controller.eventDetailOpen, isFalse);
  });

  testWidgets('事件卡片默认预览三级任务结构', (tester) async {
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
    final third = await controller.create(
      parentId: second!.id,
      title: '检查错别字',
      selectCreated: false,
    );
    await controller.create(
      parentId: third!.id,
      title: '复核标点',
      selectCreated: false,
    );
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('准备阶段'), findsOneWidget);
    expect(find.text('内容检查'), findsOneWidget);
    expect(find.text('检查错别字'), findsOneWidget);
    expect(find.text('复核标点'), findsNothing);
    expect(
      find.byKey(ValueKey<String>('event-nested-count-${third.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('event-expand-${third.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey<String>('event-expand-${second.id}')),
      findsOneWidget,
    );
  });
}
