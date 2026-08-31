import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/events/event_card_task_interaction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_node_repository.dart';
import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  testWidgets('事件卡片任务交互通过根事件展示子任务', (tester) async {
    final fixture = await _InteractionFixture.create();
    await fixture.createTask(title: '检查发布说明');
    await fixture.pump(tester);

    expect(find.text('检查发布说明'), findsOneWidget);
  });

  testWidgets('不需要宿主监听控制器也会展示新增任务', (tester) async {
    final fixture = await _InteractionFixture.create(
      idPrefix: 'self-listening',
    );
    await fixture.pump(tester);

    await fixture.createTask(title: '新增发布检查');
    await tester.pumpAndSettle();

    expect(find.text('新增发布检查'), findsOneWidget);
  });

  testWidgets('替换控制器后重命名写入新控制器', (tester) async {
    final first = await _InteractionFixture.create(idPrefix: 'replacement');
    final firstTask = await first.createTask(title: '旧控制器任务');
    await first.pump(tester);

    final second = await _InteractionFixture.create(idPrefix: 'replacement');
    final secondTask = await second.createTask(title: '新控制器任务');
    expect(secondTask.id, firstTask.id);
    await second.pump(tester);

    final title = find.byKey(
      ValueKey<String>('event-row-title-${secondTask.id}'),
    );
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ValueKey<String>('event-inline-rename-${secondTask.id}')),
      '替换后标题',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(second.controller.tree.nodes[secondTask.id]?.title, '替换后标题');
    expect(first.controller.tree.nodes[firstTask.id]?.title, '旧控制器任务');
  });

  testWidgets('可以从任务行内联创建更深层子任务', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'nested');
    final child = await fixture.createTask(title: '检查发布说明');
    await fixture.pump(tester);

    final row = find.byKey(ValueKey<String>('event-row-${child.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(row));
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey<String>('event-add-child-${child.id}')),
    );
    await tester.pumpAndSettle();
    final draftSurface = find.byKey(
      const ValueKey<String>('event-inline-draft-surface'),
    );
    expect(draftSurface.hitTestable(), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('event-inline-draft-input')),
      '复核变更记录',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('复核变更记录'), findsOneWidget);
    expect(fixture.controller.eventDetailOpen, isFalse);
  });

  testWidgets('受限高度下底部任务的子任务草稿完整可见', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'bottom-draft');
    final parent = await fixture.createTask(title: '发布阶段');
    late String targetId;
    for (var index = 0; index < 10; index++) {
      final task = await fixture.createTask(
        parentId: parent.id,
        title: '任务 $index',
      );
      targetId = task.id;
    }
    await fixture.pump(tester, height: 260);

    final taskScroll = find.byKey(
      ValueKey<String>('event-tree-scroll-${fixture.root.id}'),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: taskScroll, matching: find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();

    final targetRow = find.byKey(ValueKey<String>('event-row-$targetId'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(targetRow));
    await mouse.moveTo(tester.getCenter(targetRow));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey<String>('event-add-child-$targetId')));
    await tester.pumpAndSettle();

    final draftSurface = find.byKey(
      const ValueKey<String>('event-inline-draft-surface'),
    );
    expect(draftSurface, findsOneWidget);
    expect(
      tester.getBottomRight(draftSurface).dy,
      lessThanOrEqualTo(tester.getBottomRight(taskScroll).dy),
    );
  });

  testWidgets('卡片触及边界后下一次独立滚动才接力事件页面', (tester) async {
    final fixture = await _InteractionFixture.create(
      idPrefix: 'scroll-handoff',
    );
    for (var index = 0; index < 12; index++) {
      await fixture.createTask(title: '任务 $index');
    }
    final pageScrollController = ScrollController();
    addTearDown(pageScrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: pageScrollController,
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: 420,
                  height: 260,
                  child: EventCardTaskInteraction(
                    controller: fixture.controller,
                    rootEventId: fixture.root.id,
                  ),
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final taskScroll = find.byKey(
      ValueKey<String>('event-tree-scroll-${fixture.root.id}'),
    );
    final taskScrollable = tester.state<ScrollableState>(
      find.descendant(of: taskScroll, matching: find.byType(Scrollable)).first,
    );
    final scrollPosition = tester.getCenter(taskScroll);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: scrollPosition,
        scrollDelta: const Offset(0, 10000),
      ),
    );
    await tester.pump();
    expect(
      taskScrollable.position.pixels,
      taskScrollable.position.maxScrollExtent,
    );
    expect(pageScrollController.offset, 0);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: scrollPosition,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();
    expect(pageScrollController.offset, 0);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: scrollPosition,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();
    expect(pageScrollController.offset, greaterThan(0));

    pageScrollController.jumpTo(80);
    taskScrollable.position.jumpTo(taskScrollable.position.maxScrollExtent);
    await tester.pump();
    final upperScrollPosition = tester.getCenter(taskScroll);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: upperScrollPosition,
        scrollDelta: const Offset(0, -10000),
      ),
    );
    await tester.pump();
    expect(
      taskScrollable.position.pixels,
      taskScrollable.position.minScrollExtent,
    );
    expect(pageScrollController.offset, 80);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: upperScrollPosition,
        scrollDelta: const Offset(0, -80),
      ),
    );
    await tester.pump();
    expect(pageScrollController.offset, 80);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: upperScrollPosition,
        scrollDelta: const Offset(0, -80),
      ),
    );
    await tester.pump();
    expect(pageScrollController.offset, lessThan(80));
  });

  testWidgets('重命名写入失败时保留输入和焦点以便重试', (tester) async {
    final repository = FailingNodeRepository();
    final fixture = await _InteractionFixture.create(
      repository: repository,
      idPrefix: 'rename-failure',
    );
    final child = await fixture.createTask(title: '检查发布说明');
    await fixture.pump(tester);

    final title = find.byKey(ValueKey<String>('event-row-title-${child.id}'));
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pumpAndSettle();
    final input = find.byKey(
      ValueKey<String>('event-inline-rename-${child.id}'),
    );
    expect(input, findsOneWidget);

    repository.failNextUpdate = true;
    await tester.enterText(input, '检查最终发布说明');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(input, findsOneWidget);
    expect(find.byTooltip('保存失败，请重试'), findsOneWidget);
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isTrue);
    expect(fixture.controller.tree.nodes[child.id]?.title, '检查发布说明');
  });

  testWidgets('新增写入失败时保留草稿和焦点以便重试', (tester) async {
    final repository = FailingNodeRepository();
    final fixture = await _InteractionFixture.create(
      repository: repository,
      idPrefix: 'draft-failure',
    );
    final child = await fixture.createTask(title: '检查发布说明');
    await fixture.pump(tester);

    await tester.tap(find.byKey(ValueKey<String>('event-row-${child.id}')));
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey<String>('event-add-child-${child.id}')),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(
      const ValueKey<String>('event-inline-draft-input'),
    );
    await tester.enterText(input, '复核变更记录');

    repository.failNextInsert = true;
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).controller?.text, '复核变更记录');
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isTrue);
    expect(fixture.controller.error, isNotNull);
  });

  testWidgets('默认预览三级任务结构并可继续展开', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'depth');
    final first = await fixture.createTask(title: '准备阶段');
    final second = await fixture.createTask(parentId: first.id, title: '内容检查');
    final third = await fixture.createTask(parentId: second.id, title: '检查错别字');
    await fixture.createTask(parentId: third.id, title: '复核标点');
    await fixture.pump(tester);

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
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey<String>('event-expand-${second.id}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey<String>('event-expand-${third.id}')));
    await tester.pumpAndSettle();
    expect(find.text('复核标点'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey<String>('event-expand-${third.id}')));
    await tester.pumpAndSettle();
    expect(find.text('复核标点'), findsNothing);
  });

  testWidgets('同一父任务下支持拖拽取消和键盘排序', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'reorder');
    final controller = fixture.controller;
    final root = fixture.root;
    final first = await fixture.createTask(title: '第一步');
    final second = await fixture.createTask(title: '第二步');
    final secondChild = await fixture.createTask(
      parentId: second.id,
      title: '第二步的子任务',
    );
    await fixture.pump(tester);

    final firstRow = find.byKey(ValueKey<String>('event-row-${first.id}'));
    final handle = find.byKey(ValueKey<String>('event-task-drag-${second.id}'));
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(0, -8));
    await drag.moveTo(tester.getCenter(firstRow));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pumpAndSettle();

    expect(controller.tree.childrenOf(root.id).map((node) => node.id), <String>[
      second.id,
      first.id,
    ]);
    expect(controller.tree.nodes[secondChild.id]?.parentId, second.id);

    final cancelDrag = await tester.startGesture(
      tester.getCenter(
        find.byKey(ValueKey<String>('event-task-drag-${first.id}')),
      ),
    );
    await cancelDrag.moveBy(const Offset(0, -40));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await cancelDrag.up();
    await tester.pumpAndSettle();
    expect(controller.tree.childrenOf(root.id).map((node) => node.id), <String>[
      second.id,
      first.id,
    ]);

    await tester.tap(find.byKey(ValueKey<String>('event-row-${first.id}')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(controller.tree.childrenOf(root.id).map((node) => node.id), <String>[
      first.id,
      second.id,
    ]);
    expect(controller.eventDetailOpen, isTrue);
  });

  testWidgets('支持成功重命名任务', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'rename');
    final leaf = await fixture.createTask(title: '检查说明');
    await fixture.pump(tester);

    final title = find.byKey(ValueKey<String>('event-row-title-${leaf.id}'));
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pumpAndSettle();
    final rename = find.byKey(
      ValueKey<String>('event-inline-rename-${leaf.id}'),
    );
    await tester.enterText(rename, '检查最终说明');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fixture.controller.tree.nodes[leaf.id]?.title, '检查最终说明');
  });

  testWidgets('支持完成叶子任务', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'complete');
    final leaf = await fixture.createTask(title: '检查说明');
    await fixture.pump(tester);

    await tester.tap(find.byKey(ValueKey<String>('event-complete-${leaf.id}')));
    await tester.pumpAndSettle();
    expect(fixture.controller.tree.nodes[leaf.id]?.completedAt, isNotNull);
  });

  testWidgets('支持折叠和展开分支任务', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'expand');
    final branch = await fixture.createTask(title: '准备阶段');
    await fixture.createTask(parentId: branch.id, title: '检查说明');
    await fixture.pump(tester);

    await tester.tap(find.byKey(ValueKey<String>('event-expand-${branch.id}')));
    await tester.pumpAndSettle();
    expect(find.text('检查说明'), findsNothing);
    await tester.tap(find.byKey(ValueKey<String>('event-expand-${branch.id}')));
    await tester.pumpAndSettle();
    expect(find.text('检查说明'), findsOneWidget);
  });

  testWidgets('快速新增后高亮并展示新任务', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'quick-add');
    final controller = fixture.controller;
    final root = fixture.root;
    await fixture.pump(tester);

    await tester.tap(
      find.byKey(ValueKey<String>('event-quick-add-trigger-${root.id}')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ValueKey<String>('event-quick-add-${root.id}')),
      '发布复盘',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final created = controller.tree.childrenOf(root.id).last;
    expect(created.title, '发布复盘');
    final surface = tester.widget<DecoratedBox>(
      find.byKey(ValueKey<String>('event-row-surface-${created.id}')),
    );
    expect(
      (surface.decoration as BoxDecoration).color,
      AppColors.of(
        tester.element(
          find.byKey(ValueKey<String>('event-row-surface-${created.id}')),
        ),
      ).accentSoft,
    );
    expect(
      find.byKey(ValueKey<String>('event-row-${created.id}')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('取消删除会保留任务', (tester) async {
    final fixture = await _InteractionFixture.create(idPrefix: 'delete');
    final created = await fixture.createTask(title: '发布复盘');
    await fixture.pump(tester);

    final createdRow = find.byKey(ValueKey<String>('event-row-${created.id}'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(createdRow));
    await mouse.moveTo(tester.getCenter(createdRow));
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey<String>('event-delete-task-${created.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除这个任务？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fixture.controller.tree.nodes[created.id], isNotNull);
  });
}

class _InteractionFixture {
  const _InteractionFixture({required this.controller, required this.root});

  final AppController controller;
  final TodoNode root;

  static Future<_InteractionFixture> create({
    NodeRepository? repository,
    String idPrefix = 'interaction',
  }) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        repository ?? MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => '$idPrefix-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final root = await expectWriteSuccess(
      controller.create(title: '发布计划', selectCreated: false),
    );
    return _InteractionFixture(controller: controller, root: root);
  }

  Future<TodoNode> createTask({required String title, String? parentId}) =>
      expectWriteSuccess(
        controller.create(
          parentId: parentId ?? root.id,
          title: title,
          selectCreated: false,
        ),
      );

  Future<void> pump(WidgetTester tester, {double height = 420}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 420,
              height: height,
              child: EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
