import 'package:flutter/material.dart';

import '../domain/node_service.dart';
import '../domain/node_tree.dart';
import '../domain/timeline.dart';
import '../domain/todo_node.dart';

enum AppView { events, timeline }

class AppController extends ChangeNotifier {
  AppController(this.service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _now = (clock ?? DateTime.now)();

  final NodeService service;
  final DateTime Function() _clock;
  DateTime _now;
  List<TodoNode> _nodes = const <TodoNode>[];
  String? _selectedId;
  bool _loading = true;
  Object? _error;
  DeletedSubtree? _lastDeletion;
  bool _eventDetailOpen = false;
  late DateTime _selectedTimelineDate = _startOfDay(_now);
  late DateTime _timelineWindowStart = _startOfWeek(_now);
  bool _timelineLaterSelected = false;
  bool _timelineWindowWasMoved = false;

  AppView view = AppView.events;
  final Set<String> expandedIds = <String>{};

  List<TodoNode> get nodes => List<TodoNode>.unmodifiable(_nodes);
  NodeTree get tree => NodeTree(_nodes);
  bool get loading => _loading;
  Object? get error => _error;
  String? get selectedId => _selectedId;
  TodoNode? get selectedNode =>
      _selectedId == null ? null : tree.nodes[_selectedId];
  bool get canUndoDelete => _lastDeletion != null;
  bool get eventDetailOpen => _eventDetailOpen;
  DateTime get now => _now;
  DateTime get selectedTimelineDate => _selectedTimelineDate;
  DateTime get timelineWindowStart => _timelineWindowStart;
  bool get timelineLaterSelected => _timelineLaterSelected;
  List<DateTime> get timelineDates => List<DateTime>.generate(
    6,
    (index) => _timelineWindowStart.add(Duration(days: index)),
  );
  List<TimelineEntry> get selectedDateEntries => _timelineLaterSelected
      ? TimelineQuery(_now).laterEntries(tree, timelineDates.last)
      : TimelineQuery(_now).entriesForDate(
          tree,
          _selectedTimelineDate,
          includeOverdue: _sameDate(_selectedTimelineDate, _now),
        );

  List<TimelineEntry> get selectedDateCompletedEntries => _timelineLaterSelected
      ? const <TimelineEntry>[]
      : TimelineQuery(
          _now,
        ).completedEntriesForDate(tree, _selectedTimelineDate);

  int timelineCount(DateTime date) =>
      TimelineQuery(_now).countForDate(tree, date);

  void refreshTime() {
    final next = _clock();
    final dateChanged =
        next.year != _now.year ||
        next.month != _now.month ||
        next.day != _now.day;
    final timezoneChanged = next.timeZoneOffset != _now.timeZoneOffset;
    _now = next;
    if (dateChanged && !_timelineWindowWasMoved) {
      _selectedTimelineDate = _startOfDay(next);
      _timelineWindowStart = _startOfWeek(next);
      _timelineLaterSelected = false;
    }
    if (dateChanged || timezoneChanged) notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _nodes = await service.loadNodes();
      _chooseSelection();
      _error = null;
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void select(String nodeId) {
    _selectedId = nodeId;
    _eventDetailOpen = true;
    notifyListeners();
  }

  void showEventOverview() {
    _eventDetailOpen = false;
    notifyListeners();
  }

  void setView(AppView next) {
    view = next;
    notifyListeners();
  }

  void selectTimelineDate(DateTime date) {
    _selectedTimelineDate = _startOfDay(date);
    _timelineLaterSelected = false;
    notifyListeners();
  }

  void selectTimelineLater() {
    _timelineLaterSelected = true;
    notifyListeners();
  }

  void shiftTimelineWindow(int weeks) {
    _timelineWindowStart = _timelineWindowStart.add(Duration(days: weeks * 7));
    _selectedTimelineDate = _timelineWindowStart;
    _timelineLaterSelected = false;
    _timelineWindowWasMoved = true;
    notifyListeners();
  }

  void resetTimelineToToday() {
    _selectedTimelineDate = _startOfDay(_now);
    _timelineWindowStart = _startOfWeek(_now);
    _timelineLaterSelected = false;
    _timelineWindowWasMoved = false;
    notifyListeners();
  }

  void toggleExpanded(String nodeId) {
    if (!expandedIds.add(nodeId)) expandedIds.remove(nodeId);
    notifyListeners();
  }

  Future<TodoNode?> create({
    String? parentId,
    required String title,
    DateTime? deadline,
    bool selectCreated = true,
  }) => _write(() async {
    final node = await service.createNode(
      parentId: parentId,
      title: title,
      deadline: deadline,
    );
    if (parentId != null) expandedIds.add(parentId);
    if (selectCreated) {
      _selectedId = node.id;
      _eventDetailOpen = true;
    }
    return node;
  });

  Future<void> updateTitle(String nodeId, String title) =>
      _write(() => service.updateTitle(nodeId, title));

  Future<void> updateNotes(String nodeId, String notes) =>
      _write(() => service.updateNotes(nodeId, notes));

  Future<void> updateDeadline(String nodeId, DateTime? deadline) =>
      _write(() => service.updateDeadline(nodeId, deadline));

  Future<void> setCompleted(String nodeId, bool completed) =>
      _write(() => service.setLeafCompleted(nodeId, completed));

  Future<void> delete(String nodeId) => _write(() async {
    _lastDeletion = await service.deleteSubtree(nodeId);
    if (_selectedId == nodeId ||
        _lastDeletion!.nodes.any((node) => node.id == _selectedId)) {
      _selectedId = null;
    }
  });

  Future<void> undoDelete() => _write(() async {
    final deletion = _lastDeletion;
    if (deletion == null) return;
    await service.restoreSubtree(deletion);
    _selectedId = deletion.nodes.first.id;
    _lastDeletion = null;
  });

  Future<void> move({
    required String nodeId,
    String? newParentId,
    int? newIndex,
  }) => _write(
    () => service.moveNode(
      nodeId: nodeId,
      newParentId: newParentId,
      newIndex: newIndex,
    ),
  );

  Future<void> reorderChildren(String? parentId, List<String> ids) =>
      _write(() => service.reorderChildren(parentId, ids));

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<T?> _write<T>(Future<T> Function() operation) async {
    try {
      final result = await operation();
      _nodes = await service.loadNodes();
      _chooseSelection();
      _error = null;
      notifyListeners();
      return result;
    } catch (error) {
      _error = error;
      notifyListeners();
      return null;
    }
  }

  void _chooseSelection() {
    final currentStillExists =
        _selectedId != null && _nodes.any((node) => node.id == _selectedId);
    if (currentStillExists) return;
    final roots = NodeTree(_nodes).childrenOf(null);
    _selectedId = roots.isEmpty ? null : roots.first.id;
    if (_selectedId != null) expandedIds.add(_selectedId!);
  }

  @override
  void dispose() {
    service.repository.close();
    super.dispose();
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime _startOfWeek(DateTime date) =>
      _startOfDay(date).subtract(Duration(days: date.weekday - 1));

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
