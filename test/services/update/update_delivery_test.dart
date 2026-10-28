import 'dart:convert';
import 'dart:io';

import 'package:best_todo_list/services/update/update_delivery.dart';
import 'package:best_todo_list/services/update/update_manifest.dart';
import 'package:best_todo_list/services/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  late SimpleKeyPair key;
  late String publicKey;
  late List<int> package;
  late String envelope;
  late ReleaseInfo release;
  const packageUrl =
      'https://github.com/lmyybh/best_todo_list/releases/download/v2.0.0/setup.exe';

  Future<String> sign(Map<String, dynamic> data) async {
    final payload = utf8.encode(jsonEncode(data));
    return jsonEncode({
      'payload': base64Encode(payload),
      'signature': base64Encode(
        (await Ed25519().sign(payload, keyPair: key)).bytes,
      ),
    });
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('todo-update-test-');
    key = await Ed25519().newKeyPair();
    publicKey = base64Encode((await key.extractPublicKey()).bytes);
    package = utf8.encode('signed installer fixture');
    envelope = await sign({
      'version': '2.0.0',
      'platform': 'windows',
      'url': packageUrl,
      'length': package.length,
      'sha256': sha256.convert(package).toString(),
    });
    release = ReleaseInfo(
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
  });
  tearDown(() async => directory.delete(recursive: true));

  SignedUpdateDelivery delivery({
    List<int>? downloaded,
    Future<void> Function(File)? launch,
  }) => SignedUpdateDelivery(
    platform: 'windows',
    publicKey: publicKey,
    directory: () async => directory,
    launchInstaller: launch ?? (_) async {},
    clientFactory: () => MockClient(
      (request) async => request.url.toString() == packageUrl
          ? http.Response.bytes(downloaded ?? package, 200)
          : http.Response(envelope, 200),
    ),
  );

  test('下载验签后报告真实进度，重启可恢复并在安装前再次校验', () async {
    var verified = false;
    var bytes = 0;
    final updater = delivery();
    final file = await updater.download(
      release,
      onProgress: (received, total) {
        bytes = received;
        expect(total, package.length);
      },
      onVerifying: () => verified = true,
    );
    expect(bytes, package.length);
    expect(verified, isTrue);
    expect(await file.readAsBytes(), package);

    final restored = await delivery().restore(
      const AppVersion(version: '1.0.0'),
    );
    expect(restored?.release.version.toString(), 'v2.0.0');
    var launched = false;
    final installer = delivery(launch: (_) async => launched = true);
    await installer.install(restored!);
    expect(launched, isTrue);

    await file.writeAsString('corrupted');
    launched = false;
    await expectLater(
      installer.install(restored),
      throwsA(isA<UpdateCheckException>()),
    );
    expect(launched, isFalse);
  });

  test('拒绝被篡改的签名，不生成可安装缓存', () async {
    final data = jsonDecode(envelope) as Map<String, dynamic>;
    data['payload'] = base64Encode(utf8.encode('{}'));
    envelope = jsonEncode(data);
    await expectLater(
      delivery().download(release, onProgress: (_, _) {}, onVerifying: () {}),
      throwsA(isA<UpdateCheckException>()),
    );
    expect(await File('${directory.path}/ready.json').exists(), isFalse);
  });

  test('拒绝长度正确但内容被篡改的安装包，并清理半成品', () async {
    await expectLater(
      delivery(
        downloaded: List.filled(package.length, 0),
      ).download(release, onProgress: (_, _) {}, onVerifying: () {}),
      throwsA(isA<UpdateCheckException>()),
    );
    expect(await File('${directory.path}/download.part').exists(), isFalse);
    expect(
      await delivery().restore(const AppVersion(version: '1.0.0')),
      isNull,
    );
  });

  test('取消下载后不留下可安装包，下一次可以重新下载', () async {
    final updater = delivery();
    await expectLater(
      updater.download(
        release,
        onProgress: (_, _) => updater.cancel(),
        onVerifying: () {},
      ),
      throwsA(isA<DownloadCancelled>()),
    );
    expect(await File('${directory.path}/ready.json').exists(), isFalse);
    expect(await File('${directory.path}/download.part').exists(), isFalse);
    final file = await updater.download(
      release,
      onProgress: (_, _) {},
      onVerifying: () {},
    );
    expect(await file.exists(), isTrue);
  });

  test('拒绝错误平台、错误版本和非仓库地址，即使签名有效', () async {
    for (final mutation in <Map<String, dynamic>>[
      {'platform': 'macos'},
      {'version': '9.0.0'},
      {'url': 'https://example.com/installer.exe'},
      {'length': -1},
      {'sha256': 'invalid'},
    ]) {
      final invalid = await sign({
        'version': '2.0.0',
        'platform': 'windows',
        'url': packageUrl,
        'length': package.length,
        'sha256': sha256.convert(package).toString(),
        ...mutation,
      });
      await expectLater(
        UpdateManifest.verify(
          invalid,
          publicKey: publicKey,
          platform: 'windows',
          version: '2.0.0',
        ),
        throwsA(isA<UpdateCheckException>()),
      );
    }
  });

  test('没有嵌入公钥时不启用自定义下载安装', () async {
    final updater = SignedUpdateDelivery(
      platform: 'windows',
      publicKey: '',
      directory: () async => directory,
      launchInstaller: (_) async {},
    );
    expect(updater.supported, isFalse);
    expect(await updater.restore(const AppVersion(version: '1.0.0')), isNull);
  });

  test('恢复上次安装失败信息；已升级后清理旧更新包', () async {
    final updater = delivery();
    final file = await updater.download(
      release,
      onProgress: (_, _) {},
      onVerifying: () {},
    );
    await File('${directory.path}/install-error.txt').writeAsString('安装未完成');
    final restored = await updater.restore(const AppVersion(version: '1.0.0'));
    expect(restored?.installationError, '安装未完成');
    expect(await updater.restore(const AppVersion(version: '2.0.0')), isNull);
    expect(await file.exists(), isFalse);
    expect(await File('${directory.path}/ready.json').exists(), isFalse);
  });
}
