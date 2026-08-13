import 'dart:io';

import 'package:best_todo_list/data/app_database.dart';
import 'package:best_todo_list/data/sqlite_node_repository.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('版本 1 数据库升级后保留任务并支持备注', () async {
    final directory = await Directory.systemTemp.createTemp('todo_upgrade_');
    final path = p.join(directory.path, 'test.sqlite');
    final factory = databaseFactoryFfi;
    sqfliteFfiInit();
    final legacyDatabase = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) => database.execute('''
          CREATE TABLE nodes (
            id TEXT PRIMARY KEY,
            parent_id TEXT NULL,
            title TEXT NOT NULL,
            deadline INTEGER NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            completed_at INTEGER NULL,
            deleted_at INTEGER NULL,
            manual_order INTEGER NOT NULL
          )
        '''),
      ),
    );
    final created = DateTime.utc(2026, 8, 11, 8, 30);
    await legacyDatabase.insert('nodes', <String, Object?>{
      'id': 'legacy-node',
      'title': '已有任务',
      'created_at': created.millisecondsSinceEpoch,
      'updated_at': created.millisecondsSinceEpoch,
      'manual_order': 1000,
    });
    await legacyDatabase.close();

    final database = await AppDatabase.open(path: path);
    final repository = SqliteNodeRepository(database);
    var restored = (await repository.loadNodes()).single;
    expect(restored.title, '已有任务');
    expect(restored.notes, isEmpty);

    restored = restored.copyWith(notes: '升级后的备注');
    await repository.updateNode(restored);
    expect((await repository.loadNodes()).single.notes, '升级后的备注');
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('文件数据库重开后数据仍可恢复，软删除默认隐藏', () async {
    final directory = await Directory.systemTemp.createTemp('best_todo_test_');
    final path = p.join(directory.path, 'test.sqlite');
    final created = DateTime.utc(2026, 8, 11, 8, 30);
    final completed = DateTime.utc(2026, 8, 11, 9, 15);
    final node = TodoNode(
      id: 'node-1',
      title: '持久化任务',
      notes: '发布前确认回滚方案',
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
    expect(restored.notes, node.notes);
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
