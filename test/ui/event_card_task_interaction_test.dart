import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/events/event_card_task_interaction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  testWidgets('事件卡片任务交互通过根事件展示子任务', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'interaction-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final root = await controller.create(title: '发布计划', selectCreated: false);
    await controller.create(
      parentId: root!.id,
      title: '检查发布说明',
      selectCreated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('检查发布说明'), findsOneWidget);
  });

  testWidgets('可以从任务行内联创建更深层子任务', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'nested-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final child = await controller.create(
      parentId: root!.id,
      title: '检查发布说明',
      selectCreated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(ValueKey<String>('event-row-${child!.id}'));
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
    expect(controller.eventDetailOpen, isFalse);
  });

  testWidgets('重命名写入失败时保留输入和焦点以便重试', (tester) async {
    var id = 0;
    final repository = _FailingNodeRepository();
    final controller = AppController(
      NodeService(
        repository,
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'rename-failure-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final child = await controller.create(
      parentId: root!.id,
      title: '检查发布说明',
      selectCreated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.byKey(ValueKey<String>('event-row-title-${child!.id}'));
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
    expect(controller.tree.nodes[child.id]?.title, '检查发布说明');
  });

  testWidgets('新增写入失败时保留草稿和焦点以便重试', (tester) async {
    var id = 0;
    final repository = _FailingNodeRepository();
    final controller = AppController(
      NodeService(
        repository,
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'draft-failure-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final child = await controller.create(
      parentId: root!.id,
      title: '检查发布说明',
      selectCreated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey<String>('event-row-${child!.id}')));
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
    expect(controller.error, isNotNull);
  });

  testWidgets('默认预览三级任务结构', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'depth-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
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

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
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

  testWidgets('同一父任务下支持拖拽取消和键盘排序', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'reorder-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
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
    final secondChild = await controller.create(
      parentId: second!.id,
      title: '第二步的子任务',
      selectCreated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstRow = find.byKey(ValueKey<String>('event-row-${first!.id}'));
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
    expect(controller.tree.nodes[secondChild!.id]?.parentId, second.id);

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

  testWidgets('支持成功重命名完成展开和快速新增高亮', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 25, 9),
        idGenerator: () => 'actions-${++id}',
      ),
      clock: () => DateTime(2026, 8, 25, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    final root = await controller.create(title: '发布计划', selectCreated: false);
    final branch = await controller.create(
      parentId: root!.id,
      title: '准备阶段',
      selectCreated: false,
    );
    final leaf = await controller.create(
      parentId: branch!.id,
      title: '检查说明',
      selectCreated: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => EventCardTaskInteraction(
                controller: controller,
                rootEventId: root.id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.byKey(ValueKey<String>('event-row-title-${leaf!.id}'));
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
    expect(controller.tree.nodes[leaf.id]?.title, '检查最终说明');

    await tester.tap(find.byKey(ValueKey<String>('event-complete-${leaf.id}')));
    await tester.pumpAndSettle();
    expect(controller.tree.nodes[leaf.id]?.completedAt, isNotNull);

    await tester.tap(find.byKey(ValueKey<String>('event-expand-${branch.id}')));
    await tester.pumpAndSettle();
    expect(find.text('检查最终说明'), findsNothing);
    await tester.tap(find.byKey(ValueKey<String>('event-expand-${branch.id}')));
    await tester.pumpAndSettle();
    expect(find.text('检查最终说明'), findsOneWidget);

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
    expect(controller.tree.nodes[created.id], isNotNull);
  });
}

class _FailingNodeRepository implements NodeRepository {
  final MemoryNodeRepository _delegate = MemoryNodeRepository();

  bool failNextInsert = false;
  bool failNextUpdate = false;

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> insertNode(TodoNode node) {
    if (failNextInsert) {
      failNextInsert = false;
      throw StateError('insert failed');
    }
    return _delegate.insertNode(node);
  }

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) =>
      _delegate.loadNodes(includeDeleted: includeDeleted);

  @override
  Future<void> updateNode(TodoNode node) {
    if (failNextUpdate) {
      failNextUpdate = false;
      throw StateError('update failed');
    }
    return _delegate.updateNode(node);
  }

  @override
  Future<void> updateNodes(List<TodoNode> nodes) =>
      _delegate.updateNodes(nodes);
}
