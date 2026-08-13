import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/domain/node_tree.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/common/create_node_dialog.dart';
import 'package:best_todo_list/ui/common/deadline_dialog.dart';
import 'package:best_todo_list/ui/common/delete_confirmation_dialog.dart';
import 'package:best_todo_list/ui/common/node_tile.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  late MemoryNodeRepository repository;
  late AppController controller;
  late DateTime appNow;
  var id = 0;

  setUp(() async {
    repository = MemoryNodeRepository();
    appNow = DateTime(2026, 8, 11, 9);
    controller = AppController(
      NodeService(
        repository,
        clock: () => DateTime.utc(2026, 8, 11, 9),
        idGenerator: () => 'node-${++id}',
      ),
      clock: () => appNow,
    );
    await controller.load();
  });

  testWidgets('空应用展示引导并可创建顶层事件', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('create-event-navigation')),
      findsOneWidget,
    );
    expect(find.text('从一件想完成的事开始'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '新建事件'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新版发布');
    await tester.pump();
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

    final breadcrumb = find.text('所有事件  /  新版发布');
    expect(breadcrumb, findsOneWidget);
    expect(
      tester.widget<Text>(breadcrumb).style?.color,
      AppColors.of(tester.element(breadcrumb)).faint,
    );
    expect(find.text('手动排序'), findsOneWidget);
    expect(find.text('备注'), findsOneWidget);
    final notesField = find.byKey(const ValueKey<String>('detail-notes-field'));
    expect(notesField, findsOneWidget);
    await tester.enterText(notesField, '发布前确认回滚方案');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(controller.selectedNode!.notes, '发布前确认回滚方案');
    expect(find.text('已保存'), findsOneWidget);
    final quickAdd = find.widgetWithText(TextField, '添加一个子任务…');
    expect(quickAdd, findsOneWidget);
    final quickAddDecoration = tester.widget<TextField>(quickAdd).decoration!;
    expect(quickAddDecoration.filled, isFalse);
    expect(quickAddDecoration.border, InputBorder.none);
    expect(quickAddDecoration.enabledBorder, InputBorder.none);
    expect(quickAddDecoration.focusedBorder, InputBorder.none);
    await tester.enterText(quickAdd, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('标题不能为空'), findsOneWidget);
    expect(controller.tree.childrenOf(root!.id), isEmpty);
    await tester.enterText(quickAdd, '确认最终文案');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('确认最终文案'), findsWidgets);
    expect(controller.selectedId, root.id);
    final child = controller.tree.childrenOf(root.id).single;
    expect(
      find.descendant(
        of: find.byType(NodeTile),
        matching: find.textContaining('创建时间'),
      ),
      findsNothing,
    );
    final tileSurface = find.descendant(
      of: find.byType(NodeTile),
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Material || widget.shape is! RoundedRectangleBorder) {
          return false;
        }
        final shape = widget.shape! as RoundedRectangleBorder;
        return shape.borderRadius == BorderRadius.circular(10);
      }),
    );
    expect(tileSurface, findsOneWidget);
    final material = tester.widget<Material>(tileSurface);
    expect(
      material.color,
      Theme.of(tester.element(tileSurface)).colorScheme.surface,
    );
    expect(material.clipBehavior, Clip.antiAlias);
    final tileInk = find.descendant(
      of: tileSurface,
      matching: find.byType(InkWell),
    );
    expect(tileInk, findsOneWidget);
    expect(tester.getSize(tileInk).width, tester.getSize(tileSurface).width);
    final title = find.descendant(
      of: tileSurface,
      matching: find.text('确认最终文案'),
    );
    expect(title, findsOneWidget);
    final tileContent = find.byKey(
      ValueKey<String>('node-tile-content-${child.id}'),
    );
    expect(
      (tester.getCenter(tileContent).dy - tester.getCenter(tileSurface).dy)
          .abs(),
      lessThanOrEqualTo(1),
    );
    final trailingOpacity = find.descendant(
      of: tileSurface,
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(trailingOpacity).opacity, 0.35);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(tileSurface));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<Material>(tileSurface).color,
      AppColors.of(tester.element(tileSurface)).surfaceHover,
    );
    expect(tester.widget<AnimatedOpacity>(trailingOpacity).opacity, 1);
    await tester.enterText(quickAdd, '安排发布窗口');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await controller.setCompleted(child.id, true);
    await tester.pumpAndSettle();

    final completedTitle = find.descendant(
      of: find.byType(NodeTile),
      matching: find.text('确认最终文案'),
    );
    final nextTitle = find.descendant(
      of: find.byType(NodeTile),
      matching: find.text('安排发布窗口'),
    );
    expect(
      tester.widget<Text>(completedTitle).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      find.descendant(
        of: find.byType(NodeTile),
        matching: find.textContaining('完成时间'),
      ),
      findsNothing,
    );
    expect(
      tester.getCenter(completedTitle).dy,
      lessThan(tester.getCenter(nextTitle).dy),
    );
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('子任务'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(controller.tree.isComplete(child.id), isTrue);
    expect(controller.tree.isComplete(root.id), isFalse);
    expect(
      find.byKey(const ValueKey<String>('detail-completion-toggle')),
      findsNothing,
    );

    await tester.tap(completedTitle);
    await tester.pumpAndSettle();
    expect(find.text('创建时间 2026/08/11'), findsOneWidget);
    expect(find.text('完成时间 2026/08/11'), findsOneWidget);
    final detailToggle = find.byKey(
      const ValueKey<String>('detail-completion-toggle'),
    );
    expect(detailToggle, findsOneWidget);
    expect(
      find.descendant(of: detailToggle, matching: find.text('已完成')),
      findsOneWidget,
    );

    await tester.tap(detailToggle);
    await tester.pumpAndSettle();
    expect(controller.tree.isComplete(child.id), isFalse);
    expect(find.text('完成时间 2026/08/11'), findsNothing);
    expect(
      find.descendant(of: detailToggle, matching: find.text('标记完成')),
      findsOneWidget,
    );

    await tester.tap(detailToggle);
    await tester.pumpAndSettle();
    expect(controller.tree.isComplete(child.id), isTrue);
    expect(find.text('完成时间 2026/08/11'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('删除任务'), findsOneWidget);
    expect(find.text('删除事件'), findsNothing);
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();
    expect(find.text('删除这个任务？'), findsOneWidget);
    expect(find.text('删除后可以在提示消失前撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('时间线切换和已完成开关可用', (tester) async {
    final root = await controller.create(title: '有日期任务');
    await controller.updateDeadline(root!.id, DateTime(2026, 8, 11, 16));
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final eventsNavigation = find.byKey(
      const ValueKey<String>('events-navigation'),
    );
    final timelineNavigation = find.byKey(
      const ValueKey<String>('timeline-navigation'),
    );
    expect(eventsNavigation, findsOneWidget);
    expect(timelineNavigation, findsOneWidget);
    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
    expect(tester.getSize(eventsNavigation), const Size(38, 38));
    expect(tester.getCenter(eventsNavigation).dx, 27);

    await tester.tap(timelineNavigation);
    await tester.pumpAndSettle();
    expect(find.text('把注意力留给眼前的事'), findsOneWidget);
    expect(find.text('有日期任务'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    appNow = DateTime(2026, 8, 12, 0, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('2026 年 8 月 12 日'), findsOneWidget);
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

  testWidgets('macOS 叶子任务内容在卡片内垂直居中', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final now = DateTime.utc(2026, 8, 11, 9);
      final node = TodoNode(
        id: 'reading-v4',
        parentId: 'sglang',
        title: '阅读 v4',
        createdAt: now,
        updatedAt: now,
        manualOrder: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 700,
                child: NodeTile(
                  node: node,
                  tree: NodeTree(<TodoNode>[node]),
                  onOpen: () {},
                  onToggleComplete: (_) {},
                  trailing: const Icon(Icons.drag_indicator),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tile = find.byType(NodeTile);
      final tileContent = find.byKey(
        const ValueKey<String>('node-tile-content-reading-v4'),
      );
      expect(
        (tester.getCenter(tileContent).dy - tester.getCenter(tile).dy).abs(),
        lessThanOrEqualTo(1),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS 事件头使用确定型进度环', (tester) async {
    final root = await controller.create(title: '新版发布');
    await controller.create(parentId: root!.id, title: '确认文案');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.binding.setSurfaceSize(const Size(1100, 760));
      await tester.pumpWidget(TodoApp(controller: controller));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0,
      );
    } finally {
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS 新建事件使用桌面 Material 表单弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (context) => const CreateNodeDialog(),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
        find.byWidgetPredicate((widget) => widget is AlertDialog),
        findsOneWidget,
      );
      expect(find.text('输入事件名称'), findsOneWidget);
      expect(tester.getSize(find.byType(TextField)).width, 320);
      final confirmButton = find.byKey(
        const ValueKey<String>('node-title-confirm-button'),
      );
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
      await tester.enterText(find.byType(TextFormField), '   ');
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
      await tester.enterText(find.byType(TextFormField), '新事件');
      await tester.pump();
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
      expect(
        (tester.widget<AlertDialog>(find.byType(AlertDialog)).shape
                as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(12),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS 重命名复用桌面 Material 标题表单', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (context) => const CreateNodeDialog(
                  title: '重命名',
                  initialTitle: '旧名称',
                  fieldLabel: '名称',
                  hintText: '输入新名称',
                  confirmLabel: '保存',
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '旧名称');
      expect(
        field.controller?.selection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS 删除确认使用桌面 Material 危险操作弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (context) => const DeleteConfirmationDialog(
                  title: '删除这个节点？',
                  message: '它的所有子任务也会一起删除。',
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        (tester.widget<AlertDialog>(find.byType(AlertDialog)).shape
                as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(12),
      );
      final deleteButton = find.byKey(
        const ValueKey<String>('confirm-delete-button'),
      );
      expect(
        tester
            .widget<FilledButton>(deleteButton)
            .style
            ?.backgroundColor
            ?.resolve(<WidgetState>{}),
        AppColors.of(tester.element(deleteButton)).danger,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS 截止时间使用单个桌面表单弹窗', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<DeadlineDialogResult>(
                context: context,
                builder: (context) => DeadlineDialog(
                  initialValue: DateTime(2026, 8, 12, 9, 45),
                  now: DateTime(2026, 8, 12, 8),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('deadline-hour')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('deadline-minute')),
        findsOneWidget,
      );
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('明天'), findsOneWidget);
      expect(find.text('清除'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
