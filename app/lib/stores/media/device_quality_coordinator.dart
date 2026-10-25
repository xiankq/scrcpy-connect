import 'package:scrcpy_connect/models/application_command_exception.dart';

typedef QualityJson = Map<String, dynamic>;
typedef QualityRequest = Future<QualityJson> Function(String, QualityJson);

/// 只保存一次设备偏好，并应用于当前各逻辑窗口的捕获代际；已关闭窗口不能成为重建目标。
class DeviceQualityCoordinator {
  DeviceQualityCoordinator({
    required this.request,
    required this.applyOutput,
    this.beginReconfigure,
    this.endReconfigure,
  });
  final QualityRequest request;
  final Future<QualityJson> Function(QualityJson) applyOutput;
  final void Function(String)? beginReconfigure;
  final void Function(String)? endReconfigure;
  final _queues = <String, Future<void>>{};
  final _stopped = <String>{};
  final _deviceEpoch = <String, int>{};
  bool _disposed = false;

  void beforeRequest(String command, QualityJson params) {
    if (command == 'session.stop' && params['sessionId'] is String) {
      _stopped.add(params['sessionId'] as String);
      if (_stopped.length > 4096) _stopped.remove(_stopped.first);
    }
    if (const ['devices.disconnect', 'devices.forget'].contains(command) &&
        params['deviceId'] is String) {
      final id = params['deviceId'] as String;
      _deviceEpoch[id] = (_deviceEpoch[id] ?? 0) + 1;
    }
  }

  Future<QualityJson> change(QualityJson params) {
    final device = params['deviceId'];
    if (device is! String || device.isEmpty) {
      throw const ApplicationCommandException('invalid_argument', '缺少设备标识。');
    }
    final epoch = _deviceEpoch[device] ?? 0;
    return _serialize(device, () => _change(params, device, epoch));
  }

  /// 将捕获启动、本地核验与偏好保存串行化。
  /// 读取旧设置的启动须先完成，之后再清点画质目标；后续启动只读取新保存的设备偏好。
  Future<QualityJson> open(String device, Future<QualityJson> Function() work) {
    final epoch = _deviceEpoch[device] ?? 0;
    return _serialize(device, () {
      if (!_current(device, epoch)) {
        throw const ApplicationCommandException('cancelled', '本次画面打开已取消。');
      }
      return work();
    });
  }

  Future<T> _serialize<T>(String device, Future<T> Function() work) {
    final previous = _queues[device] ?? Future<void>.value();
    final result = previous.then((_) => work());
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[device] = completed;
    return result.whenComplete(() {
      if (identical(_queues[device], completed)) _queues.remove(device);
    });
  }

  bool _current(String device, int epoch, [String? session]) =>
      !_disposed &&
      (_deviceEpoch[device] ?? 0) == epoch &&
      (session == null || !_stopped.contains(session));

  Future<QualityJson> _change(
    QualityJson params,
    String device,
    int epoch,
  ) async {
    if (!_current(device, epoch)) {
      throw const ApplicationCommandException('cancelled', '设备画面设置已取消。');
    }
    final saved = await request('session.quality', params);
    final quality = _object(saved['current']);
    if (!_current(device, epoch)) {
      throw const ApplicationCommandException(
        'cancelled',
        '设置已保存，设备连接已变化，当前画面未重建。',
      );
    }
    QualityJson listed;
    try {
      listed = await request('session.list', {'deviceId': device});
    } catch (error) {
      return {
        ...saved,
        'saved': true,
        'appliesNextSession': false,
        'needsRestart': false,
        'appliedToAll': false,
        'appliedSessions': <QualityJson>[],
        'skippedSessions': <String>[],
        'failures': [
          {
            'name': '当前画面',
            'reason': error is ApplicationCommandException
                ? error.message
                : '$error',
            if (error is ApplicationCommandException) 'code': error.code,
          },
        ],
        'reason': '画面设置已保存，当前画面状态未能核实，请重试应用。',
      };
    }
    final sessions = (listed['sessions'] as List? ?? const [])
        .map(_object)
        .where(
          (session) =>
              session['deviceId'] == device &&
              session['sessionId'] is String &&
              !const [
                'stopped',
                'stopping',
                'disconnected',
              ].contains(session['status']) &&
              session['recordOnly'] != true,
        )
        .toList();
    final applied = <QualityJson>[];
    final failures = <QualityJson>[];
    final skipped = <String>[];
    for (final session in sessions) {
      final id = session['sessionId'] as String;
      if (!_current(device, epoch, id)) {
        skipped.add(id);
        continue;
      }
      beginReconfigure?.call(id);
      try {
        final stream = await request('session.reconfigure', {
          'deviceId': device,
          'sessionId': id,
          for (final key in const [
            'qualityPreset',
            'maxSize',
            'maxFps',
            'videoBitRate',
            'videoCodec',
            'videoEncoder',
          ])
            if (quality.containsKey(key)) key: quality[key],
        });
        if (!_current(device, epoch, id)) {
          skipped.add(id);
          continue;
        }
        if (stream['sessionId'] != id || stream['deviceId'] != device) {
          throw const ApplicationCommandException(
            'session_changed',
            '重建回执不属于当前设备画面。',
          );
        }
        final output = await applyOutput(stream);
        if (!_current(device, epoch, id)) {
          skipped.add(id);
          continue;
        }
        applied.add({
          ...output,
          'sessionId': id,
          'name': session['name'] ?? session['packageName'] ?? '手机屏幕',
        });
      } catch (error) {
        if (!_current(device, epoch, id)) {
          skipped.add(id);
          continue;
        }
        failures.add({
          'sessionId': id,
          'name': session['name'] ?? session['packageName'] ?? '手机屏幕',
          'reason': error is ApplicationCommandException
              ? error.message
              : '$error',
          if (error is ApplicationCommandException) 'code': error.code,
        });
      } finally {
        endReconfigure?.call(id);
      }
    }
    return {
      ...saved,
      'saved': true,
      'appliesNextSession': false,
      'needsRestart': false,
      'appliedToAll': failures.isEmpty && _current(device, epoch),
      'appliedSessions': applied,
      'failures': failures,
      'skippedSessions': skipped,
      'reason': failures.isEmpty
          ? applied.isEmpty
                ? '画面设置已保存。'
                : '当前画面与后续画面已使用此设置。'
          : '画面设置已保存，部分当前画面尚未应用。',
    };
  }

  void dispose() {
    _disposed = true;
  }
}

QualityJson _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
