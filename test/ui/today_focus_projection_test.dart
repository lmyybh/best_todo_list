import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/node_tree.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/events/today_focus_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('今日关注包含今天和逾期的未完成叶子任务及其祖先', () {
    final now = DateTime(2026, 9, 16, 10);
    final nodes = <TodoNode>[
      node('event', '事件'),
      node('branch', '分支', parentId: 'event'),
      node(
        'overdue',
        '逾期任务',
        parentId: 'branch',
        deadline: DateOnlyDeadline(year: 2026, month: 9, day: 15),
      ),
      node(
        'today',
        '今日任务',
        parentId: 'event',
        deadline: TimedDeadline(DateTime(2026, 9, 16, 18)),
      ),
      node(
        'future',
        '未来任务',
        parentId: 'event',
        deadline: DateOnlyDeadline(year: 2026, month: 9, day: 17),
      ),
      node('other-event', '其他事件'),
      node(
        'completed',
        '已完成逾期任务',
        parentId: 'other-event',
        deadline: DateOnlyDeadline(year: 2026, month: 9, day: 14),
        completedAt: DateTime(2026, 9, 15),
      ),
    ];
    final source = NodeTree(nodes);

    final projection = TodayFocusProjection.from(
      source: source,
      roots: source.visibleChildrenOf(null),
      now: now,
    );

    expect(projection.roots.map((node) => node.id), <String>['event']);
    expect(projection.taskCountFor('event'), 2);
    expect(projection.tree.nodes.keys, <String>{
      'event',
      'branch',
      'overdue',
      'today',
    });
  });

  test('顶层叶子任务可以进入今日关注，放弃任务不会进入', () {
    final nodes = <TodoNode>[
      node(
        'root-task',
        '顶层任务',
        deadline: DateOnlyDeadline(year: 2026, month: 9, day: 16),
      ),
      node(
        'abandoned',
        '已放弃',
        deadline: DateOnlyDeadline(year: 2026, month: 9, day: 15),
        abandonedAt: DateTime(2026, 9, 15),
      ),
    ];
    final source = NodeTree(nodes);

    final projection = TodayFocusProjection.from(
      source: source,
      roots: source.visibleChildrenOf(null),
      now: DateTime(2026, 9, 16),
    );

    expect(projection.roots.map((node) => node.id), <String>['root-task']);
    expect(projection.taskCountFor('root-task'), 1);
  });
}

TodoNode node(
  String id,
  String title, {
  String? parentId,
  Deadline? deadline,
  DateTime? completedAt,
  DateTime? abandonedAt,
}) => TodoNode(
  id: id,
  parentId: parentId,
  title: title,
  deadline: deadline,
  completedAt: completedAt,
  abandonedAt: abandonedAt,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  manualOrder: 0,
);
