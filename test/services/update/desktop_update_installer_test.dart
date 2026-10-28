import 'dart:io';

import 'package:best_todo_list/services/update/desktop_update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fail in [false, true]) {
    test('macOS 安装助手${fail ? '替换失败恢复旧包' : '成功替换并保留旧包'}', () async {
      final folder = await Directory.systemTemp.createTemp(
        'todo-installer-helper-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final app = Directory('${folder.path}/app with spaces and \$().app');
      final staged = Directory('${folder.path}/staged.app');
      final backup = Directory('${folder.path}/backup.app');
      await app.create();
      await File('${app.path}/version').writeAsString('old');
      if (!fail) {
        await staged.create();
        await File('${staged.path}/version').writeAsString('new');
      }
      final opened = File('${folder.path}/opened');
      final openStub = File('${folder.path}/open');
      await openStub.writeAsString(
        '#!/bin/sh\nprintf opened > "${opened.path}"\n',
      );
      await Process.run('/bin/chmod', ['+x', openStub.path]);
      final script = File('${folder.path}/helper.sh');
      await script.writeAsString(
        macosUpdateHelperScript.replaceAll(
          '/usr/bin/open',
          '"${openStub.path}"',
        ),
      );
      final ready = File('${folder.path}/ready');
      await File('${ready.path}.commit').writeAsString('install');
      final result = await Process.run('/bin/bash', [
        script.path,
        '99999999',
        app.path,
        staged.path,
        backup.path,
        ready.path,
        '${folder.path}/error',
      ]);
      expect(
        await File('${app.path}/version').readAsString(),
        fail ? 'old' : 'new',
      );
      expect(await opened.exists(), isTrue);
      if (fail) {
        expect(result.exitCode, isNot(0));
        expect(await File('${folder.path}/error').exists(), isTrue);
      } else {
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await File('${backup.path}/version').readAsString(), 'old');
      }
    }, skip: Platform.isWindows);
  }

  test('安装助手在旧进程退出前不替换应用', () async {
    final folder = await Directory.systemTemp.createTemp(
      'todo-installer-wait-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final app = Directory('${folder.path}/app.app');
    final staged = Directory('${folder.path}/staged.app');
    await app.create();
    await staged.create();
    await File('${app.path}/version').writeAsString('old');
    await File('${staged.path}/version').writeAsString('new');
    final parent = await Process.start('/bin/sleep', ['30']);
    addTearDown(parent.kill);
    final script = File('${folder.path}/helper.sh');
    await script.writeAsString(
      macosUpdateHelperScript.replaceAll('/usr/bin/open', '/usr/bin/true'),
    );
    final ready = File('${folder.path}/ready');
    await File('${ready.path}.commit').writeAsString('install');
    final helper = await Process.start('/bin/bash', [
      script.path,
      '${parent.pid}',
      app.path,
      staged.path,
      '${folder.path}/backup.app',
      ready.path,
      '${folder.path}/error',
    ]);
    addTearDown(helper.kill);
    for (var i = 0; i < 100 && !await ready.exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await ready.exists(), isTrue);
    expect(await File('${app.path}/version').readAsString(), 'old');
    parent.kill();
    await parent.exitCode;
    expect(await helper.exitCode, 0);
    expect(await File('${app.path}/version').readAsString(), 'new');
  }, skip: Platform.isWindows);

  test('Windows 安装助手 PowerShell 语法有效', () async {
    final folder = await Directory.systemTemp.createTemp(
      'todo-installer-powershell-',
    );
    addTearDown(() => folder.delete(recursive: true));
    final script = File('${folder.path}/helper.ps1');
    await script.writeAsString(windowsUpdateHelperScript);
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$tokens = $null; $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($env:TODO_UPDATE_TEST_SCRIPT, [ref]$tokens, [ref]$errors); if ($errors.Count) { $errors; exit 1 }',
      ],
      environment: {'TODO_UPDATE_TEST_SCRIPT': script.path},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: !Platform.isWindows);
}
