import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/node_persistence_workspace.dart';
import 'data/app_database.dart';
import 'data/sqlite_node_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final repository = SqliteNodeRepository(database);
  final controller = AppController(NodePersistenceWorkspace(repository));
  await controller.load();

  runApp(TodoApp(controller: controller));
}
