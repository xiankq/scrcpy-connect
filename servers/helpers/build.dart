import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../tooling.dart';

const targets = <String, (String, String)>{
  'arm64-v8a': ('aarch64-linux-android', 'aarch64-linux-android21-clang'),
  'armeabi-v7a': (
    'armv7-linux-androideabi',
    'armv7a-linux-androideabi21-clang',
  ),
  'x86_64': ('x86_64-linux-android', 'x86_64-linux-android21-clang'),
  'x86': ('i686-linux-android', 'i686-linux-android21-clang'),
};

Map<String, String> inputs(Directory root) => {
  for (final name in [
    'rust/adb/device_fs_helper/Cargo.toml',
    'rust/adb/device_fs_helper/Cargo.lock',
    'rust/adb/device_fs_helper/src/main.rs',
    'servers/helpers/build.dart',
    'servers/tooling.dart',
  ])
    name: digest(File(p.join(root.path, name))),
};

void check(Directory root) {
  final here = Directory(p.join(root.path, 'servers', 'helpers'));
  final manifest = readJson(File(p.join(here.path, 'manifest.json')));
  require(
    manifest['protocol'] == 1 &&
        manifest['rust'] == '1.99.1' &&
        manifest['ndk'] == '30.0.16248370' &&
        manifest['minAndroidApi'] == 21,
    'Android helper toolchain/protocol pin mismatch',
  );
  require(
    sameJson(manifest['sources'], inputs(root)),
    'Android helper sources/build tools changed; rebuild helpers',
  );
  final outputs = manifest['artifacts'] as List<dynamic>;
  require(
    outputs.length == targets.length,
    'Expected all four Android helper ABIs',
  );
  for (final entry in targets.entries) {
    final matching = outputs
        .cast<Map<String, dynamic>>()
        .where((value) => value['abi'] == entry.key)
        .toList();
    require(matching.length == 1, 'Missing/duplicate helper ABI: ${entry.key}');
    final output = matching.single;
    final name = 'bin/${entry.key}/interop-rename';
    final file = File(p.join(here.path, name));
    require(
      output['target'] == entry.value.$1 &&
          output['file'] == name &&
          output['sha256'] == digest(file) &&
          output['size'] == file.lengthSync(),
      'Android helper artifact mismatch: ${entry.key}',
    );
  }
  stdout.writeln(
    'PASS: Android helper sources, toolchain and all four artifact hashes',
  );
}

Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addFlag('check', negatable: false)
    ..addFlag(
      'rebuild',
      negatable: false,
      help: 'Build all ABIs and compare without changing artifacts',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    stdout.writeln(
      'Rebuild Android helpers with pinned Rust/NDK.\n${parser.usage}',
    );
    return;
  }
  require(
    options.rest.isEmpty &&
        !(options['check'] as bool && options['rebuild'] as bool),
    'Choose --check or --rebuild, or neither to update',
  );
  final root = repositoryRoot();
  if (options['check'] as bool) {
    check(root);
    return;
  }
  final here = Directory(p.join(root.path, 'servers', 'helpers'));
  final crate = Directory(p.join(root.path, 'rust', 'adb', 'device_fs_helper'));
  final ndk = Directory(
    Platform.environment['ANDROID_NDK_HOME'] ??
        p.join(userHome, 'Android', 'Sdk', 'ndk', '30.0.16248370'),
  );
  require(
    File(p.join(ndk.path, 'source.properties'))
        .readAsStringSync()
        .contains('Pkg.Revision = 30.0.16248370'),
    'NDK 30.0.16248370 is required',
  );
  final toolchain = p.join(
    ndk.path,
    'toolchains',
    'llvm',
    'prebuilt',
    'linux-x86_64',
    'bin',
  );
  final cargo = p.join(userHome, '.cargo', 'bin', 'cargo');
  final environment = <String, String>{
    'SOURCE_DATE_EPOCH': '0',
    'CARGO_TARGET_DIR': p.join(crate.path, 'target'),
    'RUSTFLAGS':
        '--remap-path-prefix=${root.path}=/interop '
        '--remap-path-prefix=${p.join(userHome, '.cargo')}=/cargo -C link-arg=-Wl,--build-id=none',
  };
  await withTemporary('android-helpers-', (staging) async {
    final artifacts = <Map<String, Object>>[];
    for (final entry in targets.entries) {
      final (target, linker) = entry.value;
      environment['CARGO_TARGET_${target.toUpperCase().replaceAll('-', '_')}_LINKER'] =
          p.join(toolchain, linker);
      await run(
        cargo,
        [
          '+1.99.1',
          'build',
          '--locked',
          '--release',
          '--manifest-path',
          p.join(crate.path, 'Cargo.toml'),
          '--target',
          target,
        ],
        cwd: root,
        environment: environment,
        echo: true,
      );
      final candidate = File(
        p.join(
          crate.path,
          'target',
          target,
          'release',
          'interop-android-helper',
        ),
      );
      final name = 'bin/${entry.key}/interop-rename';
      final temporary = File(p.join(staging.path, name));
      await temporary.parent.create(recursive: true);
      await candidate.copy(temporary.path);
      artifacts.add({
        'abi': entry.key,
        'target': target,
        'file': name,
        'sha256': digest(temporary),
        'size': temporary.lengthSync(),
      });
      if (options['rebuild'] as bool) {
        require(
          digest(temporary) == digest(File(p.join(here.path, name))),
          'Rebuilt helper differs: ${entry.key}',
        );
      }
    }
    if (options['rebuild'] as bool) {
      stdout.writeln('PASS: rebuilt helpers are identical for all four ABIs');
      return;
    }
    for (final output in artifacts) {
      final name = output['file'] as String;
      final destination = File(p.join(here.path, name));
      await destination.parent.create(recursive: true);
      await File(p.join(staging.path, name)).copy(destination.path);
      if (!Platform.isWindows) await run('chmod', ['644', destination.path]);
    }
    writeJson(File(p.join(here.path, 'manifest.json')), {
      'protocol': 1,
      'rust': '1.99.1',
      'ndk': '30.0.16248370',
      'minAndroidApi': 21,
      'sources': inputs(root),
      'artifacts': artifacts,
    });
  });
});
