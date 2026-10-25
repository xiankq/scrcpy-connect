import 'dart:io';

import 'package:scrcpy_connect/services/media/outgoing_media_directory.dart';

/// 对外分享文件与私有身份、应用状态隔离，原生 FileProvider 只暴露此子树。
Future<Directory> receivedDirectory() async {
  final outgoing = await outgoingMediaDirectory();
  return outgoing.createTemp('received-');
}
