import 'package:freezed_annotation/freezed_annotation.dart';

part 'keep_awake_snapshot.freezed.dart';

enum KeepAwakeStatus {
  starting,
  active,
  stopping,
  released,
  cleanupUnconfirmed,
}

@freezed
abstract class KeepAwakeFailure with _$KeepAwakeFailure {
  const KeepAwakeFailure._();
  const factory KeepAwakeFailure({
    required String code,
    required String reason,
  }) = _KeepAwakeFailure;
  Map<String, Object?> toSnapshot() => {'code': code, 'reason': reason};
}

/// 设备共享保持唤醒租约的事实；旧连接清理不覆盖新连接的当前状态。
@freezed
abstract class KeepAwakeSnapshot with _$KeepAwakeSnapshot {
  const KeepAwakeSnapshot._();
  const factory KeepAwakeSnapshot({
    required String deviceId,
    @Default(KeepAwakeStatus.starting) KeepAwakeStatus status,
    @Default(false) bool keepActive,
    @Default(false) bool keepActiveApplied,
    @Default(false) bool keepActiveLeaseActive,
    String? keepActiveLeaseId,
    int? keepActivePid,
    int? keepActiveProcessStarted,
    String? keepActiveConnectionId,
    KeepAwakeFailure? keepActiveError,
    @Default(false) bool releasePending,
    @Default(false) bool localCleanupConfirmed,
    @Default(false) bool cleanupConfirmed,
    @Default(false) bool remoteExitVerified,
    @Default(false) bool remoteRestoreVerified,
    @Default([]) List<KeepAwakeSnapshot> pendingCleanup,
  }) = _KeepAwakeSnapshot;

  static KeepAwakeSnapshot withoutLease({
    required String deviceId,
    required bool enabled,
    required bool hasWindowOwner,
  }) => KeepAwakeSnapshot(
    deviceId: deviceId,
    keepActive: enabled,
    keepActiveApplied: !(enabled && hasWindowOwner),
    localCleanupConfirmed: true,
  );

  bool get hasCleanupEvidence =>
      keepActiveLeaseId != null ||
      keepActiveError != null ||
      releasePending ||
      pendingCleanup.isNotEmpty;
  bool get healthy =>
      keepActiveError == null && !releasePending && pendingCleanup.isEmpty;

  Map<String, dynamic> toSnapshot() => {
    'deviceId': deviceId,
    'status': status.name.replaceAll(
      'cleanupUnconfirmed',
      'cleanup_unconfirmed',
    ),
    'keepActive': keepActive,
    'keepActiveApplied': keepActiveApplied,
    'keepActiveLeaseActive': keepActiveLeaseActive,
    'keepActiveLeaseId': keepActiveLeaseId,
    'keepActivePid': keepActivePid,
    'keepActiveProcessStarted': keepActiveProcessStarted,
    'keepActiveConnectionId': keepActiveConnectionId,
    'keepActiveError': keepActiveError?.toSnapshot(),
    'releasePending': releasePending,
    'localCleanupConfirmed': localCleanupConfirmed,
    'cleanupConfirmed': cleanupConfirmed,
    'remoteExitVerified': remoteExitVerified,
    'remoteRestoreVerified': remoteRestoreVerified,
    'pendingCleanup': [
      for (final pending in pendingCleanup) pending.toSnapshot(),
    ],
  };

  Map<String, dynamic> get cleanupSnapshot => {
    'leaseId': keepActiveLeaseId,
    'pid': keepActivePid,
    'processStarted': keepActiveProcessStarted,
    'connectionId': keepActiveConnectionId,
    'error': keepActiveError?.toSnapshot(),
    'releasePending': releasePending,
    'localCleanupConfirmed': localCleanupConfirmed,
    'cleanupConfirmed': cleanupConfirmed,
    'remoteExitVerified': remoteExitVerified,
    'remoteRestoreVerified': remoteRestoreVerified,
    'pendingCleanup': [
      for (final pending in pendingCleanup) pending.toSnapshot(),
    ],
  };

  Map<String, dynamic> get sessionSnapshot => {
    'keepActive': keepActive,
    'keepActiveApplied': keepActiveApplied,
    'keepActiveLeaseActive': keepActiveLeaseActive,
    'keepActiveLeaseId': keepActiveLeaseId,
    'keepActivePid': keepActivePid,
    'keepActiveProcessStarted': keepActiveProcessStarted,
    'keepActiveConnectionId': keepActiveConnectionId,
    'keepActiveError': keepActiveError?.toSnapshot(),
    'keepActiveCleanup': cleanupSnapshot,
  };
}
