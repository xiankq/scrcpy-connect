import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// 已按受控清单核验的 Android 可执行产物。
final class BundledServerFiles {
  BundledServerFiles._(Map<String, Uint8List> artifacts)
    : scrcpyBytes = artifacts['scrcpy']!.asUnmodifiableView(),
      companionBytes = artifacts['companion']!.asUnmodifiableView(),
      helperArtifacts = Map.unmodifiable({
        for (final entry in artifacts.entries)
          if (entry.key != 'scrcpy' && entry.key != 'companion')
            entry.key: entry.value.asUnmodifiableView(),
      });

  final Uint8List scrcpyBytes;
  final Uint8List companionBytes;
  final Map<String, Uint8List> helperArtifacts;
}

/// 核验受控 Android 产物，并还原到应用私有运行目录。
class BundledServers {
  BundledServers({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  static const _prefix = 'assets/servers/';
  static const _ids = {
    'scrcpy',
    'companion',
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  };

  Future<BundledServerFiles> prepare(Directory dataDirectory) async {
    final manifest = _manifest(
      jsonDecode(
        await _bundle.loadString('${_prefix}manifest.json', cache: false),
      ),
    );
    final directory = Directory('${dataDirectory.path}/bundled_servers');
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw const FormatException(
        'Bundled server directory is not a directory',
      );
    }
    final replacements = <String, List<int>>{};
    final artifacts = <String, Uint8List>{};
    for (final artifact in manifest) {
      final file = File('${directory.path}/${artifact.id}');
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        final cached = await artifact.readVerified(file);
        if (cached != null) {
          artifacts[artifact.id] = cached;
          continue;
        }
      }
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.notFound) {
        throw FormatException('Invalid cached bundled server: ${artifact.id}');
      }
      final data = await _bundle.load('$_prefix${artifact.id}.zlib');
      final output = _BoundedBytes(artifact.size);
      final decoder = ZLibDecoder().startChunkedConversion(output);
      decoder.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      decoder.close();
      final bytes = output.bytes.takeBytes();
      if (!artifact.matches(bytes)) {
        throw FormatException(
          'Bundled server size or SHA-256 mismatch: ${artifact.id}',
        );
      }
      replacements[artifact.id] = bytes;
      artifacts[artifact.id] = bytes;
    }
    // 发布任何替换前先核验全部必需负载。
    if (replacements.isNotEmpty) await directory.create(recursive: true);
    for (final entry in replacements.entries) {
      final staging = await directory.createTemp('.${entry.key}-');
      try {
        final file = File('${staging.path}/payload');
        await file.writeAsBytes(entry.value, flush: true);
        await file.rename('${directory.path}/${entry.key}');
      } finally {
        await staging.delete(recursive: true);
      }
    }
    // 调用方使用本次核验的字节，不再按路径重新读取可能已变化的缓存。
    return BundledServerFiles._(artifacts);
  }

  List<_Artifact> _manifest(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['artifacts'] is! List) {
      throw const FormatException('Invalid bundled server manifest');
    }
    final artifacts = <_Artifact>[];
    final seen = <String>{};
    for (final item in value['artifacts'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid bundled server artifact');
      }
      final id = item['id'];
      final size = item['size'];
      final hash = item['sha256'];
      if (id is! String ||
          !_ids.contains(id) ||
          !seen.add(id) ||
          item['file'] != '$id.zlib' ||
          size is! int ||
          size <= 0 ||
          size > 16 * 1024 * 1024 ||
          hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw const FormatException('Invalid bundled server artifact fields');
      }
      artifacts.add(_Artifact(id, size, hash));
    }
    if (seen.length != _ids.length) {
      throw const FormatException('Missing bundled server artifacts');
    }
    return artifacts;
  }
}

class _BoundedBytes implements Sink<List<int>> {
  _BoundedBytes(this.limit);

  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('Bundled server exceeds its declared size');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

class _Artifact {
  const _Artifact(this.id, this.size, this.hash);

  final String id;
  final int size;
  final String hash;

  bool matches(List<int> bytes) =>
      bytes.length == size && sha256.convert(bytes).toString() == hash;

  Future<Uint8List?> readVerified(File file) async {
    if (await file.length() != size) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > size) return null;
      bytes.add(chunk);
    }
    final contents = bytes.takeBytes();
    return matches(contents) ? contents : null;
  }
}
