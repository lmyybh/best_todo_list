import 'todo_node.dart';

abstract interface class NodeRepository {
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false});

  Future<void> insertNode(TodoNode node);

  Future<void> updateNode(TodoNode node);

  Future<void> updateNodes(List<TodoNode> nodes);

  Future<void> close();
}
