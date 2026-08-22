import 'package:best_todo_list/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('VersionNumber', () {
    test('比较正式语义版本', () {
      expect(
        VersionNumber.parse('v0.2.0').compareTo(VersionNumber.parse('0.1.9')),
        greaterThan(0),
      );
      expect(
        VersionNumber.parse('1.0.0').compareTo(VersionNumber.parse('1.0.0')),
        0,
      );
      expect(() => VersionNumber.parse('v1.0.0-beta'), throwsFormatException);
    });
  });

  group('GitHubUpdateService', () {
    test('解析最新正式 Release', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/lmyybh/best_todo_list/releases/latest',
        );
        expect(request.headers['Accept'], 'application/vnd.github+json');
        return http.Response(
          '''{
            "tag_name": "v0.2.0",
            "name": "Version 0.2.0",
            "body": "支持手动更新检查",
            "html_url": "https://github.com/lmyybh/best_todo_list/releases/tag/v0.2.0"
          }''',
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final release = await GitHubUpdateService(client).fetchLatestRelease();

      expect(release, isNotNull);
      expect(release!.version.toString(), '0.2.0');
      expect(release.name, 'Version 0.2.0');
      expect(release.notes, '支持手动更新检查');
      expect(
        release.isNewerThan(
          const AppVersion(version: '0.1.0', buildNumber: '1'),
        ),
        isTrue,
      );
    });

    test('仓库尚无 Release 时返回空结果', () async {
      final client = MockClient((_) async => http.Response('', 404));

      final release = await GitHubUpdateService(client).fetchLatestRelease();

      expect(release, isNull);
    });

    test('GitHub 服务异常时抛出可展示错误', () async {
      final client = MockClient((_) async => http.Response('', 503));

      expect(
        GitHubUpdateService(client).fetchLatestRelease(),
        throwsA(
          isA<UpdateCheckException>().having(
            (error) => error.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });
  });
}
