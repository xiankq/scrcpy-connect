import 'package:freezed_annotation/freezed_annotation.dart';

part 'clipboard_capture.freezed.dart';

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
