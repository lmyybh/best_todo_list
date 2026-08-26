import 'dart:async';

import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/app/node_write_result.dart';
import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_node_repository.dart';
import '../helpers/memory_node_repository.dart';

void main() {
  test('创建成功显式返回新节点', () async {
    final controller = AppController(
      NodePersistenceWorkspace(
        MemoryNodeRepository(),
        idGenerator: () => 'created',
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final result = await controller.create(title: '发布计划');

    expect(result, isA<NodeWriteSuccess<TodoNode>>());
    expect((result as NodeWriteSuccess<TodoNode>).value.id, 'created');
  });

  test('操作失败通过结果返回错误', () async {
    final repository = FailingNodeRepository()..failNextInsert = true;
    final controller = AppController(NodePersistenceWorkspace(repository));
    addTearDown(controller.dispose);
    await controller.load();

    final result = await controller.create(title: '发布计划');

    expect(result, isA<NodeWriteFailure<TodoNode>>());
    expect((result as NodeWriteFailure<TodoNode>).error, isA<StateError>());
  });

  test('写入成功直接采用工作区快照且不重新加载', () async {
    final repository = FailingNodeRepository();
    final controller = AppController(NodePersistenceWorkspace(repository));
    addTearDown(controller.dispose);
    await controller.load();
    repository.loadsBeforeFailure = 0;

    final result = await controller.create(title: '发布计划');

    expect(result, isA<NodeWriteSuccess<TodoNode>>());
    expect(controller.nodes.single.title, '发布计划');
    expect(controller.selectedId, controller.nodes.single.id);
  });

  test('销毁后延迟完成的写入不再通知控制器', () async {
    final repository = _DelayedNodeRepository();
    final controller = AppController(
      NodePersistenceWorkspace(repository, idGenerator: () => 'created'),
    );
    await controller.load();

    final write = controller.create(title: '发布计划');
    await repository.saveStarted.future;
    controller.dispose();
    repository.resumeSave.complete();

    expect(await write, isA<NodeWriteSuccess<TodoNode>>());
    await repository.closed.future;
  });
}

class _DelayedNodeRepository implements NodeRepository {
  final MemoryNodeRepository _delegate = MemoryNodeRepository();
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> resumeSave = Completer<void>();
  final Completer<void> closed = Completer<void>();

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) =>
      _delegate.loadNodes(includeDeleted: includeDeleted);

  @override
  Future<void> saveNodesAtomically(List<TodoNode> nodes) async {
    saveStarted.complete();
    await resumeSave.future;
    await _delegate.saveNodesAtomically(nodes);
  }

  @override
  Future<void> close() async {
    await _delegate.close();
    closed.complete();
  }
}
