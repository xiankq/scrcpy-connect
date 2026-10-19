import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' hide ZLibDecoder;
import 'package:crypto/crypto.dart';

/// Checks the deliverable rather than trusting the source asset declarations.
void verifyPackagedServers(Archive apk, Directory repository) {
  const prefix =
      'assets/flutter_assets/packages/interop_bridge/assets/servers/';
  final source = Directory(
    '${repository.path}/packages/interop_bridge/assets/servers',
  );
  final manifestBytes = File('${source.path}/manifest.json').readAsBytesSync();
  final manifest =
      jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  final artifacts = (manifest['artifacts'] as List)
      .cast<Map<String, dynamic>>();
  final expected = {
    '${prefix}manifest.json',
    for (final artifact in artifacts) '$prefix${artifact['file']}',
  };
  final packaged = apk.files.where((entry) => entry.name.startsWith(prefix));
  if (packaged.length != expected.length ||
      !packaged.map((entry) => entry.name).toSet().containsAll(expected)) {
    throw StateError(
      'APK must contain exactly one shared server asset bundle.',
    );
  }
  final entries = {for (final entry in packaged) entry.name: entry};
  if (sha256.convert(entries['${prefix}manifest.json']!.content as List<int>) !=
      sha256.convert(manifestBytes)) {
    throw StateError('APK shared server manifest differs from this build.');
  }
  final embeddedPatterns = <String>[];
  for (final artifact in artifacts) {
    final compressed =
        entries['$prefix${artifact['file']}']!.content as List<int>;
    if (sha256.convert(compressed) !=
        sha256.convert(
          File('${source.path}/${artifact['file']}').readAsBytesSync(),
        )) {
      throw StateError('APK shared server asset differs: ${artifact['id']}');
    }
    final bytes = ZLibDecoder().convert(compressed);
    if (bytes.length != artifact['size'] ||
        sha256.convert(bytes).toString() != artifact['sha256']) {
      throw StateError('APK shared server asset is invalid: ${artifact['id']}');
    }
    embeddedPatterns.addAll([latin1.decode(bytes), latin1.decode(compressed)]);
  }
  for (final library in apk.files.where(
    (entry) => entry.name.endsWith('/libinterop_bridge.so'),
  )) {
    final bytes = latin1.decode(library.content as List<int>);
    if (embeddedPatterns.any(bytes.contains)) {
      throw StateError(
        'Android Rust library duplicates server assets: ${library.name}',
      );
    }
  }
}
