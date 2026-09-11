import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/app/node_write_result.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';
import '../helpers/write_result.dart';

void main() {
  late MemoryNodeRepository repository;
  late NodePersistenceWorkspace workspace;
  var id = 0;
  var now = DateTime.utc(2026, 8, 11, 9);

  setUp(() async {
    repository = MemoryNodeRepository();
    id = 0;
    now = DateTime.utc(2026, 8, 11, 9);
    workspace = NodePersistenceWorkspace(
      repository,
      clock: () => now,
      idGenerator: () => 'node-${++id}',
    );
    await workspace.load();
  });

  tearDown(() => workspace.close());

  test('标题 trim 后不能为空', () async {
    final result = await workspace.createNode(title: '   ');

    expect(result, isA<NodeWriteFailure>());
    expect((result as NodeWriteFailure).error, isA<NodeRuleException>());
  });

  test('备注可更新并保留原始换行', () async {
    final task = await expectWriteSuccess(workspace.createNode(title: '任务'));
    await expectWriteSuccess(workspace.updateNotes(task.id, '第一行\n第二行'));

    final saved = workspace.nodes.single;
    expect(saved.notes, '第一行\n第二行');
    expect(saved.updatedAt, now);
  });

  test('创建任意层级节点并按 manualOrder 追加', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: ' 根事件 '));
    final first = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '第一步'),
    );
    final second = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '第二步'),
    );
    final third = await expectWriteSuccess(
      workspace.createNode(parentId: first.id, title: '第三层'),
    );

    expect(root.title, '根事件');
    expect(root.createdAt, now);
    expect(workspace.tree.childrenOf(root.id).map((node) => node.id), <String>[
      first.id,
      second.id,
    ]);
    expect(workspace.tree.pathFor(third.id), <String>['根事件', '第一步', '第三层']);
    expect(second.manualOrder, greaterThan(first.manualOrder));
  });

  test('子任务默认沿用直接父节点的截止日期', () async {
    final parentDeadline = DateOnlyDeadline(year: 2026, month: 8, day: 20);
    final parent = await expectWriteSuccess(
      workspace.createNode(title: '事件', deadline: parentDeadline),
    );

    final child = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '子任务'),
    );

    expect(child.deadline?.storage.date, '2026-08-20');
  });

  test('子任务显式设置的截止日期优先于父节点', () async {
    final parent = await expectWriteSuccess(
      workspace.createNode(
        title: '事件',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final childDeadline = TimedDeadline(DateTime(2026, 8, 18, 16, 30));

    final child = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '子任务',
        deadline: childDeadline,
      ),
    );

    expect(child.deadline, isA<TimedDeadline>());
    expect((child.deadline! as TimedDeadline).instant, childDeadline.instant);
  });

  test('无截止日期的父节点不会为子任务生成截止日期', () async {
    final parent = await expectWriteSuccess(workspace.createNode(title: '事件'));

    final child = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '子任务'),
    );

    expect(child.deadline, isNull);
  });

  test('继承后父子节点的截止日期可独立修改', () async {
    final parent = await expectWriteSuccess(
      workspace.createNode(
        title: '事件',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final child = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '子任务'),
    );

    await expectWriteSuccess(
      workspace.updateDeadline(
        child.id,
        DateOnlyDeadline(year: 2026, month: 8, day: 18),
      ),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(
        parent.id,
        DateOnlyDeadline(year: 2026, month: 8, day: 22),
      ),
    );

    expect(
      workspace.tree.nodes[parent.id]!.deadline?.storage.date,
      '2026-08-22',
    );
    expect(
      workspace.tree.nodes[child.id]!.deadline?.storage.date,
      '2026-08-18',
    );
  });

  test('叶子完成和取消完成写入正确状态', () async {
    final task = await expectWriteSuccess(workspace.createNode(title: '任务'));
    final createdAt = task.createdAt;
    await expectWriteSuccess(
      workspace.setNodeStatus(task.id, TodoNodeStatus.completed),
    );
    var saved = workspace.nodes.single;
    expect(saved.createdAt, createdAt);
    expect(saved.completedAt, now);

    await expectWriteSuccess(
      workspace.setNodeStatus(task.id, TodoNodeStatus.active),
    );
    saved = workspace.nodes.single;
    expect(saved.createdAt, createdAt);
    expect(saved.completedAt, isNull);
  });

  test('任务状态转换保持完成与放弃互斥', () async {
    final task = await expectWriteSuccess(workspace.createNode(title: '任务'));

    await expectWriteSuccess(
      workspace.setNodeStatus(task.id, TodoNodeStatus.completed),
    );
    now = now.add(const Duration(hours: 1));
    await expectWriteSuccess(
      workspace.setNodeStatus(task.id, TodoNodeStatus.abandoned),
    );
    var saved = workspace.tree.nodes[task.id]!;
    expect(saved.status, TodoNodeStatus.abandoned);
    expect(saved.completedAt, isNull);
    expect(saved.abandonedAt, now);

    await expectWriteSuccess(
      workspace.setNodeStatus(task.id, TodoNodeStatus.active),
    );
    saved = workspace.tree.nodes[task.id]!;
    expect(saved.status, TodoNodeStatus.active);
    expect(saved.completedAt, isNull);
    expect(saved.abandonedAt, isNull);
  });

  test('事件完成汇总排除已放弃叶子但不把全放弃事件算作完成', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '事件'));
    final completed = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '完成项'),
    );
    final abandoned = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '放弃项'),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(completed.id, TodoNodeStatus.completed),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(abandoned.id, TodoNodeStatus.abandoned),
    );

    expect(workspace.tree.isComplete(root.id), isTrue);
    expect(
      workspace.tree
          .actionableLeafDescendantsOf(root.id)
          .map((node) => node.id),
      [completed.id],
    );

    await expectWriteSuccess(
      workspace.setNodeStatus(completed.id, TodoNodeStatus.abandoned),
    );
    expect(workspace.tree.isComplete(root.id), isFalse);
  });

  test('有子任务的节点可以整支放弃并原样恢复', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '事件'));
    final branch = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '阶段'),
    );
    final child = await expectWriteSuccess(
      workspace.createNode(parentId: branch.id, title: '子任务'),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(child.id, TodoNodeStatus.completed),
    );

    await expectWriteSuccess(
      workspace.setNodeStatus(branch.id, TodoNodeStatus.abandoned),
    );
    expect(workspace.tree.nodes[branch.id]?.isAbandoned, isTrue);
    expect(workspace.tree.nodes[child.id]?.status, TodoNodeStatus.completed);
    expect(workspace.tree.isEffectivelyAbandoned(child.id), isTrue);
    expect(workspace.tree.visibleChildrenOf(root.id), isEmpty);
    expect(workspace.tree.actionableLeafDescendantsOf(root.id), isEmpty);

    await expectWriteSuccess(
      workspace.setNodeStatus(branch.id, TodoNodeStatus.active),
    );
    expect(workspace.tree.visibleChildrenOf(root.id).single.id, branch.id);
    expect(workspace.tree.nodes[child.id]?.status, TodoNodeStatus.completed);
  });

  test('事件完成状态取所有叶子最晚完成时间', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '事件'));
    final first = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: 'A'),
    );
    final second = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: 'B'),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(first.id, TodoNodeStatus.completed),
    );
    now = now.add(const Duration(hours: 2));
    await expectWriteSuccess(
      workspace.setNodeStatus(second.id, TodoNodeStatus.completed),
    );

    expect(workspace.tree.isComplete(root.id), isTrue);
    expect(workspace.tree.effectiveCompletedAt(root.id), now);
  });

  test('已完成叶子添加首个子节点时清空 completedAt', () async {
    final task = await expectWriteSuccess(workspace.createNode(title: '原任务'));
    await expectWriteSuccess(
      workspace.setNodeStatus(task.id, TodoNodeStatus.completed),
    );
    await expectWriteSuccess(
      workspace.createNode(parentId: task.id, title: '新子任务'),
    );

    expect(workspace.tree.nodes[task.id]!.completedAt, isNull);
    expect(workspace.tree.isComplete(task.id), isFalse);
  });

  test('事件节点不能手动完成', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '事件'));
    await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '子任务'),
    );

    final result = await workspace.setNodeStatus(
      root.id,
      TodoNodeStatus.completed,
    );

    expect(result, isA<NodeWriteFailure>());
    expect((result as NodeWriteFailure).error, isA<NodeRuleException>());
  });

  test('软删除整棵子树并可恢复', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '事件'));
    await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '子任务'),
    );
    final deletion = await expectWriteSuccess(workspace.deleteSubtree(root.id));
    expect(workspace.nodes, isEmpty);
    expect(await repository.loadNodes(includeDeleted: true), hasLength(2));

    await expectWriteSuccess(workspace.restoreSubtree(deletion));
    expect(workspace.nodes, hasLength(2));
  });

  test('禁止移动到自身或子孙节点', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '根'));
    final child = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: '子'),
    );

    final result = await workspace.moveNode(
      nodeId: root.id,
      newParentId: child.id,
    );

    expect(result, isA<NodeWriteFailure>());
    expect((result as NodeWriteFailure).error, isA<NodeRuleException>());
  });

  test('已完成节点可以移动并保留完成状态', () async {
    final first = await expectWriteSuccess(workspace.createNode(title: 'A'));
    final second = await expectWriteSuccess(workspace.createNode(title: 'B'));
    await expectWriteSuccess(
      workspace.setNodeStatus(first.id, TodoNodeStatus.completed),
    );

    final result = await workspace.moveNode(
      nodeId: first.id,
      newParentId: second.id,
    );

    expect(result, isA<NodeWriteSuccess>());
    expect(workspace.tree.nodes[first.id]!.parentId, second.id);
    expect(workspace.tree.nodes[first.id]!.completedAt, isNotNull);
  });

  test('移入已完成叶子时目标转为事件并清空完成时间', () async {
    final target = await expectWriteSuccess(
      workspace.createNode(title: '已完成目标'),
    );
    final moving = await expectWriteSuccess(workspace.createNode(title: '待移动'));
    await expectWriteSuccess(
      workspace.setNodeStatus(target.id, TodoNodeStatus.completed),
    );
    await expectWriteSuccess(
      workspace.moveNode(nodeId: moving.id, newParentId: target.id),
    );

    expect(workspace.tree.nodes[target.id]!.completedAt, isNull);
    expect(workspace.tree.childrenOf(target.id).single.id, moving.id);
    expect(workspace.tree.isComplete(target.id), isFalse);
  });

  test('同级排序保存稳定顺序', () async {
    final root = await expectWriteSuccess(workspace.createNode(title: '根'));
    final first = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: 'A'),
    );
    final second = await expectWriteSuccess(
      workspace.createNode(parentId: root.id, title: 'B'),
    );
    await expectWriteSuccess(
      workspace.reorderChildren(root.id, <String>[second.id, first.id]),
    );

    expect(workspace.tree.childrenOf(root.id).map((node) => node.id), <String>[
      second.id,
      first.id,
    ]);
  });
}
