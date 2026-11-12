import 'package:adb/adb.dart';
import 'package:scrcpy_connect/core/activities/activity_management.dart';
import 'package:scrcpy_connect/core/control/capture_resources.dart';
import 'package:scrcpy_connect/core/devices/device_observation_service.dart';
import 'package:scrcpy_connect/core/devices/device_service.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart'
    show RequestFailure;
import 'package:scrcpy_connect/core/events/runtime_events.dart';
import 'package:scrcpy_connect/core/files/file_transfer_service.dart';
import 'package:scrcpy_connect/core/files/file_transfers.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';

/// 活动只是资源所有者的只读组合；停止操作交给原能力并等待其实际关闭。
final class ActivityCatalog implements ActivityManagement {
  ActivityCatalog({
    required this._events,
    required this.diagnostics,
    required this._devices,
    required this._captures,
    required this._observations,
    required this._transfers,
    required this._disconnectDevice,
    required this._stopVideo,
    required this._stopAudio,
    required this._isDisposed,
  });
  final DiagnosticReporter diagnostics;
  final RuntimeEvents _events;
  final DeviceService _devices;
  final CaptureResources _captures;
  final DeviceObservationService _observations;
  final FileTransferService _transfers;
  final Future<void> Function(String) _disconnectDevice;
  final Future<void> Function(String) _stopVideo;
  final Future<void> Function(DeviceAudioTarget) _stopAudio;
  final bool Function() _isDisposed;

  @override
  Future<ActivityCollection> readActivities({String? deviceId}) =>
      _activityOperation(
        'activities.list',
        () => _readActivities(deviceId: deviceId),
      );
  @override
  Future<void> stopActivity(ActivityTarget target) =>
      _activityOperation('activities.stop', () => _stopActivity(target));

  Future<T> _activityOperation<T>(
    String label,
    Future<T> Function() action,
  ) async {
    final watch = Stopwatch()..start();
    try {
      return await action();
    } catch (error, stack) {
      final failure = error is AdbException
          ? RequestFailure(error.code, error.message)
          : error;
      diagnostics.command(
        label,
        const {},
        watch.elapsedMilliseconds,
        error: failure,
      );
      Error.throwWithStackTrace(failure, stack);
    }
  }

  Future<ActivityCollection> _readActivities({String? deviceId}) async {
    _checkOpen();
    if (deviceId != null) _checkId(deviceId);
    for (var attempt = 0; attempt < 4; attempt++) {
      final before = _events.cursor;
      final sessions = await _captures.readActivitySessions(deviceId: deviceId);
      final transfers = await _transfers.readTransfers();
      _checkOpen();
      final devices = _devices.readDevices();
      final observations = _observations.currentSnapshots();
      final sources = _captures.audioSnapshots();
      if (before.revision != _events.cursor.revision) continue;
      final names = {for (final device in devices) device.id: device.name};
      ActivitySnapshot activity(
        ActivityTarget target,
        String device,
        String name,
        String status,
        String impact,
      ) => ActivitySnapshot(
        target: target,
        deviceId: device,
        deviceName: names[device] ?? 'Android 设备',
        name: name,
        status: status,
        stopImpact: impact,
      );
      final result = [
        for (final device in devices)
          if (_devices.current(device.id) != null)
            activity(
              ActivityTarget.connection(device.id),
              device.id,
              '设备连接',
              'connected',
              '断开这台设备，并停止它的控制会话和传输任务；其他设备不受影响。',
            ),
        for (final session in sessions)
          activity(
            ActivityTarget.session(session.sessionId),
            session.deviceId,
            session.name,
            session.status,
            '仅关闭这个控制会话，手机应用任务交回设备，不会强停应用。',
          ),
        for (final observation in observations)
          if (observation.wanted)
            activity(
              ActivityTarget.observation(observation.deviceId),
              observation.deviceId,
              '通知与来电观察',
              observation.phase.name,
              '仅停止这台设备的通知与来电观察。',
            ),
        for (final source in sources)
          if (source.status != DeviceAudioStatus.stopped &&
              source.status != DeviceAudioStatus.error)
            activity(
              ActivityTarget.audio(
                DeviceAudioTarget(
                  deviceId: source.deviceId,
                  sourceId: source.sourceId,
                ),
              ),
              source.deviceId,
              '设备声音',
              source.status.name,
              '仅停止这台设备的这一代音源；设备连接及其他活动保持运行。',
            ),
        for (final transfer in transfers.transfers)
          if (!const {
                FileTransferStatus.completed,
                FileTransferStatus.skipped,
                FileTransferStatus.failed,
                FileTransferStatus.cancelled,
                FileTransferStatus.interrupted,
              }.contains(transfer.status) ||
              transfer.cleanupPending)
            activity(
              ActivityTarget.transfer(transfer.id),
              transfer.deviceId,
              transfer.name,
              transfer.status.name,
              '仅取消这一项传输；已完成的文件不回滚。',
            ),
      ];
      return ActivityCollection(
        activities: [
          for (final item in result)
            if (deviceId == null || item.deviceId == deviceId) item,
        ],
        pendingApplications: [
          for (final session in sessions)
            if (session.needsLaunchReview) session,
        ],
      );
    }
    throw const RequestFailure('state_busy', '应用状态持续变化，尚未取得完整活动列表，请重试。');
  }

  Future<void> _stopActivity(ActivityTarget target) async {
    _checkOpen();
    // 无效的身份必须先拒绝，不能取消任何正在进行的连接或媒体意图。
    switch (target) {
      case ConnectionActivity(:final deviceId):
        _checkId(deviceId);
        await _disconnectDevice(deviceId);
      case SessionActivityTarget(:final sessionId):
        _checkId(sessionId);
        await _stopVideo(sessionId);
      case ObservationActivity(:final deviceId):
        _checkId(deviceId);
        await _observations.stopObservation(deviceId);
      case TransferActivity(:final transferId):
        _checkId(transferId);
        await _transfers.cancelTransfer(FileTransferTarget.task(transferId));
      case AudioActivity(:final source):
        _checkId(source.deviceId);
        final id = source.sourceId;
        if (id == null) {
          throw const RequestFailure('invalid_argument', '请指定这一代音源。');
        }
        _checkId(id);
        final current = _captures
            .audioSnapshots()
            .where(
              (item) => item.sourceId == id && item.deviceId == source.deviceId,
            )
            .firstOrNull;
        if (current == null) {
          throw const RequestFailure('not_found', '这代音源已结束。');
        }
        await _stopAudio(source);
    }
  }

  void _checkOpen() {
    if (_isDisposed()) throw const RequestFailure('disposed', '应用已关闭。');
  }
}

void _checkId(String id) {
  if (id.isEmpty || id.contains('\u0000')) {
    throw const RequestFailure('invalid_argument', '活动身份无效。');
  }
}
