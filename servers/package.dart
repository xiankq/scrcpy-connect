import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tooling.dart';

const packagedServerDirectory = 'app/assets/servers';
const _helpers = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];

/// 仅从已验证的受控输入生成共享压缩载荷。
void packageServers(Directory root, {bool check = false}) {
  final vendor = readJson(
    File(p.join(root.path, 'servers/vendor/manifest.json')),
  );
  final companion = readJson(
    File(p.join(root.path, 'servers/companion/manifest.json')),
  );
  final helpers = readJson(
    File(p.join(root.path, 'servers/helpers/manifest.json')),
  );
  final vendorArtifact = vendor['artifact'] as Map<String, dynamic>;
  final companionArtifact = companion['artifact'] as Map<String, dynamic>;
  final helperArtifacts = helpers['artifacts'] as List<dynamic>;
  require(helperArtifacts.length == _helpers.length, 'Unexpected helper count');
  final generated = <String, List<int>>{};
  final artifacts = <Map<String, Object>>[];

  void add(
    String id,
    String path,
    Map<String, dynamic> pinned,
    String sizeKey,
  ) {
    final bytes = File(p.join(root.path, path)).readAsBytesSync();
    final hash = sha256(bytes);
    require(
      bytes.length == pinned[sizeKey] && hash == pinned['sha256'],
      'Controlled artifact differs from its manifest: $path',
    );
    final name = '$id.zlib';
    generated[name] = ZLibEncoder(level: 9).convert(bytes);
    artifacts.add({
      'id': id,
      'file': name,
      'sha256': hash,
      'size': bytes.length,
    });
  }

  require(
    vendorArtifact['file'] == 'scrcpy-server-v5.0.1',
    'Unexpected vendor artifact filename',
  );
  add('scrcpy', 'servers/vendor/scrcpy-server-v5.0.1', vendorArtifact, 'bytes');
  add(
    'companion',
    'servers/companion/companion.jar',
    companionArtifact,
    'size',
  );
  for (final abi in _helpers) {
    final entries = helperArtifacts.where(
      (item) => (item as Map)['abi'] == abi,
    );
    require(entries.length == 1, 'Missing or duplicate helper manifest: $abi');
    final pinned = entries.single as Map<String, dynamic>;
    require(
      pinned['file'] == 'bin/$abi/interop-rename',
      'Unexpected helper artifact filename: $abi',
    );
    add(abi, 'servers/helpers/bin/$abi/interop-rename', pinned, 'size');
  }
  generated['manifest.json'] = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'artifacts': artifacts})}\n',
  );

  final output = Directory(p.join(root.path, packagedServerDirectory));
  final existing = output.existsSync()
      ? output.listSync(recursive: true, followLinks: false)
      : <FileSystemEntity>[];
  final unexpected = existing.where(
    (entry) => entry is! File || !generated.containsKey(p.basename(entry.path)),
  );
  if (check) {
    require(unexpected.isEmpty, 'Unexpected packaged server files');
    for (final entry in generated.entries) {
      final file = File(p.join(output.path, entry.key));
      require(
        file.existsSync() && digest(file) == sha256(entry.value),
        'Packaged server is missing or stale: ${entry.key}',
      );
    }
    stdout.writeln('PASS: shared compressed server assets');
    return;
  }
  output.createSync(recursive: true);
  for (final entry in existing.reversed) {
    if (entry.existsSync() &&
        (entry is! File || !generated.containsKey(p.basename(entry.path)))) {
      entry.deleteSync(recursive: true);
    }
  }
  for (final entry in generated.entries) {
    File(p.join(output.path, entry.key)).writeAsBytesSync(entry.value);
  }
  stdout.writeln('Generated shared compressed server assets');
}
