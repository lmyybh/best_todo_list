import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  test('日期窗口切换并可回到今天', () async {
    var now = DateTime(2026, 8, 13, 9);
    final controller = AppController(
      NodeService(MemoryNodeRepository()),
      clock: () => now,
    );
    await controller.load();
    addTearDown(controller.dispose);

    expect(controller.timelineWindowStart, DateTime(2026, 8, 10));
    expect(controller.timelineDates.last, DateTime(2026, 8, 15));
    controller.shiftTimelineWindow(1);
    expect(controller.timelineWindowStart, DateTime(2026, 8, 17));
    expect(controller.selectedTimelineDate, DateTime(2026, 8, 17));
    controller.selectTimelineLater();
    expect(controller.timelineLaterSelected, isTrue);
    controller.resetTimelineToToday();
    expect(controller.selectedTimelineDate, DateTime(2026, 8, 13));
    expect(controller.timelineWindowStart, DateTime(2026, 8, 10));
    expect(controller.timelineLaterSelected, isFalse);

    now = DateTime(2026, 8, 14, 0, 1);
    controller.refreshTime();
    expect(controller.selectedTimelineDate, DateTime(2026, 8, 14));
  });

  test('主动浏览其他周时跨天刷新不覆盖用户选择', () async {
    var now = DateTime(2026, 12, 31, 23, 59);
    final controller = AppController(
      NodeService(MemoryNodeRepository()),
      clock: () => now,
    );
    await controller.load();
    addTearDown(controller.dispose);

    controller.shiftTimelineWindow(1);
    final selected = controller.selectedTimelineDate;
    now = DateTime(2027, 1, 1, 0, 1);
    controller.refreshTime();
    expect(controller.selectedTimelineDate, selected);
  });
}
