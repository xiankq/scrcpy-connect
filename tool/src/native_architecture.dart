import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'repository_tooling.dart';

const _nativePackageDependencies = <String, Set<String>>{
  'adb': {},
  'scrcpy': {'adb'},
  'media_codec': {},
};

/// 读取 Cargo 的实际路径依赖，包含带 target 条件的依赖声明。
List<String> checkNativeArchitecture(Directory root) {
  final cargo =
      executable('cargo') ?? p.join(userHome, '.cargo', 'bin', 'cargo');
  final packages = <String, Map<String, dynamic>>{};
  for (final manifest in [
    'Cargo.toml',
    'rust/media_codec/Cargo.toml',
    'rust/adb/device_fs_helper/Cargo.toml',
  ]) {
    final metadata = jsonDecode(
      runTool(
            [
              cargo,
              'metadata',
              '--offline',
              '--locked',
              '--no-deps',
              '--format-version',
              '1',
              '--manifest-path',
              manifest,
            ],
            cwd: root,
            quiet: true,
          ).stdout
          as String,
    ) as Map<String, dynamic>;
    for (final package
        in (metadata['packages'] as List).cast<Map<String, dynamic>>()) {
      packages[package['manifest_path'] as String] = package;
    }
  }
  return checkNativeDependencies(root, packages.values.toList());
}

/// 原生能力的依赖只能指向同包实现或已声明的通用下层。
List<String> checkNativeDependencies(
  Directory root,
  List<Map<String, dynamic>> packages,
) {
  final problems = <String>[];
  String relative(String path) => p.relative(path, from: root.path);
  for (final package in packages) {
    final manifest = package['manifest_path'] as String;
    final segments = p.split(relative(manifest));
    if (segments.length < 3 ||
        segments[0] != 'rust' ||
        !_nativePackageDependencies.containsKey(segments[1])) {
      problems.add('${relative(manifest)}: Rust 只能实现与能力包对应的通用能力，禁止应用运行时或业务桥');
      continue;
    }
    final owner = segments[1];
    final ownRoot = p.join(root.path, 'rust', owner);
    for (final dependency
        in (package['dependencies'] as List).cast<Map<String, dynamic>>()) {
      final target = dependency['path'] as String?;
      if (target == null) continue;
      // 一个动态库只能包含自己的 FRB 生成入口；共享实现必须依赖 api/core rlib。
      if (p.basename(target) == 'bridge') {
        problems.add(
          '${relative(manifest)}: 不允许链接另一个 FRB 动态库入口 ${relative(target)}',
        );
        continue;
      }
      if (p.equals(target, ownRoot) || p.isWithin(ownRoot, target)) continue;
      final allowed = _nativePackageDependencies[owner]!.any((name) {
        final directory = p.join(root.path, 'rust', name);
        return p.equals(target, directory) || p.isWithin(directory, target);
      });
      if (!allowed) {
        problems.add('${relative(manifest)}: $owner 不允许依赖 ${relative(target)}');
      }
    }
  }
  return problems..sort();
}
