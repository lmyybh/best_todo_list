import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';

class MemoryNodeRepository implements NodeRepository {
  MemoryNodeRepository({List<TodoNode> seed = const <TodoNode>[]}) {
    _nodes.addEntries(seed.map((node) => MapEntry(node.id, node)));
  }

  final Map<String, TodoNode> _nodes = <String, TodoNode>{};

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) async =>
      _nodes.values
          .where((node) => includeDeleted || node.deletedAt == null)
          .toList();

  @override
  Future<void> saveNodesAtomically(List<TodoNode> nodes) async {
    for (final node in nodes) {
      _nodes[node.id] = node;
    }
  }

  @override
  Future<void> close() async {}
}
