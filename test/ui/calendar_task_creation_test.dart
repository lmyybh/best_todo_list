import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/ui/timeline/calendar_create_task_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalender/kalender.dart';

import '../helpers/failing_node_repository.dart';
import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  late AppController controller;
  setUp(() async {
    var id = 0;
    controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'create-${++id}',
      ),
      clock: () => DateTime(2026, 10, 21, 9),
    );
    await controller.load();
  });
  tearDown(() => controller.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.setView(AppView.timeline);
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
  }

  Future<void> chooseEvent(
    WidgetTester tester,
    String query,
    String path,
  ) async {
    final field = find.descendant(
      of: find.byKey(const ValueKey('calendar-create-event')),
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, query);
    await tester.pumpAndSettle();
    await tester.tap(find.text(path).last);
    await tester.pumpAndSettle();
  }

  Future<void> openForm(
    WidgetTester tester, {
    DateTime? start,
    DateTime? end,
  }) async {
    final calendar = tester.widget<KalenderView>(find.byType(KalenderView));
    calendar.callbacks!.onEventCreated!(
      KalenderEvent(
        start: start ?? DateTime(2026, 10, 21, 9),
        end: end ?? DateTime(2026, 10, 21, 10),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> doubleClickMonthDate(WidgetTester tester, DateTime date) async {
    final calendar = tester.widget<KalenderView>(find.byType(KalenderView));
    final range = calendar.kalenderController.floatingVisibleRange.value;
    final first = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final index = date.difference(first).inDays;
    final rows = range.end.difference(range.start).inDays ~/ 7;
    final rect = tester.getRect(find.byType(MonthBody));
    final point = Offset(
      rect.left + rect.width / 7 * (index % 7 + 0.5),
      rect.top + rect.height / rows * (index ~/ 7 + 1) - 10,
    );
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CalendarCreateTaskDialog), findsNothing);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  testWidgets('月视图双击空白格复用创建弹窗，保存当天12点至12点半并指定事件', (tester) async {
    final event = await expectWriteSuccess(
      controller.create(title: '月计划', selectCreated: false),
    );
    await mount(tester);
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await doubleClickMonthDate(tester, DateTime(2026, 10, 21));
    final dialog = tester.widget<CalendarCreateTaskDialog>(
      find.byType(CalendarCreateTaskDialog),
    );
    expect(dialog.start, DateTime(2026, 10, 21, 12));
    expect(dialog.end, DateTime(2026, 10, 21, 12, 30));
    expect(find.text('任务时间：2026.10.21 12:00 — 12:30'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('calendar-create-title')),
      '午间任务',
    );
    await chooseEvent(tester, '月计划', '月计划');
    await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
    await tester.pumpAndSettle();
    final task = controller.nodes.singleWhere((node) => node.title == '午间任务');
    expect(task.parentId, event.id);
    expect(task.scheduledStart?.toLocal(), DateTime(2026, 10, 21, 12));
    expect(
      (task.deadline as TimedDeadline).localTime,
      DateTime(2026, 10, 21, 12, 30),
    );
    expect(find.text('2026.10'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('calendar-tile-${task.id}')));
    await tester.pumpAndSettle();
    expect(controller.selectedId, task.id);
    expect(find.byType(CalendarCreateTaskDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月视图窄窗口双击相邻月份格使用该格日期，取消不写入', (tester) async {
    await mount(tester);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await doubleClickMonthDate(tester, DateTime(2026, 11, 1));
    final dialog = tester.widget<CalendarCreateTaskDialog>(
      find.byType(CalendarCreateTaskDialog),
    );
    expect(dialog.start, DateTime(2026, 11, 1, 12));
    expect(dialog.end, DateTime(2026, 11, 1, 12, 30));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.nodes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建弹窗跨日区间显示完整起止日期', (tester) async {
    await mount(tester);
    await openForm(
      tester,
      start: DateTime(2026, 12, 31, 23, 45),
      end: DateTime(2027, 1, 1, 0, 15),
    );
    expect(
      find.text('任务时间：2026.12.31 23:45 — 2027.01.01 00:15'),
      findsOneWidget,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['日', '周']) {
    testWidgets('$mode 视图鼠标拖选预览并按结束时间创建父级下的任务', (tester) async {
      final root = await expectWriteSuccess(
        controller.create(title: '项目', selectCreated: false),
      );
      await expectWriteSuccess(
        controller.create(
          title: '阶段一',
          parentId: root.id,
          selectCreated: false,
        ),
      );
      await mount(tester);
      if (mode == '日') {
        await tester.tap(find.text('日'));
        await tester.pumpAndSettle();
      }
      final x = mode == '日'
          ? tester.getCenter(find.byType(MultiDayBody)).dx
          : tester.getCenter(find.text('周三')).dx;
      final y = tester.getCenter(find.byKey(const Key('time-9-0'))).dy;
      final start = Offset(x, y);
      final mouse = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(start + const Offset(0, 20));
      await tester.pump();
      await mouse.moveTo(start + const Offset(0, 64));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('calendar-create-preview')),
        findsOneWidget,
      );
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.byType(CalendarCreateTaskDialog), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-create-preview')),
        findsNothing,
      );
      final dialog = tester.widget<CalendarCreateTaskDialog>(
        find.byType(CalendarCreateTaskDialog),
      );
      expect(dialog.start, DateTime(2026, 10, 21, 9));
      expect(dialog.end, DateTime(2026, 10, 21, 10));
      expect(find.text('任务时间：2026.10.21 09:00 — 10:00'), findsOneWidget);
      expect(controller.nodes.length, 2);
      await tester.enterText(
        find.byKey(const ValueKey('calendar-create-title')),
        '拖选任务',
      );
      await chooseEvent(tester, '项目', '项目');
      await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
      await tester.pumpAndSettle();
      final task = controller.nodes.singleWhere((node) => node.title == '拖选任务');
      expect(task.parentId, root.id);
      expect(
        (task.deadline as TimedDeadline).localTime,
        DateTime(2026, 10, 21, 10),
      );
      expect(find.byType(CalendarCreateTaskDialog), findsNothing);
      expect(find.byKey(ValueKey('calendar-tile-${task.id}')), findsOneWidget);
      expect(task.scheduledStart?.toLocal(), DateTime(2026, 10, 21, 9));
      expect(
        tester.getSize(find.byKey(ValueKey('calendar-tile-${task.id}'))).height,
        64,
      );
      expect(controller.view, AppView.timeline);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('取消不创建任务，父级期限不覆盖拖选结束时刻且不显示时间设置', (tester) async {
    final root = await expectWriteSuccess(
      controller.create(
        title: '有期限项目',
        deadline: DateOnlyDeadline(year: 2026, month: 10, day: 22),
        selectCreated: false,
      ),
    );
    await mount(tester);
    await openForm(tester);
    expect(
      find.byKey(const ValueKey('calendar-create-deadline')),
      findsNothing,
    );
    expect(find.byTooltip('使用默认截止时间'), findsNothing);
    expect(find.text('截止时间'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.nodes.length, 1);
    await openForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('calendar-create-title')),
      '拖选期限',
    );
    await chooseEvent(tester, '有期限项目', '有期限项目');
    await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
    await tester.pumpAndSettle();
    final task = controller.nodes.singleWhere((node) => node.title == '拖选期限');
    expect(task.parentId, root.id);
    expect(
      (task.deadline as TimedDeadline).localTime,
      DateTime(2026, 10, 21, 10),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('所属事件必填，输入不存在的事件时与任务一起创建', (tester) async {
    await mount(tester);
    await openForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('calendar-create-title')),
      '新任务',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('请选择或输入所属事件'), findsOneWidget);
    expect(controller.nodes, isEmpty);
    final eventField = find.descendant(
      of: find.byKey(const ValueKey('calendar-create-event')),
      matching: find.byType(TextField),
    );
    await tester.enterText(eventField, ' 新项目 ');
    await tester.tap(find.byKey(const ValueKey('calendar-create-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
    await tester.pumpAndSettle();
    final event = controller.nodes.singleWhere((node) => node.parentId == null);
    final task = controller.nodes.singleWhere((node) => node.parentId != null);
    expect(event.title, '新项目');
    expect(task.parentId, event.id);
    expect(task.scheduledStart?.toLocal(), DateTime(2026, 10, 21, 9));
    expect(
      (task.deadline as TimedDeadline).localTime,
      DateTime(2026, 10, 21, 10),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建失败保留表单可重试，月视图不启用拖选', (tester) async {
    controller.dispose();
    final repository = FailingNodeRepository();
    controller = AppController(
      NodePersistenceWorkspace(repository),
      clock: () => DateTime(2026, 10, 21),
    );
    await controller.load();
    await mount(tester);
    await openForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('calendar-create-title')),
      '重试任务',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-create-event')),
        matching: find.byType(TextField),
      ),
      '重试事件',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-create-title')));
    await tester.pumpAndSettle();
    repository.failNextInsert = true;
    await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('创建失败，请重试'), findsOneWidget);
    expect(controller.nodes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('calendar-create-confirm')));
    await tester.pumpAndSettle();
    expect(controller.nodes.length, 2);
    expect(
      controller.nodes.where((node) => node.title == '重试任务'),
      hasLength(1),
    );
    expect(
      controller.nodes.where((node) => node.title == '重试事件'),
      hasLength(1),
    );
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await openForm(tester);
    expect(find.byType(CalendarCreateTaskDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
