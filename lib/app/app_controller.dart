import 'package:flutter/material.dart';

import '../domain/deadline.dart';
import '../domain/node_service.dart';
import '../domain/node_tree.dart';
import '../domain/timeline.dart';
import '../domain/todo_node.dart';
import 'node_write_result.dart';

enum AppView { events, timeline }

class AppController extends ChangeNotifier {
  AppController(this.service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _timeline = TimelineExperience(_clock());
    _writer = NodeWriter(service);
  }

  final NodeService service;
  final DateTime Function() _clock;
  late final TimelineExperience _timeline;
  late final NodeWriter _writer;
  List<TodoNode> _nodes = const <TodoNode>[];
  String? _selectedId;
  bool _loading = true;
  Object? _error;
  DeletedSubtree? _lastDeletion;
  bool _eventDetailOpen = false;

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
  TimelineProjection get timelineProjection => _timeline.project(tree);
  DateTime get now => _timeline.now;

  void refreshTime() {
    if (_timeline.refresh(_clock())) notifyListeners();
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
    _timeline.selectDate(date);
    notifyListeners();
  }

  void selectTimelineLater() {
    _timeline.selectLater();
    notifyListeners();
  }

  void moveTimelineSelection(int direction) {
    _timeline.moveSelection(direction);
    notifyListeners();
  }

  void shiftTimelineWindow(int weeks) {
    _timeline.shiftWindow(weeks);
    notifyListeners();
  }

  void resetTimelineToToday() {
    _timeline.resetToToday();
    notifyListeners();
  }

  void toggleExpanded(String nodeId) {
    if (!expandedIds.add(nodeId)) expandedIds.remove(nodeId);
    notifyListeners();
  }

  Future<NodeWriteResult<TodoNode>> create({
    String? parentId,
    required String title,
    Deadline? deadline,
    bool selectCreated = true,
  }) => _write(
    () => service.createNode(
      parentId: parentId,
      title: title,
      deadline: deadline,
    ),
    onSuccess: (node) {
      if (parentId != null) expandedIds.add(parentId);
      if (selectCreated) {
        _selectedId = node.id;
        _eventDetailOpen = true;
      }
    },
  );

  Future<NodeWriteResult<void>> updateTitle(String nodeId, String title) =>
      _write(() => service.updateTitle(nodeId, title));

  Future<NodeWriteResult<void>> updateNotes(String nodeId, String notes) =>
      _write(() => service.updateNotes(nodeId, notes));

  Future<NodeWriteResult<void>> updateDeadline(
    String nodeId,
    Deadline? deadline,
  ) => _write(() => service.updateDeadline(nodeId, deadline));

  Future<NodeWriteResult<void>> setCompleted(String nodeId, bool completed) =>
      _write(() => service.setLeafCompleted(nodeId, completed));

  Future<NodeWriteResult<DeletedSubtree>> delete(String nodeId) => _write(
    () => service.deleteSubtree(nodeId),
    onSuccess: (deletion) {
      _lastDeletion = deletion;
      if (_selectedId == nodeId ||
          deletion.nodes.any((node) => node.id == _selectedId)) {
        _selectedId = null;
      }
    },
  );

  Future<NodeWriteResult<void>> undoDelete() => _write(
    () async {
      final deletion = _lastDeletion;
      if (deletion == null) return;
      await service.restoreSubtree(deletion);
    },
    onSuccess: (_) {
      final deletion = _lastDeletion;
      if (deletion == null) return;
      _selectedId = deletion.nodes.first.id;
      _lastDeletion = null;
    },
  );

  Future<NodeWriteResult<void>> move({
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

  Future<NodeWriteResult<void>> reorderChildren(
    String? parentId,
    List<String> ids,
  ) => _write(() => service.reorderChildren(parentId, ids));

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<NodeWriteResult<T>> _write<T>(
    Future<T> Function() operation, {
    void Function(T value)? onSuccess,
  }) async {
    final result = await _writer.execute(operation, (value, nodes) {
      _nodes = nodes;
      onSuccess?.call(value);
      _chooseSelection();
    });
    switch (result) {
      case NodeWriteSuccess<T>():
        _error = null;
      case NodeWriteFailure<T>(:final error):
        _error = error;
    }
    notifyListeners();
    return result;
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
