import 'package:freezed_annotation/freezed_annotation.dart';

part 'remote_clipboard.freezed.dart';

/// 设备级手动操作不依赖窗口；自动同步必须归属一个具体窗口及同步代际。
@freezed
sealed class ClipboardTarget with _$ClipboardTarget {
  const factory ClipboardTarget.device({required String deviceId}) =
      DeviceClipboardTarget;
  const factory ClipboardTarget.window({
    required String deviceId,
    required String sessionId,
    ClipboardCapture? capture,
    int? synchronizationGeneration,
  }) = WindowClipboardTarget;
}

@freezed
abstract class ClipboardCapture with _$ClipboardCapture {
  const factory ClipboardCapture({
    required String reference,
    required int generation,
  }) = _ClipboardCapture;
}

@freezed
abstract class RemoteClipboardText with _$RemoteClipboardText {
  const factory RemoteClipboardText({
    required String text,
    ClipboardCapture? capture,
  }) = _RemoteClipboardText;
}

/// 写入成功表示 scrcpy ACK 与独立读回均已核验，未知结果通过失败表达，不能自动重放。
abstract interface class RemoteClipboard {
  Future<RemoteClipboardText> readClipboard(ClipboardTarget target);
  Future<void> writeClipboard(ClipboardTarget target, String text);

  /// 替换准入后，旧订阅的释放不能撤销新订阅；进行中操作继续核对原准入。
  void Function() bindClipboardAdmission(
    bool Function(String deviceId, String sessionId, int generation) check,
  );
}
