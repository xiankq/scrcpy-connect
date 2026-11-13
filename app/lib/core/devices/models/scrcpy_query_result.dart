import 'dart:typed_data';

/// 固定 scrcpy 清单查询的执行结果；退出码来自监督器对原查询子进程的 wait。
final class ScrcpyQueryResult {
  ScrcpyQueryResult(Uint8List stdout, this.exitCode)
    : stdout = Uint8List.fromList(stdout).asUnmodifiableView();
  final Uint8List stdout;
  final int exitCode;
}
