import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../packaged_servers.dart';

/// ZIP payload sizes; expanded bytes exclude Android runtime installation overhead.
final class ApkInspection {
  ApkInspection({
    required this.abis,
    required this.bytes,
    required this.compressedEntryBytes,
    required this.expandedEntryBytes,
    required this.sections,
  });

  final List<String> abis;
  final int bytes;
  final int compressedEntryBytes;
  final int expandedEntryBytes;
  final Map<String, ({int compressed, int expanded})> sections;

  Map<String, Object> toJson() => {
    'compressedEntryBytes': compressedEntryBytes,
    'expandedEntryBytes': expandedEntryBytes,
    'archiveOverheadBytes': bytes - compressedEntryBytes,
    'sections': {
      for (final entry in sections.entries)
        entry.key: {
          'compressedBytes': entry.value.compressed,
          'expandedBytes': entry.value.expanded,
        },
    },
  };
}

/// 调用 SDK 工具前校验归档；保留独立入口，便于在没有 SDK 时拒绝损坏的原生库。
ApkInspection inspectApk(
  List<int> bytes, {
  required Directory repository,
  List<String>? expectedAbis,
}) {
  final decoder = ZipDecoder();
  final archive = decoder.decodeBytes(bytes, verify: true);
  // archive 4 的 decodeBytes(verify: true) 不校验条目 CRC；在 archive.files 隐藏同名条目前检查原始目录，同时核验解压字节及中央目录/本地头的 CRC。
  final names = <String>{};
  for (final header in decoder.directory.fileHeaders) {
    if (!names.add(header.filename)) {
      throw StateError('Duplicate APK entry: ${header.filename}');
    }
    final file = header.file;
    if (file == null || header.crc32 != file.crc32 || !file.verifyCrc32()) {
      throw StateError('Corrupt APK entry: ${header.filename}');
    }
  }
  final entries = {for (final entry in archive.files) entry.name: entry};
  if (entries.keys.any(
    (name) => p.posix.basename(name) == 'libinterop_bridge.so',
  )) {
    throw StateError('APK contains the removed application bridge');
  }
  for (final required in [
    'AndroidManifest.xml',
    'classes.dex',
    'resources.arsc',
  ]) {
    if (!entries.containsKey(required)) {
      throw StateError(
        'APK lacks $required; use the final APK, not an intermediate ZIP.',
      );
    }
  }
  final abis =
      entries.keys
          .where((name) => name.startsWith('lib/') && name.endsWith('.so'))
          .map((name) => name.split('/')[1])
          .toSet()
          .toList()
        ..sort();
  if (abis.isEmpty) {
    throw StateError('APK lacks native libraries for any supported ABI.');
  }
  if (expectedAbis != null &&
      (abis.length != expectedAbis.toSet().length ||
          !abis.toSet().containsAll(expectedAbis))) {
    throw StateError('APK ABIs $abis differ from requested $expectedAbis.');
  }
  const headers = {
    'armeabi-v7a': (1, 40),
    'arm64-v8a': (2, 183),
    'x86_64': (2, 62),
  };
  for (final abi in abis) {
    final expected = headers[abi];
    if (expected == null) {
      throw StateError('Unsupported packaged native architecture: $abi');
    }
    for (final library in [
      'libflutter.so',
      'libapp.so',
      'libinterop_scrcpy_bridge.so',
      'libmedia_codec_plugin.so',
      'libc++_shared.so',
    ]) {
      final name = 'lib/$abi/$library';
      if (library == 'libapp.so' && !entries.containsKey(name)) {
        if (entries.containsKey('assets/flutter_assets/kernel_blob.bin')) {
          continue;
        }
        throw StateError('Release APK lacks its Dart AOT library: $name');
      }
      if (!entries.containsKey(name)) {
        throw StateError('APK lacks required native library: $name');
      }
    }
    for (final entry in entries.entries.where(
      (entry) => entry.key.startsWith('lib/$abi/') && entry.key.endsWith('.so'),
    )) {
      final name = entry.key;
      final header = entry.value.content.take(20).toList();
      if (header.length != 20 ||
          header[0] != 0x7f ||
          header[1] != 0x45 ||
          header[2] != 0x4c ||
          header[3] != 0x46 ||
          header[4] != expected.$1 ||
          header[5] != 1 ||
          (header[18] | header[19] << 8) != expected.$2) {
        throw StateError('Invalid packaged native architecture: $name');
      }
    }
  }
  final debug = entries.containsKey('assets/flutter_assets/kernel_blob.bin');
  if (!debug &&
      abis.any(
        (abi) => entries.containsKey('lib/$abi/libinterop_adb_bridge.so'),
      )) {
    throw StateError(
      'Release APK duplicates ADB in standalone and composed scrcpy libraries',
    );
  }
  verifyPackagedServers(archive, repository);
  final sections = <String, ({int compressed, int expanded})>{};
  var compressed = 0;
  var expanded = 0;
  for (final header in decoder.directory.fileHeaders) {
    final parts = header.filename.split('/');
    final section = parts.first == 'lib' && parts.length > 2
        ? 'lib/${parts[1]}'
        : parts.first;
    final previous = sections[section] ?? (compressed: 0, expanded: 0);
    sections[section] = (
      compressed: previous.compressed + header.compressedSize,
      expanded: previous.expanded + header.uncompressedSize,
    );
    compressed += header.compressedSize;
    expanded += header.uncompressedSize;
  }
  return ApkInspection(
    abis: abis,
    bytes: bytes.length,
    compressedEntryBytes: compressed,
    expandedEntryBytes: expanded,
    sections: sections,
  );
}
