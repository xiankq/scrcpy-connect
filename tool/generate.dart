/// 生成 token、FRB 与 Dart builder 输出；--check 仅检查，不重写生成物。
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'src/repository_tooling.dart';
import 'src/generation_workspace.dart';

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

Future<void> formatFrbRust(
  Directory directory, [
  Iterable<String>? files,
]) async {
  final formatter =
      executable('rustfmt') ?? p.join(userHome, '.cargo/bin/rustfmt');
  for (final file in files ?? outputs) {
    final output = File(p.join(directory.path, file));
    final result = await runTool(
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

/// 镜像仅包含 FRB 的 Rust、Dart 包源码与工作区清单，不复制媒体归档、runner 和设备夹具。
void copyFrbInputs(Directory source, Directory isolated) {
  final inputs = <String, File>{};
  void file(String name) {
    final input = File(p.join(source.path, name));
    if (input.existsSync()) inputs[p.normalize(name)] = input;
  }

  for (final name in [
    'Cargo.toml',
    'Cargo.lock',
    'rust-toolchain.toml',
    'pubspec.yaml',
    'pubspec.lock',
    'app/pubspec.yaml',
    for (final module in frbModules) module.config,
    '.dart_tool/package_config.json',
    '.dart_tool/package_graph.json',
  ]) {
    file(name);
  }
  final packages = Directory(p.join(source.path, 'packages'));
  if (packages.existsSync()) {
    for (final package in packages.listSync().whereType<Directory>()) {
      file(p.relative(p.join(package.path, 'pubspec.yaml'), from: source.path));
    }
  }
  const ignored = {'target', 'build', '.git', '.dart_tool'};
  void tree(String name) {
    final directory = Directory(p.join(source.path, name));
    if (!directory.existsSync()) return;
    void visit(Directory directory) {
      for (final entity in directory.listSync(followLinks: false)) {
        if (ignored.contains(p.basename(entity.path))) continue;
        if (entity is Directory) {
          visit(entity);
        } else if (entity is File) {
          file(p.relative(entity.path, from: source.path));
        } else if (entity is Link) {
          throw FileSystemException(
            'FRB input must be a private source file',
            entity.path,
          );
        }
      }
    }

    visit(directory);
  }

  for (final name in [
    'rust/adb',
    'rust/scrcpy',
    for (final module in frbModules) '${module.directory}/lib',
  ]) {
    tree(name);
  }
  synchronizeInputs(inputs, isolated);
}

Future<void> generateFrb(bool check) async {
  final generator = executable('flutter_rust_bridge_codegen');
  if (generator == null) {
    throw StateError(
      'Install flutter_rust_bridge_codegen $frbVersion: cargo install flutter_rust_bridge_codegen --version =$frbVersion --locked',
    );
  }
  final version =
      ((await runTool([generator, '--version'], quiet: true)).stdout as String)
          .trim();
  if (version != 'flutter_rust_bridge_codegen $frbVersion') {
    throw StateError(
      'Expected flutter_rust_bridge_codegen $frbVersion, got $version',
    );
  }
  Future<void> runGenerators(
    Directory directory, {
    Map<String, String>? environment,
  }) async {
    for (final module in frbModules) {
      await streamTool(
        [generator, 'generate', '--config-file', module.config],
        cwd: directory,
        environment: environment,
      );
    }
  }

  if (!check) {
    await runGenerators(root);
    await formatFrbRust(root);
    return;
  }
  await withGenerationWorkspace(
    Directory(p.join(root.path, '.dart_tool/frb_check')),
    (isolated, target) async {
      copyFrbInputs(root, isolated);
      await runGenerators(
        isolated,
        environment: {
          'CARGO_TARGET_DIR': target.path,
          'CARGO_INCREMENTAL': '0',
          'CARGO_PROFILE_DEV_DEBUG': '0',
        },
      );
      await formatFrbRust(isolated);
      compareOutputs(root, isolated);
    },
  );
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

Future<void> main(List<String> arguments) async {
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
    await streamTool([
      'node',
      'tool/design_tokens/generate.mjs',
      if (check) '--check',
    ], cwd: root);
    await streamTool([
      dartExecutable,
      '--disable-dart-dev',
      'servers/package.dart',
      if (check) '--check',
    ], cwd: root);
    await generateFrb(check);
    await streamTool(builderCommand(root, check), cwd: root);
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
