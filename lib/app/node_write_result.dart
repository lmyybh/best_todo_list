import '../domain/todo_node.dart';

sealed class NodeWriteResult<T> {
  const NodeWriteResult(this.nodes);

  final List<TodoNode> nodes;
}

final class NodeWriteSuccess<T> extends NodeWriteResult<T> {
  const NodeWriteSuccess(this.value, super.nodes);

  final T value;
}

final class NodeWriteFailure<T> extends NodeWriteResult<T> {
  const NodeWriteFailure(this.error, super.nodes);

  final Object error;
}
