import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:path/path.dart' as p;

/// SDK 资源名称由本机暂存根确定；平台租约由平台登记确认，二者不能互相替代。
final class FileShareOwner {
  const FileShareOwner({required this.cacheDirectory, required this.leaseId});
  final String cacheDirectory, leaseId;
  String get scopeKey => p.join(cacheDirectory, 'incoming');

  Future<LocalFileScope> openScope(LocalFiles files) => files.openScope(
    scopeKey: scopeKey,
    allowedRoots: [Uint8List.fromList(utf8.encode(cacheDirectory))],
  );
}
