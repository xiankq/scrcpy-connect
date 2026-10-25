import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/application/events/application_snapshot_reader.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/application/transport/command_contract.dart';
import 'package:scrcpy_connect/application/transport/commands_generated.dart';
import 'package:scrcpy_connect/connection/device_coordinator.dart';
import 'package:scrcpy_connect/media/capture/session_coordinator.dart';
import 'package:scrcpy_connect/media/capture/device_audio_source_coordinator.dart';
import 'package:scrcpy_connect/media/capture/device_keep_awake_coordinator.dart';

/// 捕获的命名操作直接借用会话与设备音源所有者，不经过应用总分派器。
/// 播放器仍使用有界的 wire adapter；它只能到达此捕获模块。
final class MediaCaptureOperations {
  MediaCaptureOperations({
    required this._sessions,
    required this._audio,
    required this._keepAwake,
    required this._devices,
    required this._state,
    required this._scrcpy,
  });

  final SessionCoordinator _sessions;
  final DeviceAudioSourceCoordinator _audio;
  final DeviceKeepAwakeCoordinator _keepAwake;
  final DeviceCoordinator _devices;
  final ApplicationSnapshotReader _state;
  final ScrcpyClient _scrcpy;

  bool handles(ApplicationCommand command) =>
      _sessions.handles(command.wire) ||
      command.wire.startsWith('audio.') ||
      command == ApplicationCommand.mediaOpen ||
      command == ApplicationCommand.mediaStatus;

  Future<Map<String, dynamic>> readyVideo(Map<String, dynamic> receipt) =>
      execute(ApplicationCommand.sessionReady, receipt);

  Future<Map<String, dynamic>> stopVideo(
    String sessionId, {
    bool keepLaunchRecord = false,
  }) => execute(ApplicationCommand.sessionStop, {
    'sessionId': sessionId,
    if (keepLaunchRecord) 'keepLaunchRecord': true,
  });

  Future<Map<String, dynamic>> readyAudio(Map<String, dynamic> receipt) =>
      execute(ApplicationCommand.audioReady, receipt);

  Future<Map<String, dynamic>> presentAudio(Map<String, dynamic> receipt) =>
      execute(ApplicationCommand.audioPresentation, receipt);

  Future<Map<String, dynamic>> stopAudio(String sourceId, String deviceId) =>
      execute(ApplicationCommand.audioStop, {
        'sourceId': sourceId,
        'deviceId': deviceId,
      });

  Future<Map<String, dynamic>> audioSources() =>
      execute(ApplicationCommand.audioSources, const {});

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> params,
  ) async => execute(validateCommandRequest(command, params), params);

  Future<Map<String, dynamic>> execute(
    ApplicationCommand operation,
    Map<String, dynamic> params,
  ) async {
    validateTypedCommandRequest(operation, params);
    try {
      return await _execute(operation, params);
    } on AdbException catch (error, stack) {
      Error.throwWithStackTrace(
        ApplicationCommandException(error.code, error.message),
        stack,
      );
    }
  }

  Future<Map<String, dynamic>> _execute(
    ApplicationCommand operation,
    Map<String, dynamic> params,
  ) async {
    final command = operation.wire;
    if (_sessions.handles(command)) {
      final closing = operation == ApplicationCommand.sessionStop
          ? _sessions
                .currentSnapshots()
                .where(
                  (session) =>
                      (params['sessionId'] == null ||
                          params['sessionId'] == session['sessionId']) &&
                      (params['deviceId'] == null ||
                          params['deviceId'] == session['deviceId']),
                )
                .singleOrNull
          : null;
      final result = await _sessions.command(command, params);
      if (operation == ApplicationCommand.sessionList) {
        return {
          ...result,
          'sessions': [
            for (final session
                in (result['sessions'] as List).cast<Map<String, Object?>>())
              _state.projectSession(session),
          ],
        };
      }
      if (closing != null) {
        final device = closing['deviceId'] as String;
        try {
          await _keepAwake.sync(device);
        } catch (_) {
          // 窗口停止已经确认；保持唤醒的失败与清理证据由原所有者单独保留。
        }
        final projected = _state.projectSession({
          ...result,
          'deviceId': device,
          'status': 'stopped',
        });
        final cleanup = projected['keepActiveCleanup'] as Map;
        final healthySharedLease =
            _sessions.hasAudioOwner(device) &&
            projected['keepActiveLeaseActive'] == true &&
            cleanup['error'] == null &&
            cleanup['releasePending'] != true &&
            (cleanup['pendingCleanup'] as List).isEmpty;
        if (healthySharedLease ||
            (cleanup['leaseId'] == null &&
                cleanup['error'] == null &&
                cleanup['releasePending'] != true &&
                (cleanup['pendingCleanup'] as List).isEmpty)) {
          projected.remove('keepActiveCleanup');
        }
        return Map.from(projected);
      }
      if (result['sessionId'] is String && result['deviceId'] is String) {
        return Map.from(_state.projectSession(result));
      }
      return Map.from(result);
    }
    if (command.startsWith('audio.')) {
      return Map.from(await _audio.command(command, params));
    }
    if (operation == ApplicationCommand.mediaOpen) {
      if (params['kind'] != 'audio') {
        throw const ApplicationCommandException(
          'invalid_argument',
          '视频输入由窗口的精确捕获直接附着。',
        );
      }
      return Map.from(
        await _audio.openSource(
          params['sourceId'] as String,
          generation: params['generation'] as int? ?? 1,
        ),
      );
    }
    if (operation == ApplicationCommand.mediaStatus) {
      return await _sourceStatus(params['relayId'] as String);
    }
    throw ApplicationCommandException('unknown_command', '不是媒体捕获操作：$command');
  }

  Future<Map<String, dynamic>> _sourceStatus(String sourceId) async {
    final sessions = await _sessions.snapshots();
    for (final session in sessions) {
      if (session['videoSourceId'] != sourceId) continue;
      final connection = _devices.requireConnection(
        session['deviceId'] as String,
      );
      final status = await _scrcpy.sourceStatus(
        connection.device,
        captureRef: session['captureRef'] as String,
        sourceId: sourceId,
      );
      if (!identical(
        _devices.current(session['deviceId'] as String),
        connection,
      )) {
        throw const ApplicationCommandException('cancelled', '输入所属的设备连接已改变。');
      }
      return {
        'relayId': sourceId,
        'sourceId': sourceId,
        'status': status.status.name,
        'packets': status.packets,
        'bytes': status.bytes,
      };
    }
    return Map.from(await _audio.sourceStatus(sourceId));
  }
}
