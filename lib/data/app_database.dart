import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static Future<Database> open({String? path}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final databasePath =
        path ??
        p.join(await factory.getDatabasesPath(), 'best_todo_list.sqlite');
    return factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE nodes (
              id TEXT PRIMARY KEY,
              parent_id TEXT NULL,
              title TEXT NOT NULL,
              notes TEXT NOT NULL DEFAULT '',
              deadline INTEGER NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              completed_at INTEGER NULL,
              deleted_at INTEGER NULL,
              manual_order INTEGER NOT NULL,
              FOREIGN KEY (parent_id) REFERENCES nodes(id)
            )
          ''');
          await database.execute(
            'CREATE INDEX nodes_parent_order_idx ON nodes(parent_id, deleted_at, manual_order)',
          );
          await database.execute(
            'CREATE INDEX nodes_deadline_idx ON nodes(deadline, deleted_at)',
          );
          await database.execute(
            'CREATE INDEX nodes_completed_idx ON nodes(completed_at, deleted_at)',
          );
          await database.execute(
            'CREATE INDEX nodes_created_idx ON nodes(created_at, deleted_at)',
          );
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              "ALTER TABLE nodes ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
            );
          }
        },
      ),
    );
  }
}
