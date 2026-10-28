import 'dart:io';

import 'package:best_todo_list/services/update/update_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自动检查默认关闭，修改后重启仍保留', () async {
    final directory = await Directory.systemTemp.createTemp(
      'todo-update-preferences-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final preferences = UpdatePreferences(() async => directory);
    expect(await preferences.loadAutoCheck(), isFalse);
    await preferences.saveAutoCheck(true);
    expect(
      await UpdatePreferences(() async => directory).loadAutoCheck(),
      isTrue,
    );
    await preferences.saveAutoCheck(false);
    expect(await preferences.loadAutoCheck(), isFalse);
    await File(
      '${directory.path}/update-preferences.json',
    ).writeAsString('{invalid');
    expect(await preferences.loadAutoCheck(), isFalse);
  });
}
