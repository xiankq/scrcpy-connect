import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../tooling.dart';

const tools = <String, Object>{
  'androidPlatform': '36',
  'buildTools': '37.0.0',
  'javaRelease': 8,
  'minApi': 21,
};

Map<String, String> inputs(Directory root) {
  final paths = [
    File(p.join(root.parent.path, 'tooling.dart')),
    File(p.join(root.parent.path, 'build.dart')),
    File(p.join(root.path, '../../scripts/src/repository_tooling.dart')),
    File(p.join(root.path, '../../scripts/src/process.dart')),
    File(p.join(root.path, 'build.dart')),
    ...files(Directory(p.join(root.path, 'src')), '.java'),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return {
    for (final file in paths) relative(file.path, root.path): digest(file),
  };
}

/// [root] 是协同助手目录，包含清单、源码与 JAR。
Future<void> verifyManifest(Directory root) async {
  final manifest = readJson(File(p.join(root.path, 'manifest.json')));
  require(
    sameJson(manifest['tools'], tools) &&
        sameJson(manifest['sources'], inputs(root)),
    'Companion sources or build tools changed; run dart servers/build.dart --update companion',
  );
  final jar = File(p.join(root.path, 'companion.jar'));
  require(
    sameJson(manifest['artifact'], artifactDigest(jar)),
    'Companion JAR differs from its build manifest',
  );
}

Future<void> build(File destination, {Directory? sourceRoot}) async {
  final root =
      sourceRoot ??
      Directory(p.join(repositoryRoot().path, 'servers', 'companion'));
  final sdk = androidSdk();
  await withTemporary('companion-', (work) async {
    final classes = await compileJava(
      work: work,
      sources: files(Directory(p.join(root.path, 'src')), '.java'),
      sdk: sdk,
    );
    final dex = await compileDex(work: work, classes: classes, sdk: sdk);
    final bytes = storedZip(
      {
        'META-INF/': <int>[],
        'META-INF/MANIFEST.MF': utf8.encode(
          'Manifest-Version: 1.0\r\nCreated-By: 21 (Interop companion)\r\n\r\n',
        ),
        'classes.dex': dex,
      },
      date: DateTime.utc(2026, 10, 16),
      system: 0,
      attributes: (name) => name.endsWith('/') ? 0x10 : 0x20,
    );
    await destination.writeAsBytes(bytes);
  });
}

Future<void> update(Directory repository, {bool compare = false}) async {
  final root = Directory(p.join(repository.path, 'servers', 'companion'));
  await withTemporary('companion-output-', (work) async {
    final candidate = File(p.join(work.path, 'companion.jar'));
    await build(candidate, sourceRoot: root);
    final jar = File(p.join(root.path, 'companion.jar'));
    if (compare) {
      verifySameFile(
        candidate,
        jar,
        'Companion JAR is stale; run dart servers/build.dart --update companion',
      );
      stdout.writeln(
        'PASS: rebuilt companion DEX JAR is byte-for-byte identical',
      );
    } else {
      await candidate.copy(jar.path);
      writeJson(File(p.join(root.path, 'manifest.json')), {
        'tools': tools,
        'sources': inputs(root),
        'artifact': artifactDigest(candidate),
      });
    }
  });
}
