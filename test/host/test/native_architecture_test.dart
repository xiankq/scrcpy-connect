import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../../../scripts/src/native_architecture.dart';

void main() {
  final root = Directory.systemTemp.absolute;
  Map<String, dynamic> crate(String manifest, List<String> paths) => {
    'manifest_path': p.join(root.path, manifest),
    'dependencies': [
      for (final path in paths) {'path': p.join(root.path, path)},
      {'name': 'tokio'},
    ],
  };

  test('scrcpy 可以使用 ADB，而通用协议不能依赖应用所有者', () {
    final scrcpy = crate('rust/scrcpy/Cargo.toml', ['rust/adb']);
    final adb = crate('rust/adb/Cargo.toml', []);
    expect(checkNativeDependencies(root, [scrcpy, adb]), isEmpty);
    (scrcpy['dependencies'] as List).add({
      'path': p.join(root.path, 'rust/app/core'),
      'target': 'cfg(target_os = "android")',
    });
    expect(checkNativeDependencies(root, [scrcpy, adb]), [
      contains('scrcpy 不允许依赖 rust/app'),
    ]);
  });

  test('ADB 不能反向依赖 scrcpy，应用运行时不能成为 Rust 目录例外', () {
    final adb = crate('rust/adb/Cargo.toml', ['rust/scrcpy']);
    final application = crate('rust/app/Cargo.toml', [
      'rust/scrcpy',
      'rust/adb',
    ]);
    expect(checkNativeDependencies(root, [application, adb]), [
      contains('adb 不允许依赖 rust/scrcpy'),
      contains('禁止应用运行时或业务桥'),
    ]);
  });

  test('独立宿主只能链接共享实现，不能链接另一份 FRB 入口', () {
    final scrcpy = crate('rust/scrcpy/bridge/Cargo.toml', [
      'rust/adb/api',
      'rust/scrcpy/api',
    ]);
    expect(checkNativeDependencies(root, [scrcpy]), isEmpty);
    (scrcpy['dependencies'] as List).add({
      'path': p.join(root.path, 'rust/adb/bridge'),
    });
    expect(checkNativeDependencies(root, [scrcpy]), [contains('不允许链接另一个 FRB')]);
  });

  test('设备端助手仍按 ADB 能力约束，独立 workspace 不获得例外', () {
    final helper = crate('rust/adb/device_fs_helper/Cargo.toml', []);
    expect(checkNativeDependencies(root, [helper]), isEmpty);
    (helper['dependencies'] as List).add({
      'path': p.join(root.path, 'rust/app/core'),
    });
    expect(checkNativeDependencies(root, [helper]), [
      contains('adb 不允许依赖 rust/app'),
    ]);
  });
}
