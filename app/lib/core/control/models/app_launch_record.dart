import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';

/// 副作用记录的阶段，不表示 Android 应用当前的生命周期。
enum AppLaunchStatus { pending, unknown, observed, closed }

/// 持久保存的一次应用打开意图及已知结果。
final class AppLaunchRecord {
  const AppLaunchRecord({
    required this.operationId,
    required this.sessionId,
    required this.deviceId,
    required this.packageName,
    required this.status,
    required this.updatedAt,
    this.failureCode,
  });
  final String operationId, sessionId, deviceId, packageName;
  final AppLaunchStatus status;
  final String? failureCode;

  /// 与原 v1 文件契约相同的 Unix 秒。
  final int updatedAt;
  bool get unresolved =>
      status == AppLaunchStatus.pending || status == AppLaunchStatus.unknown;

  VideoSessionSnapshot get snapshot => VideoSessionSnapshot(
    sessionId: operationId,
    deviceId: deviceId,
    packageName: packageName,
    name: packageName,
    kind: .app,
    status: .failed,
    launchOperationId: operationId,
    launchOutcome: .unknown,
    recordOnly: true,
    linkedSessionId: operationId == sessionId ? null : sessionId,
    failureCode: failureCode,
    reason: '应用打开请求可能已提交。请先核对手机并明确关闭本次记录，再选择重新打开。',
  );

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'sessionId': sessionId,
    'deviceId': deviceId,
    'packageName': packageName,
    'status': status.name,
    'failureCode': failureCode,
    'updatedAt': updatedAt,
  };

  AppLaunchRecord withStatus(
    AppLaunchStatus status,
    int time,
    String? failure,
  ) => AppLaunchRecord(
    operationId: operationId,
    sessionId: sessionId,
    deviceId: deviceId,
    packageName: packageName,
    status: status,
    failureCode: failure,
    updatedAt: time,
  );
}

final class AppLaunchUncertain extends RequestFailure {
  AppLaunchUncertain(this.record)
    : super('app_launch_unknown', '应用打开结果尚待核对，不会再次提交打开请求。');
  final AppLaunchRecord record;
}
