import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _latestReleaseUri =
    'https://api.github.com/repos/lmyybh/best_todo_list/releases/latest';

abstract interface class UpdateService {
  Future<AppVersion> loadCurrentVersion();

  Future<ReleaseInfo?> fetchLatestRelease();

  Future<bool> openReleasePage(Uri uri);
}

class GitHubUpdateService implements UpdateService {
  GitHubUpdateService([this._client]);

  final http.Client? _client;

  @override
  Future<AppVersion> loadCurrentVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppVersion(version: packageInfo.version);
  }

  @override
  Future<ReleaseInfo?> fetchLatestRelease() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(_latestReleaseUri),
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'best-todo-list-update-checker',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw UpdateCheckException('GitHub 返回状态码 ${response.statusCode}');
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) {
        throw const UpdateCheckException('GitHub 返回了无效数据');
      }
      final tagName = body['tag_name'];
      final pageUrl = body['html_url'];
      if (tagName is! String || pageUrl is! String) {
        throw const UpdateCheckException('GitHub Release 缺少版本或下载地址');
      }
      final uri = Uri.tryParse(pageUrl);
      if (uri == null || uri.scheme != 'https') {
        throw const UpdateCheckException('GitHub Release 下载地址无效');
      }

      return ReleaseInfo(
        version: VersionNumber.parse(tagName),
        name: body['name'] is String && (body['name'] as String).isNotEmpty
            ? body['name'] as String
            : tagName,
        notes: body['body'] is String ? body['body'] as String : '',
        pageUri: uri,
      );
    } on UpdateCheckException {
      rethrow;
    } on FormatException catch (error) {
      throw UpdateCheckException(error.message);
    } catch (error) {
      throw UpdateCheckException('无法连接 GitHub：$error');
    } finally {
      if (_client == null) client.close();
    }
  }

  @override
  Future<bool> openReleasePage(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class AppVersion {
  const AppVersion({required this.version});

  final String version;

  VersionNumber get number => VersionNumber.parse(version);

  String get display => 'v$version';
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUri,
  });

  final VersionNumber version;
  final String name;
  final String notes;
  final Uri pageUri;

  bool isNewerThan(AppVersion current) => version.compareTo(current.number) > 0;
}

class VersionNumber implements Comparable<VersionNumber> {
  const VersionNumber(this.major, this.minor, this.patch);

  factory VersionNumber.parse(String value) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(value.trim());
    if (match == null) throw FormatException('无法识别版本号：$value');
    return VersionNumber(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(VersionNumber other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => 'v$major.$minor.$patch';
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}
