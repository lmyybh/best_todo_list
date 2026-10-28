import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../update_error.dart';

/// The signature covers the original payload bytes, not re-encoded JSON.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.platform,
    required this.url,
    required this.length,
    required this.sha256,
  });

  final String version;
  final String platform;
  final Uri url;
  final int length;
  final String sha256;

  static Future<UpdateManifest> verify(
    String envelope, {
    required String publicKey,
    required String platform,
    required String version,
  }) async {
    final json = jsonDecode(envelope) as Map<String, dynamic>;
    final payload = base64Decode(json['payload'] as String);
    final valid = await Ed25519().verify(
      payload,
      signature: Signature(
        base64Decode(json['signature'] as String),
        publicKey: SimplePublicKey(
          base64Decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const UpdateCheckException('更新签名验证失败');
    final data = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    final url = Uri.parse(data['url'] as String);
    final length = data['length'] as int;
    final hash = data['sha256'] as String;
    if (data['version'] != version ||
        data['platform'] != platform ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith(
          '/lmyybh/best_todo_list/releases/download/v$version/',
        ) ||
        url.hasQuery ||
        url.hasFragment ||
        url.userInfo.isNotEmpty ||
        length <= 0 ||
        length > 2147483648 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const UpdateCheckException('更新包版本、平台或下载信息无效');
    }
    return UpdateManifest(
      version: version,
      platform: platform,
      url: url,
      length: length,
      sha256: hash,
    );
  }
}
