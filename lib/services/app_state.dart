import 'package:flutter/foundation.dart';
import 'package:scrcpy_connect/services/app_controller.dart';
import 'package:scrcpy_connect/services/notification_replies.dart';

Object? _freeze(Object? value) => switch (value) {
  Map<Object?, Object?> map => Map<String, dynamic>.unmodifiable({
    for (final entry in map.entries)
      if (entry.key case final String key) key: _freeze(entry.value),
  }),
  List<Object?> list => List<Object?>.unmodifiable(list.map(_freeze)),
  _ => value,
};
Json immutableJson(Json value) => Map<String, dynamic>.unmodifiable({
  for (final entry in value.entries) entry.key: _freeze(entry.value),
});
List<Json> _records(List<Json> records) =>
    List<Json>.unmodifiable(records.map(immutableJson));
Json? _nullableRecord(Json? Function()? update, Json? original) {
  if (update == null) return original;
  final next = update();
  return next == null ? null : immutableJson(next);
}

/// One immutable view of application-owned state. JSON collections are deeply
/// frozen at the boundary; native frames stay on the separate session stream.
@immutable
class AppState {
  const AppState._({
    required this.devices,
    required this.settings,
    required this.pendingShares,
    required this.lastEvent,
    required this.eventRevision,
    required this.loading,
    required this.deviceError,
    required this.settingsError,
    required this.audioError,
    required this.focusedDeviceId,
    required this.clipboardState,
    required this.clipboardError,
    required this.clipboardReadCount,
    required this.clipboardWriteCount,
    required this.clipboardSendCount,
    required this.reconciliationPending,
    required this.reconciliationError,
    required this.reconciledSnapshot,
    required this.notificationReplies,
  });
  factory AppState({
    List<Json> devices = const [],
    Json settings = const {},
    List<Json> pendingShares = const [],
    Json? lastEvent,
    int eventRevision = 0,
    bool loading = true,
    String? deviceError,
    String? settingsError,
    String? audioError,
    String? focusedDeviceId,
    String clipboardState = 'disabled',
    String? clipboardError,
    int clipboardReadCount = 0,
    int clipboardWriteCount = 0,
    int clipboardSendCount = 0,
    bool reconciliationPending = false,
    String? reconciliationError,
    Json? reconciledSnapshot,
    Map<NotificationReplyKey, NotificationReplyState> notificationReplies =
        const {},
  }) => AppState._(
    devices: _records(devices),
    settings: immutableJson(settings),
    pendingShares: _records(pendingShares),
    lastEvent: lastEvent == null ? null : immutableJson(lastEvent),
    eventRevision: eventRevision,
    loading: loading,
    deviceError: deviceError,
    settingsError: settingsError,
    audioError: audioError,
    focusedDeviceId: focusedDeviceId,
    clipboardState: clipboardState,
    clipboardError: clipboardError,
    clipboardReadCount: clipboardReadCount,
    clipboardWriteCount: clipboardWriteCount,
    clipboardSendCount: clipboardSendCount,
    reconciliationPending: reconciliationPending,
    reconciliationError: reconciliationError,
    reconciledSnapshot: reconciledSnapshot == null
        ? null
        : immutableJson(reconciledSnapshot),
    notificationReplies: Map.unmodifiable(notificationReplies),
  );
  final List<Json> devices;
  final Json settings;
  final List<Json> pendingShares;
  final Json? lastEvent;
  final int eventRevision;
  final bool loading;
  final String? deviceError;
  final String? settingsError;
  final String? audioError;
  final String? focusedDeviceId;
  final String clipboardState;
  final String? clipboardError;
  final int clipboardReadCount;
  final int clipboardWriteCount;
  final int clipboardSendCount;
  final bool reconciliationPending;
  final String? reconciliationError;
  final Json? reconciledSnapshot;
  final Map<NotificationReplyKey, NotificationReplyState> notificationReplies;

  AppState copyWith({
    List<Json>? devices,
    Json? settings,
    List<Json>? pendingShares,
    Json? Function()? lastEvent,
    int? eventRevision,
    bool? loading,
    String? Function()? deviceError,
    String? Function()? settingsError,
    String? Function()? audioError,
    String? Function()? focusedDeviceId,
    String? clipboardState,
    String? Function()? clipboardError,
    int? clipboardReadCount,
    int? clipboardWriteCount,
    int? clipboardSendCount,
    bool? reconciliationPending,
    String? Function()? reconciliationError,
    Json? Function()? reconciledSnapshot,
    Map<NotificationReplyKey, NotificationReplyState>? notificationReplies,
  }) => AppState._(
    devices: devices == null ? this.devices : _records(devices),
    settings: settings == null ? this.settings : immutableJson(settings),
    pendingShares: pendingShares == null
        ? this.pendingShares
        : _records(pendingShares),
    lastEvent: _nullableRecord(lastEvent, this.lastEvent),
    eventRevision: eventRevision ?? this.eventRevision,
    loading: loading ?? this.loading,
    deviceError: deviceError == null ? this.deviceError : deviceError(),
    settingsError: settingsError == null ? this.settingsError : settingsError(),
    audioError: audioError == null ? this.audioError : audioError(),
    focusedDeviceId: focusedDeviceId == null
        ? this.focusedDeviceId
        : focusedDeviceId(),
    clipboardState: clipboardState ?? this.clipboardState,
    clipboardError: clipboardError == null
        ? this.clipboardError
        : clipboardError(),
    clipboardReadCount: clipboardReadCount ?? this.clipboardReadCount,
    clipboardWriteCount: clipboardWriteCount ?? this.clipboardWriteCount,
    clipboardSendCount: clipboardSendCount ?? this.clipboardSendCount,
    reconciliationPending: reconciliationPending ?? this.reconciliationPending,
    reconciliationError: reconciliationError == null
        ? this.reconciliationError
        : reconciliationError(),
    reconciledSnapshot: _nullableRecord(
      reconciledSnapshot,
      this.reconciledSnapshot,
    ),
    notificationReplies: notificationReplies == null
        ? this.notificationReplies
        : Map.unmodifiable(notificationReplies),
  );
}
