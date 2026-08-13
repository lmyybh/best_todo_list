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
    bool showCompleted = false,
    bool includeOverdue = false,
  }) {
    final target = _startOfDay(date);
    final result = _visibleEntries(tree, showCompleted: showCompleted).where((
      entry,
    ) {
      final deadline = entry.node.deadline?.toLocal();
      if (deadline == null) return false;
      return _sameDate(deadline, target) ||
          (includeOverdue && deadline.isBefore(target));
    }).toList();
    _sortEntries(
      result,
      showCompleted: showCompleted,
      overdueBefore: includeOverdue ? target : null,
    );
    return result;
  }

  List<TimelineEntry> laterEntries(
    NodeTree tree,
    DateTime after, {
    bool showCompleted = false,
  }) {
    final boundary = _startOfDay(after).add(const Duration(days: 1));
    final result = _visibleEntries(tree, showCompleted: showCompleted).where((
      entry,
    ) {
      final deadline = entry.node.deadline?.toLocal();
      return deadline == null || !deadline.isBefore(boundary);
    }).toList();
    _sortEntries(result, showCompleted: showCompleted);
    return result;
  }

  int countForDate(NodeTree tree, DateTime date) =>
      entriesForDate(tree, date).length;

  List<TimelineEntry> _visibleEntries(
    NodeTree tree, {
    required bool showCompleted,
  }) => tree.nodes.values
      .where((node) => tree.isLeaf(node.id) || node.deadline != null)
      .map(
        (node) => TimelineEntry(
          node: node,
          path: tree.pathFor(node.id),
          isEvent: !tree.isLeaf(node.id),
          isComplete: tree.isComplete(node.id),
          completedAt: tree.effectiveCompletedAt(node.id),
        ),
      )
      .where((entry) => showCompleted || !entry.isComplete)
      .toList();

  void _sortEntries(
    List<TimelineEntry> entries, {
    required bool showCompleted,
    DateTime? overdueBefore,
  }) {
    entries.sort((a, b) {
      if (showCompleted && a.isComplete != b.isComplete) {
        return a.isComplete ? 1 : -1;
      }
      if (a.isComplete && b.isComplete) {
        return b.completedAt!.compareTo(a.completedAt!);
      }
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
