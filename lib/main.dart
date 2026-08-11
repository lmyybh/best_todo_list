import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'data/app_database.dart';
import 'data/sqlite_node_repository.dart';
import 'domain/node_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final repository = SqliteNodeRepository(database);
  final controller = AppController(NodeService(repository));
  await controller.load();

  runApp(TodoApp(controller: controller));
}
