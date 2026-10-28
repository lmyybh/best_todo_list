import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:best_todo_list/services/update/update_manifest.dart';

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--generate-key') {
    final file = File(args[1]);
    if (await file.exists()) {
      throw StateError('Refusing to overwrite a signing key');
    }
    final key = await Ed25519().newKeyPair();
    await file.writeAsString(
      base64Encode(await key.extractPrivateKeyBytes()),
      flush: true,
    );
    if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
    stdout.writeln(
      'UPDATE_PUBLIC_KEY=${base64Encode((await key.extractPublicKey()).bytes)}',
    );
    stdout.writeln(
      'Private seed saved outside the repository at ${file.absolute.path}',
    );
    return;
  }
  if (args.length.isOdd || args.isEmpty) {
    throw ArgumentError(
      'Use --package PATH --platform windows|macos --version X.Y.Z '
      '--key PATH --public-key BASE64 --output PATH',
    );
  }
  final options = <String, String>{
    for (var i = 0; i < args.length; i += 2) args[i]: args[i + 1],
  };
  final package = File(options['--package']!);
  final platform = options['--platform']!;
  final version = options['--version']!;
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
      !['windows', 'macos'].contains(platform)) {
    throw ArgumentError('Invalid platform or version');
  }
  final key = await Ed25519().newKeyPairFromSeed(
    base64Decode((await File(options['--key']!).readAsString()).trim()),
  );
  final publicKey = base64Encode((await key.extractPublicKey()).bytes);
  if (publicKey != options['--public-key']) {
    throw StateError('Signing key does not match embedded public key');
  }
  final filename = package.uri.pathSegments.last;
  final payload = utf8.encode(
    jsonEncode({
      'version': version,
      'platform': platform,
      'url':
          'https://github.com/lmyybh/best_todo_list/releases/download/v$version/$filename',
      'length': await package.length(),
      'sha256': (await sha256.bind(package.openRead()).first).toString(),
    }),
  );
  final envelope = jsonEncode({
    'payload': base64Encode(payload),
    'signature': base64Encode(
      (await Ed25519().sign(payload, keyPair: key)).bytes,
    ),
  });
  await UpdateManifest.verify(
    envelope,
    publicKey: publicKey,
    platform: platform,
    version: version,
  );
  await File(options['--output']!).writeAsString(envelope, flush: true);
  stdout.writeln('Signed ${package.path}');
}
