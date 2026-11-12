import 'package:scrcpy_connect/core/files/incoming_shares.dart';
import 'package:scrcpy_connect/core/devices/device_snapshot.dart';
import 'package:scrcpy_connect/core/settings/preferences.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';
import 'package:scrcpy_connect/utils/json_readers.dart';

part 'app_state.freezed.dart';

/// 应用级只读投影；构造和 copyWith 均隔离、深冻结外部集合。
@freezed
class AppState with _$AppState {
  AppState({
    List<DeviceSnapshot> devices = const [],
    Preferences? settings,
    List<IncomingShare> pendingShares = const [],
    Json? lastEvent,
    this.eventRevision = 0,
    this.loading = true,
    this.deviceError,
    this.settingsError,
    this.audioError,
    this.focusedDeviceId,
    this.reconciliationPending = false,
    this.reconciliationError,
    Json? reconciledSnapshot,
  }) : devices = immutableDeviceSnapshots(devices),
       settings = settings ?? Preferences(),
       pendingShares = List.unmodifiable(pendingShares),
       lastEvent = lastEvent == null ? null : immutableJson(lastEvent),
       reconciledSnapshot = reconciledSnapshot == null
           ? null
           : immutableJson(reconciledSnapshot);

  final List<DeviceSnapshot> devices;
  final Preferences settings;
  final List<IncomingShare> pendingShares;
  final Json? lastEvent;
  final int eventRevision;
  final bool loading;
  final String? deviceError;
  final String? settingsError;
  final String? audioError;
  final String? focusedDeviceId;
  final bool reconciliationPending;
  final String? reconciliationError;
  final Json? reconciledSnapshot;
}
