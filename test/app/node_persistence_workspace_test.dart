import 'dart:async';

import 'package:best_todo_list/app/node_persistence_workspace.dart';
import 'package:best_todo_list/app/node_write_result.dart';
import 'package:best_todo_list/domain/node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_node_repository.dart';

void main() {
  test('写入成功直接发布持久化快照且不重新读取仓库', () async {
    final repository = _TrackingRepository();
    final workspace = NodePersistenceWorkspace(
      repository,
      idGenerator: () => 'created',
    );
    addTearDown(workspace.close);
    await workspace.load();

    final result = await workspace.createNode(title: '发布计划');

    expect(result, isA<NodeWriteSuccess<TodoNode>>());
    expect(result.nodes.single.id, 'created');
    expect(workspace.nodes.single.id, 'created');
    expect(repository.loadCount, 1);
  });

  test('持久化失败保留最后成功快照', () async {
    final initial = _node('existing');
    final repository = _TrackingRepository(seed: <TodoNode>[initial]);
    final workspace = NodePersistenceWorkspace(repository);
    addTearDown(workspace.close);
    await workspace.load();
    repository.failNextSave = true;

    final result = await workspace.updateTitle(initial.id, '新标题');

    expect(result, isA<NodeWriteFailure<void>>());
    expect(result.nodes.single.title, 'existing');
    expect(workspace.nodes.single.title, 'existing');
  });

  test('并发写入按调用顺序串行计算和持久化', () async {
    final repository = _TrackingRepository()..pauseNextSave = true;
    var id = 0;
    final workspace = NodePersistenceWorkspace(
      repository,
      idGenerator: () => 'node-${++id}',
    );
    addTearDown(workspace.close);
    await workspace.load();

    final first = workspace.createNode(title: '第一项');
    await repository.saveStarted.future;
    final second = workspace.createNode(title: '第二项');
    await Future<void>.delayed(Duration.zero);

    expect(repository.maximumConcurrentSaves, 1);
    repository.resumeSave.complete();
    await Future.wait(<Future<NodeWriteResult<TodoNode>>>[first, second]);

    expect(repository.maximumConcurrentSaves, 1);
    expect(workspace.nodes.map((node) => node.id), <String>[
      'node-1',
      'node-2',
    ]);
    expect(workspace.nodes.map((node) => node.manualOrder), <int>[1000, 2000]);
  });

  test('关闭等待已接收写入并拒绝后续写入', () async {
    final repository = _TrackingRepository()..pauseNextSave = true;
    final workspace = NodePersistenceWorkspace(
      repository,
      idGenerator: () => 'created',
    );
    await workspace.load();

    final write = workspace.createNode(title: '关闭前');
    await repository.saveStarted.future;
    final close = workspace.close();
    final rejected = await workspace.createNode(title: '关闭后');

    expect(rejected, isA<NodeWriteFailure<TodoNode>>());
    repository.resumeSave.complete();
    expect(await write, isA<NodeWriteSuccess<TodoNode>>());
    await close;
    expect(repository.closeCount, 1);
  });

  test('并发加载共享一次读取且关闭等待加载结束', () async {
    final repository = _TrackingRepository()..pauseNextLoad = true;
    final workspace = NodePersistenceWorkspace(repository);

    final first = workspace.load();
    await repository.loadStarted.future;
    final second = workspace.load();
    final close = workspace.close();
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(repository.loadCount, 1);
    expect(repository.closeCount, 0);

    repository.resumeLoad.complete();
    expect(await first, isEmpty);
    expect(await second, isEmpty);
    await close;
    expect(repository.closeCount, 1);
  });
}

class _TrackingRepository implements NodeRepository {
  _TrackingRepository({List<TodoNode> seed = const <TodoNode>[]})
    : _delegate = MemoryNodeRepository(seed: seed);

  final MemoryNodeRepository _delegate;
  int loadCount = 0;
  int closeCount = 0;
  int concurrentSaves = 0;
  int maximumConcurrentSaves = 0;
  bool failNextSave = false;
  bool pauseNextLoad = false;
  bool pauseNextSave = false;
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> resumeLoad = Completer<void>();
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> resumeSave = Completer<void>();

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) async {
    loadCount++;
    if (pauseNextLoad) {
      pauseNextLoad = false;
      if (!loadStarted.isCompleted) loadStarted.complete();
      await resumeLoad.future;
    }
    return _delegate.loadNodes(includeDeleted: includeDeleted);
  }

  @override
  Future<void> saveNodesAtomically(List<TodoNode> nodes) async {
    concurrentSaves++;
    maximumConcurrentSaves = maximumConcurrentSaves < concurrentSaves
        ? concurrentSaves
        : maximumConcurrentSaves;
    try {
      if (pauseNextSave) {
        pauseNextSave = false;
        if (!saveStarted.isCompleted) saveStarted.complete();
        await resumeSave.future;
      }
      if (failNextSave) {
        failNextSave = false;
        throw StateError('save failed');
      }
      await _delegate.saveNodesAtomically(nodes);
    } finally {
      concurrentSaves--;
    }
  }

  @override
  Future<void> close() async {
    closeCount++;
    await _delegate.close();
  }
}

TodoNode _node(String id) => TodoNode(
  id: id,
  title: id,
  createdAt: DateTime.utc(2026, 8, 26),
  updatedAt: DateTime.utc(2026, 8, 26),
  manualOrder: 1000,
);
