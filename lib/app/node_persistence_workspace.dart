import 'dart:async';
import 'dart:collection';

import 'package:uuid/uuid.dart';

import '../domain/deadline.dart';
import '../domain/node_repository.dart';
import '../domain/node_tree.dart';
import '../domain/todo_node.dart';
import 'node_write_result.dart';

typedef Clock = DateTime Function();

class NodeRuleException implements Exception {
  const NodeRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NodePersistenceWorkspace {
  NodePersistenceWorkspace(
    this._repository, {
    Clock? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? const Uuid().v4;

  final NodeRepository _repository;
  final Clock _clock;
  final String Function() _idGenerator;
  final Queue<_QueuedWrite> _pendingWrites = Queue<_QueuedWrite>();
  Future<List<TodoNode>>? _loadFuture;
  Future<void>? _closeFuture;
  Completer<void>? _idleCompleter;
  List<TodoNode> _nodes = const <TodoNode>[];
  bool _loaded = false;
  bool _acceptingWrites = true;
  bool _writeInProgress = false;

  List<TodoNode> get nodes => List<TodoNode>.unmodifiable(_nodes);
  NodeTree get tree => NodeTree(_nodes);

  Future<List<TodoNode>> load() {
    if (!_acceptingWrites) {
      return Future<List<TodoNode>>.error(StateError('节点持久化工作区已关闭'));
    }
    if (_loaded) return Future<List<TodoNode>>.value(nodes);
    return _loadFuture ??= _loadNodes();
  }

  Future<NodeWriteResult<TodoNode>> createNode({
    String? parentId,
    required String title,
    Deadline? deadline,
  }) => _write(() {
    final cleanTitle = _validatedTitle(title);
    final currentTree = tree;
    if (parentId != null && !currentTree.nodes.containsKey(parentId)) {
      throw const NodeRuleException('父事件不存在');
    }
    final parent = parentId == null ? null : currentTree.nodes[parentId];

    final id = _idGenerator();
    if (currentTree.nodes.containsKey(id)) {
      throw StateError('节点标识已存在');
    }
    final now = _clock().toUtc();
    final siblings = currentTree.childrenOf(parentId);
    final order = siblings.isEmpty
        ? 1000
        : siblings
                  .map((node) => node.manualOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1000;
    final node = TodoNode(
      id: id,
      parentId: parentId,
      title: cleanTitle,
      deadline: deadline ?? parent?.deadline,
      createdAt: now,
      updatedAt: now,
      manualOrder: order,
      eventHue: parentId == null ? _nextEventHue(_nodes) : null,
    );
    final changes = <TodoNode>[node];
    if (parent?.completedAt != null && currentTree.isLeaf(parent!.id)) {
      changes.insert(
        0,
        parent.copyWith(clearCompletedAt: true, updatedAt: now),
      );
    }
    return _NodeMutation<TodoNode>(node, changes);
  });

  Future<NodeWriteResult<TodoNode>> createScheduledTask({
    required String title,
    required String eventName,
    String? eventId,
    required DateTime start,
    required DateTime end,
  }) => _write(() {
    final cleanTitle = _validatedTitle(title);
    final cleanEventName = eventName.trim();
    if (cleanEventName.isEmpty) throw const NodeRuleException('请选择或输入所属事件');
    if (!end.isAfter(start)) throw const NodeRuleException('结束时间必须晚于开始时间');
    final currentTree = tree;
    TodoNode? event;
    if (eventId != null) {
      event = currentTree.nodes[eventId];
      if (event == null || event.parentId != null) {
        throw const NodeRuleException('所属事件不存在，请重新选择');
      }
    } else {
      final matches = currentTree
          .childrenOf(null)
          .where((node) => node.title == cleanEventName)
          .toList();
      if (matches.length > 1) throw const NodeRuleException('存在同名事件，请从列表中选择');
      event = matches.isEmpty ? null : matches.single;
    }
    if (event != null && (event.isAbandoned || event.isEventArchived)) {
      throw const NodeRuleException('该事件已归档或放弃，请先恢复');
    }
    final now = _clock().toUtc();
    int nextOrder(String? parentId) =>
        currentTree
            .childrenOf(parentId)
            .fold<int>(
              0,
              (order, node) =>
                  node.manualOrder > order ? node.manualOrder : order,
            ) +
        1000;
    String nextId() {
      final id = _idGenerator();
      if (currentTree.nodes.containsKey(id) || event?.id == id) {
        throw StateError('节点标识已存在');
      }
      return id;
    }

    final changes = <TodoNode>[];
    if (event == null) {
      event = TodoNode(
        id: nextId(),
        title: cleanEventName,
        createdAt: now,
        updatedAt: now,
        manualOrder: nextOrder(null),
        eventHue: _nextEventHue(_nodes),
      );
      changes.add(event);
    } else if (event.completedAt != null && currentTree.isLeaf(event.id)) {
      changes.add(event.copyWith(clearCompletedAt: true, updatedAt: now));
    }
    final task = TodoNode(
      id: nextId(),
      parentId: event.id,
      title: cleanTitle,
      deadline: TimedDeadline(end),
      scheduledStart: start.toUtc(),
      createdAt: now,
      updatedAt: now,
      manualOrder: nextOrder(event.id),
    );
    changes.add(task);
    return _NodeMutation(task, changes);
  });

  Future<NodeWriteResult<void>> updateTitle(String nodeId, String title) =>
      _updateNode(
        nodeId,
        (node, now) =>
            node.copyWith(title: _validatedTitle(title), updatedAt: now),
      );

  Future<NodeWriteResult<void>> updateNotes(String nodeId, String notes) =>
      _updateNode(
        nodeId,
        (node, now) => node.copyWith(notes: notes, updatedAt: now),
      );

  Future<NodeWriteResult<void>> updateDeadline(
    String nodeId,
    Deadline? deadline,
  ) => _write(() {
    final currentTree = tree;
    final node = currentTree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    final now = _clock().toUtc();
    final updated = _withDeadline(node, deadline, now);
    final changes = <TodoNode>[updated];

    void updateChildren(TodoNode previousParent, TodoNode parent) {
      final parentDeadline = parent.deadline;
      final tightened =
          parentDeadline != null &&
          (previousParent.deadline == null ||
              parentDeadline.compareTo(previousParent.deadline!) < 0);
      final extended =
          parentDeadline != null &&
          previousParent.deadline != null &&
          parentDeadline.compareTo(previousParent.deadline!) > 0;
      for (final child in currentTree.childrenOf(parent.id)) {
        if (currentTree.isComplete(child.id)) continue;
        var updatedChild = child;
        final inherits = child.deadline == null;
        final followsParent =
            (extended || parentDeadline == null) &&
            previousParent.deadline != null &&
            child.deadline?.storage.date ==
                previousParent.deadline?.storage.date &&
            child.deadline?.storage.instantMilliseconds ==
                previousParent.deadline?.storage.instantMilliseconds;
        if (inherits ||
            followsParent ||
            (tightened && child.deadline!.compareTo(parentDeadline) > 0)) {
          if (child.deadline?.storage.date != parentDeadline?.storage.date ||
              child.deadline?.storage.instantMilliseconds !=
                  parentDeadline?.storage.instantMilliseconds) {
            updatedChild = _withDeadline(child, parentDeadline, now);
            changes.add(updatedChild);
          }
        }
        updateChildren(child, updatedChild);
      }
    }

    updateChildren(node, updated);
    return _NodeMutation<void>(null, changes);
  });

  static TodoNode _withDeadline(
    TodoNode node,
    Deadline? deadline,
    DateTime now,
  ) {
    final previous = node.deadline;
    final start = node.scheduledStart;
    final shiftedStart =
        start != null && previous is TimedDeadline && deadline is TimedDeadline
        ? start.add(deadline.localTime.difference(previous.localTime))
        : null;
    return node.copyWith(
      deadline: deadline,
      clearDeadline: deadline == null,
      scheduledStart: shiftedStart,
      clearScheduledStart: shiftedStart == null,
      updatedAt: now,
    );
  }

  Future<NodeWriteResult<void>> setNodeStatus(
    String nodeId,
    TodoNodeStatus status,
  ) => _write(() {
    final currentTree = tree;
    final node = currentTree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    if (status == TodoNodeStatus.completed && !currentTree.isLeaf(nodeId)) {
      throw const NodeRuleException('事件状态由子任务自动汇总');
    }
    final now = _clock().toUtc();
    return _NodeMutation<void>(null, <TodoNode>[
      node.copyWith(
        completedAt: status == TodoNodeStatus.completed ? now : null,
        clearCompletedAt: status != TodoNodeStatus.completed,
        abandonedAt: status == TodoNodeStatus.abandoned ? now : null,
        clearAbandonedAt: status != TodoNodeStatus.abandoned,
        isArchived: false,
        updatedAt: now,
      ),
    ]);
  });

  Future<NodeWriteResult<void>> setEventArchived(
    String eventId,
    bool archived,
  ) => _updateNode(eventId, (node, now) {
    if (node.parentId != null) {
      throw const NodeRuleException('只能归档事件卡片');
    }
    return node.copyWith(isEventArchived: archived, updatedAt: now);
  });

  Future<NodeWriteResult<void>> setTaskArchived(String nodeId, bool archived) =>
      _updateNode(nodeId, (node, now) {
        if (archived && !tree.isComplete(nodeId)) {
          throw const NodeRuleException('只能收起已完成的任务');
        }
        return node.copyWith(isArchived: archived, updatedAt: now);
      });

  Future<NodeWriteResult<void>> archiveCompletedTasks(String eventId) =>
      _write(() {
        final currentTree = tree;
        final now = _clock().toUtc();
        final tasks = currentTree.archivableCompletedTasks(eventId).toList();
        return _NodeMutation<void>(
          null,
          tasks
              .map((node) => node.copyWith(isArchived: true, updatedAt: now))
              .toList(),
        );
      });

  Future<NodeWriteResult<void>> deleteSubtree(String nodeId) => _write(() {
    final currentTree = tree;
    final node = currentTree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    final now = _clock().toUtc();
    final subtree = <TodoNode>[node, ...currentTree.descendantsOf(nodeId)];
    return _NodeMutation<void>(null, <TodoNode>[
      for (final item in subtree) item.copyWith(deletedAt: now, updatedAt: now),
    ]);
  });

  Future<NodeWriteResult<void>> moveNode({
    required String nodeId,
    required String? newParentId,
    int? newIndex,
  }) => _write(() {
    final currentTree = tree;
    final node = currentTree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    if (newParentId == nodeId ||
        (newParentId != null &&
            currentTree.isDescendant(
              nodeId: newParentId,
              ancestorId: nodeId,
            ))) {
      throw const NodeRuleException('不能移动到自身或子事件下');
    }
    if (newParentId != null && !currentTree.nodes.containsKey(newParentId)) {
      throw const NodeRuleException('目标事件不存在');
    }

    final target = currentTree
        .childrenOf(newParentId)
        .where((item) => item.id != nodeId)
        .toList();
    final index = (newIndex ?? target.length).clamp(0, target.length);
    target.insert(index, node);
    final now = _clock().toUtc();
    final changes = <TodoNode>[
      for (var index = 0; index < target.length; index++)
        target[index].copyWith(
          parentId: newParentId,
          clearParentId: newParentId == null,
          eventHue: newParentId == null && target[index].eventHue == null
              ? _nextEventHue(_nodes)
              : target[index].eventHue,
          manualOrder: (index + 1) * 1000,
          updatedAt: now,
        ),
    ];
    final newParent = newParentId == null
        ? null
        : currentTree.nodes[newParentId];
    if (newParent?.completedAt != null && currentTree.isLeaf(newParent!.id)) {
      changes.add(newParent.copyWith(clearCompletedAt: true, updatedAt: now));
    }
    return _NodeMutation<void>(null, changes);
  });

  Future<NodeWriteResult<void>> reorderChildren(
    String? parentId,
    List<String> orderedIds,
  ) => _write(() {
    final currentTree = tree;
    final siblings = currentTree.childrenOf(parentId);
    final siblingIds = siblings.map((node) => node.id).toSet();
    if (orderedIds.toSet().length != orderedIds.length ||
        orderedIds.any((id) => !siblingIds.contains(id))) {
      throw const NodeRuleException('排序列表与当前节点不一致');
    }
    final completeOrder = <String>[
      ...orderedIds,
      ...siblings
          .map((node) => node.id)
          .where((id) => !orderedIds.contains(id)),
    ];
    final now = _clock().toUtc();
    return _NodeMutation<void>(null, <TodoNode>[
      for (var index = 0; index < completeOrder.length; index++)
        currentTree.nodes[completeOrder[index]]!.copyWith(
          manualOrder: (index + 1) * 1000,
          updatedAt: now,
        ),
    ]);
  });

  Future<void> close() => _closeFuture ??= _close();

  Future<NodeWriteResult<void>> _updateNode(
    String nodeId,
    TodoNode Function(TodoNode node, DateTime now) update,
  ) => _write(() {
    final node = tree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    return _NodeMutation<void>(null, <TodoNode>[
      update(node, _clock().toUtc()),
    ]);
  });

  Future<NodeWriteResult<T>> _write<T>(
    _NodeMutation<T> Function() createMutation,
  ) {
    if (!_acceptingWrites) {
      return Future<NodeWriteResult<T>>.value(
        NodeWriteFailure<T>(StateError('节点持久化工作区已关闭'), nodes),
      );
    }
    final result = Completer<NodeWriteResult<T>>();
    _pendingWrites.add(_PendingWrite<T>(createMutation, result));
    _idleCompleter ??= Completer<void>();
    _drainWrites();
    return result.future;
  }

  void _drainWrites() {
    if (_writeInProgress) return;
    if (_pendingWrites.isEmpty) {
      _idleCompleter?.complete();
      _idleCompleter = null;
      return;
    }
    _writeInProgress = true;
    final pending = _pendingWrites.removeFirst();
    unawaited(_executeQueued(pending));
  }

  Future<void> _executeQueued(_QueuedWrite pending) async {
    try {
      await pending.execute(this);
    } finally {
      _writeInProgress = false;
      _drainWrites();
    }
  }

  Future<void> _execute<T>(_PendingWrite<T> pending) async {
    try {
      if (!_loaded) throw StateError('节点持久化工作区尚未加载');
      final mutation = pending.createMutation();
      final nextNodes = _apply(mutation.changes);
      await _repository.saveNodesAtomically(mutation.changes);
      _nodes = nextNodes;
      pending.result.complete(NodeWriteSuccess<T>(mutation.value, nodes));
    } catch (error) {
      pending.result.complete(NodeWriteFailure<T>(error, nodes));
    }
  }

  List<TodoNode> _apply(List<TodoNode> changes) {
    final next = <String, TodoNode>{for (final node in _nodes) node.id: node};
    for (final node in changes) {
      if (node.deletedAt == null) {
        next[node.id] = node;
      } else {
        next.remove(node.id);
      }
    }
    return _sorted(next.values);
  }

  Future<void> _close() async {
    _acceptingWrites = false;
    try {
      await _loadFuture;
    } catch (_) {
      // Loading errors belong to the load caller; closing still owns cleanup.
    }
    await (_idleCompleter?.future ?? Future<void>.value());
    await _repository.close();
  }

  Future<List<TodoNode>> _loadNodes() async {
    try {
      final loaded = _sorted(await _repository.loadNodes()).toList();
      final changes = <TodoNode>[];
      for (var i = 0; i < loaded.length; i++) {
        final node = loaded[i];
        if (node.parentId == null && node.eventHue == null) {
          loaded[i] = node.copyWith(eventHue: _nextEventHue(loaded));
          changes.add(loaded[i]);
        }
      }
      if (changes.isNotEmpty) await _repository.saveNodesAtomically(changes);
      _nodes = loaded;
      _loaded = true;
      return nodes;
    } finally {
      if (!_loaded) _loadFuture = null;
    }
  }

  // Fill the largest unused hue interval without recoloring existing events.
  static double _nextEventHue(Iterable<TodoNode> nodes) {
    final hues =
        nodes
            .where((node) => node.parentId == null)
            .map((node) => node.eventHue)
            .whereType<double>()
            .toList()
          ..sort();
    if (hues.isEmpty) return 20;
    var largestGap = -1.0;
    var hue = 20.0;
    for (var i = 0; i < hues.length; i++) {
      final end = i + 1 < hues.length ? hues[i + 1] : hues.first + 360;
      final gap = end - hues[i];
      if (gap > largestGap) {
        largestGap = gap;
        hue = (hues[i] + gap / 2) % 360;
      }
    }
    return hue;
  }

  static List<TodoNode> _sorted(Iterable<TodoNode> nodes) {
    final sorted = List<TodoNode>.of(nodes)
      ..sort((left, right) {
        final byCreation = left.createdAt.compareTo(right.createdAt);
        return byCreation != 0 ? byCreation : left.id.compareTo(right.id);
      });
    return List<TodoNode>.unmodifiable(sorted);
  }

  static String _validatedTitle(String title) {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw const NodeRuleException('标题不能为空');
    return cleanTitle;
  }
}

class _NodeMutation<T> {
  const _NodeMutation(this.value, this.changes);

  final T value;
  final List<TodoNode> changes;
}

abstract interface class _QueuedWrite {
  Future<void> execute(NodePersistenceWorkspace workspace);
}

class _PendingWrite<T> implements _QueuedWrite {
  const _PendingWrite(this.createMutation, this.result);

  final _NodeMutation<T> Function() createMutation;
  final Completer<NodeWriteResult<T>> result;

  @override
  Future<void> execute(NodePersistenceWorkspace workspace) =>
      workspace._execute(this);
}
