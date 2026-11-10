import 'dart:typed_data';

/// 固定 scrcpy 清单查询的执行结果；退出码来自监督器对原查询子进程的 wait。
final class ScrcpyQueryResult {
  ScrcpyQueryResult(this.stdout, this.exitCode);
  final Uint8List stdout;
  final int exitCode;
}
