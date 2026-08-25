import 'package:best_todo_list/app/app_controller.dart';
import 'package:best_todo_list/app/node_write_result.dart';
import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_node_repository.dart';
import '../helpers/memory_node_repository.dart';

void main() {
  test('创建成功显式返回新节点', () async {
    final controller = AppController(
      NodeService(MemoryNodeRepository(), idGenerator: () => 'created'),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final result = await controller.create(title: '发布计划');

    expect(result, isA<NodeWriteSuccess<TodoNode>>());
    expect((result as NodeWriteSuccess<TodoNode>).value.id, 'created');
  });

  test('操作失败通过结果返回错误', () async {
    final repository = FailingNodeRepository()..failNextInsert = true;
    final controller = AppController(NodeService(repository));
    addTearDown(controller.dispose);
    await controller.load();

    final result = await controller.create(title: '发布计划');

    expect(result, isA<NodeWriteFailure<TodoNode>>());
    expect((result as NodeWriteFailure<TodoNode>).error, isA<StateError>());
  });

  test('写入成功但重新加载失败不会返回成功', () async {
    final repository = FailingNodeRepository();
    final controller = AppController(NodeService(repository));
    addTearDown(controller.dispose);
    await controller.load();
    repository.loadsBeforeFailure = 1;

    final result = await controller.create(title: '发布计划');

    expect(result, isA<NodeWriteFailure<TodoNode>>());
    expect((result as NodeWriteFailure<TodoNode>).error, isA<StateError>());
    expect(controller.nodes, isEmpty);
    expect(controller.selectedId, isNull);
  });
}
