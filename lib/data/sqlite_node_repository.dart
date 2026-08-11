import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/node_repository.dart';
import '../domain/todo_node.dart';

class SqliteNodeRepository implements NodeRepository {
  SqliteNodeRepository(this.database);

  final Database database;

  @override
  Future<List<TodoNode>> loadNodes({bool includeDeleted = false}) async {
    final rows = await database.query(
      'nodes',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(TodoNode.fromMap).toList();
  }

  @override
  Future<void> insertNode(TodoNode node) =>
      database.insert('nodes', node.toMap());

  @override
  Future<void> updateNode(TodoNode node) async {
    await database.update(
      'nodes',
      node.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[node.id],
    );
  }

  @override
  Future<void> updateNodes(List<TodoNode> nodes) async {
    await database.transaction((transaction) async {
      for (final node in nodes) {
        final updated = await transaction.update(
          'nodes',
          node.toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[node.id],
        );
        if (updated == 0) await transaction.insert('nodes', node.toMap());
      }
    });
  }

  @override
  Future<void> close() => database.close();
}
