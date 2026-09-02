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

class DeletedSubtree {
  const DeletedSubtree(this.nodes);

  final List<TodoNode> nodes;
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
      deadline: deadline,
      createdAt: now,
      updatedAt: now,
      manualOrder: order,
    );
    final changes = <TodoNode>[node];
    final parent = parentId == null ? null : currentTree.nodes[parentId];
    if (parent?.completedAt != null && currentTree.isLeaf(parent!.id)) {
      changes.insert(
        0,
        parent.copyWith(clearCompletedAt: true, updatedAt: now),
      );
    }
    return _NodeMutation<TodoNode>(node, changes);
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
  ) => _updateNode(
    nodeId,
    (node, now) => node.copyWith(
      deadline: deadline,
      clearDeadline: deadline == null,
      updatedAt: now,
    ),
  );

  Future<NodeWriteResult<void>> setLeafCompleted(
    String nodeId,
    bool completed,
  ) => _write(() {
    final currentTree = tree;
    final node = currentTree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    if (!currentTree.isLeaf(nodeId)) {
      throw const NodeRuleException('事件状态由子任务自动汇总');
    }
    final now = _clock().toUtc();
    return _NodeMutation<void>(null, <TodoNode>[
      node.copyWith(
        completedAt: completed ? now : null,
        clearCompletedAt: !completed,
        updatedAt: now,
      ),
    ]);
  });

  Future<NodeWriteResult<DeletedSubtree>> deleteSubtree(String nodeId) =>
      _write(() {
        final currentTree = tree;
        final node = currentTree.nodes[nodeId];
        if (node == null) throw const NodeRuleException('任务不存在');
        final now = _clock().toUtc();
        final subtree = <TodoNode>[node, ...currentTree.descendantsOf(nodeId)];
        return _NodeMutation<DeletedSubtree>(
          DeletedSubtree(List<TodoNode>.unmodifiable(subtree)),
          <TodoNode>[
            for (final item in subtree)
              item.copyWith(deletedAt: now, updatedAt: now),
          ],
        );
      });

  Future<NodeWriteResult<void>> restoreSubtree(DeletedSubtree deletion) =>
      _write(() {
        final now = _clock().toUtc();
        return _NodeMutation<void>(null, <TodoNode>[
          for (final node in deletion.nodes)
            node.copyWith(clearDeletedAt: true, updatedAt: now),
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
    if (siblings.length != orderedIds.length ||
        siblings
            .map((node) => node.id)
            .toSet()
            .difference(orderedIds.toSet())
            .isNotEmpty) {
      throw const NodeRuleException('排序列表与当前节点不一致');
    }
    final now = _clock().toUtc();
    return _NodeMutation<void>(null, <TodoNode>[
      for (var index = 0; index < orderedIds.length; index++)
        currentTree.nodes[orderedIds[index]]!.copyWith(
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
      _nodes = _sorted(await _repository.loadNodes());
      _loaded = true;
      return nodes;
    } finally {
      if (!_loaded) _loadFuture = null;
    }
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
