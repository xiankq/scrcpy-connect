import 'dart:convert';
import 'dart:typed_data';

import 'package:adb/adb.dart';

NativeAdbEvent adbData(List<int> bytes, {String kind = 'data'}) =>
    NativeAdbEvent(kind: kind, bytes: Uint8List.fromList(bytes), done: false);

NativeAdbEvent adbText(String text, {String kind = 'data'}) =>
    adbData(utf8.encode(text), kind: kind);

// 空退出码保留“退出结果未知”，不能统一补成成功。
NativeAdbEvent adbDone({
  String kind = 'done',
  int? exitCode,
  int transferred = 0,
  AdbServiceFacts? facts,
}) => NativeAdbEvent(
  kind: kind,
  bytes: Uint8List(0),
  done: true,
  exitCode: exitCode,
  transferred: transferred,
  facts: facts,
);

Stream<AdbShellEvent> shellOutput(List<int> bytes, {int? exitCode = 0}) async* {
  yield AdbShellEvent(AdbShellChannel.stdout, Uint8List.fromList(bytes));
  yield AdbShellEvent(AdbShellChannel.exit, Uint8List(0), exitCode: exitCode);
}

Stream<AdbShellEvent> shellText(String text, {int? exitCode = 0}) =>
    shellOutput(utf8.encode(text), exitCode: exitCode);
