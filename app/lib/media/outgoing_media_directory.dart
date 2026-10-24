import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 统一解析系统路径别名，受管文件本身不能是符号链接。
Future<Directory> outgoingMediaDirectory() async {
  final temporary = await getTemporaryDirectory();
  final outgoing = await Directory('${temporary.path}/outgoing')
      .create(recursive: true);
  return Directory(await outgoing.resolveSymbolicLinks());
}
