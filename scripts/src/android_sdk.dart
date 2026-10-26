import 'dart:io';

import 'package:path/path.dart' as p;

String androidSdkPath([String? explicit]) {
  final environment = Platform.environment;
  final configured =
      explicit ??
      environment['ANDROID_SDK_ROOT'] ??
      environment['ANDROID_HOME'];
  if (configured != null) return configured;
  final home = environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';
  for (final candidate in [
    p.join(home, 'Android/Sdk'),
    p.join(home, 'Library/Android/sdk'),
    if (environment['LOCALAPPDATA'] case final local?)
      p.join(local, 'Android/Sdk'),
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  throw StateError('Set ANDROID_SDK_ROOT to the Android SDK directory.');
}

/// 只选择正式数字版本；按数值排序，避免将 9.x 排在 36.x 后面。
Directory latestAndroidVersion(
  String path, {
  String prefix = '',
  bool Function(Directory)? usable,
}) {
  final parent = Directory(path);
  final versions = <(Directory, List<int>)>[];
  if (parent.existsSync()) {
    for (final directory in parent.listSync().whereType<Directory>()) {
      final name = p.basename(directory.path);
      if (!name.startsWith(prefix)) continue;
      final parts = name.substring(prefix.length).split('.').map(int.tryParse);
      if (parts.any((part) => part == null)) continue;
      if (usable?.call(directory) ?? true) {
        versions.add((directory, parts.cast<int>().toList()));
      }
    }
  }
  versions.sort((a, b) {
    for (var i = 0; i < a.$2.length && i < b.$2.length; i++) {
      final comparison = a.$2[i].compareTo(b.$2[i]);
      if (comparison != 0) return comparison;
    }
    return a.$2.length.compareTo(b.$2.length);
  });
  if (versions.isEmpty) {
    throw StateError('No usable Android SDK versions below $path');
  }
  return versions.last.$1;
}

String androidSdkTool(String directory, String name) => p.join(
  directory,
  Platform.isWindows
      ? '$name${name == 'd8' || name == 'apksigner' || name == 'apkanalyzer' ? '.bat' : '.exe'}'
      : name,
);
