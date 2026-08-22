import 'package:auto_updater/auto_updater.dart';

class WindowsUpdateInstaller {
  static const String feedUrl =
      'https://github.com/lmyybh/best_todo_list/releases/latest/download/'
      'appcast-windows.xml';

  Future<void> checkForUpdates() async {
    await autoUpdater.setFeedURL(feedUrl);
    await autoUpdater.checkForUpdates();
  }
}
