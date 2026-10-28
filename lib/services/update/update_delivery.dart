import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../update_service.dart';
import 'update_manifest.dart';

class PreparedUpdate {
  const PreparedUpdate(this.release, this.file, {this.installationError});
  final ReleaseInfo release;
  final File file;
  final String? installationError;
}

class DownloadCancelled implements Exception {}

class InvalidPreparedUpdate extends UpdateCheckException {
  const InvalidPreparedUpdate() : super('更新包已失效，请重新下载');
}

abstract interface class UpdateDelivery {
  bool get supported;
  Future<PreparedUpdate?> restore(AppVersion current);
  Future<File> download(
    ReleaseInfo release, {
    required void Function(int received, int total) onProgress,
    required void Function() onVerifying,
  });
  void cancel();
  Future<void> install(PreparedUpdate update);
}

class SignedUpdateDelivery implements UpdateDelivery {
  SignedUpdateDelivery({
    required this.platform,
    required this.directory,
    required this.launchInstaller,
    this.publicKey = const String.fromEnvironment('UPDATE_PUBLIC_KEY'),
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String platform;
  final String publicKey;
  final Future<Directory> Function() directory;
  final Future<void> Function(File file) launchInstaller;
  final http.Client Function() _clientFactory;
  http.Client? _activeClient;
  bool _cancelled = false;

  @override
  bool get supported =>
      publicKey.isNotEmpty && (platform == 'windows' || platform == 'macos');

  @override
  void cancel() {
    _cancelled = true;
    _activeClient?.close();
  }

  Future<UpdateManifest> _verify(String envelope, ReleaseInfo release) =>
      UpdateManifest.verify(
        envelope,
        publicKey: publicKey,
        platform: platform,
        version: release.version.toString().substring(1),
      );

  Future<bool> _validFile(File file, UpdateManifest manifest) async =>
      await file.exists() &&
      await file.length() == manifest.length &&
      (await sha256.bind(file.openRead()).first).toString() == manifest.sha256;

  @override
  Future<PreparedUpdate?> restore(AppVersion current) async {
    if (!supported) return null;
    final folder = await directory();
    final record = File('${folder.path}/ready.json');
    if (!await record.exists()) return null;
    try {
      final data =
          jsonDecode(await record.readAsString()) as Map<String, dynamic>;
      final release = ReleaseInfo.fromCache(
        data['release'] as Map<String, dynamic>,
      );
      if (!release.isNewerThan(current)) {
        await record.delete();
        final stale = _package(folder);
        if (await stale.exists()) await stale.delete();
        return null;
      }
      final manifest = await _verify(data['envelope'] as String, release);
      final file = _package(folder);
      if (await _validFile(file, manifest)) {
        final error = File('${folder.path}/install-error.txt');
        return PreparedUpdate(
          release,
          file,
          installationError: await error.exists()
              ? await error.readAsString()
              : null,
        );
      }
    } catch (_) {
      // An incomplete or invalid cache is never treated as an installable update.
    }
    await record.delete();
    return null;
  }

  File _package(Directory folder) =>
      File('${folder.path}/update.${platform == 'windows' ? 'exe' : 'zip'}');

  @override
  Future<File> download(
    ReleaseInfo release, {
    required void Function(int received, int total) onProgress,
    required void Function() onVerifying,
  }) async {
    if (!supported || release.manifestUri == null) {
      throw const UpdateCheckException('此版本尚未提供应用内更新包，请前往发布页面下载');
    }
    _cancelled = false;
    final client = _activeClient = _clientFactory();
    IOSink? sink;
    File? partial;
    try {
      final folder = await directory();
      await folder.create(recursive: true);
      final response = await client
          .get(release.manifestUri!)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const UpdateCheckException('无法读取更新签名');
      }
      final envelope = utf8.decode(response.bodyBytes);
      final manifest = await _verify(envelope, release);
      if (_cancelled) throw DownloadCancelled();
      final record = File('${folder.path}/ready.json');
      if (await record.exists()) await record.delete();
      partial = File('${folder.path}/download.part');
      sink = partial.openWrite();
      final stream = await client
          .send(http.Request('GET', manifest.url))
          .timeout(const Duration(seconds: 30));
      if (stream.statusCode != 200) throw const UpdateCheckException('更新包下载失败');
      var received = 0;
      onProgress(0, manifest.length);
      await for (final chunk in stream.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (_cancelled) throw DownloadCancelled();
        received += chunk.length;
        if (received > manifest.length) {
          throw const UpdateCheckException('更新包大小不符');
        }
        sink.add(chunk);
        // Backpressure keeps large installers out of memory.
        await sink.flush();
        onProgress(received, manifest.length);
      }
      await sink.close();
      sink = null;
      if (_cancelled) throw DownloadCancelled();
      onVerifying();
      if (!await _validFile(partial, manifest)) {
        throw const UpdateCheckException('更新包完整性校验失败，请重新下载');
      }
      if (_cancelled) throw DownloadCancelled();
      final file = _package(folder);
      if (await file.exists()) await file.delete();
      await partial.rename(file.path);
      await record.writeAsString(
        jsonEncode({'release': release.toCache(), 'envelope': envelope}),
        flush: true,
      );
      return file;
    } catch (_) {
      if (_cancelled) throw DownloadCancelled();
      rethrow;
    } finally {
      await sink?.close();
      if (partial != null && await partial.exists()) await partial.delete();
      client.close();
      _activeClient = null;
    }
  }

  @override
  Future<void> install(PreparedUpdate update) async {
    final restored = await restore(AppVersion(version: '0.0.0'));
    if (restored == null ||
        restored.release.version.toString() !=
            update.release.version.toString()) {
      throw const InvalidPreparedUpdate();
    }
    await launchInstaller(restored.file);
  }
}
