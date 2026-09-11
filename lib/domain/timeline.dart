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

class TimelineTreeEntry {
  const TimelineTreeEntry({
    required this.entry,
    required this.depth,
    required this.ancestorIds,
    required this.isContext,
    required this.matchingCount,
  });

  final TimelineEntry entry;
  final int depth;
  final List<String> ancestorIds;
  final bool isContext;
  final int matchingCount;
}

class TimelineExperience {
  TimelineExperience(DateTime now)
    : _now = now,
      _selectedDate = _startOfDay(now),
      _windowStart = _startOfWeek(now);

  DateTime _now;
  DateTime _selectedDate;
  DateTime _windowStart;
  bool _laterSelected = false;
  bool _windowWasMoved = false;

  DateTime get now => _now;
  DateTime get selectedDate => _selectedDate;
  DateTime get windowStart => _windowStart;
  bool get laterSelected => _laterSelected;
  List<DateTime> get dates => List<DateTime>.generate(
    7,
    (index) => _windowStart.add(Duration(days: index)),
  );

  void selectDate(DateTime date) {
    _selectedDate = _startOfDay(date);
    _laterSelected = false;
  }

  void selectLater() => _laterSelected = true;

  void moveSelection(int direction) {
    final visibleDates = dates;
    if (_laterSelected) {
      if (direction < 0) selectDate(visibleDates.last);
      return;
    }
    final currentIndex = visibleDates.indexWhere(
      (date) => _sameDate(date, _selectedDate),
    );
    if (currentIndex < 0) return;
    final next = currentIndex + direction;
    if (next < 0) {
      shiftWindow(-1);
    } else if (next >= visibleDates.length) {
      selectLater();
    } else {
      selectDate(visibleDates[next]);
    }
  }

  void shiftWindow(int weeks) {
    _windowStart = _windowStart.add(Duration(days: weeks * 7));
    _selectedDate = _windowStart;
    _laterSelected = false;
    _windowWasMoved = true;
  }

  void resetToToday() {
    _selectedDate = _startOfDay(_now);
    _windowStart = _startOfWeek(_now);
    _laterSelected = false;
    _windowWasMoved = false;
  }

  bool refresh(DateTime next) {
    final dateChanged = !_sameDate(next, _now);
    final timezoneChanged = next.timeZoneOffset != _now.timeZoneOffset;
    _now = next;
    if (dateChanged && !_windowWasMoved) resetToToday();
    return dateChanged || timezoneChanged;
  }

  TimelineProjection project(NodeTree tree) {
    final query = _TimelineQuery(_now);
    final visibleDates = dates;
    final laterEntries = query.laterEntries(tree, visibleDates.last);
    final selectedEntries = _laterSelected
        ? laterEntries
        : query.entriesForDate(
            tree,
            _selectedDate,
            includeOverdue: _sameDate(_selectedDate, _now),
          );
    final completed = _laterSelected
        ? const <TimelineEntry>[]
        : query.completedEntriesForDate(tree, _selectedDate);
    final abandoned = _laterSelected
        ? const <TimelineEntry>[]
        : query.abandonedEntriesForDate(tree, _selectedDate);
    final overdue = !_laterSelected && _sameDate(_selectedDate, _now)
        ? selectedEntries
              .where((entry) => entry.node.deadline?.isOverdue(_now) ?? false)
              .toList()
        : const <TimelineEntry>[];
    final overdueIds = overdue.map((entry) => entry.node.id).toSet();
    final regular = overdueIds.isEmpty
        ? selectedEntries
        : selectedEntries
              .where((entry) => !overdueIds.contains(entry.node.id))
              .toList();
    return TimelineProjection._(
      now: _now,
      selectedDate: _selectedDate,
      windowStart: _windowStart,
      laterSelected: _laterSelected,
      dates: visibleDates,
      openCounts: <DateTime, int>{
        for (final date in visibleDates)
          date: query
              .entriesForDate(tree, date, includeOverdue: _sameDate(date, _now))
              .length,
      },
      completedCounts: <DateTime, int>{
        for (final date in visibleDates)
          date: query.completedEntriesForDate(tree, date).length,
      },
      abandonedCounts: <DateTime, int>{
        for (final date in visibleDates)
          date: query.abandonedEntriesForDate(tree, date).length,
      },
      overdue: overdue,
      overdueTree: query.treeEntries(tree, overdue),
      regular: regular,
      regularTree: query.treeEntries(tree, regular),
      completed: completed,
      abandoned: abandoned,
      laterCount: laterEntries.length,
    );
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _startOfWeek(DateTime date) =>
      _startOfDay(date).subtract(Duration(days: date.weekday - 1));

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class TimelineProjection {
  TimelineProjection._({
    required this.now,
    required this.selectedDate,
    required this.windowStart,
    required this.laterSelected,
    required List<DateTime> dates,
    required Map<DateTime, int> openCounts,
    required Map<DateTime, int> completedCounts,
    required Map<DateTime, int> abandonedCounts,
    required List<TimelineEntry> overdue,
    required List<TimelineTreeEntry> overdueTree,
    required List<TimelineEntry> regular,
    required List<TimelineTreeEntry> regularTree,
    required List<TimelineEntry> completed,
    required List<TimelineEntry> abandoned,
    required this.laterCount,
  }) : dates = List<DateTime>.unmodifiable(dates),
       _openCounts = Map<DateTime, int>.unmodifiable(openCounts),
       _completedCounts = Map<DateTime, int>.unmodifiable(completedCounts),
       _abandonedCounts = Map<DateTime, int>.unmodifiable(abandonedCounts),
       overdue = List<TimelineEntry>.unmodifiable(overdue),
       overdueTree = List<TimelineTreeEntry>.unmodifiable(overdueTree),
       regular = List<TimelineEntry>.unmodifiable(regular),
       regularTree = List<TimelineTreeEntry>.unmodifiable(regularTree),
       completed = List<TimelineEntry>.unmodifiable(completed),
       abandoned = List<TimelineEntry>.unmodifiable(abandoned);

  final DateTime now;
  final DateTime selectedDate;
  final DateTime windowStart;
  final bool laterSelected;
  final List<DateTime> dates;
  final Map<DateTime, int> _openCounts;
  final Map<DateTime, int> _completedCounts;
  final Map<DateTime, int> _abandonedCounts;
  final List<TimelineEntry> overdue;
  final List<TimelineTreeEntry> overdueTree;
  final List<TimelineEntry> regular;
  final List<TimelineTreeEntry> regularTree;
  final List<TimelineEntry> completed;
  final List<TimelineEntry> abandoned;
  final int laterCount;

  int countFor(DateTime date) =>
      _openCounts[DateTime(date.year, date.month, date.day)] ?? 0;

  int completedCountFor(DateTime date) =>
      _completedCounts[DateTime(date.year, date.month, date.day)] ?? 0;

  int abandonedCountFor(DateTime date) =>
      _abandonedCounts[DateTime(date.year, date.month, date.day)] ?? 0;
}

class _TimelineQuery {
  const _TimelineQuery(this.now);

  final DateTime now;

  List<TimelineEntry> entriesForDate(
    NodeTree tree,
    DateTime date, {
    bool includeOverdue = false,
  }) {
    final target = _startOfDay(date);
    final result = _openEntries(tree).where((entry) {
      final deadline = entry.node.deadline?.calendarDate;
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

  List<TimelineEntry> abandonedEntriesForDate(NodeTree tree, DateTime date) {
    final target = _startOfDay(date);
    final result =
        tree.nodes.values
            .where((node) {
              final abandonedAt = node.abandonedAt?.toLocal();
              return abandonedAt != null && _sameDate(abandonedAt, target);
            })
            .map((node) => _entryFor(tree, node))
            .toList()
          ..sort((a, b) => b.node.abandonedAt!.compareTo(a.node.abandonedAt!));
    return result;
  }

  List<TimelineEntry> laterEntries(NodeTree tree, DateTime after) {
    final boundary = _startOfDay(after).add(const Duration(days: 1));
    final result = _openEntries(tree).where((entry) {
      final deadline = entry.node.deadline?.calendarDate;
      return deadline == null || !deadline.isBefore(boundary);
    }).toList();
    _sortEntries(result);
    return result;
  }

  List<TimelineEntry> _openEntries(NodeTree tree) => tree.nodes.values
      .where((node) => tree.isLeaf(node.id) || node.deadline != null)
      .map((node) => _entryFor(tree, node))
      .where(
        (entry) =>
            !entry.isComplete && !tree.isEffectivelyAbandoned(entry.node.id),
      )
      .toList();

  TimelineEntry _entryFor(NodeTree tree, TodoNode node) => TimelineEntry(
    node: node,
    path: List<String>.unmodifiable(tree.pathFor(node.id)),
    isEvent: !tree.isLeaf(node.id),
    isComplete: tree.isComplete(node.id),
    completedAt: tree.effectiveCompletedAt(node.id),
  );

  List<TimelineTreeEntry> treeEntries(
    NodeTree tree,
    List<TimelineEntry> matches,
  ) {
    if (matches.isEmpty) return const <TimelineTreeEntry>[];
    final matchingIds = matches.map((entry) => entry.node.id).toSet();
    final includedIds = <String>{...matchingIds};
    final roots = <String>[];
    for (final match in matches) {
      var current = match.node;
      while (current.parentId != null) {
        includedIds.add(current.parentId!);
        current = tree.nodes[current.parentId!]!;
      }
      if (!roots.contains(current.id)) roots.add(current.id);
    }

    int matchingCount(String nodeId) =>
        (matchingIds.contains(nodeId) ? 1 : 0) +
        tree
            .descendantsOf(nodeId)
            .where((node) => matchingIds.contains(node.id))
            .length;

    final result = <TimelineTreeEntry>[];
    void append(String nodeId, List<String> ancestorIds) {
      if (!includedIds.contains(nodeId)) return;
      final node = tree.nodes[nodeId]!;
      result.add(
        TimelineTreeEntry(
          entry: _entryFor(tree, node),
          depth: ancestorIds.length,
          ancestorIds: List<String>.unmodifiable(ancestorIds),
          isContext: !matchingIds.contains(nodeId),
          matchingCount: matchingCount(nodeId),
        ),
      );
      for (final child in tree.childrenOf(nodeId)) {
        append(child.id, <String>[...ancestorIds, nodeId]);
      }
    }

    for (final rootId in roots) {
      append(rootId, const <String>[]);
    }
    return result;
  }

  void _sortEntries(List<TimelineEntry> entries, {DateTime? overdueBefore}) {
    entries.sort((a, b) {
      if (overdueBefore != null) {
        final aOverdue = a.node.deadline!.calendarDate.isBefore(overdueBefore);
        final bOverdue = b.node.deadline!.calendarDate.isBefore(overdueBefore);
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
