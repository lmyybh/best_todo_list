import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';

class MemoryNodeRepository implements NodeRepository {
  final Map<String, TodoNode> _nodes = <String, TodoNode>{};

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) async =>
      _nodes.values
          .where((node) => includeDeleted || node.deletedAt == null)
          .toList();

  @override
  Future<void> insertNode(TodoNode node) async {
    if (_nodes.containsKey(node.id)) throw StateError('Duplicate id');
    _nodes[node.id] = node;
  }

  @override
  Future<void> updateNode(TodoNode node) async {
    if (!_nodes.containsKey(node.id)) throw StateError('Missing id');
    _nodes[node.id] = node;
  }

  @override
  Future<void> updateNodes(List<TodoNode> nodes) async {
    for (final node in nodes) {
      _nodes[node.id] = node;
    }
  }

  @override
  Future<void> close() async {}
}
