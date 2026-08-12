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

  AppView view = AppView.events;
  TimelineGroup timelineGroup = TimelineGroup.today;
  bool showCompleted = false;
  ThemeMode themeMode = ThemeMode.system;
  final Set<String> expandedIds = <String>{};

  List<TodoNode> get nodes => List<TodoNode>.unmodifiable(_nodes);
  NodeTree get tree => NodeTree(_nodes);
  bool get loading => _loading;
  Object? get error => _error;
  String? get selectedId => _selectedId;
  TodoNode? get selectedNode =>
      _selectedId == null ? null : tree.nodes[_selectedId];
  bool get canUndoDelete => _lastDeletion != null;
  DateTime get now => _now;

  List<TimelineEntry> get timelineEntries => TimelineQuery(
    _now,
  ).entries(tree, timelineGroup, showCompleted: showCompleted);

  void refreshTime() {
    final next = _clock();
    final dateChanged =
        next.year != _now.year ||
        next.month != _now.month ||
        next.day != _now.day;
    final timezoneChanged = next.timeZoneOffset != _now.timeZoneOffset;
    _now = next;
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
    notifyListeners();
  }

  void setView(AppView next) {
    view = next;
    notifyListeners();
  }

  void setTimelineGroup(TimelineGroup group) {
    timelineGroup = group;
    notifyListeners();
  }

  void setShowCompleted(bool value) {
    showCompleted = value;
    notifyListeners();
  }

  void toggleExpanded(String nodeId) {
    if (!expandedIds.add(nodeId)) expandedIds.remove(nodeId);
    notifyListeners();
  }

  void cycleTheme() {
    themeMode = switch (themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
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
    if (selectCreated) _selectedId = node.id;
    return node;
  });

  Future<void> updateTitle(String nodeId, String title) =>
      _write(() => service.updateTitle(nodeId, title));

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
}
