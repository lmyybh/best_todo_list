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

  test('今天可以包含逾期并将逾期置顶', () {
    final tree = NodeTree(<TodoNode>[
      node('today', deadline: DateTime(2026, 8, 11, 18)),
      node('overdue', deadline: DateTime(2026, 8, 10, 18)),
      node('tomorrow', deadline: DateTime(2026, 8, 12, 9)),
    ]);
    final result = TimelineQuery(
      now,
    ).entriesForDate(tree, now, includeOverdue: true);
    expect(result.map((entry) => entry.node.id), <String>['overdue', 'today']);
  });

  test('按日期只返回对应自然日', () {
    final tree = NodeTree(<TodoNode>[
      node('monday', deadline: DateTime(2026, 8, 10, 9)),
      node('sunday', deadline: DateTime(2026, 8, 16, 22)),
      node('next-monday', deadline: DateTime(2026, 8, 17, 9)),
    ]);
    final monday = TimelineQuery(
      now,
    ).entriesForDate(tree, DateTime(2026, 8, 10));
    final sunday = TimelineQuery(
      now,
    ).entriesForDate(tree, DateTime(2026, 8, 16));
    expect(monday.map((entry) => entry.node.id), <String>['monday']);
    expect(sunday.map((entry) => entry.node.id), <String>['sunday']);
  });

  test('更晚按未来、无 deadline 排序', () {
    final tree = NodeTree(<TodoNode>[
      node('none'),
      node('future', deadline: DateTime(2026, 8, 20)),
    ]);
    final result = TimelineQuery(now).laterEntries(tree, DateTime(2026, 8, 15));
    expect(result.map((entry) => entry.node.id), <String>['future', 'none']);
  });

  test('无 deadline 的事件不显示，叶子显示', () {
    final tree = NodeTree(<TodoNode>[
      node('event'),
      node('leaf', parentId: 'event'),
    ]);
    final result = TimelineQuery(now).laterEntries(tree, DateTime(2026, 8, 15));
    expect(result.map((entry) => entry.node.id), <String>['leaf']);
  });

  test('已完成任务按完成自然日归档并按 completedAt 倒序', () {
    final tree = NodeTree(<TodoNode>[
      node(
        'old',
        deadline: DateTime(2026, 8, 12),
        completedAt: DateTime.utc(2026, 8, 11, 1),
      ),
      node('new', completedAt: DateTime.utc(2026, 8, 11, 2)),
      node('other-day', completedAt: DateTime.utc(2026, 8, 10, 2)),
    ]);
    final query = TimelineQuery(now);
    expect(query.entriesForDate(tree, DateTime(2026, 8, 12)), isEmpty);
    final shown = query.completedEntriesForDate(tree, now);
    expect(shown.map((entry) => entry.node.id), <String>['new', 'old']);
  });

  test('按自然日查询并只在需要时包含逾期', () {
    final tree = NodeTree(<TodoNode>[
      node('overdue', deadline: DateTime(2026, 8, 10, 18)),
      node('today', deadline: DateTime(2026, 8, 11, 18)),
      node('tomorrow', deadline: DateTime(2026, 8, 12, 9)),
    ]);
    final query = TimelineQuery(now);
    expect(
      query.entriesForDate(tree, DateTime(2026, 8, 11)).map((e) => e.node.id),
      <String>['today'],
    );
    expect(
      query
          .entriesForDate(tree, DateTime(2026, 8, 11), includeOverdue: true)
          .map((e) => e.node.id),
      <String>['overdue', 'today'],
    );
  });

  test('更晚查询包含窗口之后和无日期任务', () {
    final tree = NodeTree(<TodoNode>[
      node('inside', deadline: DateTime(2026, 8, 15)),
      node('later', deadline: DateTime(2026, 8, 16)),
      node('none'),
    ]);
    final result = TimelineQuery(now).laterEntries(tree, DateTime(2026, 8, 15));
    expect(result.map((entry) => entry.node.id), <String>['later', 'none']);
  });

  test('按日查询跨月跨年且保持稳定排序', () {
    final newYear = DateTime(2026, 12, 31, 12);
    final tree = NodeTree(<TodoNode>[
      node('b', deadline: DateTime(2027, 1, 1, 9)),
      node('a', deadline: DateTime(2027, 1, 1, 9)),
      node('old-year', deadline: DateTime(2026, 12, 31, 23)),
    ]);
    final result = TimelineQuery(
      newYear,
    ).entriesForDate(tree, DateTime(2027, 1, 1));
    expect(result.map((entry) => entry.node.id), <String>['a', 'b']);
  });

  test('按日计数包含当天到期未完成和当天完成的任务', () {
    final tree = NodeTree(<TodoNode>[
      node('open', deadline: DateTime(2026, 8, 11, 9)),
      node(
        'done',
        deadline: DateTime(2026, 8, 11, 10),
        completedAt: DateTime.utc(2026, 8, 11, 10),
      ),
    ]);
    expect(TimelineQuery(now).countForDate(tree, now), 2);
  });
}
