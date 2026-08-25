import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/deadline.dart';

class AppDatabase {
  static Future<Database> open({String? path}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final databasePath = path ?? await _defaultPath(factory);
    return factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _createNodesTable(database);
          await _createNodeIndexes(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              "ALTER TABLE nodes ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
            );
          }
          if (oldVersion < 3) {
            await database.execute(
              'ALTER TABLE nodes ADD COLUMN deadline_has_time INTEGER NOT NULL DEFAULT 0',
            );
            await database.execute(
              'UPDATE nodes SET deadline_has_time = 1 WHERE deadline IS NOT NULL',
            );
          }
          if (oldVersion < 4) {
            await _migrateDeadlinesToVersion4(database);
          }
        },
      ),
    );
  }

  static Future<String> _defaultPath(DatabaseFactory factory) async {
    final legacyPath = p.join(
      await factory.getDatabasesPath(),
      'best_todo_list.sqlite',
    );
    if (!Platform.isWindows) return legacyPath;

    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('Windows LOCALAPPDATA is unavailable.');
    }
    final databasePath = p.join(
      localAppData,
      'BestTodoList',
      'data',
      'best_todo_list.sqlite',
    );
    await migrateLegacyFiles(
      legacyPath: legacyPath,
      databasePath: databasePath,
    );
    await Directory(p.dirname(databasePath)).create(recursive: true);
    return databasePath;
  }

  static Future<void> migrateLegacyFiles({
    required String legacyPath,
    required String databasePath,
  }) async {
    if (p.equals(legacyPath, databasePath) ||
        await File(databasePath).exists() ||
        !await File(legacyPath).exists()) {
      return;
    }

    await Directory(p.dirname(databasePath)).create(recursive: true);
    for (final suffix in const <String>['-wal', '-shm', '']) {
      final source = File('$legacyPath$suffix');
      if (await source.exists()) {
        await source.copy('$databasePath$suffix');
      }
    }
  }
}

Future<void> _createNodesTable(DatabaseExecutor database) =>
    database.execute('''
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
''');

Future<void> _createNodeIndexes(DatabaseExecutor database) async {
  await database.execute(
    'CREATE INDEX nodes_parent_order_idx ON nodes(parent_id, deleted_at, manual_order)',
  );
  await database.execute(
    'CREATE INDEX nodes_deadline_date_idx ON nodes(deadline_date, deleted_at)',
  );
  await database.execute(
    'CREATE INDEX nodes_deadline_at_idx ON nodes(deadline_at, deleted_at)',
  );
  await database.execute(
    'CREATE INDEX nodes_completed_idx ON nodes(completed_at, deleted_at)',
  );
  await database.execute(
    'CREATE INDEX nodes_created_idx ON nodes(created_at, deleted_at)',
  );
}

Future<void> _migrateDeadlinesToVersion4(Database database) async {
  await database.execute('ALTER TABLE nodes RENAME TO nodes_v3');
  await _createNodesTable(database);

  final rows = await database.query(
    'nodes_v3',
    orderBy: 'created_at ASC, id ASC',
  );
  for (final row in rows) {
    final migrated = Map<String, Object?>.of(row);
    final deadline = migrated.remove('deadline') as int?;
    final hasTime = (migrated.remove('deadline_has_time') as int? ?? 0) == 1;
    String? deadlineDate;
    int? deadlineAt;
    if (deadline != null && hasTime) {
      deadlineAt = deadline;
    } else if (deadline != null) {
      final local = DateTime.fromMillisecondsSinceEpoch(
        deadline,
        isUtc: true,
      ).toLocal();
      deadlineDate = DateOnlyDeadline(
        year: local.year,
        month: local.month,
        day: local.day,
      ).storage.date;
    }
    migrated['deadline_date'] = deadlineDate;
    migrated['deadline_at'] = deadlineAt;
    await database.insert('nodes', migrated);
  }

  await database.execute('DROP TABLE nodes_v3');
  await _createNodeIndexes(database);
}
