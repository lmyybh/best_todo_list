import 'package:best_todo_list/domain/node_tree.dart';
import 'package:best_todo_list/domain/timeline.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 11, 12);
  final created = DateTime.utc(2026, 8, 1);

  TodoNode node(
    String id, {
    DateTime? deadline,
    String? parentId,
    DateTime? completedAt,
  }) => TodoNode(
    id: id,
    parentId: parentId,
    title: id,
    deadline: deadline,
    createdAt: created,
    updatedAt: created,
    completedAt: completedAt,
    manualOrder: 1000,
  );

  test('今天包含逾期并将逾期置顶', () {
    final tree = NodeTree(<TodoNode>[
      node('today', deadline: DateTime(2026, 8, 11, 18)),
      node('overdue', deadline: DateTime(2026, 8, 10, 18)),
      node('tomorrow', deadline: DateTime(2026, 8, 12, 9)),
    ]);
    final result = TimelineQuery(now).entries(tree, TimelineGroup.today);
    expect(result.map((entry) => entry.node.id), <String>['overdue', 'today']);
  });

  test('本周按周一到周日计算', () {
    final tree = NodeTree(<TodoNode>[
      node('monday', deadline: DateTime(2026, 8, 10, 9)),
      node('sunday', deadline: DateTime(2026, 8, 16, 22)),
      node('next-monday', deadline: DateTime(2026, 8, 17, 9)),
    ]);
    final result = TimelineQuery(now).entries(tree, TimelineGroup.thisWeek);
    expect(result.map((entry) => entry.node.id), <String>['monday', 'sunday']);
  });

  test('其他按逾期、未来、无 deadline 分区', () {
    final tree = NodeTree(<TodoNode>[
      node('none'),
      node('future', deadline: DateTime(2026, 8, 20)),
      node('overdue', deadline: DateTime(2026, 8, 1)),
    ]);
    final result = TimelineQuery(now).entries(tree, TimelineGroup.other);
    expect(result.map((entry) => entry.node.id), <String>[
      'overdue',
      'future',
      'none',
    ]);
  });

  test('无 deadline 的事件不显示，叶子显示', () {
    final tree = NodeTree(<TodoNode>[
      node('event'),
      node('leaf', parentId: 'event'),
    ]);
    final result = TimelineQuery(now).entries(tree, TimelineGroup.other);
    expect(result.map((entry) => entry.node.id), <String>['leaf']);
  });

  test('默认隐藏已完成，开启后按 completedAt 倒序', () {
    final tree = NodeTree(<TodoNode>[
      node('old', completedAt: DateTime.utc(2026, 8, 9)),
      node('new', completedAt: DateTime.utc(2026, 8, 10)),
    ]);
    expect(TimelineQuery(now).entries(tree, TimelineGroup.other), isEmpty);
    final shown = TimelineQuery(
      now,
    ).entries(tree, TimelineGroup.other, showCompleted: true);
    expect(shown.map((entry) => entry.node.id), <String>['new', 'old']);
  });
}
