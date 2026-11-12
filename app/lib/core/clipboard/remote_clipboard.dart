import 'package:scrcpy_connect/core/clipboard/models/clipboard_capture.dart';

export 'package:scrcpy_connect/core/clipboard/models/clipboard_capture.dart';

/// 写入成功表示 scrcpy ACK 与独立读回均已核验，未知结果通过失败表达，不能自动重放。
abstract interface class RemoteClipboard {
  Future<RemoteClipboardText> readClipboard(ClipboardTarget target);
  Future<void> writeClipboard(ClipboardTarget target, String text);

  /// 替换准入后，旧订阅的释放不能撤销新订阅；进行中操作继续核对原准入。
  void Function() bindClipboardAdmission(
    bool Function(String deviceId, String sessionId, int generation) check,
  );
}
