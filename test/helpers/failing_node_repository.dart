import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';

import 'memory_node_repository.dart';

class FailingNodeRepository implements NodeRepository {
  final MemoryNodeRepository _delegate = MemoryNodeRepository();

  bool failNextInsert = false;
  bool failNextUpdate = false;
  int? loadsBeforeFailure;

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> insertNode(TodoNode node) {
    if (failNextInsert) {
      failNextInsert = false;
      throw StateError('insert failed');
    }
    return _delegate.insertNode(node);
  }

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) {
    final remaining = loadsBeforeFailure;
    if (remaining != null) {
      if (remaining == 0) throw StateError('reload failed');
      loadsBeforeFailure = remaining - 1;
    }
    return _delegate.loadNodes(includeDeleted: includeDeleted);
  }

  @override
  Future<void> updateNode(TodoNode node) {
    if (failNextUpdate) {
      failNextUpdate = false;
      throw StateError('update failed');
    }
    return _delegate.updateNode(node);
  }

  @override
  Future<void> updateNodes(List<TodoNode> nodes) =>
      _delegate.updateNodes(nodes);
}
