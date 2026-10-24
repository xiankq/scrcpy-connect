/// 生成 token、FRB 与 Dart builder 输出；--check 仅检查，不重写生成物。
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/repository_tooling.dart';

final root = repositoryRoot();
const frbVersion = '2.13.0';
const frbModules = [
  (
    config: 'flutter_rust_bridge.yaml',
    directory: 'packages/adb',
    rust: 'rust/adb/bridge',
    dart: 'lib/src/native/generated',
  ),
  (
    config: 'flutter_rust_bridge.scrcpy.yaml',
    directory: 'packages/scrcpy',
    rust: 'rust/scrcpy/bridge',
    dart: 'lib/src/native/generated',
  ),
];
final outputs = [
  for (final module in frbModules) '${module.rust}/src/frb_generated.rs',
];

Set<String> generatedOutputs(Directory directory) {
  final files = outputs.toSet();
  for (final module in frbModules) {
    final generated = Directory(
      p.join(directory.path, module.directory, module.dart),
    );
    if (!generated.existsSync()) continue;
    files.addAll(
      generated
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => p.relative(file.path, from: directory.path)),
    );
  }
  return files;
}

void compareOutputs(Directory original, Directory generated) {
  final changed =
      {...generatedOutputs(original), ...generatedOutputs(generated)}.where((
        name,
      ) {
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

void formatFrbRust(Directory directory, [Iterable<String>? files]) {
  final formatter =
      executable('rustfmt') ?? p.join(userHome, '.cargo/bin/rustfmt');
  for (final file in files ?? outputs) {
    final output = File(p.join(directory.path, file));
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
}

/// 复制全部生成输入至私有目录，防止生成器格式化或新增文件影响原树。
void copyFrbInputs(Directory source, Directory isolated) {
  for (final name in [
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
    'pubspec.yaml',
    'pubspec.lock',
    for (final module in frbModules) module.config,
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
  // 只将应用源码及工作区清单作为生成输入；原生 runner 可能包含本机 SDK 路径或签名凭据。
  final appManifest = File(p.join(source.path, 'app/pubspec.yaml'));
  final isolatedManifest = File(p.join(isolated.path, 'app/pubspec.yaml'));
  isolatedManifest.parent.createSync(recursive: true);
  appManifest.copySync(isolatedManifest.path);
  for (final name in [
    'packages',
    'app/lib',
    'rust',
    'app/assets',
    'servers',
    'protocol',
  ]) {
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
  void runGenerators(Directory directory, {Map<String, String>? environment}) {
    for (final module in frbModules) {
      runTool(
        [generator, 'generate', '--config-file', module.config],
        cwd: directory,
        environment: environment,
      );
    }
  }

  if (!check) {
    runGenerators(root);
    formatFrbRust(root);
    return;
  }
  final isolated = Directory.systemTemp.createTempSync('interop-frb-');
  try {
    copyFrbInputs(root, isolated);
    runGenerators(
      isolated,
      environment: {'CARGO_TARGET_DIR': p.join(isolated.path, 'target')},
    );
    formatFrbRust(isolated);
    compareOutputs(root, isolated);
  } finally {
    isolated.deleteSync(recursive: true);
  }
  stdout.writeln('PASS: FRB $frbVersion Rust/Dart generated outputs');
}

/// 定位已安装的 runner，不调用 pub 或 dart run。
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
    runTool([
      dartExecutable,
      'servers/package.dart',
      if (check) '--check',
    ], cwd: root);
    generateFrb(check);
    runTool(builderCommand(root, check), cwd: root);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
