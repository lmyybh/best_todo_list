import 'package:uuid/uuid.dart';

import 'node_repository.dart';
import 'node_tree.dart';
import 'todo_node.dart';

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

class NodeService {
  NodeService(this.repository, {Clock? clock, String Function()? idGenerator})
    : clock = clock ?? DateTime.now,
      idGenerator = idGenerator ?? const Uuid().v4;

  final NodeRepository repository;
  final Clock clock;
  final String Function() idGenerator;

  Future<List<TodoNode>> loadNodes() => repository.loadNodes();

  Future<TodoNode> createNode({
    String? parentId,
    required String title,
    DateTime? deadline,
    bool deadlineHasTime = true,
  }) async {
    final cleanTitle = _validatedTitle(title);
    final nodes = await repository.loadNodes();
    final tree = NodeTree(nodes);
    if (parentId != null && !tree.nodes.containsKey(parentId)) {
      throw const NodeRuleException('父事件不存在');
    }

    final now = clock().toUtc();
    final siblings = tree.childrenOf(parentId);
    final order = siblings.isEmpty
        ? 1000
        : siblings
                  .map((node) => node.manualOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1000;
    final node = TodoNode(
      id: idGenerator(),
      parentId: parentId,
      title: cleanTitle,
      deadline: deadline?.toUtc(),
      deadlineHasTime: deadline != null && deadlineHasTime,
      createdAt: now,
      updatedAt: now,
      manualOrder: order,
    );

    final parent = parentId == null ? null : tree.nodes[parentId];
    if (parent?.completedAt != null && tree.isLeaf(parent!.id)) {
      await repository.updateNodes(<TodoNode>[
        parent.copyWith(clearCompletedAt: true, updatedAt: now),
        node,
      ]);
    } else {
      await repository.insertNode(node);
    }
    return node;
  }

  Future<void> updateTitle(String nodeId, String title) async {
    final node = await _requireNode(nodeId);
    await repository.updateNode(
      node.copyWith(title: _validatedTitle(title), updatedAt: clock().toUtc()),
    );
  }

  Future<void> updateNotes(String nodeId, String notes) async {
    final node = await _requireNode(nodeId);
    await repository.updateNode(
      node.copyWith(notes: notes, updatedAt: clock().toUtc()),
    );
  }

  Future<void> updateDeadline(
    String nodeId,
    DateTime? deadline, {
    bool hasTime = true,
  }) async {
    final node = await _requireNode(nodeId);
    await repository.updateNode(
      node.copyWith(
        deadline: deadline?.toUtc(),
        deadlineHasTime: deadline != null && hasTime,
        clearDeadline: deadline == null,
        updatedAt: clock().toUtc(),
      ),
    );
  }

  Future<void> setLeafCompleted(String nodeId, bool completed) async {
    final nodes = await repository.loadNodes();
    final tree = NodeTree(nodes);
    final node = tree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    if (!tree.isLeaf(nodeId)) throw const NodeRuleException('事件状态由子任务自动汇总');
    await repository.updateNode(
      node.copyWith(
        completedAt: completed ? clock().toUtc() : null,
        clearCompletedAt: !completed,
        updatedAt: clock().toUtc(),
      ),
    );
  }

  Future<DeletedSubtree> deleteSubtree(String nodeId) async {
    final nodes = await repository.loadNodes();
    final tree = NodeTree(nodes);
    final node = tree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    final now = clock().toUtc();
    final subtree = <TodoNode>[node, ...tree.descendantsOf(nodeId)];
    await repository.updateNodes(
      subtree
          .map((item) => item.copyWith(deletedAt: now, updatedAt: now))
          .toList(),
    );
    return DeletedSubtree(subtree);
  }

  Future<void> restoreSubtree(DeletedSubtree deletion) async {
    final now = clock().toUtc();
    await repository.updateNodes(
      deletion.nodes
          .map((node) => node.copyWith(clearDeletedAt: true, updatedAt: now))
          .toList(),
    );
  }

  Future<void> moveNode({
    required String nodeId,
    required String? newParentId,
    int? newIndex,
  }) async {
    final nodes = await repository.loadNodes();
    final tree = NodeTree(nodes);
    final node = tree.nodes[nodeId];
    if (node == null) throw const NodeRuleException('任务不存在');
    if (tree.isComplete(nodeId)) throw const NodeRuleException('请先取消完成，再移动任务');
    if (newParentId == nodeId ||
        (newParentId != null &&
            tree.isDescendant(nodeId: newParentId, ancestorId: nodeId))) {
      throw const NodeRuleException('不能移动到自身或子事件下');
    }
    if (newParentId != null && !tree.nodes.containsKey(newParentId)) {
      throw const NodeRuleException('目标事件不存在');
    }

    final target = tree
        .childrenOf(newParentId)
        .where((item) => item.id != nodeId)
        .toList();
    final index = (newIndex ?? target.length).clamp(0, target.length);
    target.insert(index, node);
    final now = clock().toUtc();
    final updates = <TodoNode>[];
    for (var i = 0; i < target.length; i++) {
      final item = target[i];
      updates.add(
        item.copyWith(
          parentId: newParentId,
          clearParentId: newParentId == null,
          manualOrder: (i + 1) * 1000,
          updatedAt: now,
        ),
      );
    }
    final newParent = newParentId == null ? null : tree.nodes[newParentId];
    if (newParent?.completedAt != null && tree.isLeaf(newParent!.id)) {
      updates.add(newParent.copyWith(clearCompletedAt: true, updatedAt: now));
    }
    await repository.updateNodes(updates);
  }

  Future<void> reorderChildren(
    String? parentId,
    List<String> orderedIds,
  ) async {
    final nodes = await repository.loadNodes();
    final tree = NodeTree(nodes);
    final siblings = tree.childrenOf(parentId);
    if (siblings.length != orderedIds.length ||
        siblings
            .map((node) => node.id)
            .toSet()
            .difference(orderedIds.toSet())
            .isNotEmpty) {
      throw const NodeRuleException('排序列表与当前节点不一致');
    }
    final now = clock().toUtc();
    await repository.updateNodes(<TodoNode>[
      for (var i = 0; i < orderedIds.length; i++)
        tree.nodes[orderedIds[i]]!.copyWith(
          manualOrder: (i + 1) * 1000,
          updatedAt: now,
        ),
    ]);
  }

  Future<TodoNode> _requireNode(String nodeId) async {
    final nodes = await repository.loadNodes();
    final node = nodes.where((item) => item.id == nodeId).firstOrNull;
    if (node == null) throw const NodeRuleException('任务不存在');
    return node;
  }

  static String _validatedTitle(String title) {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) throw const NodeRuleException('标题不能为空');
    return cleanTitle;
  }
}
