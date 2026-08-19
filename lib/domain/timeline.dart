import 'node_tree.dart';
import 'todo_node.dart';

class TimelineEntry {
  const TimelineEntry({
    required this.node,
    required this.path,
    required this.isEvent,
    required this.isComplete,
    required this.completedAt,
  });

  final TodoNode node;
  final List<String> path;
  final bool isEvent;
  final bool isComplete;
  final DateTime? completedAt;
}

class TimelineQuery {
  const TimelineQuery(this.now);

  final DateTime now;

  List<TimelineEntry> entriesForDate(
    NodeTree tree,
    DateTime date, {
    bool includeOverdue = false,
  }) {
    final target = _startOfDay(date);
    final result = _openEntries(tree).where((entry) {
      final deadline = entry.node.deadline?.toLocal();
      if (deadline == null) return false;
      return _sameDate(deadline, target) ||
          (includeOverdue && deadline.isBefore(target));
    }).toList();
    _sortEntries(result, overdueBefore: includeOverdue ? target : null);
    return result;
  }

  List<TimelineEntry> completedEntriesForDate(NodeTree tree, DateTime date) {
    final target = _startOfDay(date);
    final result =
        tree.nodes.values
            .where((node) {
              final completedAt = node.completedAt?.toLocal();
              return completedAt != null && _sameDate(completedAt, target);
            })
            .map((node) => _entryFor(tree, node))
            .toList()
          ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    return result;
  }

  List<TimelineEntry> laterEntries(NodeTree tree, DateTime after) {
    final boundary = _startOfDay(after).add(const Duration(days: 1));
    final result = _openEntries(tree).where((entry) {
      final deadline = entry.node.deadline?.toLocal();
      return deadline == null || !deadline.isBefore(boundary);
    }).toList();
    _sortEntries(result);
    return result;
  }

  int countForDate(NodeTree tree, DateTime date) =>
      entriesForDate(tree, date).length +
      completedEntriesForDate(tree, date).length;

  List<TimelineEntry> _openEntries(NodeTree tree) => tree.nodes.values
      .where((node) => tree.isLeaf(node.id) || node.deadline != null)
      .map((node) => _entryFor(tree, node))
      .where((entry) => !entry.isComplete)
      .toList();

  TimelineEntry _entryFor(NodeTree tree, TodoNode node) => TimelineEntry(
    node: node,
    path: tree.pathFor(node.id),
    isEvent: !tree.isLeaf(node.id),
    isComplete: tree.isComplete(node.id),
    completedAt: tree.effectiveCompletedAt(node.id),
  );

  void _sortEntries(List<TimelineEntry> entries, {DateTime? overdueBefore}) {
    entries.sort((a, b) {
      if (overdueBefore != null) {
        final aOverdue = a.node.deadline!.toLocal().isBefore(overdueBefore);
        final bOverdue = b.node.deadline!.toLocal().isBefore(overdueBefore);
        if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
      }
      return _deadlineComparator(a.node, b.node);
    });
  }

  int _deadlineComparator(TodoNode a, TodoNode b) {
    final aDeadline = a.deadline;
    final bDeadline = b.deadline;
    if (aDeadline == null && bDeadline != null) return 1;
    if (aDeadline != null && bDeadline == null) return -1;
    if (aDeadline != null && bDeadline != null) {
      final deadlineOrder = aDeadline.compareTo(bDeadline);
      if (deadlineOrder != 0) return deadlineOrder;
    }
    final createdOrder = a.createdAt.compareTo(b.createdAt);
    return createdOrder != 0 ? createdOrder : a.id.compareTo(b.id);
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
