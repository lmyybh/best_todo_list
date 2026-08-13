import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  testWidgets('时间线支持连续日期跨周更晚和回到今天', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'timeline-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.create(
      title: '明天任务',
      deadline: DateTime(2026, 8, 14, 16),
      selectCreated: false,
    );
    await controller.create(
      title: '远期任务',
      deadline: DateTime(2026, 8, 20, 16),
      selectCreated: false,
    );
    controller.setView(AppView.timeline);
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('2026 年 8 月'), findsOneWidget);
    expect(find.text('今天'), findsWidgets);
    expect(find.text('明天'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('timeline-later')),
      findsOneWidget,
    );

    await tester.tap(find.text('明天'));
    await tester.pumpAndSettle();
    expect(find.text('明天任务'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('timeline-later')));
    await tester.pumpAndSettle();
    expect(find.text('远期任务'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('timeline-next-week')));
    await tester.pumpAndSettle();
    expect(controller.timelineWindowStart, DateTime(2026, 8, 17));
    await tester.tap(find.byKey(const ValueKey<String>('timeline-today')));
    await tester.pumpAndSettle();
    expect(controller.selectedTimelineDate, DateTime(2026, 8, 13));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.selectedTimelineDate, DateTime(2026, 8, 14));
  });
}
