import 'dart:io';

import 'package:best_todo_list/data/app_database.dart';
import 'package:best_todo_list/data/sqlite_node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('文件数据库重开后数据仍可恢复，软删除默认隐藏', () async {
    final directory = await Directory.systemTemp.createTemp('best_todo_test_');
    final path = p.join(directory.path, 'test.sqlite');
    final created = DateTime.utc(2026, 8, 11, 8, 30);
    final completed = DateTime.utc(2026, 8, 11, 9, 15);
    final node = TodoNode(
      id: 'node-1',
      title: '持久化任务',
      deadline: DateTime.utc(2026, 8, 12, 10),
      createdAt: created,
      updatedAt: created,
      completedAt: completed,
      manualOrder: 1000,
    );

    var database = await AppDatabase.open(path: path);
    var repository = SqliteNodeRepository(database);
    await repository.insertNode(node);
    await repository.close();

    database = await AppDatabase.open(path: path);
    repository = SqliteNodeRepository(database);
    final restored = (await repository.loadNodes()).single;
    expect(restored.title, node.title);
    expect(restored.deadline, node.deadline);
    expect(restored.createdAt, created);
    expect(restored.completedAt, completed);

    final deletedAt = DateTime.utc(2026, 8, 11, 9);
    await repository.updateNode(
      restored.copyWith(deletedAt: deletedAt, updatedAt: deletedAt),
    );
    expect(await repository.loadNodes(), isEmpty);
    expect(await repository.loadNodes(includeDeleted: true), hasLength(1));
    await repository.close();
    await directory.delete(recursive: true);
  });
}
