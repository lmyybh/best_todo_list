import 'todo_node.dart';

class NodeTree {
  NodeTree(Iterable<TodoNode> nodes)
    : nodes = <String, TodoNode>{for (final node in nodes) node.id: node} {
    for (final node in this.nodes.values) {
      (_children[node.parentId] ??= <TodoNode>[]).add(node);
    }
    for (final children in _children.values) {
      children.sort(_manualOrderComparator);
    }
  }

  final Map<String, TodoNode> nodes;
  final Map<String?, List<TodoNode>> _children = <String?, List<TodoNode>>{};

  List<TodoNode> childrenOf(String? parentId) =>
      List<TodoNode>.unmodifiable(_children[parentId] ?? const <TodoNode>[]);

  List<TodoNode> visibleChildrenOf(String? parentId) => childrenOf(
    parentId,
  ).where((node) => !node.isAbandoned).toList(growable: false);

  bool isLeaf(String nodeId) => childrenOf(nodeId).isEmpty;

  Iterable<TodoNode> descendantsOf(String nodeId) sync* {
    for (final child in childrenOf(nodeId)) {
      yield child;
      yield* descendantsOf(child.id);
    }
  }

  Iterable<TodoNode> visibleDescendantsOf(String nodeId) =>
      descendantsOf(nodeId).where((node) => !isEffectivelyAbandoned(node.id));

  bool isEffectivelyAbandoned(String nodeId) {
    TodoNode? current = nodes[nodeId];
    while (current != null) {
      if (current.isAbandoned) return true;
      current = current.parentId == null ? null : nodes[current.parentId];
    }
    return false;
  }

  bool isDescendant({required String nodeId, required String ancestorId}) =>
      descendantsOf(ancestorId).any((node) => node.id == nodeId);

  List<TodoNode> leafDescendantsOf(String nodeId) {
    if (isLeaf(nodeId)) return <TodoNode>[nodes[nodeId]!];
    return descendantsOf(nodeId).where((node) => isLeaf(node.id)).toList();
  }

  List<TodoNode> actionableLeafDescendantsOf(String nodeId) =>
      leafDescendantsOf(nodeId)
          .where((leaf) => !isEffectivelyAbandoned(leaf.id))
          .toList(growable: false);

  bool isComplete(String nodeId) {
    final node = nodes[nodeId]!;
    if (node.isAbandoned) return false;
    if (isLeaf(nodeId)) {
      return node.completedAt != null;
    }
    final leaves = actionableLeafDescendantsOf(nodeId);
    return leaves.isNotEmpty &&
        leaves.every((leaf) => leaf.completedAt != null);
  }

  DateTime? effectiveCompletedAt(String nodeId) {
    final node = nodes[nodeId]!;
    if (isLeaf(nodeId)) return node.completedAt;
    if (!isComplete(nodeId)) return null;
    return actionableLeafDescendantsOf(
      nodeId,
    ).map((leaf) => leaf.completedAt!).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  List<String> pathFor(String nodeId) {
    final result = <String>[];
    TodoNode? current = nodes[nodeId];
    while (current != null) {
      result.add(current.title);
      current = current.parentId == null ? null : nodes[current.parentId];
    }
    return result.reversed.toList();
  }

  static int _manualOrderComparator(TodoNode a, TodoNode b) {
    final order = a.manualOrder.compareTo(b.manualOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  }
}
