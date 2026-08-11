import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/app_theme.dart';
import 'package:best_todo_list/domain/node_tree.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/common/create_node_dialog.dart';
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

    expect(find.text('todo'), findsOneWidget);
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

    final breadcrumb = find.text('所有事件  /  新版发布');
    expect(breadcrumb, findsOneWidget);
    expect(
      tester.widget<Text>(breadcrumb).style?.color,
      AppColors.of(tester.element(breadcrumb)).faint,
    );
    expect(find.text('手动排序'), findsOneWidget);
    final quickAdd = find.widgetWithText(TextField, '添加一个子任务…');
    expect(quickAdd, findsOneWidget);
    final quickAddDecoration = tester.widget<TextField>(quickAdd).decoration!;
    expect(quickAddDecoration.filled, isFalse);
    expect(quickAddDecoration.border, InputBorder.none);
    expect(quickAddDecoration.enabledBorder, InputBorder.none);
    expect(quickAddDecoration.focusedBorder, InputBorder.none);
    await tester.enterText(quickAdd, '确认最终文案');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('确认最终文案'), findsWidgets);
    expect(controller.selectedId, root!.id);
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
    expect(
      (tester.getCenter(title).dy - tester.getCenter(tileSurface).dy).abs(),
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

  testWidgets('左侧节点右键菜单只提供重命名和删除', (tester) async {
    final node = await controller.create(title: '旧名称');
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    final treeItem = find.widgetWithText(ListTile, '旧名称');
    await tester.tap(treeItem, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(controller.selectedId, node!.id);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.byType(MenuItemButton), findsNWidgets(2));

    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '新名称');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(controller.nodes.single.title, '新名称');

    await tester.tap(
      find.widgetWithText(ListTile, '新名称'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(controller.nodes, isEmpty);
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
      final title = find.text('阅读 v4');
      expect(
        (tester.getCenter(title).dy - tester.getCenter(tile).dy).abs(),
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
      expect(tester.getSize(find.byType(TextField)).width, 360);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
