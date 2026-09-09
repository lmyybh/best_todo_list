import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/deadline.dart';

class UnsupportedDatabaseVersion implements Exception {
  const UnsupportedDatabaseVersion({
    required this.found,
    required this.supported,
  });

  final int found;
  final int supported;

  @override
  String toString() => '不支持数据库版本 $found；当前仅支持版本 $supported，原数据库未修改。';
}

class AppDatabase {
  static const int currentVersion = 5;

  static Future<Database> open({String? path}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final databasePath = path ?? await _defaultPath(factory);
    return factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: currentVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _createNodesTable(database);
          await _createNodeIndexes(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion >= 1 && oldVersion <= 4 && newVersion == 5) {
            if (oldVersion < 4) {
              await _migrateLegacyDeadlines(database, oldVersion);
            }
            await database.execute(
              'ALTER TABLE nodes ADD COLUMN abandoned_at INTEGER NULL',
            );
            await database.execute(
              'CREATE INDEX nodes_abandoned_idx ON nodes(abandoned_at, deleted_at)',
            );
            return;
          }
          throw UnsupportedDatabaseVersion(
            found: oldVersion,
            supported: newVersion,
          );
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

Future<void> _migrateLegacyDeadlines(Database database, int version) async {
  if (version < 2) {
    await database.execute(
      "ALTER TABLE nodes ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
    );
  }
  await database.execute(
    'ALTER TABLE nodes ADD COLUMN deadline_date TEXT NULL',
  );
  await database.execute(
    'ALTER TABLE nodes ADD COLUMN deadline_at INTEGER NULL',
  );
  for (final row in await database.query('nodes')) {
    final deadline = row['deadline'] as int?;
    if (deadline == null) continue;
    final hasTime = version < 3 || row['deadline_has_time'] == 1;
    final local = DateTime.fromMillisecondsSinceEpoch(deadline);
    await database.update(
      'nodes',
      hasTime
          ? <String, Object?>{'deadline_at': deadline}
          : <String, Object?>{
              'deadline_date': DateOnlyDeadline(
                year: local.year,
                month: local.month,
                day: local.day,
              ).storage.date,
            },
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
  }
  await database.execute('DROP INDEX IF EXISTS nodes_deadline_idx');
  await database.execute('ALTER TABLE nodes DROP COLUMN deadline');
  if (version >= 3) {
    await database.execute('ALTER TABLE nodes DROP COLUMN deadline_has_time');
  }
  await database.execute(
    'CREATE INDEX nodes_deadline_date_idx ON nodes(deadline_date, deleted_at)',
  );
  await database.execute(
    'CREATE INDEX nodes_deadline_at_idx ON nodes(deadline_at, deleted_at)',
  );
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
    abandoned_at INTEGER NULL,
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
    'CREATE INDEX nodes_abandoned_idx ON nodes(abandoned_at, deleted_at)',
  );
  await database.execute(
    'CREATE INDEX nodes_created_idx ON nodes(created_at, deleted_at)',
  );
}
