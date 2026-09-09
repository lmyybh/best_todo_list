import 'dart:io';

import 'package:best_todo_list/data/app_database.dart';
import 'package:best_todo_list/data/sqlite_node_repository.dart';
import 'package:best_todo_list/domain/deadline.dart';
import 'package:best_todo_list/domain/todo_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('旧数据库迁移到独立用户目录并保留 SQLite 辅助文件', () async {
    final directory = await Directory.systemTemp.createTemp('todo_migrate_');
    try {
      final legacyPath = p.join(directory.path, 'legacy', 'todo.sqlite');
      final databasePath = p.join(directory.path, 'data', 'todo.sqlite');
      await Directory(p.dirname(legacyPath)).create(recursive: true);
      await File(legacyPath).writeAsString('database');
      await File('$legacyPath-wal').writeAsString('wal');
      await File('$legacyPath-shm').writeAsString('shm');

      await AppDatabase.migrateLegacyFiles(
        legacyPath: legacyPath,
        databasePath: databasePath,
      );

      expect(await File(databasePath).readAsString(), 'database');
      expect(await File('$databasePath-wal').readAsString(), 'wal');
      expect(await File('$databasePath-shm').readAsString(), 'shm');
      expect(await File(legacyPath).readAsString(), 'database');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  for (final version in <int>[1, 2, 3]) {
    test('版本 $version 数据库升级后保留任务与精确截止时间', () async {
      final directory = await Directory.systemTemp.createTemp(
        'todo_unsupported_',
      );
      final path = p.join(directory.path, 'test.sqlite');
      sqfliteFfiInit();
      await _createLegacyDatabase(path, version);

      final preserved = await AppDatabase.open(path: path);
      final versionRows = await preserved.rawQuery('PRAGMA user_version');
      expect(versionRows.single['user_version'], 5);
      expect((await preserved.query('nodes')).single['title'], '已有任务');
      final node = (await SqliteNodeRepository(preserved).loadNodes()).single;
      expect(node.notes, '');
      expect(node.abandonedAt, isNull);
      expect(
        (node.deadline! as TimedDeadline).instant,
        DateTime.utc(2026, 8, 12, 10),
      );
      await preserved.close();
      expect(await File(path).exists(), isTrue);
      await directory.delete(recursive: true);
    });
  }

  test('版本 3 升级保留日期期限、父子层级和已删除任务', () async {
    final directory = await Directory.systemTemp.createTemp('todo_v3_tree_');
    final path = p.join(directory.path, 'test.sqlite');
    await _createLegacyDatabase(path, 3);
    final legacy = await databaseFactoryFfi.openDatabase(path);
    final parent = (await legacy.query('nodes')).single;
    final date = DateTime(2026, 9, 9);
    await legacy.insert('nodes', <String, Object?>{
      ...parent,
      'id': 'child',
      'parent_id': parent['id'],
      'notes': '保留备注',
      'deadline': date.millisecondsSinceEpoch,
      'deadline_has_time': 0,
      'deleted_at': date.millisecondsSinceEpoch,
    });
    await legacy.execute(
      'CREATE INDEX nodes_deadline_idx ON nodes(deadline, deleted_at)',
    );
    await legacy.close();

    var database = await AppDatabase.open(path: path);
    await database.close();
    database = await AppDatabase.open(path: path);
    final child = (await database.query(
      'nodes',
      where: 'id = ?',
      whereArgs: <Object?>['child'],
    )).single;
    expect(child['parent_id'], 'legacy-node');
    expect(child['notes'], '保留备注');
    expect(child['deadline_date'], '2026-09-09');
    expect(child['deadline_at'], isNull);
    expect(child['deleted_at'], date.millisecondsSinceEpoch);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await database.close();
    await directory.delete(recursive: true);
  });

  test('版本 4 数据库升级后保留数据并支持放弃状态', () async {
    final directory = await Directory.systemTemp.createTemp('todo_v4_');
    final path = p.join(directory.path, 'test.sqlite');
    await _createVersion4Database(path);

    final database = await AppDatabase.open(path: path);
    final repository = SqliteNodeRepository(database);
    final restored = (await repository.loadNodes()).single;
    expect(restored.title, '已有任务');
    expect(restored.abandonedAt, isNull);

    final abandonedAt = DateTime.utc(2026, 8, 12, 9);
    await repository.saveNodesAtomically(<TodoNode>[
      restored.copyWith(abandonedAt: abandonedAt, updatedAt: abandonedAt),
    ]);
    expect((await repository.loadNodes()).single.abandonedAt, abandonedAt);
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
      deadline: TimedDeadline(DateTime.utc(2026, 8, 12, 10)),
      createdAt: created,
      updatedAt: created,
      completedAt: completed,
      manualOrder: 1000,
    );

    var database = await AppDatabase.open(path: path);
    var repository = SqliteNodeRepository(database);
    await repository.saveNodesAtomically(<TodoNode>[node]);
    await repository.close();

    database = await AppDatabase.open(path: path);
    repository = SqliteNodeRepository(database);
    final restored = (await repository.loadNodes()).single;
    expect(restored.title, node.title);
    expect(restored.notes, node.notes);
    expect(
      (restored.deadline! as TimedDeadline).instant,
      (node.deadline! as TimedDeadline).instant,
    );
    expect(restored.createdAt, created);
    expect(restored.completedAt, completed);
    expect(restored.abandonedAt, isNull);

    final deletedAt = DateTime.utc(2026, 8, 11, 9);
    await repository.saveNodesAtomically(<TodoNode>[
      restored.copyWith(deletedAt: deletedAt, updatedAt: deletedAt),
    ]);
    expect(await repository.loadNodes(), isEmpty);
    expect(await repository.loadNodes(includeDeleted: true), hasLength(1));
    await repository.close();
    await directory.delete(recursive: true);
  });

  test('批量保存任一节点失败时整体回滚', () async {
    final directory = await Directory.systemTemp.createTemp('todo_atomic_');
    final path = p.join(directory.path, 'test.sqlite');
    final created = DateTime.utc(2026, 8, 26, 9);
    final original = TodoNode(
      id: 'existing',
      title: '原标题',
      createdAt: created,
      updatedAt: created,
      manualOrder: 1000,
    );
    final database = await AppDatabase.open(path: path);
    final repository = SqliteNodeRepository(database);
    await repository.saveNodesAtomically(<TodoNode>[original]);

    await expectLater(
      repository.saveNodesAtomically(<TodoNode>[
        original.copyWith(title: '不应提交'),
        TodoNode(
          id: 'invalid-child',
          parentId: 'missing-parent',
          title: '无效节点',
          createdAt: created,
          updatedAt: created,
          manualOrder: 1000,
        ),
      ]),
      throwsA(anything),
    );

    expect((await repository.loadNodes()).single.title, '原标题');
    await repository.close();
    await directory.delete(recursive: true);
  });
}

Future<void> _createVersion4Database(String path) async {
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (database, _) => database.execute('''
        CREATE TABLE nodes (
          id TEXT PRIMARY KEY,
          parent_id TEXT NULL,
          title TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          deadline_date TEXT NULL,
          deadline_at INTEGER NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          completed_at INTEGER NULL,
          deleted_at INTEGER NULL,
          manual_order INTEGER NOT NULL,
          FOREIGN KEY (parent_id) REFERENCES nodes(id),
          CHECK (deadline_date IS NULL OR deadline_at IS NULL)
        )
      '''),
    ),
  );
  final created = DateTime.utc(2026, 8, 11, 8, 30);
  await database.insert('nodes', <String, Object?>{
    'id': 'v4-node',
    'title': '已有任务',
    'notes': '',
    'created_at': created.millisecondsSinceEpoch,
    'updated_at': created.millisecondsSinceEpoch,
    'manual_order': 1000,
  });
  await database.close();
}

Future<void> _createLegacyDatabase(String path, int version) async {
  final notesColumn = version >= 2 ? "notes TEXT NOT NULL DEFAULT ''," : '';
  final deadlineKindColumn = version >= 3
      ? 'deadline_has_time INTEGER NOT NULL DEFAULT 0,'
      : '';
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (database, _) => database.execute('''
        CREATE TABLE nodes (
          id TEXT PRIMARY KEY,
          parent_id TEXT NULL,
          title TEXT NOT NULL,
          $notesColumn
          deadline INTEGER NULL,
          $deadlineKindColumn
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
  await database.insert('nodes', <String, Object?>{
    'id': 'legacy-node',
    'title': '已有任务',
    if (version >= 2) 'notes': '',
    'deadline': DateTime.utc(2026, 8, 12, 10).millisecondsSinceEpoch,
    if (version >= 3) 'deadline_has_time': 1,
    'created_at': created.millisecondsSinceEpoch,
    'updated_at': created.millisecondsSinceEpoch,
    'manual_order': 1000,
  });
  await database.close();
}
