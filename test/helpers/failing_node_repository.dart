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
  Future<void> saveNodesAtomically(List<TodoNode> nodes) {
    if (failNextInsert || failNextUpdate) {
      failNextInsert = false;
      failNextUpdate = false;
      throw StateError('save failed');
    }
    return _delegate.saveNodesAtomically(nodes);
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
}
