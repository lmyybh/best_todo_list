import 'package:best_todo_list/domain/node_service.dart';
import 'package:best_todo_list/domain/node_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  late MemoryNodeRepository repository;
  late NodeService service;
  var id = 0;
  var now = DateTime.utc(2026, 8, 11, 9);

  setUp(() {
    repository = MemoryNodeRepository();
    id = 0;
    now = DateTime.utc(2026, 8, 11, 9);
    service = NodeService(
      repository,
      clock: () => now,
      idGenerator: () => 'node-${++id}',
    );
  });

  test('标题 trim 后不能为空', () async {
    await expectLater(
      service.createNode(title: '   '),
      throwsA(isA<NodeRuleException>()),
    );
  });

  test('创建任意层级节点并按 manualOrder 追加', () async {
    final root = await service.createNode(title: ' 根事件 ');
    final first = await service.createNode(parentId: root.id, title: '第一步');
    final second = await service.createNode(parentId: root.id, title: '第二步');
    final third = await service.createNode(parentId: first.id, title: '第三层');

    final tree = NodeTree(await service.loadNodes());
    expect(root.title, '根事件');
    expect(tree.childrenOf(root.id).map((node) => node.id), <String>[
      first.id,
      second.id,
    ]);
    expect(tree.pathFor(third.id), <String>['根事件', '第一步', '第三层']);
    expect(second.manualOrder, greaterThan(first.manualOrder));
  });

  test('叶子完成和取消完成写入正确状态', () async {
    final task = await service.createNode(title: '任务');
    await service.setLeafCompleted(task.id, true);
    expect((await service.loadNodes()).single.completedAt, now);

    await service.setLeafCompleted(task.id, false);
    expect((await service.loadNodes()).single.completedAt, isNull);
  });

  test('事件完成状态取所有叶子最晚完成时间', () async {
    final root = await service.createNode(title: '事件');
    final first = await service.createNode(parentId: root.id, title: 'A');
    final second = await service.createNode(parentId: root.id, title: 'B');
    await service.setLeafCompleted(first.id, true);
    now = now.add(const Duration(hours: 2));
    await service.setLeafCompleted(second.id, true);

    final tree = NodeTree(await service.loadNodes());
    expect(tree.isComplete(root.id), isTrue);
    expect(tree.effectiveCompletedAt(root.id), now);
  });

  test('已完成叶子添加首个子节点时清空 completedAt', () async {
    final task = await service.createNode(title: '原任务');
    await service.setLeafCompleted(task.id, true);
    await service.createNode(parentId: task.id, title: '新子任务');

    final tree = NodeTree(await service.loadNodes());
    expect(tree.nodes[task.id]!.completedAt, isNull);
    expect(tree.isComplete(task.id), isFalse);
  });

  test('事件节点不能手动完成', () async {
    final root = await service.createNode(title: '事件');
    await service.createNode(parentId: root.id, title: '子任务');
    await expectLater(
      service.setLeafCompleted(root.id, true),
      throwsA(isA<NodeRuleException>()),
    );
  });

  test('软删除整棵子树并可恢复', () async {
    final root = await service.createNode(title: '事件');
    await service.createNode(parentId: root.id, title: '子任务');
    final deletion = await service.deleteSubtree(root.id);
    expect(await service.loadNodes(), isEmpty);
    expect(await repository.loadNodes(includeDeleted: true), hasLength(2));

    await service.restoreSubtree(deletion);
    expect(await service.loadNodes(), hasLength(2));
  });

  test('禁止移动到自身或子孙节点', () async {
    final root = await service.createNode(title: '根');
    final child = await service.createNode(parentId: root.id, title: '子');
    await expectLater(
      service.moveNode(nodeId: root.id, newParentId: child.id),
      throwsA(isA<NodeRuleException>()),
    );
  });

  test('已完成节点移动前必须取消完成', () async {
    final first = await service.createNode(title: 'A');
    final second = await service.createNode(title: 'B');
    await service.setLeafCompleted(first.id, true);
    await expectLater(
      service.moveNode(nodeId: first.id, newParentId: second.id),
      throwsA(isA<NodeRuleException>()),
    );
  });

  test('移入已完成叶子时目标转为事件并清空完成时间', () async {
    final target = await service.createNode(title: '已完成目标');
    final moving = await service.createNode(title: '待移动');
    await service.setLeafCompleted(target.id, true);
    await service.moveNode(nodeId: moving.id, newParentId: target.id);

    final tree = NodeTree(await service.loadNodes());
    expect(tree.nodes[target.id]!.completedAt, isNull);
    expect(tree.childrenOf(target.id).single.id, moving.id);
    expect(tree.isComplete(target.id), isFalse);
  });

  test('同级排序保存稳定顺序', () async {
    final root = await service.createNode(title: '根');
    final first = await service.createNode(parentId: root.id, title: 'A');
    final second = await service.createNode(parentId: root.id, title: 'B');
    await service.reorderChildren(root.id, <String>[second.id, first.id]);

    final tree = NodeTree(await service.loadNodes());
    expect(tree.childrenOf(root.id).map((node) => node.id), <String>[
      second.id,
      first.id,
    ]);
  });
}
