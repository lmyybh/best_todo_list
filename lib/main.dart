import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/app_controller.dart';
import 'app/node_persistence_workspace.dart';
import 'data/app_database.dart';
import 'data/sqlite_node_repository.dart';
import 'services/update/desktop_update_installer.dart';
import 'services/update/update_delivery.dart';
import 'services/update/update_preferences.dart';
import 'services/update_controller.dart';
import 'services/update_service.dart';
import 'services/windows_update_installer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final database = await AppDatabase.open();
  final repository = SqliteNodeRepository(database);
  final controller = AppController(NodePersistenceWorkspace(repository));
  await controller.load();

  Future<Directory> updateDirectory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/updates');
  final installer = DesktopUpdateInstaller(
    beforeQuit: () async {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(Duration.zero);
      await controller.prepareForUpdate();
    },
  );
  final updates = UpdateController(
    GitHubUpdateService(),
    delivery: SignedUpdateDelivery(
      platform: Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
          ? 'macos'
          : 'unsupported',
      directory: updateDirectory,
      launchInstaller: installer.install,
    ),
    preferences: UpdatePreferences(updateDirectory),
    installUpdate: Platform.isWindows
        ? WindowsUpdateInstaller().checkForUpdates
        : null,
  );
  unawaited(updates.initialize());
  runApp(TodoApp(controller: controller, updates: updates));
}
