import 'dart:async';
import 'dart:io';
import 'package:best_todo_list/services/update/update_delivery.dart';
import 'package:best_todo_list/services/update_service.dart';

final release = ReleaseInfo(
  version: VersionNumber.parse('2.0.0'),
  name: 'Version 2.0.0',
  notes: 'Changes',
  pageUri: Uri.parse(
    'https://github.com/lmyybh/best_todo_list/releases/tag/v2.0.0',
  ),
  manifestUri: Uri.parse(
    'https://github.com/lmyybh/best_todo_list/releases/download/v2.0.0/update-windows.json',
  ),
);

class FakeService implements UpdateService {
  int checkCount = 0;
  int versionReads = 0;
  Object? error;
  Completer<ReleaseInfo?>? pending;
  @override
  Future<AppVersion> loadCurrentVersion() async {
    versionReads++;
    return const AppVersion(version: '1.0.0');
  }

  @override
  Future<ReleaseInfo?> fetchLatestRelease() async {
    checkCount++;
    if (pending != null) return pending!.future;
    if (error != null) throw error!;
    return release;
  }

  @override
  Future<bool> openReleasePage(Uri uri) async => true;
}

class FakeDelivery implements UpdateDelivery {
  PreparedUpdate? cached;
  Completer<File> downloaded = Completer<File>();
  late void Function(int, int) progress;
  late void Function() verifying;
  int installCount = 0;
  Object? installError;
  bool started = false;
  @override
  bool get supported => true;
  @override
  Future<PreparedUpdate?> restore(AppVersion current) async => cached;
  @override
  Future<File> download(
    ReleaseInfo release, {
    required void Function(int received, int total) onProgress,
    required void Function() onVerifying,
  }) {
    started = true;
    downloaded = Completer<File>();
    progress = onProgress;
    verifying = onVerifying;
    return downloaded.future;
  }

  @override
  void cancel() {
    if (started && !downloaded.isCompleted) {
      downloaded.completeError(DownloadCancelled());
    }
  }

  @override
  Future<void> install(PreparedUpdate update) async {
    installCount++;
    if (installError != null) throw installError!;
  }
}
