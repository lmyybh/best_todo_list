import '../../domain/node_tree.dart';
import '../../domain/todo_node.dart';

class TodayFocusProjection {
  TodayFocusProjection._({
    required this.tree,
    required this.roots,
    required this.taskCountsByRootId,
  });

  factory TodayFocusProjection.from({
    required NodeTree source,
    required Iterable<TodoNode> roots,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final includedIds = <String>{};
    final matchingRoots = <TodoNode>[];
    final taskCounts = <String, int>{};

    for (final root in roots) {
      final matchingLeaves = source
          .actionableLeafDescendantsOf(root.id)
          .where(
            (leaf) =>
                leaf.completedAt == null &&
                leaf.deadline != null &&
                !leaf.deadline!.calendarDate.isAfter(today),
          )
          .toList(growable: false);
      if (matchingLeaves.isEmpty) continue;

      matchingRoots.add(root);
      taskCounts[root.id] = matchingLeaves.length;
      includedIds.add(root.id);
      for (final leaf in matchingLeaves) {
        TodoNode? current = leaf;
        while (current != null) {
          includedIds.add(current.id);
          if (current.id == root.id) break;
          current = current.parentId == null
              ? null
              : source.nodes[current.parentId];
        }
      }
    }

    return TodayFocusProjection._(
      tree: NodeTree(
        source.nodes.values.where((node) => includedIds.contains(node.id)),
      ),
      roots: List<TodoNode>.unmodifiable(matchingRoots),
      taskCountsByRootId: Map<String, int>.unmodifiable(taskCounts),
    );
  }

  final NodeTree tree;
  final List<TodoNode> roots;
  final Map<String, int> taskCountsByRootId;

  int taskCountFor(String rootId) => taskCountsByRootId[rootId] ?? 0;
}
