import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/app/node_write_result.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  late NodePersistenceWorkspace workspace;
  final start = DateTime(2026, 10, 21, 9);
  final end = DateTime(2026, 10, 21, 11);
  setUp(() async {
    var id = 0;
    workspace = NodePersistenceWorkspace(
      MemoryNodeRepository(),
      idGenerator: () => 'scheduled-${++id}',
    );
    await workspace.load();
  });
  tearDown(() => workspace.close());

  test('同名事件并发创建复用同一事件，记录准确起止时间', () async {
    final results = await Future.wait([
      workspace.createScheduledTask(
        title: '任务一',
        eventName: ' 项目 ',
        start: start,
        end: end,
      ),
      workspace.createScheduledTask(
        title: '任务二',
        eventName: '项目',
        start: start,
        end: end,
      ),
    ]);
    expect(results.every((result) => result is NodeWriteSuccess), isTrue);
    final event = workspace.tree.childrenOf(null).single;
    expect(event.title, '项目');
    expect(event.eventHue, isNotNull);
    final tasks = workspace.tree.childrenOf(event.id);
    expect(tasks, hasLength(2));
    for (final task in tasks) {
      expect(task.scheduledStart?.toLocal(), start);
      expect((task.deadline as TimedDeadline).localTime, end);
      expect(task.copyWith(title: '改名').scheduledStart, task.scheduledStart);
    }
  });

  test('事件必填、区间有效且只能挂到可用顶层事件', () async {
    expect(
      await workspace.createScheduledTask(
        title: '任务',
        eventName: ' ',
        start: start,
        end: end,
      ),
      isA<NodeWriteFailure>(),
    );
    expect(
      await workspace.createScheduledTask(
        title: '任务',
        eventName: '项目',
        start: end,
        end: start,
      ),
      isA<NodeWriteFailure>(),
    );
    expect(workspace.nodes, isEmpty);
    final event = await expectWriteSuccess(workspace.createNode(title: '项目'));
    final child = await expectWriteSuccess(
      workspace.createNode(title: '子任务', parentId: event.id),
    );
    expect(
      await workspace.createScheduledTask(
        title: '任务',
        eventName: '子任务',
        eventId: child.id,
        start: start,
        end: end,
      ),
      isA<NodeWriteFailure>(),
    );
    await expectWriteSuccess(workspace.setEventArchived(event.id, true));
    expect(
      await workspace.createScheduledTask(
        title: '任务',
        eventName: '项目',
        start: start,
        end: end,
      ),
      isA<NodeWriteFailure>(),
    );
    expect(workspace.nodes, hasLength(2));
  });

  test('同名事件要求明确选择，已完成叶子事件新增任务会恢复未完成', () async {
    final first = await expectWriteSuccess(workspace.createNode(title: '项目'));
    final second = await expectWriteSuccess(workspace.createNode(title: '项目'));
    expect(
      await workspace.createScheduledTask(
        title: '任务',
        eventName: '项目',
        start: start,
        end: end,
      ),
      isA<NodeWriteFailure>(),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(second.id, TodoNodeStatus.completed),
    );
    final task = await expectWriteSuccess(
      workspace.createScheduledTask(
        title: '任务',
        eventName: '项目',
        eventId: second.id,
        start: start,
        end: end,
      ),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(task.parentId!, TimedDeadline(end)),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(
        task.parentId!,
        TimedDeadline(DateTime(2026, 10, 22, 11)),
      ),
    );
    expect(
      workspace.tree.nodes[task.id]!.scheduledStart?.toLocal(),
      DateTime(2026, 10, 22, 9),
    );
    expect(task.parentId, second.id);
    expect(workspace.tree.childrenOf(first.id), isEmpty);
    expect(workspace.tree.isComplete(second.id), isFalse);
    expect(workspace.tree.nodes[second.id]!.completedAt, isNull);
  });

  test('改期保持所选时长，改为纯日期或清除期限后移除开始时间', () async {
    final task = await expectWriteSuccess(
      workspace.createScheduledTask(
        title: '任务',
        eventName: '项目',
        start: start,
        end: end,
      ),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(
        task.id,
        TimedDeadline(DateTime(2026, 10, 22, 12)),
      ),
    );
    expect(
      workspace.tree.nodes[task.id]!.scheduledStart?.toLocal(),
      DateTime(2026, 10, 22, 10),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(
        task.id,
        DateOnlyDeadline(year: 2026, month: 10, day: 23),
      ),
    );
    expect(workspace.tree.nodes[task.id]!.scheduledStart, isNull);
    final other = await expectWriteSuccess(
      workspace.createScheduledTask(
        title: '任务二',
        eventName: '项目',
        start: start,
        end: end,
      ),
    );
    await expectWriteSuccess(workspace.updateDeadline(other.id, null));
    expect(workspace.tree.nodes[other.id]!.scheduledStart, isNull);
  });
}
