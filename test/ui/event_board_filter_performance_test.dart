import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/ui/events/event_card_task_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  testWidgets('从今日切回全部时复用已挂载的事件卡片', (tester) async {
    var id = 0;
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        clock: () => DateTime.utc(2026, 8, 13, 9),
        idGenerator: () => 'filter-performance-${++id}',
      ),
      clock: () => DateTime(2026, 8, 13, 9),
    );
    await controller.load();
    addTearDown(controller.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? futureEventId;
    for (var eventIndex = 0; eventIndex < 4; eventIndex++) {
      final event = await expectWriteSuccess(
        controller.create(title: '事件 $eventIndex', selectCreated: false),
      );
      if (eventIndex == 1) futureEventId = event.id;
      for (var taskIndex = 0; taskIndex < 4; taskIndex++) {
        await controller.create(
          parentId: event.id,
          title: '任务 $eventIndex-$taskIndex',
          deadline: DateOnlyDeadline(
            year: 2026,
            month: 8,
            day: eventIndex.isEven && taskIndex == 0 ? 13 : 20,
          ),
          selectCreated: false,
        );
      }
    }
    controller.showEventOverview();

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(TodoApp(controller: controller));
    await tester.pumpAndSettle();
    final futureCard = find.byKey(
      ValueKey<String>('event-card-$futureEventId'),
    );
    final taskInteraction = find.descendant(
      of: futureCard,
      matching: find.byType(EventCardTaskInteraction),
    );
    final stateBeforeFiltering = tester.state(taskInteraction);

    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(futureCard, findsNothing);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(tester.state(taskInteraction), same(stateBeforeFiltering));
  });
}
