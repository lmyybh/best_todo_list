import 'dart:convert';
import 'dart:io';

import 'package:best_todo_list/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final external in [false, true]) {
    test('GitHub 更新源${external ? '忽略外部清单地址' : '选取当前平台的签名清单'}', () async {
      final platform = Platform.isWindows ? 'windows' : 'macos';
      final manifest = external
          ? 'https://example.com/update.json'
          : 'https://github.com/lmyybh/best_todo_list/releases/download/v2.0.0/update-$platform.json';
      final service = GitHubUpdateService(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v2.0.0',
              'html_url':
                  'https://github.com/lmyybh/best_todo_list/releases/tag/v2.0.0',
              'assets': [
                {
                  'name': 'update-$platform.json',
                  'browser_download_url': manifest,
                },
              ],
            }),
            200,
          ),
        ),
      );
      final release = await service.fetchLatestRelease();
      expect(release?.manifestUri, external ? isNull : Uri.parse(manifest));
    });
  }
}
