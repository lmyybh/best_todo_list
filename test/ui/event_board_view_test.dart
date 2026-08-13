import 'package:best_todo_list/app/app.dart';
import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  testWidgets('事件卡片随桌面宽度形成一到三列并保持自然高度', (tester) async {
    var id = 0;
    final controller = AppController(
      NodeService(
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
      final root = await controller.create(
        title: '事件 $index',
        selectCreated: false,
      );
      roots.add(root!.id);
    }
    for (var index = 0; index < 4; index++) {
      await controller.create(
        parentId: roots.first,
        title: '任务 $index',
        selectCreated: false,
      );
    }
    controller.showEventOverview();

    Future<void> expectColumns(double width, int expectedColumns) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(TodoApp(controller: controller));
      await tester.pumpAndSettle();
      final cards = <Finder>[
        for (final root in roots)
          find.byKey(ValueKey<String>('event-card-$root')),
      ];
      final firstRowY = tester.getTopLeft(cards.first).dy;
      final firstRowCount = cards
          .where((card) => (tester.getTopLeft(card).dy - firstRowY).abs() < 1)
          .length;
      expect(firstRowCount, expectedColumns);
    }

    await expectColumns(720, 1);
    await expectColumns(1100, 2);
    await expectColumns(1440, 3);

    final tallCard = find.byKey(ValueKey<String>('event-card-${roots.first}'));
    final shortCard = find.byKey(ValueKey<String>('event-card-${roots[1]}'));
    expect(
      tester.getSize(tallCard).height,
      greaterThan(tester.getSize(shortCard).height),
    );
  });
}
