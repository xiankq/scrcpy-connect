import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
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
    File(p.join(root.path, 'build.dart')),
    File(p.join(root.path, 'build.sh')),
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
    'Companion sources or build tools changed; rebuild servers/companion/build.dart',
  );
  final jar = File(p.join(root.path, 'companion.jar'));
  require(
    sameJson(manifest['artifact'], {
      'sha256': digest(jar),
      'size': jar.lengthSync(),
    }),
    'Companion JAR differs from its build manifest',
  );
}

Future<void> build(File destination, {Directory? sourceRoot}) async {
  final root =
      sourceRoot ??
      Directory(p.join(repositoryRoot().path, 'servers', 'companion'));
  final sdk = androidSdk();
  final javac = javaTool('javac');
  final version = await run(javac, ['-version']);
  require(
    '${version.stdout}${version.stderr}'.startsWith('javac 21.'),
    'JDK 21 is required for reproducible companion bytecode',
  );
  await withTemporary('companion-', (work) async {
    final classes = Directory(p.join(work.path, 'classes'))..createSync();
    final dex = Directory(p.join(work.path, 'dex'))..createSync();
    final android = p.join(sdk.path, 'platforms', 'android-36', 'android.jar');
    await run(javac, [
      '--release',
      '8',
      '-encoding',
      'UTF-8',
      '-cp',
      android,
      '-d',
      classes.path,
      ...files(
        Directory(p.join(root.path, 'src')),
        '.java',
      ).map((file) => file.path),
    ], echo: true);
    await run(
      p.join(
        sdk.path,
        'build-tools',
        '37.0.0',
        Platform.isWindows ? 'd8.bat' : 'd8',
      ),
      [
        '--min-api',
        '21',
        '--lib',
        android,
        '--output',
        dex.path,
        ...files(classes, '.class').map((file) => file.path),
      ],
      echo: true,
    );
    final bytes = storedZip(
      {
        'META-INF/': <int>[],
        'META-INF/MANIFEST.MF': utf8.encode(
          'Manifest-Version: 1.0\r\nCreated-By: 21 (Interop companion)\r\n\r\n',
        ),
        'classes.dex': File(p.join(dex.path, 'classes.dex')).readAsBytesSync(),
      },
      date: DateTime.utc(2026, 10, 16),
      system: 0,
      attributes: (name) => name.endsWith('/') ? 0x10 : 0x20,
    );
    await destination.writeAsBytes(bytes);
  });
}

Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addFlag('check', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  require(options.rest.isEmpty, 'Unexpected positional arguments');
  if (options['help'] as bool) {
    stdout.writeln(
      'Build the companion DEX JAR deterministically.\n${parser.usage}',
    );
    return;
  }
  final root = Directory(p.join(repositoryRoot().path, 'servers', 'companion'));
  final check = options['check'] as bool;
  if (check) await verifyManifest(root);
  await withTemporary('companion-output-', (work) async {
    final candidate = File(p.join(work.path, 'companion.jar'));
    await build(candidate, sourceRoot: root);
    final jar = File(p.join(root.path, 'companion.jar'));
    if (check) {
      require(
        digest(candidate) == digest(jar) &&
            candidate.lengthSync() == jar.lengthSync(),
        'Companion JAR is stale; run dart servers/companion/build.dart',
      );
      stdout.writeln(
        'PASS: companion source manifest and deterministic DEX JAR',
      );
    } else {
      await candidate.copy(jar.path);
      writeJson(File(p.join(root.path, 'manifest.json')), {
        'tools': tools,
        'sources': inputs(root),
        'artifact': {
          'sha256': digest(candidate),
          'size': candidate.lengthSync(),
        },
      });
    }
  });
});
