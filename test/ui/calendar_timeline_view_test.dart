import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/node_tree.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/timeline/calendar_timeline_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:calendar_date_picker2/calendar_date_picker2.dart';
import 'package:flutter/gestures.dart';
import 'package:kalender/kalender.dart';
import 'package:best_todo_list/ui/common/event_color.dart';
import 'package:best_todo_list/ui/common/formatters.dart';
import '../helpers/write_result.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/memory_node_repository.dart';

void main() {
  for (final total in [3, 8]) {
    for (final checkPopup in [false, true]) {
      testWidgets('月视图同一时段$total项任务新增后${checkPopup ? '浮层不漏项' : '折叠数量准确'}', (
        tester,
      ) async {
        var id = 0;
        final controller = AppController(
          NodePersistenceWorkspace(
            MemoryNodeRepository(),
            idGenerator: () => 'overflow-${++id}',
          ),
          clock: () => DateTime(2026, 10, 21),
        );
        await controller.load();
        addTearDown(controller.dispose);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final root = await expectWriteSuccess(
          controller.create(title: '项目', selectCreated: false),
        );
        final dateTask = await expectWriteSuccess(
          controller.create(
            title: '日期事项',
            parentId: root.id,
            deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
            selectCreated: false,
          ),
        );
        final tasks = <TodoNode>[];
        for (var i = 0; i < 2; i++) {
          tasks.add(
            await expectWriteSuccess(
              controller.createScheduledTask(
                title: '同时间任务$i',
                eventId: root.id,
                eventName: '项目',
                start: DateTime(2026, 10, 21, 9),
                end: DateTime(2026, 10, 21, 10),
              ),
            ),
          );
        }
        controller.setView(AppView.timeline);
        await tester.binding.setSurfaceSize(const Size(1200, 600));
        await tester.pumpWidget(TodoApp(controller: controller));
        await tester.pumpAndSettle();
        await tester.tap(find.text('月'));
        await tester.pumpAndSettle();
        for (var i = 2; i < total; i++) {
          tasks.add(
            await expectWriteSuccess(
              controller.createScheduledTask(
                title: '新增的同时间任务$i',
                eventId: root.id,
                eventName: '项目',
                start: DateTime(2026, 10, 21, 9),
                end: DateTime(2026, 10, 21, 10),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        if (!checkPopup) {
          final allTasks = [dateTask, ...tasks];
          final visibleCount = allTasks
              .where(
                (task) => find
                    .byKey(ValueKey('calendar-tile-${task.id}'))
                    .hitTestable()
                    .evaluate()
                    .isNotEmpty,
              )
              .length;
          expect(
            find.text('+${allTasks.length - visibleCount} 项').hitTestable(),
            findsOneWidget,
          );
        }
        await tester.tap(
          find.textContaining(RegExp(r'^\+\d+ 项$')).hitTestable(),
        );
        await tester.pumpAndSettle();
        final popup = find.byKey(const ValueKey('calendar-month-day-popup'));
        expect(
          find.descendant(of: popup, matching: find.text('${total + 1} 项任务')),
          findsOneWidget,
        );
        for (final task in tasks) {
          expect(
            find.descendant(
              of: popup,
              matching: find.byKey(
                ValueKey('calendar-month-day-task-${task.id}'),
              ),
            ),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(of: popup, matching: find.text('日期事项')),
          findsOneWidget,
        );
        await controller.setTaskStatus(tasks.last.id, TodoNodeStatus.completed);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: popup,
                  matching: find.text(tasks.last.title),
                ),
              )
              .style
              ?.decoration,
          TextDecoration.lineThrough,
        );
        await tester.tap(find.byTooltip('关闭当天任务'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('周'));
        await tester.pumpAndSettle();
        final calendar = tester.widget<KalenderView>(find.byType(KalenderView));
        expect(
          calendar.eventsController.events.map((event) => event.id),
          containsAll([dateTask.id, ...tasks.map((task) => task.id)]),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('拖选区间按原范围投影，同截止时间但不同开始时间不会合并', () {
    final now = DateTime(2026, 10, 21);
    final end = DateTime(2026, 10, 21, 11);
    TodoNode task(String id, DateTime? start) => TodoNode(
      id: id,
      title: id,
      createdAt: now,
      updatedAt: now,
      manualOrder: 1000,
      deadline: TimedDeadline(end),
      scheduledStart: start,
    );
    final events = calendarDeadlineEvents(
      NodeTree([
        task('one', DateTime(2026, 10, 21, 9)),
        task('two', DateTime(2026, 10, 21, 9)),
        task('three', DateTime(2026, 10, 21, 10)),
        task('default', null),
      ]),
    );
    expect(events, hasLength(4));
    expect(events.map((event) => event.start.toLocal()), [
      DateTime(2026, 10, 21, 9),
      DateTime(2026, 10, 21, 9),
      DateTime(2026, 10, 21, 10),
      DateTime(2026, 10, 21, 10, 30),
    ]);
    expect(events.every((event) => event.end.toLocal() == end), isTrue);
    expect(events.map((event) => event.id).toSet(), hasLength(4));
  });

  testWidgets('月视图按高度容纳紧凑任务行，更多入口展开完整当天任务', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'month-${++id}',
      ),
      clock: () => DateTime(2026, 10, 21, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tasks = <TodoNode>[];
    for (var i = 1; i <= 12; i++) {
      tasks.add(
        await expectWriteSuccess(
          controller.create(
            title: '月任务${i.toString().padLeft(2, '0')}',
            deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
            selectCreated: false,
          ),
        ),
      );
    }
    await controller.setTaskStatus(tasks.first.id, TodoNodeStatus.completed);
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();

    int visibleCount() => tasks
        .where(
          (task) => find
              .byKey(ValueKey('calendar-tile-${task.id}'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        )
        .length;
    final largeCount = visibleCount();
    expect(largeCount, greaterThan(2));
    final visibleTile = find
        .byKey(ValueKey('calendar-tile-${tasks.first.id}'))
        .hitTestable();
    expect(tester.getSize(visibleTile).height, 20);
    final completedTitle = tester.widget<Text>(find.text('✓ 月任务01').first);
    expect(completedTitle.style?.fontSize, 11);
    expect(completedTitle.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('+${12 - largeCount} 项').hitTestable(), findsOneWidget);
    expect(find.textContaining('还有'), findsNothing);

    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpAndSettle();
    final smallCount = visibleCount();
    expect(smallCount, lessThan(largeCount));
    final more = find.text('+${12 - smallCount} 项').hitTestable();
    expect(more, findsOneWidget);
    expect(tester.widget<Text>(more).style?.fontSize, 11);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final popup = find.byKey(const ValueKey('calendar-month-day-popup'));
    expect(popup, findsOneWidget);
    expect(find.text('10 月 21 日 周三'), findsOneWidget);
    expect(find.text('12 项任务'), findsOneWidget);
    expect(tester.getSize(popup).height, lessThanOrEqualTo(360));
    final scrollbar = tester.widget<RawScrollbar>(
      find.byKey(const ValueKey('calendar-month-day-scrollbar')),
    );
    expect(scrollbar.thickness, 3);
    final list = find.byKey(const ValueKey('calendar-month-day-list'));
    final firstRow = find.byKey(
      ValueKey('calendar-month-day-task-${tasks.first.id}'),
    );
    expect(tester.getRect(list).right - tester.getRect(firstRow).right, 14);
    final popupCompletedTitle = tester.widget<Text>(
      find.descendant(of: popup, matching: find.text('月任务01')),
    );
    expect(popupCompletedTitle.style?.decoration, TextDecoration.lineThrough);
    final lastTask = find.text('月任务12').last;
    await tester.ensureVisible(lastTask);
    await tester.pumpAndSettle();
    await tester.tap(lastTask);
    await tester.pumpAndSettle();
    expect(controller.selectedId, tasks.last.id);
    expect(popup, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月任务浮层按时间列出全部任务，靠边避让并可关闭', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'day-popup-${++id}',
      ),
      clock: () => DateTime(2026, 10, 21),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final late = await expectWriteSuccess(
      controller.create(
        title: '晚间事项',
        deadline: TimedDeadline(DateTime(2026, 10, 25, 21)),
        selectCreated: false,
      ),
    );
    for (final title in ['午后事项甲', '午后事项乙']) {
      await expectWriteSuccess(
        controller.createScheduledTask(
          title: title,
          eventName: '项目',
          start: DateTime(2026, 10, 25, 14),
          end: DateTime(2026, 10, 25, 15),
        ),
      );
    }
    final morning = await expectWriteSuccess(
      controller.createScheduledTask(
        title: '上午事项',
        eventName: '项目',
        start: DateTime(2026, 10, 25, 9),
        end: DateTime(2026, 10, 25, 10),
      ),
    );
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    final calendar = tester
        .widget<KalenderView>(find.byType(KalenderView))
        .kalenderController;
    await calendar.showDayOverlay(DateTime(2026, 10, 25));
    await tester.pumpAndSettle();
    final popup = find.byKey(const ValueKey('calendar-month-day-popup'));
    expect(popup, findsOneWidget);
    expect(find.text('4 项任务'), findsOneWidget);
    expect(
      find.descendant(of: popup, matching: find.text('14:00 — 15:00')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: popup, matching: find.text('09:00 — 10:00')),
      findsOneWidget,
    );
    final morningRow = find.byKey(
      ValueKey('calendar-month-day-task-${morning.id}'),
    );
    final lateRow = find.byKey(ValueKey('calendar-month-day-task-${late.id}'));
    expect(
      tester.getTopLeft(morningRow).dy,
      lessThan(tester.getTopLeft(lateRow).dy),
    );
    final body = tester.getRect(find.byType(MonthBody));
    expect(tester.getRect(popup).right, lessThan(body.right - body.width / 7));
    expect(tester.getRect(popup).top, greaterThanOrEqualTo(8));
    expect(tester.getRect(popup).bottom, lessThanOrEqualTo(592));
    await tester.tapAt(const Offset(90, 125));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    await calendar.showDayOverlay(DateTime(2026, 10, 25));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭当天任务'));
    await tester.pumpAndSettle();
    expect(popup, findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('期限投影使用截止前30分钟、保留纯日期和已完成位置，排除放弃与删除', () {
    final now = DateTime(2026, 10, 21);
    TodoNode node(
      String id, {
      String? parentId,
      Deadline? deadline,
      DateTime? completedAt,
      DateTime? abandonedAt,
      DateTime? deletedAt,
    }) => TodoNode(
      id: id,
      parentId: parentId,
      title: id,
      createdAt: now,
      updatedAt: now,
      manualOrder: 0,
      deadline: deadline,
      completedAt: completedAt,
      abandonedAt: abandonedAt,
      deletedAt: deletedAt,
    );
    final events = calendarDeadlineEvents(
      NodeTree([
        node('midnight', deadline: TimedDeadline(now)),
        node(
          'date',
          deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
        ),
        node(
          'complete',
          deadline: TimedDeadline(now),
          completedAt: DateTime(2026, 10, 22),
        ),
        node('none'),
        node('abandoned', deadline: TimedDeadline(now), abandonedAt: now),
        node('deleted', deadline: TimedDeadline(now), deletedAt: now),
        node('parent', deadline: TimedDeadline(now)),
        node(
          'branch',
          parentId: 'parent',
          deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
        ),
        node('leaf-without-deadline', parentId: 'branch'),
      ]),
    );
    expect(events.map((e) => e.node.id), ['midnight', 'date', 'complete']);
    expect(events.first.start.toLocal(), DateTime(2026, 10, 20, 23, 30));
    expect(events.first.end.toLocal(), now);
    expect(events[1].isAllDay, isTrue);
    expect(events[1].end.toLocal(), DateTime(2026, 10, 22));
    expect(events.last.complete, isTrue);
    expect(events.last.end.toLocal(), now);
  });

  testWidgets('悬停展示父级面包屑与备注且颜色继承所属事件', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'hover-${++id}',
      ),
      clock: () => DateTime(2026, 10, 21, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await expectWriteSuccess(
      controller.create(title: '发布项目', selectCreated: false),
    );
    final parent = await expectWriteSuccess(
      controller.create(title: '版本迭代', parentId: root.id, selectCreated: false),
    );
    final task = await expectWriteSuccess(
      controller.create(
        title: '准备上线',
        parentId: parent.id,
        deadline: TimedDeadline(DateTime(2026, 10, 21, 10)),
        selectCreated: false,
      ),
    );
    await controller.updateNotes(task.id, '上线前检查文档');
    final sundayTask = await expectWriteSuccess(
      controller.create(
        title: '周日检查',
        parentId: parent.id,
        deadline: TimedDeadline(DateTime(2026, 10, 25, 10)),
        selectCreated: false,
      ),
    );
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
    final event = calendarDeadlineEvents(
      controller.tree,
    ).singleWhere((event) => event.node.id == task.id);
    expect(event.color, eventColor(controller.tree.nodes[root.id]!));
    expect(event.end.difference(event.start), const Duration(minutes: 30));
    final tile = find.text('准备上线').first;
    expect(find.textContaining('10:00 截止'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getTopLeft(tile) + const Offset(8, 10));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final hover = find.byKey(ValueKey('calendar-hover-${task.id}'));
    expect(hover, findsOneWidget);
    final titleLeft = tester
        .getTopLeft(find.descendant(of: hover, matching: find.text('准备上线')))
        .dx;
    expect(
      tester
          .getTopLeft(
            find.descendant(of: hover, matching: find.text('发布项目  ›  版本迭代')),
          )
          .dx,
      titleLeft,
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: hover,
              matching: find.text(formatDeadline(task.deadline)),
            ),
          )
          .dx,
      titleLeft,
    );
    expect(
      tester.getRect(hover).left,
      greaterThan(
        tester.getRect(find.byKey(ValueKey('calendar-tile-${task.id}'))).right,
      ),
    );
    expect(
      find.descendant(of: hover, matching: find.text('发布项目  ›  版本迭代')),
      findsOneWidget,
    );
    expect(find.text('无子任务'), findsNothing);
    expect(
      find.descendant(of: hover, matching: find.text('上线前检查文档')),
      findsOneWidget,
    );
    final shortWidth = tester.getSize(hover).width;
    await controller.updateTitle(task.id, '准备上线前检查所有部署配置与发布说明以及监控指标');
    await tester.pumpAndSettle();
    expect(tester.getSize(hover).width, greaterThan(shortWidth));
    expect(tester.getSize(hover).width, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.text('周日检查')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final sundayHover = find.byKey(ValueKey('calendar-hover-${sundayTask.id}'));
    expect(sundayHover, findsOneWidget);
    expect(
      tester.getRect(sundayHover).right,
      lessThan(
        tester
            .getRect(find.byKey(ValueKey('calendar-tile-${sundayTask.id}')))
            .left,
      ),
    );
    await tester.tap(find.byKey(ValueKey('calendar-tile-${sundayTask.id}')));
    await tester.pumpAndSettle();
    expect(sundayHover, findsNothing);
    expect(controller.selectedId, sundayTask.id);
    await mouse.moveTo(Offset.zero);
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });

  for (final mode in ['日', '周']) {
    testWidgets('$mode视图重叠任务独立并列，自适应填满列宽', (tester) async {
      var id = 0;
      final controller = AppController(
        NodePersistenceWorkspace(
          MemoryNodeRepository(),
          idGenerator: () => 'parallel-${++id}',
        ),
        clock: () => DateTime(2026, 10, 21, 9),
      );
      await controller.load();
      addTearDown(controller.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<TodoNode> task(String title, int start, int end, {int day = 21}) =>
          expectWriteSuccess(
            controller.createScheduledTask(
              title: title,
              eventName: '项目',
              start: DateTime(2026, 10, day, start),
              end: DateTime(2026, 10, day, end),
            ),
          );
      final long = await task('长任务', 9, 11);
      final first = await task('短任务一', 9, 10);
      final second = await task('短任务二', 9, 10);
      final later = await task('后半段', 10, 11);
      final isolated = await task('独立任务', 11, 12);
      final otherDay = await task('次日任务', 9, 11, day: 22);
      await controller.setTaskStatus(first.id, TodoNodeStatus.completed);
      controller.setView(AppView.timeline);
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(TodoApp(controller: controller));
      await tester.pumpAndSettle();
      if (mode == '日') {
        await tester.tap(find.text('日'));
        await tester.pumpAndSettle();
      }
      Finder tile(TodoNode node) =>
          find.byKey(ValueKey('calendar-tile-${node.id}'));
      Rect rect(TodoNode node) => tester.getRect(tile(node));
      final full = rect(isolated);
      final columns = [rect(long), rect(first), rect(second)]
        ..sort((a, b) => a.left.compareTo(b.left));
      for (final column in columns) {
        expect(column.width, closeTo(full.width / 3, 0.01));
      }
      expect(columns.first.left, closeTo(full.left, 0.01));
      expect(columns[0].right, closeTo(columns[1].left, 0.01));
      expect(columns[1].right, closeTo(columns[2].left, 0.01));
      expect(columns.last.right, closeTo(full.right, 0.01));
      expect(rect(later).width, closeTo(full.width * 2 / 3, 0.01));
      expect(rect(later).right, closeTo(full.right, 0.01));
      expect(rect(first).bottom, closeTo(rect(later).top, 0.01));
      expect(rect(long).bottom, closeTo(full.top, 0.01));
      if (mode == '周') {
        expect(rect(otherDay).width, closeTo(full.width, 0.01));
      }
      final calendar = tester.widget<KalenderView>(find.byType(KalenderView));
      expect(calendar.eventsController.events, hasLength(6));
      for (final endHour in [9, 10, 11]) {
        calendar.kalenderController.selectEvent(
          KalenderEvent(
            start: DateTime(2026, 10, 21, 8),
            end: DateTime(2026, 10, 21, endHour),
          ),
          internal: true,
        );
        await tester.pumpAndSettle();
        final preview = tester.getRect(
          find.byKey(const ValueKey('calendar-create-preview')),
        );
        expect(preview.left, closeTo(full.left, 0.01));
        expect(preview.width, closeTo(full.width, 0.01));
        expect(rect(long).width, closeTo(full.width / 3, 0.01));
      }
      calendar.kalenderController.deselectEvent();
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(tile(first)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final hover = find.byKey(ValueKey('calendar-hover-${first.id}'));
      expect(
        find.descendant(of: hover, matching: find.text(first.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hover, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      await controller.updateDeadline(
        second.id,
        TimedDeadline(DateTime(2026, 10, 21, 13)),
      );
      await tester.pumpAndSettle();
      expect(rect(long).width, closeTo(rect(isolated).width / 2, 0.01));
      expect(rect(first).width, closeTo(rect(isolated).width / 2, 0.01));
      expect(rect(second).width, closeTo(rect(isolated).width, 0.01));
      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pumpAndSettle();
      expect(
        rect(long).width + rect(first).width,
        closeTo(rect(isolated).width, 0.01),
      );
      await tester.tap(tile(first));
      await tester.pumpAndSettle();
      expect(controller.selectedId, first.id);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpAndSettle();
    });
  }

  for (final mode in ['日', '周']) {
    testWidgets('$mode重叠任务按创建时间排序，早创建的任务靠左', (tester) async {
      var id = 0;
      var tick = 0;
      final controller = AppController(
        NodePersistenceWorkspace(
          MemoryNodeRepository(),
          idGenerator: () => 'order-${++id}',
          clock: () => DateTime(2026, 10, 20, 0, 0, tick++),
        ),
        clock: () => DateTime(2026, 10, 21, 9),
      );
      await controller.load();
      addTearDown(controller.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tasks = <TodoNode>[];
      for (final hour in [10, 9, 8]) {
        tasks.add(
          await expectWriteSuccess(
            controller.createScheduledTask(
              title: '任务$hour',
              eventName: '项目',
              start: DateTime(2026, 10, 21, hour),
              end: DateTime(2026, 10, 21, 11),
            ),
          ),
        );
      }
      controller.setView(AppView.timeline);
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpWidget(TodoApp(controller: controller));
      await tester.pumpAndSettle();
      if (mode == '日') {
        await tester.tap(find.text('日'));
        await tester.pumpAndSettle();
      }
      final rects = [
        for (final task in tasks)
          tester.getRect(find.byKey(ValueKey('calendar-tile-${task.id}'))),
      ];
      expect(rects[0].right, closeTo(rects[1].left, 0.01));
      expect(rects[1].right, closeTo(rects[2].left, 0.01));
      expect(rects[0].width, closeTo(rects[2].width, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('日周月展示范围、翻页、详情和窄窗口', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => '${++id}',
      ),
      clock: () => DateTime(2026, 10, 21, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.create(
      title: '当日事项',
      deadline: DateOnlyDeadline(year: 2026, month: 10, day: 21),
      selectCreated: false,
    );
    await controller.create(
      title: '周内事项',
      deadline: DateOnlyDeadline(year: 2026, month: 10, day: 23),
      selectCreated: false,
    );
    await controller.create(
      title: '月底事项',
      deadline: DateOnlyDeadline(year: 2026, month: 10, day: 31),
      selectCreated: false,
    );
    await controller.create(
      title: '定时事项',
      deadline: TimedDeadline(DateTime(2026, 10, 21, 21)),
      selectCreated: false,
    );
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('当日事项'), findsWidgets);
    expect(find.text('周内事项'), findsWidgets);
    expect(find.text('月底事项'), findsNothing);
    expect(find.text('定时事项').hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('time-21-0')), findsOneWidget);
    expect(find.byKey(const Key('time-21-30')), findsNothing);

    expect(find.byTooltip('上一周'), findsOneWidget);
    expect(find.byTooltip('下一周'), findsOneWidget);
    expect(find.text('回到今天'), findsNothing);
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('回到今天'), findsOneWidget);
    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();
    expect(find.text('回到今天'), findsNothing);

    final weekLabel = tester
        .widget<Text>(find.byKey(const ValueKey('calendar-range')))
        .data;
    await tester.tap(find.text('周五'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('calendar-range'))).data,
      weekLabel,
    );
    expect(find.text('周内事项'), findsWidgets);

    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();
    expect(find.text('2026.10.21 周三'), findsOneWidget);
    expect(find.byTooltip('上一天'), findsOneWidget);
    expect(find.text('回到今天'), findsNothing);
    expect(find.text('当日事项'), findsWidgets);
    expect(find.text('周内事项'), findsNothing);
    await tester.tap(find.byTooltip('下一天'));
    await tester.pumpAndSettle();
    expect(find.text('2026.10.22 周四'), findsOneWidget);
    expect(find.text('回到今天'), findsOneWidget);
    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(find.text('月底事项'), findsWidgets);
    expect(find.byTooltip('上一月'), findsOneWidget);
    expect(find.text('回到今天'), findsNothing);
    await tester.tap(find.byTooltip('下一月'));
    await tester.pumpAndSettle();
    expect(find.text('2026.11'), findsOneWidget);
    expect(find.text('回到今天'), findsOneWidget);
    await tester.tap(find.text('回到今天'));
    await tester.pumpAndSettle();
    expect(find.text('2026.10'), findsOneWidget);
    expect(find.text('回到今天'), findsNothing);

    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('当日事项').first);
    await tester.pumpAndSettle();
    expect(controller.view, AppView.timeline);
    expect(controller.selectedNode?.title, '当日事项');
  });
  testWidgets('日期弹层在日周月均可选日期，选择后关闭，浏览月份不改变日程', (tester) async {
    final controller = AppController(
      NodePersistenceWorkspace(MemoryNodeRepository()),
      clock: () => DateTime(2026, 10, 21, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    for (final (mode, day, label) in [
      ('日', '23', '2026.10.23 周五'),
      ('周', '24', '2026.10.19 — 2026.10.25'),
      ('月', '25', '2026.10'),
    ]) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-date-menu')));
      await tester.pumpAndSettle();
      if (mode == '周') {
        for (final date in [19, 20, 21, 22, 23, 24, 25]) {
          final cell = tester.widget<Container>(
            find.byKey(ValueKey('calendar-pick-week-2026-10-$date')),
          );
          expect((cell.decoration! as BoxDecoration).color, isNotNull);
        }
      }
      await tester.tap(
        mode == '月'
            ? find.byKey(const ValueKey('calendar-pick-month-10'))
            : find.descendant(
                of: find.byType(CalendarDatePicker2),
                matching: find.text(day),
              ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker2), findsNothing);
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Browsing candidate months in day mode must not navigate the schedule.
    await tester.tap(find.text('日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-date-menu')));
    await tester.pumpAndSettle();
    final picker = find.byType(CalendarDatePicker2);
    final localizations = MaterialLocalizations.of(tester.element(picker));
    await tester.tap(find.byTooltip(localizations.nextMonthTooltip));
    await tester.pumpAndSettle();
    expect(find.text('2026.10.01 周四'), findsOneWidget);
    await tester.tap(find.descendant(of: picker, matching: find.text('5')));
    await tester.pumpAndSettle();
    expect(find.text('2026.11.05 周四'), findsOneWidget);
    expect(picker, findsNothing);

    // Month mode confirms a month directly and can browse years independently.
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-date-menu')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CalendarDatePicker2>(picker).value.single,
      DateTime(2026, 11, 5),
    );
    expect(
      find.descendant(of: picker, matching: find.text('23')),
      findsNothing,
    );
    await tester.tap(find.byTooltip('下一年'));
    await tester.pumpAndSettle();
    expect(find.text('2026.11'), findsOneWidget);
    expect(find.text('回到今天'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-pick-month-12')));
    await tester.pumpAndSettle();
    expect(find.text('2027.12'), findsOneWidget);
    expect(picker, findsNothing);
    await tester.tap(find.byTooltip('下一月'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-date-menu')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CalendarDatePicker2>(picker).value.single,
      DateTime(2028, 1, 1),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('各模式日期格式和宽度固定，跨月跨年不改变控件宽度', (tester) async {
    final controller = AppController(
      NodePersistenceWorkspace(MemoryNodeRepository()),
      clock: () => DateTime(2026, 12, 31, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('calendar-date-menu'));
    final label = find.byKey(const ValueKey('calendar-range'));
    for (final (mode, before, after, tooltip) in [
      ('日', '2026.12.31 周四', '2027.01.01 周五', '下一天'),
      ('周', '2026.12.28 — 2027.01.03', '2027.01.04 — 2027.01.10', '下一周'),
      ('月', '2027.01', '2027.02', '下一月'),
    ]) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).data, before);
      final width = tester.getSize(field).width;
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).data, after);
      expect(tester.getSize(field).width, width);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
