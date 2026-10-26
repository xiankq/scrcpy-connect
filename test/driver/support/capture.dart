import 'dart:io';

/// 所有 driver 使用同一文件名规则保存截图，阻止输出路径离开证据目录。
Future<bool> saveScreenshot(
  Directory directory,
  String name,
  List<int> bytes,
) async {
  final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeName.isEmpty) throw ArgumentError('Empty screenshot name');
  await directory.create(recursive: true);
  await File('${directory.path}/$safeName.png')
      .writeAsBytes(bytes, flush: true);
  return true;
}
