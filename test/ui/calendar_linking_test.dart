import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/ui/timeline/calendar_timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart';
import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  late AppController controller;
  setUp(() async {
    var id = 0;
    controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'link-${++id}',
      ),
      clock: () => DateTime(2026, 10, 21, 9),
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('日历详情原地编辑，改期同步，关闭和切换保持月份', (tester) async {
    final task = await expectWriteSuccess(
      controller.create(
        title: '设计方案',
        deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
        selectCreated: false,
      ),
    );
    controller.setView(AppView.timeline);
    await mount(tester);
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设计方案').first);
    await tester.pumpAndSettle();
    expect(controller.view, AppView.timeline);
    expect(find.byKey(const ValueKey('event-detail-panel')), findsOneWidget);
    await controller.updateTitle(task.id, '更新后的方案');
    await controller.updateDeadline(
      task.id,
      DateOnlyDeadline(year: 2026, month: 11, day: 5),
    );
    await tester.pumpAndSettle();
    final calendar = tester.widget<KalenderView>(find.byType(KalenderView));
    final event =
        calendar.eventsController.events.single as DeadlineCalendarEvent;
    expect(event.node.title, '更新后的方案');
    expect(event.start.toLocal(), DateTime(2026, 11, 5));
    expect(find.text('2026.10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-to-event-board')));
    await tester.pumpAndSettle();
    controller.setView(AppView.events);
    await tester.pumpAndSettle();
    controller.setView(AppView.timeline);
    await tester.pumpAndSettle();
    expect(find.text('2026.10'), findsOneWidget);
    controller.select(task.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('detail-show-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('2026.11'), findsOneWidget);
    expect(find.byKey(const ValueKey('event-detail-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS 日程详情点击保存截止日期后刷新日历', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final task = await expectWriteSuccess(
        controller.create(
          title: '保存日期',
          deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
          selectCreated: false,
        ),
      );
      controller.setView(AppView.timeline);
      await mount(tester);
      controller.select(task.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('截止日期'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('明天'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('deadline-save')));
      await tester.pumpAndSettle();
      expect(
        controller.tree.nodes[task.id]!.deadline!.calendarDate,
        DateTime(2026, 10, 22),
      );
      final calendar = tester.widget<KalenderView>(find.byType(KalenderView));
      expect(
        calendar.eventsController.events.single.start.toLocal(),
        DateTime(2026, 10, 22, 20, 30),
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('定位截止日期时仍显示其他事件', (tester) async {
    final root = await expectWriteSuccess(
      controller.create(title: '项目甲', selectCreated: false),
    );
    final child = await expectWriteSuccess(
      controller.create(
        parentId: root.id,
        title: '甲任务',
        deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
        selectCreated: false,
      ),
    );
    await controller.create(
      title: '项目乙',
      deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
      selectCreated: false,
    );
    controller.showInCalendar(child.id);
    await mount(tester);
    expect(find.text('甲任务'), findsWidgets);
    expect(find.text('项目乙'), findsWidgets);
    expect(
      tester
          .widget<KalenderView>(find.byType(KalenderView))
          .eventsController
          .events
          .length,
      2,
    );
    controller.select(child.id);
    await tester.pumpAndSettle();
    expect(find.text('只看这个事件'), findsNothing);
    expect(find.byKey(const ValueKey('detail-show-calendar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回事件树展开深层祖先并保留日历状态', (tester) async {
    final root = await expectWriteSuccess(
      controller.create(title: '项目甲', selectCreated: false),
    );
    var parent = root;
    for (var i = 0; i < 4; i++) {
      parent = await expectWriteSuccess(
        controller.create(
          parentId: parent.id,
          title: '层级$i',
          selectCreated: false,
        ),
      );
    }
    controller.setView(AppView.timeline);
    await mount(tester);
    controller.showInEventTree(parent.id);
    await tester.pumpAndSettle();
    expect(controller.view, AppView.events);
    expect(controller.selectedId, parent.id);
    expect(find.byKey(ValueKey('event-card-${root.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('event-row-${parent.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-detail-panel')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('事件滚动位置在切换日程后保留', (tester) async {
    for (var i = 0; i < 16; i++) {
      await controller.create(title: '事件$i', selectCreated: false);
    }
    await mount(tester);
    final scrollView = tester.widget<SingleChildScrollView>(
      find
          .descendant(
            of: find.byKey(const ValueKey('event-board-scroll')),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );
    final scroll = scrollView.controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(100));
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    controller.setView(AppView.timeline);
    await tester.pumpAndSettle();
    controller.setView(AppView.events);
    await tester.pumpAndSettle();
    expect(scroll.offset, 100);
    expect(tester.takeException(), isNull);
  });
}
