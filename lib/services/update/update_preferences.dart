import 'dart:convert';
import 'dart:io';

class UpdatePreferences {
  UpdatePreferences(this.directory);

  final Future<Directory> Function() directory;

  Future<bool> loadAutoCheck() async {
    final file = File('${(await directory()).path}/update-preferences.json');
    if (!await file.exists()) return false;
    try {
      return (jsonDecode(await file.readAsString()) as Map)['autoCheck'] ==
          true;
    } on FormatException {
      return false;
    }
  }

  Future<void> saveAutoCheck(bool enabled) async {
    final folder = await directory();
    await folder.create(recursive: true);
    final file = File('${folder.path}/update-preferences.json');
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'autoCheck': enabled}),
      flush: true,
    );
    // Windows cannot rename over an existing file.
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
