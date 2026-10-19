/// Generate tokens, FRB and Dart builders; --check never rewrites outputs.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/core_tooling.dart';

final root = repositoryRoot();
const frbVersion = '2.13.0';
const outputs = [
  'crates/interop_bridge/src/frb_generated.rs',
  'packages/interop_bridge/lib/src/rust/api.dart',
  'packages/interop_bridge/lib/src/rust/frb_generated.dart',
  'packages/interop_bridge/lib/src/rust/frb_generated.io.dart',
];

void compareOutputs(Directory original, Directory generated) {
  final changed = outputs.where((name) {
    final before = File(p.join(original.path, name));
    final after = File(p.join(generated.path, name));
    if (!before.existsSync() || !after.existsSync()) return true;
    final a = before.readAsBytesSync(), b = after.readAsBytesSync();
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }).toList();
  if (changed.isNotEmpty) {
    throw StateError(
      'FRB generated files are stale; run dart tool/generate.dart:\n${changed.join('\n')}',
    );
  }
}

void formatFrbRust(Directory directory) {
  final formatter =
      executable('rustfmt') ?? p.join(userHome, '.cargo/bin/rustfmt');
  final output = File(p.join(directory.path, outputs.first));
  final result = runTool(
    [
      formatter,
      '--quiet',
      '--edition',
      '2024',
      '--emit',
      'stdout',
      output.path,
    ],
    cwd: directory,
    quiet: true,
  );
  output.writeAsStringSync(result.stdout as String);
}

/// Make all generator inputs private. Codegen can format or add source files.
void copyFrbInputs(Directory source, Directory isolated) {
  for (final name in [
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
    'flutter_rust_bridge.yaml',
    'pubspec.yaml',
    'pubspec.lock',
  ]) {
    File(p.join(source.path, name)).copySync(p.join(isolated.path, name));
  }
  const ignored = {
    'target',
    'build',
    '.git',
    '.gradle',
    'ephemeral',
    'Pods',
    '.dart_tool',
    '.cxx',
  };
  // Only app sources and its workspace manifest are generator inputs. Native
  // runners can contain machine-local SDK paths and signing credentials.
  final appManifest = File(p.join(source.path, 'app/pubspec.yaml'));
  final isolatedManifest = File(p.join(isolated.path, 'app/pubspec.yaml'));
  isolatedManifest.parent.createSync(recursive: true);
  appManifest.copySync(isolatedManifest.path);
  for (final name in ['crates', 'packages', 'app/lib', 'servers', 'protocol']) {
    final directory = Directory(p.join(source.path, name));
    if (directory.existsSync()) {
      copyDirectory(
        directory,
        Directory(p.join(isolated.path, name)),
        exclude: ignored.contains,
      );
    }
  }
  final metadata = Directory(p.join(isolated.path, '.dart_tool'))..createSync();
  for (final name in ['package_config.json', 'package_graph.json']) {
    final input = File(p.join(source.path, '.dart_tool', name));
    if (input.existsSync()) input.copySync(p.join(metadata.path, name));
  }
}

void generateFrb(bool check) {
  final generator = executable('flutter_rust_bridge_codegen');
  if (generator == null) {
    throw StateError(
      'Install flutter_rust_bridge_codegen $frbVersion: cargo install flutter_rust_bridge_codegen --version =$frbVersion --locked',
    );
  }
  final version =
      (runTool([generator, '--version'], quiet: true).stdout as String).trim();
  if (version != 'flutter_rust_bridge_codegen $frbVersion') {
    throw StateError(
      'Expected flutter_rust_bridge_codegen $frbVersion, got $version',
    );
  }
  final command = [
    generator,
    'generate',
    '--config-file',
    'flutter_rust_bridge.yaml',
  ];
  if (!check) {
    runTool(command, cwd: root);
    formatFrbRust(root);
    return;
  }
  final isolated = Directory.systemTemp.createTempSync('interop-frb-');
  try {
    copyFrbInputs(root, isolated);
    runTool(
      command,
      cwd: isolated,
      environment: {'CARGO_TARGET_DIR': p.join(isolated.path, 'target')},
    );
    formatFrbRust(isolated);
    compareOutputs(root, isolated);
  } finally {
    isolated.deleteSync(recursive: true);
  }
  stdout.writeln('PASS: FRB $frbVersion Rust/Dart generated outputs');
}

/// Resolve the already installed runner without invoking pub or dart run.
List<String> builderCommand(Directory directory, bool check) {
  final config = File(p.join(directory.path, '.dart_tool/package_config.json'));
  final metadata =
      jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final packages = (metadata['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final runner = packages
      .where((package) => package['name'] == 'build_runner')
      .firstOrNull;
  if (runner == null) {
    throw StateError('Resolve the locked Dart dependencies before generation');
  }
  final runnerUri = config.uri.resolve(
    '${(runner['rootUri'] as String).replaceFirst(RegExp(r'/+$'), '')}/bin/build_runner.dart',
  );
  return [
    dartExecutable,
    '--disable-dart-dev',
    '--packages=${config.path}',
    runnerUri.toFilePath(),
    'build',
    '--workspace',
    if (check) '--only-check',
  ];
}

void main(List<String> arguments) {
  try {
    final parser = ArgParser()
      ..addFlag('check', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false);
    final args = parser.parse(arguments);
    if (args['help'] as bool) {
      stdout.writeln(
        'Generate tokens, FRB and Dart builders.\n${parser.usage}',
      );
      return;
    }
    if (args.rest.isNotEmpty) {
      throw ArgumentError('Unexpected positional arguments');
    }
    final check = args['check'] as bool;
    runTool([
      'node',
      'tool/design_tokens/generate.mjs',
      if (check) '--check',
    ], cwd: root);
    generateFrb(check);
    runTool(builderCommand(root, check), cwd: root);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
