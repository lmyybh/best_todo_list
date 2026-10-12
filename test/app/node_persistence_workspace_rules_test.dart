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

  test('事件色相分散且新增、排序、归档不会改变已有颜色', () async {
    final events = <TodoNode>[];
    for (var i = 0; i < 11; i++) {
      events.add(
        await expectWriteSuccess(workspace.createNode(title: '事件 $i')),
      );
    }
    final hues = events.map((node) => node.eventHue!).toList()..sort();
    for (var i = 0; i < hues.length; i++) {
      final next = i + 1 < hues.length ? hues[i + 1] : hues.first + 360;
      expect(next - hues[i], greaterThanOrEqualTo(22.5));
    }
    await expectWriteSuccess(
      workspace.reorderChildren(
        null,
        events.reversed.map((node) => node.id).toList(),
      ),
    );
    await expectWriteSuccess(workspace.setEventArchived(events.first.id, true));
    await expectWriteSuccess(workspace.createNode(title: '新事件'));
    final saved = await repository.loadNodes();
    for (final event in events) {
      expect(workspace.tree.nodes[event.id]!.eventHue, event.eventHue);
      expect(
        saved.singleWhere((node) => node.id == event.id).eventHue,
        event.eventHue,
      );
    }
  });

  test('收起仅允许已完成任务，恢复未完成时取消收起', () async {
    final node = await expectWriteSuccess(workspace.createNode(title: '任务'));
    expect(
      await workspace.setTaskArchived(node.id, true),
      isA<NodeWriteFailure>(),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(node.id, TodoNodeStatus.completed),
    );
    await expectWriteSuccess(workspace.setTaskArchived(node.id, true));
    expect(workspace.tree.nodes[node.id]!.isArchived, isTrue);
    expect((await repository.loadNodes()).single.isArchived, isTrue);
    await expectWriteSuccess(
      workspace.setNodeStatus(node.id, TodoNodeStatus.active),
    );
    expect(workspace.tree.nodes[node.id]!.isArchived, isFalse);
  });

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

  test('无日期子任务和多层后代自动继承并跟随父任务延后', () async {
    final parent = await expectWriteSuccess(workspace.createNode(title: '父任务'));
    final child = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '子任务'),
    );
    final grandchild = await expectWriteSuccess(
      workspace.createNode(parentId: child.id, title: '孙任务'),
    );
    for (final day in [20, 22]) {
      await expectWriteSuccess(
        workspace.updateDeadline(
          parent.id,
          DateOnlyDeadline(year: 2026, month: 8, day: day),
        ),
      );
      for (final id in [child.id, grandchild.id]) {
        expect(
          workspace.tree.nodes[id]!.deadline?.storage.date,
          '2026-08-$day',
        );
      }
    }
  });

  test('父任务提前收紧较晚日期且收紧后随相同父任务日期延后', () async {
    final parent = await expectWriteSuccess(
      workspace.createNode(
        title: '父任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final early = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '较早',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 16),
      ),
    );
    final late = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '较晚',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 19),
      ),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(
        parent.id,
        DateOnlyDeadline(year: 2026, month: 8, day: 18),
      ),
    );
    expect(
      workspace.tree.nodes[early.id]!.deadline?.storage.date,
      '2026-08-16',
    );
    expect(workspace.tree.nodes[late.id]!.deadline?.storage.date, '2026-08-18');
    await expectWriteSuccess(
      workspace.updateDeadline(
        parent.id,
        DateOnlyDeadline(year: 2026, month: 8, day: 22),
      ),
    );
    expect(workspace.tree.nodes[late.id]!.deadline?.storage.date, '2026-08-22');
    expect(
      workspace.tree.nodes[early.id]!.deadline?.storage.date,
      '2026-08-16',
    );
  });

  test('与父任务相同的日期不论设置方式都随父任务延后', () async {
    final deadline = DateOnlyDeadline(year: 2026, month: 8, day: 20);
    final parent = await expectWriteSuccess(
      workspace.createNode(title: '父任务', deadline: deadline),
    );
    final inherited = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '继承'),
    );
    final manual = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '手动'),
    );
    await expectWriteSuccess(workspace.updateDeadline(manual.id, deadline));
    final grandchild = await expectWriteSuccess(
      workspace.createNode(
        parentId: manual.id,
        title: '手动设置的孙任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    await expectWriteSuccess(
      workspace.updateDeadline(
        parent.id,
        DateOnlyDeadline(year: 2026, month: 8, day: 22),
      ),
    );
    expect(
      workspace.tree.nodes[inherited.id]!.deadline?.storage.date,
      '2026-08-22',
    );
    expect(
      workspace.tree.nodes[manual.id]!.deadline?.storage.date,
      '2026-08-22',
    );
    expect(
      workspace.tree.nodes[grandchild.id]!.deadline?.storage.date,
      '2026-08-22',
    );
  });

  test('具体截止时间完全一致才随延后，同日不同时间保持不变', () async {
    final deadline = TimedDeadline(DateTime(2026, 8, 20, 18));
    final parent = await expectWriteSuccess(
      workspace.createNode(title: '父任务', deadline: deadline),
    );
    final equal = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '相同时间',
        deadline: TimedDeadline(deadline.instant),
      ),
    );
    final earlier = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '同日较早',
        deadline: TimedDeadline(DateTime(2026, 8, 20, 16)),
      ),
    );
    final dateOnly = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '仅日期',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final later = TimedDeadline(DateTime(2026, 8, 22, 18));
    await expectWriteSuccess(workspace.updateDeadline(parent.id, later));
    expect(workspace.tree.nodes[equal.id]!.deadline, same(later));
    expect(
      workspace.tree.nodes[earlier.id]!.deadline!.effectiveAt,
      DateTime(2026, 8, 20, 16),
    );
    expect(
      workspace.tree.nodes[dateOnly.id]!.deadline?.storage.date,
      '2026-08-20',
    );
  });

  test('多层收紧按直接父任务比较日期和具体时间', () async {
    final parent = await expectWriteSuccess(
      workspace.createNode(
        title: '父任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final branch = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '阶段',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 19),
      ),
    );
    final inherited = await expectWriteSuccess(
      workspace.createNode(parentId: branch.id, title: '继承'),
    );
    final manual = await expectWriteSuccess(
      workspace.createNode(
        parentId: branch.id,
        title: '更早的时间',
        deadline: TimedDeadline(DateTime(2026, 8, 19, 16)),
      ),
    );
    final deadline = TimedDeadline(DateTime(2026, 8, 19, 18));
    await expectWriteSuccess(workspace.updateDeadline(parent.id, deadline));
    for (final id in [branch.id, inherited.id]) {
      expect(workspace.tree.nodes[id]!.deadline, same(deadline));
    }
    expect(
      workspace.tree.nodes[manual.id]!.deadline!.effectiveAt,
      DateTime(2026, 8, 19, 16),
    );
  });

  test('清除父任务日期按相同时间判断，不区分设置方式并逐层处理', () async {
    final parent = await expectWriteSuccess(
      workspace.createNode(
        title: '父任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final inherited = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '继承'),
    );
    final sameDate = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '手动设置相同日期',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final grandchild = await expectWriteSuccess(
      workspace.createNode(
        parentId: sameDate.id,
        title: '孙任务',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    final completed = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '已完成'),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(completed.id, TodoNodeStatus.completed),
    );
    final timed = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '同日具体时间',
        deadline: TimedDeadline(DateTime(2026, 8, 20, 18)),
      ),
    );
    final manual = await expectWriteSuccess(
      workspace.createNode(
        parentId: parent.id,
        title: '手动',
        deadline: DateOnlyDeadline(year: 2026, month: 8, day: 18),
      ),
    );
    await expectWriteSuccess(workspace.updateDeadline(parent.id, null));
    for (final id in [inherited.id, sameDate.id, grandchild.id]) {
      expect(workspace.tree.nodes[id]!.deadline, isNull);
    }
    expect(
      workspace.tree.nodes[completed.id]!.deadline?.storage.date,
      '2026-08-20',
    );
    expect(
      workspace.tree.nodes[timed.id]!.deadline!.effectiveAt,
      DateTime(2026, 8, 20, 18),
    );
    expect(
      workspace.tree.nodes[manual.id]!.deadline?.storage.date,
      '2026-08-18',
    );
  });

  test('清除父任务日期保留移入任务的不同继承日期', () async {
    final source = await expectWriteSuccess(
      workspace.createNode(
        title: '来源',
        deadline: TimedDeadline(DateTime(2026, 8, 18, 16)),
      ),
    );
    final child = await expectWriteSuccess(
      workspace.createNode(parentId: source.id, title: '继承来源日期'),
    );
    final target = await expectWriteSuccess(
      workspace.createNode(
        title: '目标',
        deadline: TimedDeadline(DateTime(2026, 8, 20, 18)),
      ),
    );
    final matching = await expectWriteSuccess(
      workspace.createNode(
        parentId: target.id,
        title: '相同时间',
        deadline: TimedDeadline(DateTime(2026, 8, 20, 18)),
      ),
    );
    await expectWriteSuccess(
      workspace.moveNode(nodeId: child.id, newParentId: target.id),
    );
    await expectWriteSuccess(workspace.updateDeadline(target.id, null));
    expect(
      workspace.tree.nodes[child.id]!.deadline!.effectiveAt,
      DateTime(2026, 8, 18, 16),
    );
    expect(workspace.tree.nodes[matching.id]!.deadline, isNull);
  });

  test('已完成子任务及完成分支不改变日期和更新时间', () async {
    final parent = await expectWriteSuccess(workspace.createNode(title: '父任务'));
    final branch = await expectWriteSuccess(
      workspace.createNode(parentId: parent.id, title: '已完成分支'),
    );
    final child = await expectWriteSuccess(
      workspace.createNode(parentId: branch.id, title: '已完成子任务'),
    );
    await expectWriteSuccess(
      workspace.setNodeStatus(child.id, TodoNodeStatus.completed),
    );
    final before = workspace.tree;
    now = now.add(const Duration(hours: 1));
    await expectWriteSuccess(
      workspace.updateDeadline(
        parent.id,
        DateOnlyDeadline(year: 2026, month: 8, day: 20),
      ),
    );
    for (final id in [branch.id, child.id]) {
      expect(workspace.tree.nodes[id], same(before.nodes[id]));
    }
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
