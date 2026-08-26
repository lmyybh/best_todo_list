import 'dart:async';

import 'package:best_todo_list/app/node_write_result.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:best_todo_list/ui/events/event_card_editing_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('草稿提交失败时保留输入并阻止切换到重命名', () async {
    final session = EventCardEditingSession(
      create: (parentId, title) async =>
          NodeWriteFailure<TodoNode>(StateError('create failed'), const []),
      rename: (nodeId, title) async => const NodeWriteSuccess<void>(null, []),
    );
    addTearDown(session.dispose);
    final node = TodoNode(
      id: 'task',
      title: '原标题',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 1000,
    );

    expect(await session.openDraft('parent'), isTrue);
    session.updateDraft('保留的草稿');

    expect(await session.openRename(node), isFalse);
    expect(session.draftParentId, 'parent');
    expect(session.draftText, '保留的草稿');
    expect(session.draftSubmitting, isFalse);
    expect(session.renameNodeId, isNull);
  });

  test('草稿提交成功后输出新节点并切换到重命名', () async {
    final created = TodoNode(
      id: 'created',
      parentId: 'parent',
      title: '新任务',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 1000,
    );
    TodoNode? emitted;
    final session = EventCardEditingSession(
      create: (parentId, title) async => NodeWriteSuccess(created, const []),
      rename: (nodeId, title) async => const NodeWriteSuccess<void>(null, []),
      onCreated: (node) => emitted = node,
    );
    addTearDown(session.dispose);
    final renameTarget = TodoNode(
      id: 'rename',
      title: '原标题',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 2000,
    );

    await session.openDraft('parent');
    session.updateDraft('  新任务  ');

    expect(await session.openRename(renameTarget), isTrue);
    expect(emitted, created);
    expect(session.draftParentId, isNull);
    expect(session.draftText, isEmpty);
    expect(session.renameNodeId, renameTarget.id);
    expect(session.renameText, renameTarget.title);
  });

  test('重命名失败时保留输入并阻止切换到草稿', () async {
    final node = TodoNode(
      id: 'rename',
      title: '原标题',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 1000,
    );
    final session = EventCardEditingSession(
      create: (parentId, title) async => NodeWriteSuccess(node, const []),
      rename: (nodeId, title) async =>
          NodeWriteFailure<void>(StateError('rename failed'), const []),
    );
    addTearDown(session.dispose);

    await session.openRename(node);
    session.updateRename('保留的新标题');

    expect(await session.openDraft('parent'), isFalse);
    expect(session.renameNodeId, node.id);
    expect(session.renameText, '保留的新标题');
    expect(session.renameSubmitting, isFalse);
    expect(session.renameFailed, isTrue);
    expect(session.draftParentId, isNull);
  });

  test('离开编辑前按草稿、重命名顺序收束活动编辑', () async {
    final node = TodoNode(
      id: 'rename',
      title: '原标题',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 1000,
    );
    final session = EventCardEditingSession(
      create: (parentId, title) async => NodeWriteSuccess(node, const []),
      rename: (nodeId, title) async => const NodeWriteSuccess<void>(null, []),
    );
    addTearDown(session.dispose);
    await session.openRename(node);
    session.updateRename('新标题');

    expect(await session.finishActive(), isTrue);
    expect(session.renameNodeId, isNull);
    expect(session.draftParentId, isNull);
  });

  test('会话销毁后延迟返回的新增不再输出状态', () async {
    final completer = Completer<NodeWriteResult<TodoNode>>();
    var createdCount = 0;
    final session = EventCardEditingSession(
      create: (parentId, title) => completer.future,
      rename: (nodeId, title) async => const NodeWriteSuccess<void>(null, []),
      onCreated: (_) => createdCount += 1,
    );
    await session.openDraft('parent');
    session.updateDraft('延迟任务');
    final finish = session.finishDraft();

    session.dispose();
    completer.complete(
      NodeWriteSuccess(
        TodoNode(
          id: 'created',
          parentId: 'parent',
          title: '延迟任务',
          createdAt: _now,
          updatedAt: _now,
          manualOrder: 1000,
        ),
        const [],
      ),
    );

    await expectLater(finish, completion(isFalse));
    expect(createdCount, 0);
  });

  test('旧草稿延迟返回不会关闭后来打开的草稿', () async {
    final completer = Completer<NodeWriteResult<TodoNode>>();
    final created = TodoNode(
      id: 'created',
      parentId: 'first',
      title: '第一个草稿',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 1000,
    );
    final session = EventCardEditingSession(
      create: (parentId, title) => completer.future,
      rename: (nodeId, title) async => const NodeWriteSuccess<void>(null, []),
    );
    addTearDown(session.dispose);
    await session.openDraft('first');
    session.updateDraft('第一个草稿');
    final finish = session.finishDraft();

    session.cancelDraft();
    await session.openDraft('second');
    session.updateDraft('第二个草稿');
    completer.complete(NodeWriteSuccess(created, const []));

    expect(await finish, isFalse);
    expect(session.draftParentId, 'second');
    expect(session.draftText, '第二个草稿');
  });

  test('旧草稿延迟返回不会改变后来打开的重命名', () async {
    final completer = Completer<NodeWriteResult<TodoNode>>();
    final renameTarget = TodoNode(
      id: 'rename',
      title: '原标题',
      createdAt: _now,
      updatedAt: _now,
      manualOrder: 1000,
    );
    final session = EventCardEditingSession(
      create: (parentId, title) => completer.future,
      rename: (nodeId, title) async => const NodeWriteSuccess<void>(null, []),
    );
    addTearDown(session.dispose);
    await session.openDraft('first');
    session.updateDraft('第一个草稿');
    final finish = session.finishDraft();

    session.cancelDraft();
    await session.openRename(renameTarget);
    session.updateRename('新标题');
    completer.complete(
      NodeWriteSuccess(
        TodoNode(
          id: 'created',
          parentId: 'first',
          title: '第一个草稿',
          createdAt: _now,
          updatedAt: _now,
          manualOrder: 2000,
        ),
        const [],
      ),
    );

    expect(await finish, isFalse);
    expect(session.draftParentId, isNull);
    expect(session.renameNodeId, renameTarget.id);
    expect(session.renameText, '新标题');
  });
}

final _now = DateTime.utc(2026, 8, 26, 9);
