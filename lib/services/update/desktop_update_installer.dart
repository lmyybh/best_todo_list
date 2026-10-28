import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../update_error.dart';

/// Prepares a detached helper before exiting. Helpers wait for this process and
/// never touch the user database. All dynamic values travel as arguments/JSON.
class DesktopUpdateInstaller {
  DesktopUpdateInstaller({required this.beforeQuit});
  final Future<void> Function() beforeQuit;

  Future<void> install(File package) async {
    final folder = await Directory(
      p.dirname(package.path),
    ).createTemp('install-');
    final ready = File(p.join(folder.path, 'helper-ready'));
    final error = File(p.join(p.dirname(package.path), 'install-error.txt'));
    if (await error.exists()) await error.delete();
    Process helper;
    if (Platform.isWindows) {
      final executable = Platform.resolvedExecutable;
      final local = Platform.environment['LOCALAPPDATA'];
      final target = p.join(
        local ?? '',
        'Programs',
        'BestTodoList',
        'best_todo_list.exe',
      );
      if (local == null ||
          !p.equals(
            p.normalize(executable).toLowerCase(),
            p.normalize(target).toLowerCase(),
          )) {
        throw const UpdateCheckException('请先将正式版安装到默认目录，再使用应用内更新');
      }
      final config = File(p.join(folder.path, 'install.json'));
      await config.writeAsString(
        jsonEncode({
          'pid': pid,
          'package': package.path,
          'target': executable,
          'ready': ready.path,
          'error': error.path,
        }),
        flush: true,
      );
      final script = File(p.join(folder.path, 'install.ps1'));
      await script.writeAsString(windowsUpdateHelperScript, flush: true);
      helper = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '-Config',
        config.path,
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      final app = p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
      if (!app.endsWith('.app') || app.startsWith('/Volumes/')) {
        throw const UpdateCheckException('请先将应用移至“应用程序”文件夹，再更新');
      }
      await _run('/usr/bin/ditto', ['-x', '-k', package.path, folder.path]);
      final incoming = p.join(folder.path, 'todo.app');
      await _run('/usr/bin/codesign', [
        '--verify',
        '--deep',
        '--strict',
        incoming,
      ]);
      await _run('/usr/sbin/spctl', [
        '--assess',
        '--type',
        'execute',
        incoming,
      ]);
      final oldTeam = await _team(app);
      final newTeam = await _team(incoming);
      if (oldTeam.isEmpty || oldTeam != newTeam) {
        throw const UpdateCheckException('更新包的开发者签名与当前应用不一致');
      }
      final identifier = await _run('/usr/libexec/PlistBuddy', [
        '-c',
        'Print :CFBundleIdentifier',
        p.join(incoming, 'Contents', 'Info.plist'),
      ]);
      if (identifier.trim() != 'com.besttodolist.app') {
        throw const UpdateCheckException('更新包的应用标识无效');
      }
      final staged = p.join(
        p.dirname(app),
        '.todo-update-${p.basename(folder.path)}.app',
      );
      await _run('/usr/bin/ditto', [incoming, staged]);
      final script = File(p.join(folder.path, 'install.sh'));
      await script.writeAsString(macosUpdateHelperScript, flush: true);
      helper = await Process.start('/bin/bash', [
        script.path,
        '$pid',
        app,
        staged,
        '$staged.backup',
        ready.path,
        error.path,
      ], mode: ProcessStartMode.detached);
    } else {
      throw const UpdateCheckException('当前系统不支持应用内安装');
    }
    for (var attempt = 0; attempt < 50 && !await ready.exists(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!await ready.exists()) {
      helper.kill();
      throw const UpdateCheckException('安装助手未能启动，请重试');
    }
    try {
      await beforeQuit();
    } catch (_) {
      // The helper will not install until it receives an explicit commit file.
      helper.kill();
      rethrow;
    }
    await File('${ready.path}.commit').writeAsString('install', flush: true);
    exit(0);
  }

  Future<String> _team(String app) async {
    final result = await Process.run('/usr/bin/codesign', [
      '-dv',
      '--verbose=4',
      app,
    ]);
    final match = RegExp(
      r'^TeamIdentifier=(.+)$',
      multiLine: true,
    ).firstMatch('${result.stderr}');
    final team = match?.group(1)?.trim() ?? '';
    return team == 'not set' ? '' : team;
  }

  Future<String> _run(String command, List<String> arguments) async {
    final result = await Process.run(command, arguments);
    if (result.exitCode != 0) {
      throw UpdateCheckException('安装准备失败：${result.stderr}');
    }
    return '${result.stdout}';
  }
}

const windowsUpdateHelperScript = r'''
param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference = 'Stop'
$c = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$exited = $false
try {
  Set-Content -LiteralPath $c.ready -Value 'ready'
  $committed = $false
  for ($i = 0; $i -lt 120; $i++) {
    if (Test-Path -LiteralPath ($c.ready + '.commit')) { $committed = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $committed) { exit 1 }
  $parent = Get-Process -Id $c.pid -ErrorAction SilentlyContinue
  if ($parent) { Wait-Process -Id $c.pid -Timeout 120 -ErrorAction Stop }
  $exited = $true
  $installer = Start-Process -FilePath $c.package -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/SP-', '/NORESTART',
    '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS'
  ) -PassThru -Wait
  if ($installer.ExitCode -ne 0) { throw "Installer exit code: $($installer.ExitCode)" }
} catch {
  Set-Content -LiteralPath $c.error -Value $_.Exception.Message -Encoding UTF8
} finally {
  if ($exited) { Start-Process -FilePath $c.target }
}
''';

const macosUpdateHelperScript = r'''
set -eu
parent_pid="$1"
app="$2"
staged="$3"
backup="$4"
ready="$5"
error="$6"
committed=0
moved=0
report_failure() {
  printf '%s\n' '安装未完成，已尝试恢复原版本。请重试或从发布页面下载安装。' > "$error"
  if [[ "$moved" -eq 1 && -d "$backup" ]]; then
    if [[ -d "$app" ]]; then /bin/mv "$app" "$staged.failed"; fi
    /bin/mv "$backup" "$app"
  fi
  if [[ "$committed" -eq 1 ]]; then /usr/bin/open -n "$app"; fi
}
trap report_failure ERR
printf ready > "$ready"
for ((i=0; i<120; i++)); do
  if [[ -f "$ready.commit" ]]; then committed=1; break; fi
  /bin/sleep 1
done
[[ "$committed" -eq 1 ]] || exit 1
for ((i=0; i<120; i++)); do
  if ! /bin/kill -0 "$parent_pid" 2>/dev/null; then break; fi
  /bin/sleep 1
done
if /bin/kill -0 "$parent_pid" 2>/dev/null; then exit 1; fi
/bin/mv "$app" "$backup"
moved=1
/bin/mv "$staged" "$app"
/usr/bin/open -n "$app"
trap - ERR
# Keep the previous bundle for recovery; never delete user files here.
''';
