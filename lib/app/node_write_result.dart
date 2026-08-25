import '../domain/node_service.dart';
import '../domain/todo_node.dart';

sealed class NodeWriteResult<T> {
  const NodeWriteResult();
}

final class NodeWriteSuccess<T> extends NodeWriteResult<T> {
  const NodeWriteSuccess(this.value);

  final T value;
}

final class NodeWriteFailure<T> extends NodeWriteResult<T> {
  const NodeWriteFailure(this.error);

  final Object error;
}

class NodeWriter {
  const NodeWriter(this.service);

  final NodeService service;

  Future<NodeWriteResult<T>> execute<T>(
    Future<T> Function() operation,
    void Function(T value, List<TodoNode> nodes) commit,
  ) async {
    try {
      final value = await operation();
      final nodes = await service.loadNodes();
      commit(value, nodes);
      return NodeWriteSuccess<T>(value);
    } catch (error) {
      return NodeWriteFailure<T>(error);
    }
  }
}
