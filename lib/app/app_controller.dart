import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/deadline.dart';
import '../domain/node_tree.dart';
import '../domain/timeline.dart';
import '../domain/todo_node.dart';
import 'node_persistence_workspace.dart';
import 'node_write_result.dart';

enum AppView { events, timeline }

class AppController extends ChangeNotifier {
  AppController(this._workspace, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _timeline = TimelineExperience(_clock());
  }

  final NodePersistenceWorkspace _workspace;
  final DateTime Function() _clock;
  late final TimelineExperience _timeline;
  String? _selectedId;
  bool _loading = true;
  Object? _error;
  DeletedSubtree? _lastDeletion;
  bool _eventDetailOpen = false;
  bool _disposed = false;

  AppView view = AppView.events;
  final Set<String> expandedIds = <String>{};

  List<TodoNode> get nodes => _workspace.nodes;
  NodeTree get tree => _workspace.tree;
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
      await _workspace.load();
      if (_disposed) return;
      _chooseSelection();
      _error = null;
    } catch (error) {
      if (!_disposed) _error = error;
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
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
    _workspace.createNode(parentId: parentId, title: title, deadline: deadline),
    onSuccess: (node) {
      if (parentId != null) expandedIds.add(parentId);
      if (selectCreated) {
        _selectedId = node.id;
        _eventDetailOpen = true;
      }
    },
  );

  Future<NodeWriteResult<void>> updateTitle(String nodeId, String title) =>
      _write(_workspace.updateTitle(nodeId, title));

  Future<NodeWriteResult<void>> updateNotes(String nodeId, String notes) =>
      _write(_workspace.updateNotes(nodeId, notes));

  Future<NodeWriteResult<void>> updateDeadline(
    String nodeId,
    Deadline? deadline,
  ) => _write(_workspace.updateDeadline(nodeId, deadline));

  Future<NodeWriteResult<void>> setTaskStatus(
    String nodeId,
    TodoNodeStatus status,
  ) => _write(_workspace.setNodeStatus(nodeId, status));

  Future<NodeWriteResult<DeletedSubtree>> delete(String nodeId) => _write(
    _workspace.deleteSubtree(nodeId),
    onSuccess: (deletion) {
      _lastDeletion = deletion;
      if (_selectedId == nodeId ||
          deletion.nodes.any((node) => node.id == _selectedId)) {
        _selectedId = null;
      }
    },
  );

  Future<NodeWriteResult<void>> undoDelete() {
    final deletion = _lastDeletion;
    if (deletion == null) {
      return Future<NodeWriteResult<void>>.value(
        NodeWriteSuccess<void>(null, _workspace.nodes),
      );
    }
    return _write(
      _workspace.restoreSubtree(deletion),
      onSuccess: (_) {
        _selectedId = deletion.nodes.first.id;
        _lastDeletion = null;
      },
    );
  }

  Future<NodeWriteResult<void>> move({
    required String nodeId,
    String? newParentId,
    int? newIndex,
  }) => _write(
    _workspace.moveNode(
      nodeId: nodeId,
      newParentId: newParentId,
      newIndex: newIndex,
    ),
  );

  Future<NodeWriteResult<void>> reorderChildren(
    String? parentId,
    List<String> ids,
  ) => _write(_workspace.reorderChildren(parentId, ids));

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<NodeWriteResult<T>> _write<T>(
    Future<NodeWriteResult<T>> operation, {
    void Function(T value)? onSuccess,
  }) async {
    final result = await operation;
    if (_disposed) return result;
    switch (result) {
      case NodeWriteSuccess<T>(:final value):
        onSuccess?.call(value);
        _chooseSelection();
        _error = null;
      case NodeWriteFailure<T>(:final error):
        _error = error;
    }
    notifyListeners();
    return result;
  }

  void _chooseSelection() {
    final currentStillExists =
        _selectedId != null && nodes.any((node) => node.id == _selectedId);
    if (currentStillExists) return;
    final roots = tree.childrenOf(null);
    _selectedId = roots.isEmpty ? null : roots.first.id;
    if (_selectedId != null) expandedIds.add(_selectedId!);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_workspace.close());
    super.dispose();
  }
}
