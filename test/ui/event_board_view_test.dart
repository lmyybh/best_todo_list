import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/events/event_board_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  testWidgets('未完成事件可以归档并从已归档视图恢复，不弹出提示', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'event-archive-${++id}',
      ),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final event = await expectWriteSuccess(
      controller.create(title: '待办项目', selectCreated: false),
    );
    final task = await expectWriteSuccess(
      controller.create(
        parentId: event.id,
        title: '未完成事项',
        selectCreated: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => EventBoardView(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double baseline(String label) {
      final finder = find.text(label);
      final box = tester.renderObject<RenderBox>(finder);
      return tester.getTopLeft(finder).dy +
          box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
    }

    expect(baseline('已归档 0'), closeTo(baseline('1 个事件'), 0.01));
    expect(baseline('事件'), closeTo(baseline('1 个事件'), 0.01));
    expect(
      tester
          .getCenter(find.byKey(ValueKey<String>('event-drag-${event.id}')))
          .dx,
      tester
          .getCenter(find.byKey(ValueKey<String>('event-task-drag-${task.id}')))
          .dx,
    );
    final count = find.byKey(
      ValueKey<String>('event-header-count-${event.id}'),
    );
    final completed = find.byKey(
      ValueKey<String>('event-header-completed-${event.id}'),
    );
    final progress = find.byKey(
      ValueKey<String>('event-header-progress-${event.id}'),
    );
    expect(tester.getTopLeft(count).dy, tester.getTopLeft(completed).dy);
    expect(tester.getTopLeft(count).dx, tester.getTopLeft(progress).dx);
    expect(tester.getTopRight(completed).dx, tester.getTopRight(progress).dx);
    Future<void> choose(String label) async {
      await tester.tap(find.byKey(ValueKey<String>('event-menu-${event.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await choose('归档事件');
    expect(find.text('待办项目'), findsNothing);
    expect(controller.tree.nodes[task.id]!.status, TodoNodeStatus.active);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('event-archived-view')));
    await tester.pumpAndSettle();
    expect(find.text('待办项目'), findsOneWidget);
    expect(find.text('未完成事项'), findsOneWidget);
    await choose('恢复事件');
    expect(find.text('暂无已归档事件'), findsOneWidget);
    await tester.tap(find.text('返回事件'));
    await tester.pumpAndSettle();
    expect(find.text('待办项目'), findsOneWidget);
    expect(controller.tree.nodes[task.id]!.status, TodoNodeStatus.active);
  });

  testWidgets('卡片菜单批量收起已完成任务，不弹出提示', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'batch-${++id}',
      ),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final event = await expectWriteSuccess(
      controller.create(title: '事件', selectCreated: false),
    );
    final tasks = <TodoNode>[];
    for (final title in ['之前收起', '完成甲', '完成乙', '待处理']) {
      tasks.add(
        await expectWriteSuccess(
          controller.create(
            parentId: event.id,
            title: title,
            selectCreated: false,
          ),
        ),
      );
    }
    for (final task in tasks.take(3)) {
      await controller.setTaskStatus(task.id, TodoNodeStatus.completed);
    }
    await controller.setTaskArchived(tasks.first.id, true);
    final hiddenBranch = await expectWriteSuccess(
      controller.create(
        parentId: event.id,
        title: '已收起分支',
        selectCreated: false,
      ),
    );
    final hiddenChild = await expectWriteSuccess(
      controller.create(
        parentId: hiddenBranch.id,
        title: '分支内已完成任务',
        selectCreated: false,
      ),
    );
    await controller.setTaskStatus(hiddenChild.id, TodoNodeStatus.completed);
    await controller.setTaskArchived(hiddenBranch.id, true);
    await controller.setTaskArchived(tasks[1].id, true);
    await controller.setTaskArchived(tasks[2].id, true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => EventBoardView(controller: controller),
          ),
        ),
        theme: AppTheme.light(),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> openMenu() async {
      await tester.tap(find.byKey(ValueKey<String>('event-menu-${event.id}')));
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.ancestor(
              of: find.text('收起已完成'),
              matching: find.byType(PopupMenuItem<String>),
            ),
          )
          .enabled,
      isFalse,
    );
    await tester.tapAt(const Offset(10, 10));
    await controller.setTaskArchived(tasks[1].id, false);
    await controller.setTaskArchived(tasks[2].id, false);
    await tester.pumpAndSettle();
    await openMenu();
    await tester.tap(find.text('收起已完成'));
    await tester.pumpAndSettle();
    expect(find.text('完成甲'), findsNothing);
    expect(find.text('完成乙'), findsNothing);
    expect(find.text('待处理'), findsOneWidget);
    expect(controller.tree.nodes[hiddenChild.id]!.isArchived, isFalse);
    expect(controller.tree.nodes[event.id]!.isArchived, isFalse);
    await openMenu();
    expect(find.text('收起已完成'), findsOneWidget);
    final disabledAction = find.ancestor(
      of: find.text('收起已完成'),
      matching: find.byType(PopupMenuItem<String>),
    );
    expect(
      tester.widget<PopupMenuItem<String>>(disabledAction).enabled,
      isFalse,
    );
    await tester.tap(find.text('收起已完成'));
    await tester.pumpAndSettle();
    expect(find.text('收起已完成'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(controller.tree.nodes[tasks[1].id]!.isArchived, isTrue);
    expect(controller.tree.nodes[tasks[2].id]!.isArchived, isTrue);
    expect(controller.tree.nodes[tasks.first.id]!.isArchived, isTrue);
  });

  testWidgets('今日筛选展示今天和逾期任务的事件分支并提供空状态', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'focus-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final focusedEvent = await expectWriteSuccess(
      controller.create(title: '需要关注的事件', selectCreated: false),
    );
    final branch = await expectWriteSuccess(
      controller.create(
        parentId: focusedEvent.id,
        title: '保留的祖先分支',
        selectCreated: false,
      ),
    );
    final overdue = await expectWriteSuccess(
      controller.create(
        parentId: branch.id,
        title: '逾期任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 12),
        selectCreated: false,
      ),
    );
    final today = await expectWriteSuccess(
      controller.create(
        parentId: focusedEvent.id,
        title: '今日任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 13),
        selectCreated: false,
      ),
    );
    await controller.create(
      parentId: focusedEvent.id,
      title: '未来任务',
      deadline: DateOnlyDeadline(year: 2026, month: 8, day: 14),
      selectCreated: false,
    );
    final futureEvent = await expectWriteSuccess(
      controller.create(title: '未来事件', selectCreated: false),
    );
    await controller.create(
      parentId: futureEvent.id,
      title: '另一个未来任务',
      deadline: DateOnlyDeadline(year: 2026, month: 8, day: 15),
      selectCreated: false,
    );
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('event-board-toolbar')))
          .height,
      32,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('event-board-filter')))
          .height,
      32,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('event-board-filter')))
          .width,
      122,
    );
    expect(
      tester
          .widget<MouseRegion>(
            find.byKey(const ValueKey<String>('event-board-filter-cursor')),
          )
          .cursor,
      SystemMouseCursors.click,
    );
    var filter = tester
        .widget<CupertinoSlidingSegmentedControl<EventBoardFilter>>(
          find.byKey(const ValueKey<String>('event-board-filter-control')),
        );
    expect(filter.groupValue, EventBoardFilter.all);
    expect(filter.backgroundColor, const Color(0xFFECEDE9));
    expect(filter.thumbColor, const Color(0xFFC9DED9));
    expect(filter.padding, const EdgeInsets.all(2));
    expect(filter.proportionalWidth, isTrue);
    expect(find.text('今日'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('event-board-today-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('event-card-${futureEvent.id}')),
      findsOneWidget,
    );

    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    expect(controller.eventBoardFilter, EventBoardFilter.todayFocus);
    filter = tester.widget<CupertinoSlidingSegmentedControl<EventBoardFilter>>(
      find.byKey(const ValueKey<String>('event-board-filter-control')),
    );
    expect(filter.groupValue, EventBoardFilter.todayFocus);
    expect(
      find.byKey(ValueKey<String>('event-card-${focusedEvent.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('event-card-${futureEvent.id}')),
      findsNothing,
    );
    expect(find.text('保留的祖先分支'), findsOneWidget);
    expect(find.text('逾期任务'), findsOneWidget);
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('未来任务'), findsNothing);
    expect(find.byKey(const ValueKey<String>('event-new-card')), findsNothing);
    expect(
      find.byKey(ValueKey<String>('event-drag-${focusedEvent.id}')),
      findsNothing,
    );
    expect(
      find.byKey(
        ValueKey<String>('event-quick-add-trigger-${focusedEvent.id}'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(ValueKey<String>('event-complete-${overdue.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('event-board-today-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(ValueKey<String>('event-complete-${today.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天没有需要关注的任务'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('event-board-today-count')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('查看全部事件'));
    await tester.pumpAndSettle();
    expect(controller.eventBoardFilter, EventBoardFilter.all);
    expect(
      find.byKey(ValueKey<String>('event-card-${futureEvent.id}')),
      findsOneWidget,
    );
  });

  testWidgets('事件卡片随桌面宽度分列并在同行保持等高', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
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
      final root = await expectWriteSuccess(
        controller.create(title: '事件 $index', selectCreated: false),
      );
      roots.add(root.id);
    }
    for (var index = 0; index < 8; index++) {
      await controller.create(
        parentId: roots.first,
        title: '任务 $index',
        selectCreated: false,
      );
    }
    controller.showEventOverview();

    Future<Size> expectLayout(
      double width,
      double height,
      int expectedColumns,
      double expectedPanelPadding, {
      bool expectReflowAnimation = false,
    }) async {
      await tester.binding.setSurfaceSize(Size(width, height));
      await tester.pumpWidget(TodoApp(controller: controller));
      await tester.pump();
      if (expectReflowAnimation) {
        expect(
          tester
              .widget<AnimatedPositioned>(
                find.byKey(ValueKey<String>('event-layout-${roots.first}')),
              )
              .duration,
          const Duration(milliseconds: 140),
        );
      }
      await tester.pumpAndSettle();
      final boardScroll = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('event-board-scroll')),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(
        boardScroll.padding,
        EdgeInsets.fromLTRB(
          expectedPanelPadding,
          expectedPanelPadding,
          expectedPanelPadding,
          expectedPanelPadding + 8,
        ),
      );
      final newEventCard = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey<String>('event-new-card')),
      );
      expect(
        newEventCard.style?.mouseCursor?.resolve(const <WidgetState>{}),
        SystemMouseCursors.click,
      );
      final cards = <Finder>[
        for (final root in roots)
          find.byKey(ValueKey<String>('event-card-$root')),
      ];
      final firstRowY = tester.getTopLeft(cards.first).dy;
      final firstRowCount = cards
          .where((card) => (tester.getTopLeft(card).dy - firstRowY).abs() < 1)
          .length;
      expect(firstRowCount, expectedColumns);
      final cardSize = tester.getSize(cards.first);
      if (expectedColumns > 1) {
        expect(
          cardSize.width,
          inInclusiveRange(
            EventBoardView.minimumCardWidth,
            EventBoardView.maximumCardWidth,
          ),
        );
      } else {
        expect(
          cardSize.width,
          lessThanOrEqualTo(EventBoardView.singleColumnMaximumWidth),
        );
      }
      expect(
        tester
            .getCenter(find.byKey(const ValueKey<String>('event-board-wrap')))
            .dx,
        closeTo(
          tester
              .getCenter(
                find.byKey(const ValueKey<String>('event-board-scroll')),
              )
              .dx,
          1,
        ),
      );
      return cardSize;
    }

    await expectLayout(500, 900, 1, 16);
    await expectLayout(720, 900, 2, 20, expectReflowAnimation: true);
    await expectLayout(900, 900, 2, 20);
    await expectLayout(1100, 900, 3, 20, expectReflowAnimation: true);
    final tallCardSize = await expectLayout(
      1440,
      900,
      4,
      24,
      expectReflowAnimation: true,
    );
    final shortCardSize = await expectLayout(1440, 600, 4, 24);
    expect(shortCardSize.height, lessThan(tallCardSize.height));
    final ultraWideCardSize = await expectLayout(1900, 900, 4, 24);
    expect(
      ultraWideCardSize.width,
      closeTo(EventBoardView.maximumCardWidth, 0.1),
    );
    await expectLayout(1440, 900, 4, 24);

    final firstCard = find.byKey(ValueKey<String>('event-card-${roots.first}'));
    final firstRowPeer = find.byKey(ValueKey<String>('event-card-${roots[1]}'));
    final secondRowCard = find.byKey(
      ValueKey<String>('event-card-${roots[4]}'),
    );
    final lastRowCard = find.byKey(ValueKey<String>('event-card-${roots[7]}'));
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
    await cardDrag.moveBy(const Offset(1, 0));
    await tester.pump();
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

  testWidgets('事件总览进入详情修改后可以返回并同步状态', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'detail-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await expectWriteSuccess(
      controller.create(title: '发布计划', selectCreated: false),
    );
    final task = await expectWriteSuccess(
      controller.create(parentId: root.id, title: '确认文案', selectCreated: false),
    );
    controller.showEventOverview();
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey<String>('event-row-${task.id}')));
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

  testWidgets('事件拖动支持边缘滚动、Esc 取消和键盘排序', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'drag-a11y-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final roots = <String>[];
    for (var index = 0; index < 8; index++) {
      final root = await expectWriteSuccess(
        controller.create(title: '事件 $index', selectCreated: false),
      );
      roots.add(root.id);
    }
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(720, 600));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final firstHandle = find.byKey(
      ValueKey<String>('event-drag-${roots.first}'),
    );
    Color? firstCardColor() => tester
        .widget<LinearProgressIndicator>(
          find.descendant(
            of: find.byKey(ValueKey<String>('event-card-${roots.first}')),
            matching: find.byType(LinearProgressIndicator),
          ),
        )
        .color;
    final originalColor = firstCardColor();
    await tester.tap(firstHandle);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
      controller.tree.childrenOf(null).take(2).map((node) => node.id),
      <String>[roots[1], roots.first],
    );
    expect(firstCardColor(), originalColor);

    final reorderedHandle = find.byKey(
      ValueKey<String>('event-drag-${roots.first}'),
    );
    final drag = await tester.startGesture(tester.getCenter(reorderedHandle));
    await drag.moveBy(const Offset(0, 20));
    await drag.moveTo(const Offset(350, 590));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final boardScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('event-board-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(boardScrollable.position.pixels, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await drag.up();
    await tester.pumpAndSettle();
    expect(controller.tree.childrenOf(null).map((node) => node.id), <String>[
      roots[1],
      roots.first,
      ...roots.skip(2),
    ]);
  });

  testWidgets('事件卡片内输入不会改变事件面板滚动位置', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'scroll-child-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rootIds = <String>[];
    final taskIds = <String>[];
    for (var index = 0; index < 8; index++) {
      final root = await expectWriteSuccess(
        controller.create(title: '事件 $index', selectCreated: false),
      );
      final task = await expectWriteSuccess(
        controller.create(
          parentId: root.id,
          title: '任务 $index',
          selectCreated: false,
        ),
      );
      rootIds.add(root.id);
      taskIds.add(task.id);
    }
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(720, 600));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final boardScroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('event-board-scroll')),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final boardController = boardScroll.controller!;
    boardController.jumpTo(boardController.position.maxScrollExtent * 0.55);
    await tester.pump();

    final targetId = taskIds.firstWhere(
      (taskId) => find
          .byKey(ValueKey<String>('event-row-$taskId'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    final row = find.byKey(ValueKey<String>('event-row-$targetId'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(row));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 150));
    final offsetBeforeCreate = boardController.offset;

    await tester.tap(find.byKey(ValueKey<String>('event-add-child-$targetId')));
    await tester.pumpAndSettle();

    expect(boardController.offset, closeTo(offsetBeforeCreate, 0.1));
    expect(
      find.byKey(const ValueKey<String>('event-inline-draft-input')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final renameOffset = boardController.offset;
    final title = find.byKey(ValueKey<String>('event-row-title-$targetId'));
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(boardController.offset, closeTo(renameOffset, 0.1));
    expect(
      find.byKey(ValueKey<String>('event-inline-rename-$targetId')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final quickAddRootId = rootIds.firstWhere(
      (rootId) => find
          .byKey(ValueKey<String>('event-quick-add-trigger-$rootId'))
          .hitTestable()
          .evaluate()
          .isNotEmpty,
    );
    final quickAddOffset = boardController.offset;
    await tester.tap(
      find.byKey(ValueKey<String>('event-quick-add-trigger-$quickAddRootId')),
    );
    await tester.pumpAndSettle();
    expect(boardController.offset, closeTo(quickAddOffset, 0.1));
    expect(
      find.byKey(ValueKey<String>('event-quick-add-$quickAddRootId')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(ValueKey<String>('event-quick-add-$quickAddRootId')),
      '快速新增任务',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(boardController.offset, closeTo(quickAddOffset, 0.1));
  });
}
