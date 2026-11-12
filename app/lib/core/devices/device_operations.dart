import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/companion/companion_exception.dart';
import 'package:scrcpy_connect/core/devices/device_assessment.dart';
import 'package:scrcpy_connect/core/devices/device_calls.dart';
import 'package:scrcpy_connect/core/devices/device_management.dart';
import 'package:scrcpy_connect/core/devices/device_notifications.dart';
import 'package:scrcpy_connect/core/devices/device_observation.dart';
import 'package:scrcpy_connect/core/devices/device_record_storage.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';

/// 设备读取与观察动作的准入；连接代际、观察意图与原生资源由能力所有者核验。
final class DeviceOperations
    implements
        DeviceAssessment,
        DeviceObservation,
        DeviceCalls,
        DeviceNotifications,
        DeviceWake {
  DeviceOperations({
    required this._capabilities,
    required this._observation,
    required this._calls,
    required this._notifications,
    required this.wake,
    required this.isDisposed,
    required this.isStateUnverified,
    required this._diagnostics,
  });

  final DeviceAssessment Function() _capabilities;
  final DeviceObservation Function() _observation;
  final DeviceCalls Function() _calls;
  final DeviceNotifications Function() _notifications;
  final Future<DeviceWakeReceipt> Function(String, {String? connectionId}) wake;
  final bool Function() isDisposed;
  final bool Function() isStateUnverified;
  final DiagnosticReporter _diagnostics;

  @override
  Future<DeviceCapabilities> readCapabilities(
    String deviceId, {
    AdbCancellation? cancellation,
  }) {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    cancellation?.check();
    return _capabilities().readCapabilities(
      deviceId,
      cancellation: cancellation,
    );
  }

  @override
  Future<DeviceDiagnosis> diagnoseDevice(
    String deviceId, {
    AdbCancellation? cancellation,
  }) {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    cancellation?.check();
    return _capabilities().diagnoseDevice(deviceId, cancellation: cancellation);
  }

  @override
  Future<DeviceNotificationsSnapshot> readNotifications(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'notifications.list',
    () => _notifications().readNotifications(
      deviceId,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    cancellation: cancellation,
  );

  @override
  Future<DeviceNotificationOpening> openNotification(
    String deviceId,
    String notificationId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'notifications.open',
    () => _notifications().openNotification(
      deviceId,
      notificationId,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    cancellation: cancellation,
    requiresVerifiedState: true,
  );

  @override
  Future<bool> dismissNotification(
    String deviceId,
    String notificationId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'notifications.dismiss',
    () => _notifications().dismissNotification(
      deviceId,
      notificationId,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    cancellation: cancellation,
    requiresVerifiedState: true,
  );

  @override
  Future<DeviceCallsSnapshot> readCalls(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'calls.list',
    () => _calls().readCalls(deviceId, cancellation: cancellation),
    deviceId: deviceId,
    cancellation: cancellation,
  );

  @override
  Future<void> requestCurrentCallUi(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'calls.open',
    () => _calls().requestCurrentCallUi(deviceId, cancellation: cancellation),
    deviceId: deviceId,
    cancellation: cancellation,
    requiresVerifiedState: true,
  );

  @override
  Future<void> requestPhoneApp(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'calls.openPhoneApp',
    () => _calls().requestPhoneApp(deviceId, cancellation: cancellation),
    deviceId: deviceId,
    cancellation: cancellation,
    requiresVerifiedState: true,
  );

  @override
  Future<List<DeviceObservationSnapshot>> readObservations({
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.list',
    () => _observation().readObservations(cancellation: cancellation),
    cancellation: cancellation,
  );

  @override
  Future<DeviceObservationSnapshot> readObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.status',
    () => _observation().readObservation(deviceId, cancellation: cancellation),
    deviceId: deviceId,
    cancellation: cancellation,
  );

  @override
  Future<DeviceObservationSnapshot> startObservation(
    String deviceId, {
    bool allowStart = true,
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.start',
    () => _observation().startObservation(
      deviceId,
      allowStart: allowStart,
      cancellation: cancellation,
    ),
    deviceId: deviceId,
    cancellation: cancellation,
    requiresVerifiedState: true,
  );

  @override
  Future<DeviceObservationSnapshot> stopObservation(
    String deviceId, {
    AdbCancellation? cancellation,
  }) => _observationOperation(
    'observation.stop',
    () => _observation().stopObservation(deviceId, cancellation: cancellation),
    deviceId: deviceId,
    cancellation: cancellation,
  );

  Future<T> _observationOperation<T>(
    String diagnosticLabel,
    Future<T> Function() action, {
    String? deviceId,
    AdbCancellation? cancellation,
    bool requiresVerifiedState = false,
  }) async {
    if (isDisposed()) throw const RequestFailure('disposed', '连接界面已关闭。');
    if (deviceId != null && (deviceId.isEmpty || deviceId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '请指定设备。');
    }
    // 状态核验先于改变观察意图或执行通知、电话动作。
    if (requiresVerifiedState && isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      cancellation?.check();
      return await action();
    } catch (error, stack) {
      final failure = switch (error) {
        CompanionException(:final code, :final message) ||
        AdbException(
          :final code,
          :final message,
        ) => RequestFailure(code, message),
        DeviceRecordsFailure(:final code, :final message, :final details) =>
          RequestFailure(code, message, details),
        _ => error,
      };
      _diagnostics.observationFailed(
        diagnosticLabel,
        deviceId,
        failure,
        watch.elapsedMilliseconds,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  @override
  Future<DeviceWakeReceipt> wakeDevice(
    String id, {
    String? connectionId,
  }) async {
    if (isDisposed()) throw const RequestFailure('disposed', '应用已关闭。');
    if (id.isEmpty ||
        id.contains('\u0000') ||
        connectionId != null &&
            (connectionId.isEmpty || connectionId.contains('\u0000'))) {
      throw const RequestFailure('invalid_argument', '设备或连接标识无效。');
    }
    if (isStateUnverified()) {
      throw const RequestFailure('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    final watch = Stopwatch()..start();
    try {
      return await wake(id, connectionId: connectionId);
    } catch (error) {
      _diagnostics.deviceWakeFailed(id, error, watch.elapsedMilliseconds);
      rethrow;
    }
  }
}
