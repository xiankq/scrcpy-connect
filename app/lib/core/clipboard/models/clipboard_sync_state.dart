import 'package:freezed_annotation/freezed_annotation.dart';

part 'clipboard_sync_state.freezed.dart';

enum ClipboardSyncStatus {
  disabled,
  waitingDevice,
  waitingForeground,
  checking,
  waitingVerification,
  watching,
  limited,
}

@freezed
abstract class ClipboardSyncState with _$ClipboardSyncState {
  const factory ClipboardSyncState({
    @Default(ClipboardSyncStatus.disabled) ClipboardSyncStatus status,
    String? error,
    @Default(0) int readCount,
    @Default(0) int writeCount,
    @Default(0) int sendCount,
  }) = _ClipboardSyncState;
}
