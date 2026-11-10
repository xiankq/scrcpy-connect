import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/services/media/video_quality_policy.dart';
import 'package:scrcpy_connect/services/media/virtual_display_policy.dart';
import 'package:scrcpy_connect/stores/media/app_launch_store.dart';
import 'package:scrcpy_connect/stores/media/physical_display_lease.dart';
import 'package:scrcpy_connect/models/session_policy.dart';
import 'package:scrcpy_connect/services/media/session_shell.dart';
import 'package:scrcpy_connect/services/connection/scrcpy_server_queries.dart';

export 'package:scrcpy_connect/models/session_policy.dart';

typedef SessionJson = Map<String, dynamic>;

final class _SessionWork {
  final stop = AdbCancellation();
  String? failure;
  void cancel([String code = 'cancelled']) {
    failure ??= code;
    stop.cancel();
  }
}

final class _Capture {
  _Capture(this.sdk, this.generation);
  final ScrcpySession sdk;
  final int generation;
  ScrcpySessionInfo? info;
  StreamSubscription<ScrcpyEvent>? observer;
  Future<void>? closing;
  bool closed = false;
  bool expectedStop = false;
}

final class _LogicalSession {
  _LogicalSession(this.id, this.deviceId, this.connection, this.state);
  final String id, deviceId;
  final DeviceConnection connection;
  final SessionJson state;
  final initial = _SessionWork();
  final captures = <_Capture>[];
  final captureReservations = <int>{};
  final operations = <Future<void>>{};
  final works = <_SessionWork>{};
  _Capture? current;
  Future<SessionJson>? starting;
  Future<void>? stopping;
  Future<SessionJson>? resizing;
  bool qualityPreparing = false;
  bool revoked = false;
  bool launchBegan = false;
  bool launchSubmitted = false;
  bool qualityCleanupPending = false;
  AppLaunchPermit? permit;
  PhysicalDisplayLease? physicalDisplay;
  Timer? handoff;
  bool get rebuilding => state['qualityRebuilding'] == true;
}

/// 能力查询属于发起时的精确连接；同设备重连也不能继承旧查询。
final class _SessionQuery {
  _SessionQuery(this.connection);
  final DeviceConnection connection;
  final stop = AdbCancellation();
  final settled = Completer<void>();
}

/// 产品窗口与精确 SDK 捕获的唯一对应关系。
///
/// 连接、捕获、渲染器各有独立身份；失败的关闭仍占容量并保留重试权。
/// 应用打开先持久登记，再向控制队列提交一次，结果未知时绝不重放。
final class SessionCoordinator {
  SessionCoordinator({
    required this._scrcpy,
    required this._requireConnection,
    required this._launches,
    required this._serverQueries,
    required void Function(String, String, Map<String, Object?>) emit,
    Map<String, dynamic> Function()? settings,
    this.policy = const SessionPolicy(),
    DateTime Function()? now,
    String Function()? newId,
    this.onAudioEligibilityChanged,
  }) : _emitEvent = emit,
       _settings = settings ?? (() => <String, dynamic>{}),
       _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4 {
    policy.validate();
  }

  final ScrcpyClient _scrcpy;
  final DeviceConnection Function(String) _requireConnection;
  final AppLaunchStore _launches;
  // 借用应用唯一清单查询所有者；窗口关闭不能关闭并行的安装应用查询。
  final ScrcpyServerQueries _serverQueries;
  final void Function(String, String, Map<String, Object?>) _emitEvent;
  final Map<String, dynamic> Function() _settings;
  final DateTime Function() _now;
  final String Function() _newId;
  final SessionPolicy policy;

  /// 同步通知资格变化；回调可登记异步音源排空，但不能延迟撤销准入。
  final void Function(String deviceId)? onAudioEligibilityChanged;
  final _sessions = <String, _LogicalSession>{};
  final _queries = <_SessionQuery>{};
  final _clipboardProbes = <ScrcpySession, DeviceConnection>{};
  final _clipboardTails = <String, Future<void>>{};
  bool Function(String device, String session, int generation)?
  _clipboardAdmission;

  void Function() bindClipboardAdmission(
    bool Function(String, String, int) check,
  ) {
    _clipboardAdmission = check;
    return () {
      if (identical(_clipboardAdmission, check)) _clipboardAdmission = null;
    };
  }

  Future<void> _qualityTail = Future.value();
  Future<void>? _closing;
  bool _closed = false;

  int get _capacityUsed => _sessions.values.fold(
    0,
    (count, slot) =>
        count +
        math.max(
          1,
          slot.captures.where((capture) => !capture.closed).length +
              slot.captureReservations.length,
        ),
  );

  bool handles(String command) => const {
    'apps.launch',
    'clipboard.get',
    'clipboard.set',
    'session.start',
    'session.stop',
    'session.list',
    'session.ready',
    'session.frame',
    'session.key',
    'session.text',
    'session.touch',
    'session.scroll',
    'session.clipboard',
    'session.rotate',
    'session.screen',
    'session.refresh',
    'session.pause',
    'session.resume',
    'session.launch',
    'session.display',
    'session.quality',
    'session.quality.options',
    'session.reconfigure',
  }.contains(command);

  /// 包含启动中窗口及尚未到期的画质交接；未知清理不产生新的音源资格。
  bool hasAudioOwner(String deviceId) => _sessions.values.any(
    (slot) =>
        slot.deviceId == deviceId &&
        !slot.revoked &&
        (slot.handoff != null ||
            const [
              'starting',
              'streaming',
              'paused',
              'awaiting_renderer',
            ].contains(slot.state['status'])),
  );

  Future<SessionJson> command(String command, SessionJson params) =>
      _boundary(() => _command(command, Map.of(params)));

  Future<SessionJson> _command(String command, SessionJson params) async {
    if (!handles(command)) _fail('unknown_command', '不是控制窗口操作。');
    if (command == 'session.list') {
      return {
        'sessions': await snapshots(deviceId: params['deviceId'] as String?),
      };
    }
    if (command == 'session.stop') {
      final id = params['sessionId'];
      if (id is String && !_sessions.containsKey(id)) {
        final closed = await _launches.close(
          id,
          deviceId: params['deviceId'] as String?,
        );
        if (!closed) _fail('session_not_found', '找不到这个控制窗口或待核对记录。');
        return {
          'sessionId': id,
          'stopped': true,
          'recordOnly': true,
          'applicationStopped': false,
        };
      }
      final slot = _select(params);
      await _stop(slot, keepLaunchRecord: params['keepLaunchRecord'] == true);
      return {
        'sessionId': slot.id,
        'stopped': true,
        'applicationStopped': false,
      };
    }
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    if (command == 'clipboard.get' || command == 'clipboard.set') {
      return _query(
        _string(params, 'deviceId'),
        (connection, stop) => _clipboard(command, params, connection, stop),
      );
    }
    if (command == 'session.start' || command == 'apps.launch') {
      return _start(params);
    }
    if (command == 'session.quality.options') {
      return _query(
        _string(params, 'deviceId'),
        (connection, stop) => _qualityOptions(params, connection, stop),
      );
    }
    if (command == 'session.quality') {
      return _query(
        _string(params, 'deviceId'),
        (connection, stop) => _qualitySelection(params, connection, stop),
      );
    }
    final slot = _select(params);
    if (command == 'session.reconfigure') return _reconfigure(slot, params);
    final capture = _bound(slot, params);
    return _control(slot, capture, command, params);
  }

  Future<List<SessionJson>> snapshots({String? deviceId}) async {
    final unresolved = await _launches.unresolved(deviceId: deviceId);
    final active = currentSnapshots(deviceId: deviceId);
    final ids = active.map((value) => value['sessionId']).toSet();
    for (final record in unresolved) {
      if (!ids.contains(record.operationId)) active.add(record.projection);
    }
    return active;
  }

  /// 同步读取当前窗口事实，供组合层附加设备投影；不恢复持久启动记录。
  List<SessionJson> currentSnapshots({String? deviceId}) => [
    for (final slot in _sessions.values)
      if (deviceId == null || slot.deviceId == deviceId) Map.of(slot.state),
  ];

  void rendererFailed(String sessionId, int captureGeneration, Object error) {
    final slot = _sessions[sessionId];
    if (_closed ||
        slot == null ||
        slot.revoked ||
        !slot.rebuilding ||
        slot.current?.generation != captureGeneration) {
      return;
    }
    slot.state.addAll({
      'status': 'failed',
      'qualityRebuilding': false,
      'qualityRebuildOutcome': 'failed',
      'qualityRetryable': true,
      'qualityFailureCode': _code(error),
      'reason': '新画面的本机输出未能完成，请重试画质设置。',
    });
    _changed(slot);
  }

  _LogicalSession _select(SessionJson params) {
    final id = params['sessionId'], device = params['deviceId'];
    final candidates = _sessions.values
        .where(
          (slot) =>
              (id == null || slot.id == id) &&
              (device == null || slot.deviceId == device),
        )
        .toList();
    if (candidates.isEmpty) _fail('session_not_found', '找不到这个控制窗口。');
    if (candidates.length != 1) _fail('ambiguous_session', '请指定要操作的控制窗口。');
    return candidates.single;
  }

  _Capture _bound(
    _LogicalSession slot,
    SessionJson params, {
    bool input = false,
  }) {
    final capture = slot.current;
    if (slot.revoked ||
        capture == null ||
        capture.closed ||
        capture.expectedStop) {
      _fail('session_stopped', '控制窗口已停止。');
    }
    _checkConnection(slot);
    if (params['expectedCaptureRef'] != null &&
            params['expectedCaptureRef'] != capture.sdk.id ||
        params['captureGeneration'] != null &&
            params['captureGeneration'] != capture.generation ||
        input && params['captureGeneration'] != capture.generation) {
      _fail('stale_capture', '画面已重建，已取消旧画面的请求。');
    }
    return capture;
  }

  void _checkConnection(_LogicalSession slot) {
    if (!identical(_requireConnection(slot.deviceId), slot.connection)) {
      _fail('stale_connection', '设备连接已更换，本次控制窗口不能继续操作。');
    }
  }

  void _check(_LogicalSession slot, _SessionWork work) {
    if (_closed || slot.revoked || work.stop.isCancelled) {
      _fail(work.failure ?? 'cancelled', '这次窗口操作已取消或超时。');
    }
    _checkConnection(slot);
  }

  void _changed(_LogicalSession slot, [String type = 'session.updated']) {
    _publishEvent(type, slot.deviceId, Map<String, Object?>.of(slot.state));
  }

  void _publishEvent(String type, String device, Map<String, Object?> data) {
    try {
      _emitEvent(type, device, data);
    } catch (_) {
      // 观察者失败不能中断捕获启动或回收；真实执行错误仍由命令 Future 报告。
    }
  }

  Future<T> _track<T>(_LogicalSession slot, Future<T> future) {
    final settled = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    slot.operations.add(settled);
    unawaited(settled.then((_) => slot.operations.remove(settled)));
    return future;
  }

  Future<SessionJson> _query(
    String deviceId,
    Future<SessionJson> Function(DeviceConnection, AdbCancellation) action,
  ) {
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    final query = _SessionQuery(_requireConnection(deviceId));
    _queries.add(query);
    return Future.sync(() => action(query.connection, query.stop))
        .then((value) {
          if (_closed || query.stop.isCancelled) {
            _fail('cancelled', '本次能力查询已撤销。');
          }
          if (!identical(_requireConnection(deviceId), query.connection)) {
            _fail('stale_connection', '设备连接已更换，本次查询结果已失效。');
          }
          return value;
        })
        .whenComplete(() {
          // 取消只撤准入，完成信号必须等原查询及其迟到会话实际退出。
          _queries.remove(query);
          query.settled.complete();
        });
  }

  Future<void> _closeClipboardProbe(ScrcpySession session) async {
    await session.close();
    _clipboardProbes.remove(session);
  }

  Future<SessionJson> _clipboard(
    String command,
    SessionJson params,
    DeviceConnection connection,
    AdbCancellation stop,
  ) {
    final device = _string(params, 'deviceId');
    final admission = _clipboardAdmission;
    final slot = params['sessionId'] == null ? null : _select(params);
    final capture = slot == null ? null : _bound(slot, params);
    void check() {
      stop.check();
      if (_closed || !identical(_requireConnection(device), connection)) {
        _fail('cancelled', '剪贴板所属连接已停止。');
      }
      if (slot != null &&
          (!identical(_sessions[slot.id], slot) ||
              !identical(_bound(slot, params), capture) ||
              slot.state['status'] != 'streaming')) {
        _fail('stale_capture', '剪贴板所属画面已停止或更换。');
      }
      if (params['automatic'] == true &&
          (slot == null ||
              params['clipboardGeneration'] is! int ||
              admission?.call(
                    device,
                    slot.id,
                    params['clipboardGeneration'] as int,
                  ) !=
                  true)) {
        _fail('cancelled', '画面已失焦或自动剪贴板已暂停。');
      }
    }

    check();
    final result = (_clipboardTails[device] ?? Future<void>.value()).then((_) {
      stop.check();
      check();
      return _clipboardProbe(
        command,
        params,
        connection,
        stop,
        capture?.sdk,
        check,
      );
    });
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _clipboardTails[device] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_clipboardTails[device], tail)) {
          _clipboardTails.remove(device);
        }
      }),
    );
    return result;
  }

  Future<SessionJson> _clipboardProbe(
    String command,
    SessionJson params,
    DeviceConnection connection,
    AdbCancellation stop,
    ScrcpySession? window,
    void Function() check,
  ) async {
    final device = _string(params, 'deviceId');
    for (final entry in _clipboardProbes.entries.toList()) {
      if (identical(entry.value, connection)) {
        await _closeClipboardProbe(entry.key);
      }
    }
    ScrcpySession? probe;
    void Function()? detach;
    try {
      // Upstream suppresses GET_CLIPBOARD when autosync is enabled. Snapshot probes
      // have no video/audio and never turn on the screen; window captures own listeners.
      probe = await _scrcpy.createSession(
        connection.device,
        options: const ScrcpyOptions(
          video: false,
          audio: false,
          powerOn: false,
          clipboardAutosync: false,
        ),
        cancellation: stop,
      );
      _clipboardProbes[probe] = connection;
      final owned = probe;
      detach = stop.onCancel(() {
        unawaited(owned.close().catchError((Object _) {}));
      });
      await probe.start(cancellation: stop);
      check();
      if (command == 'clipboard.set') {
        final text = params['text'];
        if (text is! String) _fail('invalid_argument', '请提供文字剪贴板内容。');
        final writer = window ?? probe;
        check();
        final receipt = await writer.sendControl(ScrcpyClipboard(text));
        check();
        if (receipt.completion !=
            ScrcpyControlCompletion.clipboardAcknowledged) {
          _fail('clipboard_result_unknown', '设备尚未确认收到剪贴板写入。');
        }
        final actual = await probe.readClipboard();
        check();
        if (actual != text) {
          _fail('clipboard_not_applied', '设备剪贴板读回内容不一致，请主动核对。');
        }
        return {'deviceId': device, 'source': 'scrcpy', 'applied': true};
      }
      final text = await probe.readClipboard();
      check();
      final current = _sessions[params['sessionId']]?.current;
      return {
        'deviceId': device,
        'source': 'scrcpy',
        'text': text,
        'available': true,
        if (current != null) 'captureRef': current.sdk.id,
        if (current != null) 'captureGeneration': current.generation,
      };
    } on ScrcpyCreationCleanupFailure catch (failure) {
      _clipboardProbes[failure.session] = connection;
      rethrow;
    } finally {
      detach?.call();
      if (probe != null) await _closeClipboardProbe(probe);
    }
  }

  /// 截止时关闭原捕获唤醒执行，仍等待原 Future；没有逐请求取消的动作结果保持未知。
  Future<T> _native<T>(
    _LogicalSession slot,
    _SessionWork work,
    _Capture capture,
    Future<T> Function() action,
    Duration duration,
  ) async {
    _check(slot, work);
    void revoke() {
      unawaited(_closeCapture(capture).catchError((Object _, StackTrace _) {}));
    }

    final detach = work.stop.onCancel(revoke);
    final timer = Timer(duration, () => work.cancel('timeout'));
    try {
      final value = await action();
      _check(slot, work);
      return value;
    } catch (error, stack) {
      if (work.failure != null) {
        Error.throwWithStackTrace(
          RequestFailure(work.failure!, '这次捕获操作已撤销，仍需核对远端结果。'),
          stack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      timer.cancel();
      detach();
    }
  }

  Future<void> _closeCapture(_Capture capture) {
    if (capture.closed) return Future.value();
    if (capture.closing case final pending?) return pending;
    capture.expectedStop = true;
    final result = () async {
      await capture.sdk.close();
      await capture.observer?.cancel();
      capture.closed = true;
    }();
    return capture.closing = result.catchError((
      Object error,
      StackTrace stack,
    ) {
      capture.closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  void _observe(_LogicalSession slot, _Capture capture) {
    capture.observer = capture.sdk.events.listen(
      (event) {
        if (capture.closed ||
            !identical(slot.current, capture) ||
            slot.revoked) {
          return;
        }
        switch (event) {
          case ScrcpyClipboardChanged(:final text):
            _publishEvent('clipboard.changed', slot.deviceId, {
              'sessionId': slot.id,
              'captureRef': capture.sdk.id,
              'captureGeneration': capture.generation,
              'text': text,
              'connectionId': slot.connection.device.id,
              'source': 'scrcpy',
            });
          case ScrcpyStopped(:final reason):
            if (!capture.expectedStop) {
              _failedCapture(slot, reason ?? 'capture_stopped');
            }
        }
      },
      onError: (Object error, StackTrace _) {
        if (!capture.expectedStop && identical(slot.current, capture)) {
          _failedCapture(slot, '$error');
        }
      },
    );
  }

  void _failedCapture(_LogicalSession slot, String reason) {
    slot.state.addAll({
      'status': 'failed',
      'failureCode': 'capture_stopped',
      'reason': reason,
    });
    slot.handoff?.cancel();
    slot.handoff = null;
    _changed(slot, 'session.failed');
    final task = _stop(slot, keepLaunchRecord: true);
    unawaited(task.catchError((Object _, StackTrace _) {}));
  }

  Future<SessionJson> _start(SessionJson params) {
    final device = _string(params, 'deviceId');
    final id = params['sessionId'] as String? ?? _newId();
    final previous = _sessions[id];
    if (previous != null) {
      if (previous.deviceId != device ||
          previous.state['packageName'] != params['packageName']) {
        _fail('session_conflict', '窗口身份已用于另一次操作。');
      }
      return previous.starting ?? Future.value(Map.of(previous.state));
    }
    if (_capacityUsed >= 16) {
      _fail('session_capacity', '控制窗口数量已达上限。');
    }
    final package = params['packageName'];
    if (package != null && (package is! String || !_package(package))) {
      _fail('invalid_argument', '应用包名无效。');
    }
    _displayDimensions(params, minimum: package == null ? 320 : 2);
    if (params['displayAuto'] != null && params['displayAuto'] is! bool) {
      _fail('invalid_argument', '自动显示模式必须为布尔值。');
    }
    final connection = _requireConnection(device);
    final quality = _quality(device, params);
    final slot = _LogicalSession(id, device, connection, {
      'id': id,
      'sessionId': id,
      'deviceId': device,
      'name': params['name'] ?? package ?? '手机屏幕',
      'packageName': package,
      'kind': package == null ? 'screen' : 'app',
      'status': 'starting',
      'captureGeneration': 1,
      'generation': 1,
      'createdAt': _now().millisecondsSinceEpoch ~/ 1000,
      'audio': false,
      'quality': VideoQualityPolicy.current(quality),
      'videoCodec': quality['videoCodec'],
      'videoEncoder': quality['videoEncoder'],
      'displayAuto': params['displayAuto'] == true,
    });
    _sessions[id] = slot;
    _changed(slot, 'session.starting');
    final start = _track(slot, _begin(slot, params, quality));
    slot.starting = start;
    return start;
  }

  Future<SessionJson> _begin(
    _LogicalSession slot,
    SessionJson params,
    SessionJson quality,
  ) async {
    try {
      onAudioEligibilityChanged?.call(slot.deviceId);
      final capture = await _spawn(slot, slot.initial, params, quality, 1);
      _check(slot, slot.initial);
      slot.current = capture;
      _install(slot, capture, quality);
      _observe(slot, capture);
      _changed(slot);
      return Map.of(slot.state);
    } catch (error, stack) {
      slot.permit?.cancel();
      Object? recordFailure;
      if (slot.launchBegan) {
        try {
          await _launches.finish(
            slot.id,
            failureCode: slot.launchSubmitted
                ? 'app_launch_unknown'
                : 'not_submitted',
          );
        } catch (error) {
          recordFailure = error;
        }
      }
      slot.state.addAll({
        'status': 'failed',
        'failureCode': _code(error),
        'reason': '$error',
      });
      if (slot.launchBegan) slot.state['launchOutcome'] = 'unknown';
      Object? cleanup;
      for (final capture in slot.captures.toList()) {
        try {
          await _closeCapture(capture);
        } catch (error) {
          cleanup ??= error;
        }
      }
      // 未确认退出的捕获仍可能使用原显示；不能提前恢复覆盖。
      if (slot.captures.every((capture) => capture.closed)) {
        try {
          await _closePhysicalDisplay(slot);
        } catch (error) {
          cleanup ??= error;
        }
      }
      try {
        onAudioEligibilityChanged?.call(slot.deviceId);
      } catch (error) {
        cleanup ??= error;
      }
      _changed(slot, 'session.failed');
      if (cleanup != null) {
        _fail('session_cleanup_unconfirmed', '窗口启动失败，精确捕获尚未确认释放，请重试停止。');
      }
      if (recordFailure != null) throw recordFailure;
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<_Capture> _spawn(
    _LogicalSession slot,
    _SessionWork work,
    SessionJson params,
    SessionJson quality,
    int generation, {
    int? retainedTask,
  }) async {
    _check(slot, work);
    final shell = SessionShell(slot.connection, policy.shellTimeout);
    final api = await shell.run(
      'getprop ro.build.version.sdk',
      cancellation: work.stop,
      maxBytes: 128,
      requireExitCode: false,
    );
    final apiLevel = int.tryParse(api.stdout.trim());
    final package = slot.state['packageName'] as String?;
    if (apiLevel == null || apiLevel < (package == null ? 21 : 29)) {
      _fail('unsupported', '这台设备的 Android 版本不支持该窗口。');
    }
    slot.state['apiLevel'] = apiLevel;
    if (package != null ||
        quality['videoCodec'] != 'h264' ||
        quality['videoEncoder'] != null) {
      _validateEncoder(
        quality,
        await _serverQueries.encoders(slot.connection, work.stop),
      );
      _check(slot, work);
    }
    ScrcpyDisplayOptions? display;
    if (package == null && generation == 1) {
      final dimensions = _displayDimensions(params, minimum: 320);
      if (dimensions != null) {
        await _physicalDisplay(slot, work, dimensions.width, dimensions.height);
      }
    } else if (package != null) {
      final metrics = await shell.metrics(work.stop);
      final fitted = VirtualDisplayPolicy.fit({
        ...params,
        'displayWidth': params['displayWidth'] ?? metrics.width,
        'displayHeight': params['displayHeight'] ?? metrics.height,
      }, quality['maxSize']);
      final width = _integer(fitted, 'displayWidth', 2, 4096);
      final height = _integer(fitted, 'displayHeight', 2, 4096);
      display = ScrcpyDisplayOptions(
        width: width,
        height: height,
        density: scaledDisplayDensity(metrics, width, height),
      );
      slot.state.addAll({
        'displayWidth': width,
        'displayHeight': height,
        'displayDensity': display.density,
        'displaySize': {'width': width, 'height': height},
      });
    }
    _check(slot, work);
    ScrcpySession sdk;
    try {
      sdk = await _scrcpy.createSession(
        slot.connection.device,
        options: ScrcpyOptions(
          // 独立窗口需读取服务端的 New display 编号；整机捕获只保留警告。
          logLevel: display == null ? ScrcpyLogLevel.warn : ScrcpyLogLevel.info,
          audio: false,
          videoCodec: ScrcpyVideoCodec.values.byName(
            quality['videoCodec'] as String,
          ),
          videoEncoder: quality['videoEncoder'] as String?,
          maxSize: quality['maxSize'] as int,
          maxFps: quality['maxFps'] as int,
          videoBitRate: quality['videoBitRate'] as int,
          display: display,
          powerOn: false,
          clipboardAutosync: true,
          vdDestroyContent: false,
          flexDisplay: true,
          vdSystemDecorations: false,
          repeatPreviousFrameAfterUs: 100000,
        ),
      );
    } on ScrcpyCreationCleanupFailure catch (error) {
      slot.captures.add(_Capture(error.session, generation));
      slot.captureReservations.remove(generation);
      rethrow;
    }
    final capture = _Capture(sdk, generation);
    slot.captures.add(capture);
    // 创建预约在真实句柄登记时转成交付责任，不能与同一捕获重复占名额。
    slot.captureReservations.remove(generation);
    _check(slot, work);
    await _native(slot, work, capture, sdk.startControl, policy.startupTimeout);
    if (package != null) {
      final displayId = await _ownedDisplay(slot, work, capture);
      if (retainedTask != null) {
        await shell.moveTask(retainedTask, displayId, cancellation: work.stop);
        slot.state['taskId'] = retainedTask;
      } else {
        slot.permit = await _launches.begin(
          operationId: slot.id,
          sessionId: slot.id,
          deviceId: slot.deviceId,
          packageName: package,
        );
        slot.launchBegan = true;
        _check(slot, work);
        if (!slot.permit!.claim()) _fail('cancelled', '这次应用打开已撤销。');
        slot.launchSubmitted = true;
        final receipt = await _native(
          slot,
          work,
          capture,
          () => sdk.sendControl(ScrcpyStartApp(package)),
          policy.controlTimeout,
        );
        if (receipt.completion != ScrcpyControlCompletion.written) {
          _fail('app_launch_unknown', '没有收到应用打开消息的写入确认。');
        }
        slot.state.addAll({
          'launchOperationId': slot.id,
          'launchOutcome': 'sent',
        });
      }
      // 只接受本捕获进程日志中的显示身份，不从全局显示列表猜测。
      capture.info = await _native(
        slot,
        work,
        capture,
        () => sdk.awaitMedia(generation: generation),
        policy.startupTimeout,
      );
      _validateMedia(capture);
      if (retainedTask == null) {
        await _launches.finish(slot.id);
        slot.state['launchOutcome'] = 'observed';
      }
      slot.state['displayId'] = displayId;
    } else {
      capture.info = await _native(
        slot,
        work,
        capture,
        () => sdk.awaitMedia(generation: generation),
        policy.startupTimeout,
      );
      _validateMedia(capture);
    }
    return capture;
  }

  void _validateMedia(_Capture capture) {
    final info = capture.info;
    if (info == null ||
        !info.controlReady ||
        !info.mediaReady ||
        info.source == null ||
        info.id != capture.sdk.id ||
        info.width <= 0 ||
        info.height <= 0) {
      _fail('media_not_ready', '捕获没有交付真实首关键帧与精确媒体源。');
    }
  }

  Future<int> _ownedDisplay(
    _LogicalSession slot,
    _SessionWork work,
    _Capture capture,
  ) async {
    final deadline = _now().add(policy.displayIdentityTimeout);
    while (true) {
      final process = await _native(
        slot,
        work,
        capture,
        capture.sdk.processInfo,
        policy.controlTimeout,
      );
      final text = utf8.decode(process.logTail, allowMalformed: true);
      final ids = RegExp(r'New display:[^\r\n]*\(id=(\d+)\)(?:\r?\n)')
          .allMatches(text)
          .map((m) => int.parse(m[1]!))
          .toSet();
      if (ids.length > 1 || ids.contains(0)) {
        _fail('display_identity_unverified', '捕获日志中的显示身份不唯一。');
      }
      if (ids.length == 1) return ids.single;
      if (!_now().isBefore(deadline)) {
        _fail('display_identity_unverified', '未能从当前捕获日志核实独立显示。');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
      _check(slot, work);
    }
  }

  void _install(_LogicalSession slot, _Capture capture, SessionJson quality) {
    final info = capture.info!;
    slot.state.remove('frameCount');
    slot.state.addAll({
      'captureRef': capture.sdk.id,
      'captureGeneration': capture.generation,
      'videoSourceId': info.source!.sourceId,
      'width': info.width,
      'height': info.height,
      'videoCodec': info.videoCodec.name,
      'videoEncoder': quality['videoEncoder'],
      'codec': info.videoCodec.name,
      'quality': VideoQualityPolicy.current(quality),
      'status': 'awaiting_renderer',
      'awaitingSession': true,
      'textureId': null,
      'generation': capture.generation,
      'processId': info.processId,
      'processStarted': info.processStarted,
    });
  }

  Future<void> _stop(_LogicalSession slot, {bool keepLaunchRecord = false}) {
    if (slot.stopping case final pending?) return pending;
    slot.revoked = true;
    slot.permit?.cancel();
    slot.initial.cancel();
    for (final work in slot.works.toList()) {
      work.cancel();
    }
    slot.handoff?.cancel();
    slot.handoff = null;
    slot.state['status'] = 'stopping';
    Object? audioFailure;
    StackTrace? audioFailureStack;
    try {
      onAudioEligibilityChanged?.call(slot.deviceId);
    } catch (error, stack) {
      // 资格撤销失败仍必须释放精确捕获；保留窗口，让后继停止重试依赖收尾。
      audioFailure = error;
      audioFailureStack = stack;
    }
    // 先发起精确停止，唤醒控制/首帧等待，再等待应用执行退出；不互相等待自己。
    final earlyCloses = <_Capture, Future<void>>{};
    for (final capture in slot.captures.toList()) {
      final close = _closeCapture(capture);
      earlyCloses[capture] = close;
      unawaited(close.catchError((Object _, StackTrace _) {}));
    }
    final result = () async {
      // 关闭失败可能无法唤醒首帧或控制等待；先报告失败并释放停止重试入口，
      // 原操作及捕获仍登记在此窗口，后续停止继续沿原句柄排空。
      await Future.wait(earlyCloses.values);
      while (slot.operations.isNotEmpty) {
        await Future.wait(slot.operations.toList());
      }
      Object? failure = audioFailure;
      StackTrace? failureStack = audioFailureStack;
      for (final capture in slot.captures.toList()) {
        try {
          await (earlyCloses[capture] ?? _closeCapture(capture));
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (slot.captures.every((capture) => capture.closed)) {
        try {
          await _closePhysicalDisplay(slot);
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
      if (slot.launchBegan) {
        if (keepLaunchRecord) {
          await _launches.finish(slot.id, failureCode: 'renderer_start_failed');
        } else {
          await _launches.close(slot.id, deviceId: slot.deviceId);
        }
      }
      if (identical(_sessions[slot.id], slot)) _sessions.remove(slot.id);
      slot.state['status'] = 'stopped';
      _changed(slot, 'session.stopped');
    }();
    return slot.stopping = result.catchError((Object error, StackTrace stack) {
      slot.stopping = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _closePhysicalDisplay(_LogicalSession slot) async {
    final lease = slot.physicalDisplay;
    if (lease == null || lease.isClosed) return;
    // 调用处已等所有精确捕获关闭；页面状态和错误码都不能代替此事实。
    if (!slot.captures.every((capture) => capture.closed)) {
      _fail('display_cleanup_unconfirmed', '捕获尚未实际关闭，不能释放显示租约。');
    }
    final connection = slot.connection;
    final facts = await connection.client.services.connectionFacts(
      connection.device,
    );
    if (facts.closed) {
      await lease.detachClosedConnection();
      return;
    }
    try {
      await lease.close();
    } catch (error, stack) {
      // 正常恢复过程中断链也只接受同一句柄的 closed 事实，不解析错误字符串。
      final latest = await connection.client.services.connectionFacts(
        connection.device,
      );
      if (!latest.closed) Error.throwWithStackTrace(error, stack);
      await lease.detachClosedConnection();
    }
  }

  Future<void> stopForConnection(
    String deviceId,
    DeviceConnection connection,
  ) async {
    final queries = _queries
        .where((query) => identical(query.connection, connection))
        .toList();
    for (final query in queries) {
      query.stop.cancel();
    }
    _serverQueries.cancelForConnection(connection);
    final selected = _sessions.values
        .where(
          (slot) =>
              slot.deviceId == deviceId &&
              identical(slot.connection, connection),
        )
        .toList();
    Object? failure;
    StackTrace? stack;
    try {
      await Future.wait(selected.map(_stop));
    } catch (error, trace) {
      failure = error;
      stack = trace;
    }
    await Future.wait(queries.map((query) => query.settled.future));
    try {
      await _serverQueries.stopForConnection(connection);
    } catch (error, trace) {
      failure ??= error;
      stack ??= trace;
    }
    for (final entry in _clipboardProbes.entries.toList()) {
      if (identical(entry.value, connection)) {
        await _closeClipboardProbe(entry.key);
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    _closed = true;
    for (final query in _queries.toList()) {
      query.stop.cancel();
    }
    final result = () async {
      await Future.wait(_sessions.values.toList().map(_stop));
      await Future.wait(_queries.map((query) => query.settled.future).toList());
      await Future.wait(
        _clipboardProbes.keys.toList().map(_closeClipboardProbe),
      );
    }();
    return _closing = result.catchError((Object error, StackTrace stack) {
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    });
  }
}

Never _fail(String code, String message) => throw RequestFailure(code, message);
String _code(Object error) => switch (error) {
  RequestFailure(:final code) ||
  AdbException(:final code) ||
  ScrcpyException(:final code) => code,
  _ => 'session_failed',
};
Future<T> _boundary<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AdbException catch (error, stack) {
    Error.throwWithStackTrace(RequestFailure(error.code, error.message), stack);
  } on ScrcpyException catch (error, stack) {
    Error.throwWithStackTrace(RequestFailure(error.code, error.message), stack);
  }
}

String _string(SessionJson value, String key) {
  final result = value[key];
  if (result is! String ||
      result.isEmpty ||
      result.contains('\x00') ||
      utf8.encode(result).length > 1024) {
    _fail('invalid_argument', '缺少有效的 $key。');
  }
  return result;
}

int _integer(
  SessionJson value,
  String key,
  int minimum,
  int maximum, {
  int? fallback,
}) {
  final result = value[key] ?? fallback;
  if (result is! int || result < minimum || result > maximum) {
    _fail('invalid_argument', '$key 超出有效范围。');
  }
  return result;
}

bool _package(String value) =>
    value.length <= 230 &&
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')
        .hasMatch(value);

extension _SessionCommands on SessionCoordinator {
  Future<SessionJson> _control(
    _LogicalSession slot,
    _Capture capture,
    String command,
    SessionJson params,
  ) {
    if (command == 'session.ready') {
      return Future.value(_ready(slot, capture, params));
    }
    if (command == 'session.frame') {
      return Future.value(_frame(slot, capture, params));
    }
    final work = _SessionWork();
    slot.works.add(work);
    return _track(slot, () async {
      try {
        _check(slot, work);
        final isInput = const {
          'session.key',
          'session.touch',
          'session.scroll',
          'session.text',
          'session.clipboard',
        }.contains(command);
        if (isInput) _bound(slot, params, input: true);
        if (slot.rebuilding && !_releaseInput(command, params)) {
          _fail('stale_capture', '画质正在重建，暂不接纳旧画面的输入。');
        }
        Future<ScrcpyControlReceipt> send(ScrcpyControlMessage message) =>
            _native(
              slot,
              work,
              capture,
              () => capture.sdk.sendControl(message),
              policy.controlTimeout,
            );
        switch (command) {
          case 'session.pause':
          case 'session.resume':
            if (slot.state['textureId'] is! int) {
              _fail('renderer_not_ready', '画面尚未完成绑定。');
            }
            final paused = command == 'session.pause';
            if (!paused) await send(const ScrcpyResetVideo());
            slot.state.addAll({
              'status': paused ? 'paused' : 'streaming',
              'paused': paused,
              'awaitingSession': !paused,
              'capturePaused': false,
            });
            _changed(slot);
            return {...slot.state, 'paused': paused, 'capturePaused': false};
          case 'session.refresh':
            return _receipt(await send(const ScrcpyResetVideo()));
          case 'session.rotate':
            return _receipt(await send(const ScrcpyRotate()));
          case 'session.screen':
            final mode = params['mode'];
            if (mode != 'on' && mode != 'off') {
              _fail('invalid_argument', '屏幕模式无效。');
            }
            return _receipt(
              await send(ScrcpySetDisplayPower(on: mode == 'on')),
            );
          case 'session.key':
            final code = _integer(params, 'keyCode', 0, 1024);
            final repeat = _integer(
              params,
              'repeat',
              0,
              0xffffffff,
              fallback: 0,
            );
            final meta = _integer(
              params,
              'metaState',
              0,
              0xffffffff,
              fallback: 0,
            );
            final action = params['action'] ?? 'press';
            if (!const ['down', 'up', 'press'].contains(action)) {
              _fail('invalid_argument', '按键动作无效。');
            }
            var receipt = await send(
              ScrcpyKey(
                action: action == 'up'
                    ? ScrcpyKeyAction.up
                    : ScrcpyKeyAction.down,
                keycode: code,
                repeat: repeat,
                metaState: meta,
              ),
            );
            if (action == 'press') {
              // 固定使用本次 down 的捕获，迟到 finally 不能向新代次发送 up。
              receipt = await send(
                ScrcpyKey(
                  action: ScrcpyKeyAction.up,
                  keycode: code,
                  metaState: meta,
                ),
              );
            }
            return _receipt(receipt);
          case 'session.text':
            final text = _text(params);
            if (text.runes.any((rune) => rune > 127)) {
              if ((slot.state['apiLevel'] as int) < 24) {
                _fail('unsupported', '这台设备不支持剪贴板粘贴 Unicode 文本。');
              }
              return _receipt(await send(ScrcpyClipboard(text, paste: true)));
            }
            ScrcpyControlReceipt? receipt;
            for (var offset = 0; offset < text.length; offset += 300) {
              receipt = await send(
                ScrcpyText(
                  text.substring(offset, math.min(offset + 300, text.length)),
                ),
              );
            }
            return receipt == null
                ? {'accepted': true, 'empty': true}
                : _receipt(receipt);
          case 'session.clipboard':
            final text = _text(params);
            return _receipt(
              await send(ScrcpyClipboard(text, paste: params['paste'] == true)),
            );
          case 'session.touch':
            final action = switch (params['action']) {
              'down' => ScrcpyTouchAction.down,
              'up' => ScrcpyTouchAction.up,
              'move' => ScrcpyTouchAction.move,
              'cancel' => ScrcpyTouchAction.cancel,
              'hover' => ScrcpyTouchAction.hoverMove,
              _ => throw const RequestFailure('invalid_argument', '触控动作无效。'),
            };
            final point = _point(
              slot,
              params,
              cleanup: _releaseInput(command, params),
            );
            final pressure =
                (params['pressure'] as num?)?.toDouble() ??
                (action == ScrcpyTouchAction.up ||
                        action == ScrcpyTouchAction.cancel
                    ? 0
                    : 1);
            if (!pressure.isFinite || pressure < 0 || pressure > 1) {
              _fail('invalid_argument', '触控压力无效。');
            }
            return _receipt(
              await send(
                ScrcpyTouch(
                  action: action,
                  pointerId: params['mouse'] == true
                      ? -1
                      : _integer(params, 'pointerId', 0, 0x7fffffffffffffff),
                  x: point.x,
                  y: point.y,
                  width: point.width,
                  height: point.height,
                  pressure: pressure,
                  buttons: _integer(params, 'buttons', 0, 31, fallback: 0),
                  actionButton: _integer(
                    params,
                    'actionButton',
                    0,
                    31,
                    fallback: 0,
                  ),
                ),
              ),
            );
          case 'session.scroll':
            final point = _point(slot, params);
            double distance(String key) {
              final value = params[key];
              if (value is! num ||
                  !value.isFinite ||
                  value < -32768 ||
                  value > 32767.999) {
                _fail('invalid_argument', '滚动距离无效。');
              }
              return value.toDouble();
            }
            return _receipt(
              await send(
                ScrcpyScroll(
                  x: point.x,
                  y: point.y,
                  width: point.width,
                  height: point.height,
                  horizontal: distance('hscroll'),
                  vertical: distance('vscroll'),
                  buttons: _integer(params, 'buttons', 0, 31, fallback: 0),
                ),
              ),
            );
          case 'session.display':
            if (slot.qualityPreparing || slot.resizing != null) {
              _fail('display_busy', '显示调整或画质切换尚未结束。');
            }
            final resize = slot.resizing = _resize(slot, capture, work, params);
            try {
              return await resize;
            } finally {
              slot.resizing = null;
            }
          case 'session.launch':
            return await _launch(slot, capture, work, params);
          default:
            _fail('unknown_command', '此操作不是控制窗口命令。');
        }
      } catch (error, stack) {
        if (work.failure != null && !slot.revoked) {
          slot.state.addAll({
            'status': 'failed',
            'failureCode': work.failure,
            'reason': '控制执行已撤销，远端动作结果需要核对。',
          });
          onAudioEligibilityChanged?.call(slot.deviceId);
          _changed(slot, 'session.failed');
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        slot.works.remove(work);
      }
    }());
  }

  SessionJson _ready(
    _LogicalSession slot,
    _Capture capture,
    SessionJson params,
  ) {
    _bound(slot, params, input: true);
    final texture = _integer(params, 'textureId', 0, 0x7fffffffffffffff);
    final generation = _integer(params, 'generation', 1, 0x7fffffffffffffff);
    if (generation < (slot.state['generation'] as int)) {
      _fail('stale_renderer', '旧渲染器不能覆盖新绑定。');
    }
    if (generation > (slot.state['generation'] as int)) {
      slot.state.remove('frameCount');
    }
    final target = slot.state['qualityRebuildTarget'];
    if (slot.rebuilding && target != null && capture.generation != target) {
      _fail('stale_capture', '画质重建的目标捕获尚未就绪。');
    }
    slot.state.addAll({
      'textureId': texture,
      'generation': generation,
      'status': slot.state['paused'] == true ? 'paused' : 'streaming',
      'awaitingSession': false,
      'qualityRebuilding': false,
      if (slot.rebuilding) 'qualityRebuildOutcome': 'applied',
      if (slot.rebuilding) 'qualityRetryable': false,
    });
    for (final key in [
      'decoder',
      'hardwareAccelerated',
      'hardwareAcceleration',
      'renderer',
    ]) {
      if (params[key] is String || params[key] is bool) {
        slot.state[key] = params[key];
      }
    }
    _decoded(slot, params);
    _changed(slot);
    return {'ready': true, ...slot.state};
  }

  SessionJson _frame(
    _LogicalSession slot,
    _Capture capture,
    SessionJson params,
  ) {
    _bound(slot, params, input: true);
    if (slot.rebuilding ||
        params['generation'] != slot.state['generation'] ||
        params['textureId'] != slot.state['textureId'] ||
        slot.state['textureId'] == null) {
      _fail('stale_renderer', '旧渲染器的帧回执已失效。');
    }
    final frames = params['frameCount'],
        previousFrames = slot.state['frameCount'];
    if (frames is int && previousFrames is int && frames <= previousFrames) {
      return {'received': false, 'staleFrame': true};
    }
    slot.state['lastFrameAt'] = _now().millisecondsSinceEpoch ~/ 1000;
    for (final key in ['frameCount', 'framesDecoded', 'presentationTimeUs']) {
      final value = params[key];
      if (value is int && value >= 0) slot.state[key] = value;
    }
    final geometryChanged = _decoded(slot, params);
    if (geometryChanged) _changed(slot);
    _changed(slot, 'session.frame');
    return {'received': true};
  }

  Future<SessionJson> _launch(
    _LogicalSession slot,
    _Capture capture,
    _SessionWork work,
    SessionJson params,
  ) async {
    final package = _string(params, 'packageName');
    if (!_package(package) ||
        slot.state['packageName'] != null &&
            slot.state['packageName'] != package) {
      _fail('invalid_argument', '只能在原独立窗口中打开同一个应用。');
    }
    final operation = _newId();
    final permit = await _launches.begin(
      operationId: operation,
      sessionId: slot.id,
      deviceId: slot.deviceId,
      packageName: package,
    );
    var submitted = false;
    try {
      _check(slot, work);
      if (!permit.claim()) _fail('cancelled', '这次应用打开已经撤销。');
      submitted = true;
      final receipt = await _native(
        slot,
        work,
        capture,
        () => capture.sdk.sendControl(ScrcpyStartApp(package)),
        policy.controlTimeout,
      );
      if (receipt.completion != ScrcpyControlCompletion.written) {
        _fail('app_launch_unknown', '没有收到打开消息的实际写入确认。');
      }
      await _launches.finish(operation);
      return {
        'sessionId': slot.id,
        'launchOperationId': operation,
        'launchOutcome': 'sent',
        'applicationOpened': false,
      };
    } catch (error, stack) {
      permit.cancel();
      await _launches.finish(
        operation,
        failureCode: submitted ? 'app_launch_unknown' : 'not_submitted',
      );
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<SessionJson> _resize(
    _LogicalSession slot,
    _Capture capture,
    _SessionWork work,
    SessionJson params,
  ) async {
    if (slot.state['packageName'] == null) {
      final dimensions = _displayDimensions(params, minimum: 320);
      if (dimensions == null) _fail('invalid_argument', '请提供手机显示宽高。');
      await _physicalDisplay(slot, work, dimensions.width, dimensions.height);
      _check(slot, work);
      _changed(slot);
      return {...slot.state, 'applied': true};
    }
    final fitted = VirtualDisplayPolicy.fit(
      params,
      (slot.state['quality'] as Map)['maxSize'],
    );
    final width = _integer(fitted, 'displayWidth', 2, 4096),
        height = _integer(fitted, 'displayHeight', 2, 4096);
    final display = slot.state['displayId'];
    if (display is! int || display <= 0) {
      _fail('display_identity_unverified', '独立显示身份尚未核实。');
    }
    final shell = SessionShell(slot.connection, policy.shellTimeout);
    final density = scaledDisplayDensity(
      await shell.metrics(work.stop),
      width,
      height,
    );
    await shell.run(
      'wm density $density -d $display',
      cancellation: work.stop,
      maxBytes: 8192,
    );
    final receipt = await _native(
      slot,
      work,
      capture,
      () => capture.sdk.sendControl(
        ScrcpyResizeDisplay(width: width, height: height),
      ),
      policy.controlTimeout,
    );
    slot.state.addAll({
      'displayWidth': width,
      'displayHeight': height,
      'displayDensity': density,
      'displaySize': {'width': width, 'height': height},
    });
    _changed(slot);
    return {...slot.state, ..._receipt(receipt)};
  }

  Future<void> _physicalDisplay(
    _LogicalSession slot,
    _SessionWork work,
    int width,
    int height,
  ) async {
    _check(slot, work);
    final previous = slot.physicalDisplay;
    if (previous == null) {
      if (_sessions.values.any(
        (other) =>
            !identical(other, slot) &&
            identical(other.connection, slot.connection) &&
            other.physicalDisplay?.isClosed == false,
      )) {
        _fail('display_busy', '此手机的物理显示仍由另一个窗口持有，请先确认原窗口停止。');
      }
      final lease = PhysicalDisplayLease(
        slot.connection,
        timeout: policy.shellTimeout,
        onLost: () => _failedCapture(slot, 'display_supervision_lost'),
      );
      // 在第一个异步创建之前登记，失败启动和迟到回执都沿此精确所有者清理。
      slot.physicalDisplay = lease;
      try {
        await lease.start(width, height, cancellation: work.stop);
      } catch (error) {
        slot.state.addAll({
          'displayOutcome': 'unknown',
          'displayFailureCode': _code(error),
        });
        _changed(slot);
        rethrow;
      }
    } else {
      try {
        await previous.resize(width, height, cancellation: work.stop);
      } catch (error) {
        slot.state.addAll({
          'displayOutcome': 'unknown',
          'displayFailureCode': _code(error),
        });
        _changed(slot);
        rethrow;
      }
    }
    _check(slot, work);
    slot.state.addAll({
      'displayWidth': width,
      'displayHeight': height,
      'displaySize': {'width': width, 'height': height},
      'displayOutcome': 'applied',
    });
    slot.state.remove('displayFailureCode');
  }
}

({int width, int height})? _displayDimensions(
  SessionJson params, {
  required int minimum,
}) {
  if (!params.containsKey('displayWidth') &&
      !params.containsKey('displayHeight')) {
    return null;
  }
  return (
    width: _integer(params, 'displayWidth', minimum, 4096),
    height: _integer(params, 'displayHeight', minimum, 4096),
  );
}

bool _releaseInput(String command, SessionJson params) =>
    command == 'session.key' && params['action'] == 'up' ||
    command == 'session.touch' &&
        const ['up', 'cancel'].contains(params['action']);
String _text(SessionJson params) {
  final value = params['text'];
  if (value is! String ||
      value.contains('\x00') ||
      utf8.encode(value).length > 256 * 1024) {
    _fail('invalid_argument', '文本超过限制或包含无效字符。');
  }
  return value;
}

SessionJson _receipt(ScrcpyControlReceipt receipt) =>
    switch (receipt.completion) {
      ScrcpyControlCompletion.admitted => {'accepted': true},
      ScrcpyControlCompletion.written => {'sent': true},
      ScrcpyControlCompletion.clipboardAcknowledged => {'acknowledged': true},
    };
({int x, int y, int width, int height}) _point(
  _LogicalSession slot,
  SessionJson params, {
  bool cleanup = false,
}) {
  final width = _integer(params, 'screenWidth', 1, 65535),
      height = _integer(params, 'screenHeight', 1, 65535);
  if (width != slot.state['width'] || height != slot.state['height']) {
    if (!cleanup) _fail('stale_capture', '输入尺寸与当前精确捕获不一致。');
    final currentWidth = slot.state['width'] as int;
    final currentHeight = slot.state['height'] as int;
    return (
      x: _integer(params, 'x', 0, width - 1).clamp(0, currentWidth - 1),
      y: _integer(params, 'y', 0, height - 1).clamp(0, currentHeight - 1),
      width: currentWidth,
      height: currentHeight,
    );
  }
  return (
    x: _integer(params, 'x', 0, width - 1),
    y: _integer(params, 'y', 0, height - 1),
    width: width,
    height: height,
  );
}

bool _decoded(_LogicalSession slot, SessionJson params) {
  final width = params['decodedWidth'], height = params['decodedHeight'];
  if (width is int &&
      height is int &&
      width >= 1 &&
      height >= 1 &&
      width <= 16384 &&
      height <= 16384 &&
      width * height <= 67108864) {
    final changed =
        slot.state['width'] != width || slot.state['height'] != height;
    // 调用者已核验捕获、renderer 与纹理身份；当前解码尺寸才是 scrcpy 输入使用的几何。
    slot.state.addAll({
      'width': width,
      'height': height,
      'decodedWidth': width,
      'decodedHeight': height,
    });
    return changed;
  }
  return false;
}

extension _SessionQuality on SessionCoordinator {
  SessionJson _quality(String device, SessionJson patch) {
    final result = VideoQualityPolicy.resolve(_settings(), device, patch);
    _integer(result, 'maxSize', 320, 4096);
    _integer(result, 'maxFps', 1, 120);
    _integer(result, 'videoBitRate', 500000, 50000000);
    if (!ScrcpyVideoCodec.values.any(
      (codec) => codec.name == result['videoCodec'],
    )) {
      _fail('invalid_argument', '视频编码格式无效。');
    }
    final encoder = result['videoEncoder'];
    if (encoder != null &&
        (encoder is! String ||
            encoder.isEmpty ||
            encoder.length > 256 ||
            !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(encoder))) {
      _fail('invalid_argument', '视频编码器名称无效。');
    }
    return result;
  }

  void _validateEncoder(SessionJson quality, List<SessionJson> encoders) {
    if (!encoders.any(
      (entry) =>
          entry['codec'] == quality['videoCodec'] &&
          (quality['videoEncoder'] == null ||
              entry['name'] == quality['videoEncoder']),
    )) {
      _fail('encoder_unavailable', '设备没有枚举到所选格式与编码器组合，现有窗口保持运行。');
    }
  }

  Future<SessionJson> _qualityOptions(
    SessionJson params,
    DeviceConnection connection,
    AdbCancellation stop,
  ) async {
    final device = _string(params, 'deviceId');
    final encoders = await _serverQueries.encoders(connection, stop);
    final quality = _quality(device, const {});
    final codecs = <SessionJson>[];
    for (final codec in ScrcpyVideoCodec.values) {
      final matching = encoders
          .where((entry) => entry['codec'] == codec.name)
          .toList();
      final available = matching.isNotEmpty;
      codecs.add({
        'id': codec.name,
        'name': codec.name,
        'mime': _mime(codec.name),
        'available': available,
        'status': available ? 'available' : 'unavailable',
        'reason': available ? '已从这台设备枚举到编码器，实际配置仍需验证。' : '设备未枚举到此格式的编码器。',
        'encoders': matching,
      });
    }
    return {
      'deviceId': device,
      'scope': 'device',
      'probe': {'status': 'enumerated'},
      'current': VideoQualityPolicy.current(quality),
      'codecs': codecs,
      'encoders': encoders,
      'activeStreams': [
        for (final slot in _sessions.values)
          if (slot.deviceId == device && !slot.revoked) Map.of(slot.state),
      ],
      'audioAvailable': false,
    };
  }

  Future<SessionJson> _qualitySelection(
    SessionJson params,
    DeviceConnection connection,
    AdbCancellation stop,
  ) async {
    final device = _string(params, 'deviceId');
    final quality = _quality(device, params);
    final encoders = await _serverQueries.encoders(connection, stop);
    _validateEncoder(quality, encoders);
    final active = _sessions.values
        .where((slot) => slot.deviceId == device && !slot.revoked)
        .toList();
    return {
      'deviceId': device,
      'appliesNextSession': true,
      'needsRestart': active.isNotEmpty,
      if (active.length == 1) 'existingSessionId': active.single.id,
      'current': VideoQualityPolicy.current(quality),
      'seamless': false,
    };
  }

  Future<SessionJson> _reconfigure(_LogicalSession slot, SessionJson params) {
    final quality = _quality(slot.deviceId, params);
    final work = _SessionWork();
    slot.works.add(work);
    final queuedAt = _now();
    final previous = _qualityTail;
    var preparing = false;
    final action = () async {
      try {
        await previous;
        _check(slot, work);
        if (_now().difference(queuedAt) >= policy.qualityQueueTimeout) {
          _fail('quality_queue_timeout', '画质重建排队超时，现有窗口保持运行。');
        }
        final old = _bound(slot, params);
        slot.qualityPreparing = preparing = true;
        // 先封存新的尺寸修改，再等已受理修改落定；失败回滚不能覆盖迟到尺寸事实。
        await slot.resizing?.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        _check(slot, work);
        if (slot.qualityCleanupPending ||
            slot.captures.any(
              (capture) => !identical(capture, old) && !capture.closed,
            )) {
          _fail('quality_cleanup_unconfirmed', '上一次画质候选尚未确认释放，请先重试停止。');
        }
        if (slot.rebuilding) _fail('quality_busy', '请先等待上一代画面完成绑定。');
        _validateEncoder(
          quality,
          await _serverQueries.encoders(slot.connection, work.stop),
        );
        _check(slot, work);
        if (_capacityUsed >= 16) {
          _fail('session_capacity', '没有可用于捕获替换的资源名额。');
        }
        final snapshot = Map<String, dynamic>.of(slot.state);
        final shell = SessionShell(slot.connection, policy.shellTimeout);
        final package = slot.state['packageName'] as String?;
        int? task, oldDisplay;
        if (package != null) {
          oldDisplay = _integer(slot.state, 'displayId', 1, 0x7fffffff);
          task = await shell.task(package, oldDisplay, work.stop);
          if (slot.state['taskId'] != null && slot.state['taskId'] != task) {
            _fail('task_identity_unverified', '原应用任务已变化，不会重新打开应用。');
          }
        }
        _check(slot, work);
        // 任务查询期间其他窗口可以取得名额，预约前须在无等待点的边界重新核对。
        if (_capacityUsed >= 16) {
          _fail('session_capacity', '没有可用于捕获替换的资源名额。');
        }
        final generation = old.generation + 1;
        slot.captureReservations.add(generation);
        slot.state.addAll({
          'qualityRebuilding': true,
          'qualityRebuildTarget': generation,
          'qualityRebuildOutcome': 'rebuilding',
        });
        slot.handoff = Timer(policy.qualityHandoffTimeout, () {
          slot.handoff = null;
          work.cancel('quality_handoff_timeout');
          try {
            onAudioEligibilityChanged?.call(slot.deviceId);
          } catch (_) {
            _failedCapture(slot, 'audio_eligibility_unconfirmed');
          }
        });
        _changed(slot);
        try {
          onAudioEligibilityChanged?.call(slot.deviceId);
          // written 消息排在之前已接纳的旧输入之后；它不是远端应用处理证明。
          final barrier = await _native(
            slot,
            work,
            old,
            () => old.sdk.sendControl(const ScrcpyResetVideo()),
            policy.controlTimeout,
          );
          if (barrier.completion != ScrcpyControlCompletion.written) {
            _fail('control_barrier_unconfirmed', '旧输入队列尚未确认写出。');
          }
          final candidate = await _spawn(
            slot,
            work,
            {
              'displayWidth': snapshot['displayWidth'],
              'displayHeight': snapshot['displayHeight'],
            },
            quality,
            generation,
            retainedTask: task,
          );
          _check(slot, work);
          await _closeCapture(old);
          _check(slot, work);
          slot.current = candidate;
          _install(slot, candidate, quality);
          slot.state.addAll({
            'qualityRebuilding': true,
            'qualityRebuildTarget': generation,
            'qualityRebuildOutcome': 'awaiting_renderer',
            'paused': snapshot['paused'] == true,
          });
          _observe(slot, candidate);
          _changed(slot);
          return Map<String, dynamic>.of(slot.state);
        } catch (error, stack) {
          Object? cleanup;
          // 新显示可能在首帧之前已经接纳 move-stack；先还原任务，再释放候选显示。
          if (task != null &&
              oldDisplay != null &&
              !old.closed &&
              !old.expectedStop) {
            try {
              await shell.moveTask(task, oldDisplay);
            } catch (error) {
              cleanup = error;
            }
          }
          for (final candidate
              in slot.captures
                  .where((value) => value.generation == generation)
                  .toList()) {
            try {
              await _closeCapture(candidate);
            } catch (error) {
              cleanup ??= error;
            }
          }
          slot.current = old;
          slot.state
            ..clear()
            ..addAll(snapshot);
          slot.state.addAll({
            'qualityRebuilding': false,
            'qualityRebuildOutcome':
                old.closed || old.expectedStop || cleanup != null
                ? 'failed'
                : 'restored',
            'qualityRetryable':
                old.closed || old.expectedStop || cleanup != null,
            'qualityFailureCode': _code(error),
            if (old.closed || old.expectedStop) ...{
              'status': 'failed',
              'failureCode': 'capture_stopped',
              'reason': '原捕获已撤销准入，关闭结果尚需核对，不能恢复为可用窗口。',
            },
          });
          _changed(slot);
          if (cleanup != null) {
            slot.qualityCleanupPending = true;
            _fail('quality_cleanup_unconfirmed', '画质切换收尾或任务恢复尚未确认，请先重试停止。');
          }
          Error.throwWithStackTrace(error, stack);
        } finally {
          slot.captureReservations.remove(generation);
          slot.handoff?.cancel();
          slot.handoff = null;
          onAudioEligibilityChanged?.call(slot.deviceId);
        }
      } finally {
        if (preparing) slot.qualityPreparing = false;
        slot.works.remove(work);
      }
    }();
    _qualityTail = action.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return _track(slot, action);
  }
}

String _mime(String codec) => switch (codec) {
  'h264' => 'video/avc',
  'h265' => 'video/hevc',
  'av1' => 'video/av01',
  'vp8' => 'video/x-vnd.on2.vp8',
  'vp9' => 'video/x-vnd.on2.vp9',
  _ => throw const RequestFailure('invalid_argument', '视频格式无效。'),
};
