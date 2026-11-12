import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:adb/adb.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/clipboard/remote_clipboard.dart';
import 'package:scrcpy_connect/core/control/app_launch_journal.dart';
import 'package:scrcpy_connect/core/control/app_launch_permit.dart';
import 'package:scrcpy_connect/core/control/display_lease.dart';
import 'package:scrcpy_connect/core/control/models/session_activity.dart';
import 'package:scrcpy_connect/core/control/models/session_policy.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/control/models/video_renderer_receipt.dart';
import 'package:scrcpy_connect/core/control/models/video_session.dart';
import 'package:scrcpy_connect/core/control/remote_control.dart';
import 'package:scrcpy_connect/core/control/session_shell.dart';
import 'package:scrcpy_connect/core/control/video_display.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/control/video_quality_policy.dart';
import 'package:scrcpy_connect/core/control/virtual_display_policy.dart';
import 'package:scrcpy_connect/core/devices/device_connection.dart';
import 'package:scrcpy_connect/core/devices/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';
import 'package:uuid/uuid.dart';

export 'package:scrcpy_connect/core/control/models/session_policy.dart';

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
  VideoSessionSnapshot state;
  final initial = _SessionWork();
  final captures = <_Capture>[];
  final captureReservations = <int>{};
  final operations = <Future<void>>{};
  final works = <_SessionWork>{};
  _Capture? current;
  Future<VideoSessionSnapshot>? starting;
  Future<void>? stopping;
  Future<void>? resizing;
  bool qualityPreparing = false;
  bool revoked = false;
  bool launchBegan = false;
  bool launchSubmitted = false;
  bool qualityCleanupPending = false;
  AppLaunchPermit? permit;
  DisplayLease? physicalDisplay;
  Timer? handoff;
  bool get rebuilding => state.qualityRebuilding;
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
final class ControlSessionService implements RemoteClipboard, RemoteControl {
  ControlSessionService({
    required this._scrcpy,
    required this._requireConnection,
    required this._launches,
    required this._serverQueries,
    required void Function(String, String, Map<String, Object?>) emit,
    Preferences Function()? settings,
    this.policy = const SessionPolicy(),
    DateTime Function()? now,
    String Function()? newId,
    this.onAudioEligibilityChanged,
    this.onClipboardFailure,
    required this._requireClipboardAccess,
  }) : _emitEvent = emit,
       _settings = settings ?? Preferences.new,
       _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4 {
    policy.validate();
  }

  final ScrcpyClient _scrcpy;
  final DeviceConnection Function(String) _requireConnection;
  final AppLaunchJournal _launches;
  // 借用应用唯一清单查询所有者；窗口关闭不能关闭并行的安装应用查询。
  final ScrcpyServerQueries _serverQueries;
  final void Function(String, String, Map<String, Object?>) _emitEvent;
  final Preferences Function() _settings;
  final DateTime Function() _now;
  final String Function() _newId;
  final SessionPolicy policy;

  /// 同步通知资格变化；回调可登记异步音源排空，但不能延迟撤销准入。
  final void Function(String deviceId)? onAudioEligibilityChanged;
  final void Function() _requireClipboardAccess;
  final void Function(
    String deviceId,
    bool writing,
    int elapsedMs,
    Object error,
  )?
  onClipboardFailure;
  final _sessions = <String, _LogicalSession>{};
  final _queries = <_SessionQuery>{};
  final _clipboardProbes = <ScrcpySession, DeviceConnection>{};
  final _clipboardTails = <String, Future<void>>{};
  bool Function(String device, String session, int generation)?
  _clipboardAdmission;

  @override
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

  /// 包含启动中窗口及尚未到期的画质交接；未知清理不产生新的音源资格。
  bool hasAudioOwner(String deviceId) => _sessions.values.any(
    (slot) =>
        slot.deviceId == deviceId &&
        !slot.revoked &&
        (slot.handoff != null ||
            const [
              VideoSessionStatus.starting,
              VideoSessionStatus.streaming,
              VideoSessionStatus.paused,
              VideoSessionStatus.awaitingRenderer,
            ].contains(slot.state.status)),
  );

  Set<String> get audioEligibleDevices => Set.unmodifiable({
    for (final slot in _sessions.values)
      if (!slot.revoked &&
          const [
            VideoSessionStatus.streaming,
            VideoSessionStatus.paused,
            VideoSessionStatus.starting,
          ].contains(slot.state.status))
        slot.deviceId,
  });

  @override
  Future<ControlReceipt> sendControl(
    ControlTarget target,
    ControlAction action,
  ) => _boundary(() async {
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    final slot = _selectMatching(target.sessionId, target.deviceId);
    final capture = _boundCapture(
      slot,
      target.captureRef,
      target.captureGeneration,
    );
    return _controlWork(
      slot,
      releasing: action.isRelease,
      validate: () {
        if (action.isInput) {
          _boundCapture(
            slot,
            target.captureRef,
            target.captureGeneration,
            input: true,
          );
        }
      },
      action: (work) async {
        Future<ControlReceipt> send(ScrcpyControlMessage message) async =>
            ControlReceipt.delivered(
              (await _native(
                slot,
                work,
                capture,
                () => capture.sdk.sendControl(message),
                policy.controlTimeout,
              )).completion,
            );
        switch (action) {
          case ControlKey(
            :final keyCode,
            action: final keyAction,
            :final repeat,
            :final metaState,
          ):
            _range(keyCode, 'keyCode', 0, 1024);
            _range(repeat, 'repeat', 0, 0xffffffff);
            _range(metaState, 'metaState', 0, 0xffffffff);
            var receipt = await send(
              ScrcpyKey(
                action: keyAction == .up ? .up : .down,
                keycode: keyCode,
                repeat: repeat,
                metaState: metaState,
              ),
            );
            if (keyAction == .press) {
              // UP 固定使用本次 DOWN 的精确捕获，不转发到后继代际。
              receipt = await send(
                ScrcpyKey(action: .up, keycode: keyCode, metaState: metaState),
              );
            }
            return receipt;
          case ControlText(:final text):
            _text(text);
            if (text.runes.any((rune) => rune > 127)) {
              if ((slot.state.apiLevel!) < 24) {
                _fail('unsupported', '这台设备不支持剪贴板粘贴 Unicode 文本。');
              }
              return send(ScrcpyClipboard(text, paste: true));
            }
            ControlReceipt receipt = const ControlReceipt.emptyText();
            for (var offset = 0; offset < text.length; offset += 300) {
              receipt = await send(
                ScrcpyText(
                  text.substring(offset, math.min(offset + 300, text.length)),
                ),
              );
            }
            return receipt;
          case ControlTouch(
            point: final originalPoint,
            action: final touchAction,
            :final pointerId,
            :final pressure,
            :final mouse,
            :final buttons,
            :final actionButton,
          ):
            final point = _point(
              slot,
              originalPoint,
              cleanup: action.isRelease,
            );
            final force =
                pressure ??
                (touchAction == .up || touchAction == .cancel ? 0 : 1);
            if (!force.isFinite || force < 0 || force > 1) {
              _fail('invalid_argument', '触控压力无效。');
            }
            return send(
              ScrcpyTouch(
                action: switch (touchAction) {
                  .down => .down,
                  .up => .up,
                  .move => .move,
                  .cancel => .cancel,
                  .hover => .hoverMove,
                },
                pointerId: mouse
                    ? -1
                    : _range(pointerId, 'pointerId', 0, 0x7fffffffffffffff),
                x: point.x,
                y: point.y,
                width: point.width,
                height: point.height,
                pressure: force.toDouble(),
                buttons: _range(buttons, 'buttons', 0, 31),
                actionButton: _range(actionButton, 'actionButton', 0, 31),
              ),
            );
          case ControlScroll(
            point: final originalPoint,
            :final horizontal,
            :final vertical,
            :final buttons,
          ):
            final point = _point(slot, originalPoint);
            double distance(double value) {
              if (!value.isFinite || value < -32768 || value > 32767.999) {
                _fail('invalid_argument', '滚动距离无效。');
              }
              return value;
            }
            return send(
              ScrcpyScroll(
                x: point.x,
                y: point.y,
                width: point.width,
                height: point.height,
                horizontal: distance(horizontal),
                vertical: distance(vertical),
                buttons: _range(buttons, 'buttons', 0, 31),
              ),
            );
          case ControlRotate():
            return send(const ScrcpyRotate());
          case ControlScreenPower(:final on):
            return send(ScrcpySetDisplayPower(on: on));
          case ControlLaunchApplication(:final packageName):
            return _launch(slot, capture, work, packageName);
        }
      },
    );
  });

  Future<VideoSessionSnapshot> setPaused(
    ControlTarget target, {
    required bool paused,
  }) => _boundary(() async {
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    final slot = _selectMatching(target.sessionId, target.deviceId);
    final capture = _boundCapture(
      slot,
      target.captureRef,
      target.captureGeneration,
    );
    return _controlWork(
      slot,
      releasing: false,
      action: (work) async {
        if (slot.state.textureId is! int) {
          _fail('renderer_not_ready', '画面尚未完成绑定。');
        }
        if (!paused) {
          await _native(
            slot,
            work,
            capture,
            () => capture.sdk.sendControl(const ScrcpyResetVideo()),
            policy.controlTimeout,
          );
        }
        slot.state = slot.state.copyWith(
          status: paused
              ? VideoSessionStatus.paused
              : VideoSessionStatus.streaming,
          paused: paused,
          awaitingSession: !paused,
          capturePaused: false,
        );
        _changed(slot);
        return slot.state;
      },
    );
  });

  Future<void> acceptRenderer(VideoRendererReceipt receipt) => _boundary(
    () async {
      if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
      final slot = _selectMatching(receipt.sessionId, receipt.deviceId);
      final capture = _boundCapture(
        slot,
        receipt.expectedCaptureRef,
        receipt.captureGeneration,
        input: true,
      );
      _range(receipt.textureId, 'textureId', 0, 0x7fffffffffffffff);
      final generation = _range(
        receipt.generation,
        'generation',
        1,
        0x7fffffffffffffff,
      );
      if (generation < slot.state.generation) {
        _fail('stale_renderer', '旧渲染器不能覆盖新绑定。');
      }
      if (generation > slot.state.generation) {
        slot.state = slot.state.copyWith(frameCount: null);
      }
      final target = slot.state.qualityRebuildTarget;
      if (slot.rebuilding && target != null && capture.generation != target) {
        _fail('stale_capture', '画质重建的目标捕获尚未就绪。');
      }
      slot.state = slot.state.copyWith(
        textureId: receipt.textureId,
        generation: generation,
        status: slot.state.paused == true
            ? VideoSessionStatus.paused
            : VideoSessionStatus.streaming,
        awaitingSession: false,
        qualityRebuilding: false,
        qualityRebuildOutcome: slot.rebuilding
            ? VideoQualityRebuildOutcome.applied
            : slot.state.qualityRebuildOutcome,
        qualityRetryable: slot.rebuilding ? false : slot.state.qualityRetryable,
        decoder: receipt.decoder ?? slot.state.decoder,
        renderer: receipt.renderer ?? slot.state.renderer,
        hardwareAccelerated:
            receipt.hardwareAccelerated ?? slot.state.hardwareAccelerated,
        hardwareAcceleration:
            receipt.hardwareAcceleration ?? slot.state.hardwareAcceleration,
      );
      _decoded(slot, receipt.decodedWidth, receipt.decodedHeight);
      _changed(slot);
    },
  );

  Future<bool> acceptFrame(VideoRendererReceipt receipt) => _boundary(() async {
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    final slot = _selectMatching(receipt.sessionId, receipt.deviceId);
    _boundCapture(
      slot,
      receipt.expectedCaptureRef,
      receipt.captureGeneration,
      input: true,
    );
    if (slot.rebuilding ||
        receipt.generation != slot.state.generation ||
        receipt.textureId != slot.state.textureId ||
        slot.state.textureId == null) {
      _fail('stale_renderer', '旧渲染器的帧回执已失效。');
    }
    final frames = receipt.frameCount, previousFrames = slot.state.frameCount;
    if (frames != null && previousFrames is int && frames <= previousFrames) {
      return false;
    }
    slot.state = slot.state.copyWith(
      lastFrameAt: _now().millisecondsSinceEpoch ~/ 1000,
    );
    int? accepted(int? value, int? previous) =>
        value != null && value >= 0 ? value : previous;
    slot.state = slot.state.copyWith(
      frameCount: accepted(receipt.frameCount, slot.state.frameCount),
      framesDecoded: accepted(receipt.framesDecoded, slot.state.framesDecoded),
      presentationTimeUs: accepted(
        receipt.presentationTimeUs,
        slot.state.presentationTimeUs,
      ),
    );
    final geometryChanged = _decoded(
      slot,
      receipt.decodedWidth,
      receipt.decodedHeight,
    );
    if (geometryChanged) _changed(slot);
    _changed(slot, 'session.frame');
    return true;
  });

  Future<void> resizeDisplay(ControlTarget target, VideoDisplaySize size) =>
      _boundary(() async {
        if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
        final slot = _selectMatching(target.sessionId, target.deviceId);
        final capture = _boundCapture(
          slot,
          target.captureRef,
          target.captureGeneration,
        );
        await _controlWork(
          slot,
          releasing: false,
          action: (work) async {
            if (slot.qualityPreparing || slot.resizing != null) {
              _fail('display_busy', '显示调整或画质切换尚未结束。');
            }
            final resizing = slot.resizing = _resize(slot, capture, work, size);
            try {
              await resizing;
            } finally {
              slot.resizing = null;
            }
          },
        );
      });

  Future<VideoQualityOptions> readVideoQualityOptions(String deviceId) =>
      _boundary(
        () => _query(deviceId, (connection, stop) async {
          final encoders = await _serverQueries.encoders(connection, stop);
          return VideoQualityOptions(
            current: _quality(deviceId),
            codecs: [
              for (final codec in VideoCodec.values)
                VideoCodecOption(
                  codec: codec,
                  encoders: encoders
                      .where((item) => item.codec == codec)
                      .toList(),
                  decoder: VideoDecoderCapability(
                    codec: codec,
                    evidence: .unknown,
                    canAttempt: false,
                    reason: '尚未核验本机解码能力。',
                  ),
                ),
            ],
            activeSessions: [
              for (final slot in _sessions.values)
                if (slot.deviceId == deviceId && !slot.revoked) _activity(slot),
            ],
          );
        }),
      );

  Future<VideoQuality> selectVideoQuality(
    String deviceId,
    VideoQualityPatch patch,
  ) => _boundary(
    () => _query(deviceId, (connection, stop) async {
      final quality = _quality(deviceId, patch);
      final encoders = await _serverQueries.encoders(connection, stop);
      _validateEncoder(quality, encoders);
      return quality;
    }),
  );

  Future<VideoCapture> reconfigureVideo(
    ControlTarget target,
    VideoQuality quality,
  ) => _boundary(() async {
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    return _reconfigure(
      _selectMatching(target.sessionId, target.deviceId),
      target,
      quality,
    );
  });

  Future<VideoStopReceipt> stopSession(
    ControlTarget target, {
    bool keepLaunchRecord = false,
  }) => _boundary(() async {
    final id = target.sessionId;
    if (id != null && !_sessions.containsKey(id)) {
      final closed = await _launches.close(id, deviceId: target.deviceId);
      if (!closed) _fail('session_not_found', '找不到这个控制窗口或待核对记录。');
      return VideoStopReceipt(sessionId: id, recordOnly: true);
    }
    final slot = _selectMatching(id, target.deviceId);
    if (target.captureRef != null || target.captureGeneration != null) {
      _boundCapture(slot, target.captureRef, target.captureGeneration);
    }
    await _stop(slot, keepLaunchRecord: keepLaunchRecord);
    return VideoStopReceipt(sessionId: slot.id, deviceId: slot.deviceId);
  });

  Future<List<SessionActivity>> readActivitySessions({
    String? deviceId,
  }) async => List.unmodifiable([
    for (final session in await readSessions(deviceId: deviceId))
      _activitySnapshot(session),
  ]);

  VideoCapture _captureDescription(_LogicalSession slot) {
    final capture = _currentCapture(slot);
    final info = capture.info;
    if (info == null || info.source == null) {
      _fail('media_not_ready', '捕获没有交付精确视频源。');
    }
    return VideoCapture(
      sessionId: slot.id,
      deviceId: slot.deviceId,
      captureRef: capture.sdk.id,
      captureGeneration: capture.generation,
      generation: slot.state.generation,
      videoSourceId: info.source!.sourceId,
      codec: VideoCodec.values.byName(info.videoCodec.name),
      width: slot.state.width!,
      height: slot.state.height!,
    );
  }

  SessionActivity _activity(_LogicalSession slot) =>
      _activitySnapshot(slot.state);

  SessionActivity _activitySnapshot(VideoSessionSnapshot session) =>
      SessionActivity(
        sessionId: session.sessionId,
        deviceId: session.deviceId,
        name: session.name,
        status: session.status.name.replaceAll(
          'awaitingRenderer',
          'awaiting_renderer',
        ),
        needsLaunchReview: session.launchOutcome == VideoLaunchOutcome.unknown,
        recordOnly: session.recordOnly,
        linkedSessionId: session.linkedSessionId,
        reason: session.reason,
      );

  Future<List<VideoSessionSnapshot>> readSessions({String? deviceId}) async {
    final unresolved = await _launches.unresolved(deviceId: deviceId);
    final active = currentSessions(deviceId: deviceId);
    final ids = active.map((value) => value.sessionId).toSet();
    for (final record in unresolved) {
      if (!ids.contains(record.operationId)) {
        active.add(
          VideoSessionSnapshot(
            sessionId: record.operationId,
            deviceId: record.deviceId,
            packageName: record.packageName,
            name: record.packageName,
            kind: VideoSessionKind.app,
            status: VideoSessionStatus.failed,
            launchOperationId: record.operationId,
            launchOutcome: VideoLaunchOutcome.unknown,
            recordOnly: true,
            linkedSessionId: record.operationId == record.sessionId
                ? null
                : record.sessionId,
            failureCode: record.failureCode,
            reason: '应用打开请求可能已提交。请先核对手机并明确关闭本次记录，再选择重新打开。',
          ),
        );
      }
    }
    return List.unmodifiable(active);
  }

  /// 同步读取当前窗口事实；组合层不取得捕获修改权。
  List<VideoSessionSnapshot> currentSessions({String? deviceId}) => [
    for (final slot in _sessions.values)
      if (deviceId == null || slot.deviceId == deviceId) slot.state,
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
    slot.state = slot.state.copyWith(
      status: VideoSessionStatus.failed,
      qualityRebuilding: false,
      qualityRebuildOutcome: VideoQualityRebuildOutcome.failed,
      qualityRetryable: true,
      qualityFailureCode: _code(error),
      reason: '新画面的本机输出未能完成，请重试画质设置。',
    );
    _changed(slot);
  }

  _LogicalSession _selectMatching(String? id, String? device) {
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

  _Capture _boundCapture(
    _LogicalSession slot,
    String? captureRef,
    int? generation, {
    bool input = false,
  }) {
    final capture = _currentCapture(slot);
    if (captureRef != null && captureRef != capture.sdk.id ||
        generation != null && generation != capture.generation ||
        input && generation != capture.generation) {
      _fail('stale_capture', '画面已重建，已取消旧画面的请求。');
    }
    return capture;
  }

  _Capture _currentCapture(_LogicalSession slot) {
    final capture = slot.current;
    if (slot.revoked ||
        capture == null ||
        capture.closed ||
        capture.expectedStop) {
      _fail('session_stopped', '控制窗口已停止。');
    }
    _checkConnection(slot);
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
    _publishEvent(type, slot.deviceId, slot.state.toSnapshot());
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

  Future<T> _query<T>(
    String deviceId,
    Future<T> Function(DeviceConnection, AdbCancellation) action,
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

  @override
  Future<RemoteClipboardText> readClipboard(ClipboardTarget target) =>
      _clipboard(target, (connection, stop, window, check) async {
        final text = await _clipboardProbe(connection, stop, window, check);
        return RemoteClipboardText(
          text: text,
          capture: window == null
              ? null
              : ClipboardCapture(
                  reference: window.sdk.id,
                  generation: window.generation,
                ),
        );
      }, writing: false);

  @override
  Future<void> writeClipboard(ClipboardTarget target, String text) =>
      _clipboard(target, (connection, stop, window, check) async {
        await _clipboardProbe(connection, stop, window, check, text: text);
      }, writing: true);

  Future<T> _clipboard<T>(
    ClipboardTarget target,
    Future<T> Function(
      DeviceConnection,
      AdbCancellation,
      _Capture?,
      void Function(),
    )
    action, {
    required bool writing,
  }) async {
    final watch = Stopwatch()..start();
    try {
      return await _boundary(() {
        _requireClipboardAccess();
        final device = target.deviceId;
        if (device.isEmpty ||
            device.contains('\x00') ||
            utf8.encode(device).length > 1024) {
          _fail('invalid_argument', '设备标识无效。');
        }
        return _query(device, (connection, stop) {
          final admission = _clipboardAdmission;
          final window = target is WindowClipboardTarget ? target : null;
          final slot = window == null ? null : _clipboardSession(window);
          final capture = slot == null
              ? null
              : _clipboardCapture(slot, window!);
          void check() {
            stop.check();
            _requireClipboardAccess();
            if (_closed || !identical(_requireConnection(device), connection)) {
              _fail('cancelled', '剪贴板所属连接已停止。');
            }
            if (slot != null &&
                (!identical(_sessions[slot.id], slot) ||
                    !identical(_clipboardCapture(slot, window!), capture) ||
                    slot.state.status != VideoSessionStatus.streaming)) {
              _fail('stale_capture', '剪贴板所属画面已停止或更换。');
            }
            final generation = window?.synchronizationGeneration;
            if (generation != null &&
                admission?.call(device, slot!.id, generation) != true) {
              _fail('cancelled', '画面已失焦或自动剪贴板已暂停。');
            }
          }

          check();
          final result = (_clipboardTails[device] ?? Future<void>.value()).then(
            (_) {
              check();
              return action(connection, stop, capture, check);
            },
          );
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
        });
      });
    } catch (error) {
      try {
        onClipboardFailure?.call(
          target.deviceId,
          writing,
          watch.elapsedMilliseconds,
          error,
        );
      } catch (_) {
        // 诊断消费者不能改变原操作的结果或资源回收权。
      }
      rethrow;
    }
  }

  _LogicalSession _clipboardSession(WindowClipboardTarget target) {
    final slot = _sessions[target.sessionId];
    if (slot == null || slot.deviceId != target.deviceId) {
      _fail('session_not_found', '找不到这个控制窗口。');
    }
    return slot;
  }

  _Capture _clipboardCapture(
    _LogicalSession slot,
    WindowClipboardTarget target,
  ) {
    final capture = _currentCapture(slot);
    final expected = target.capture;
    if (expected != null &&
        (expected.reference != capture.sdk.id ||
            expected.generation != capture.generation)) {
      _fail('stale_capture', '画面已重建，已取消旧画面的请求。');
    }
    return capture;
  }

  Future<String> _clipboardProbe(
    DeviceConnection connection,
    AdbCancellation stop,
    _Capture? window,
    void Function() check, {
    String? text,
  }) async {
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
      if (text != null) {
        final writer = window?.sdk ?? probe;
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
        return actual;
      }
      final actual = await probe.readClipboard();
      check();
      return actual;
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
    slot.state = slot.state.copyWith(
      status: VideoSessionStatus.failed,
      failureCode: 'capture_stopped',
      reason: reason,
    );
    slot.handoff?.cancel();
    slot.handoff = null;
    _changed(slot, 'session.failed');
    final task = _stop(slot, keepLaunchRecord: true);
    unawaited(task.catchError((Object _, StackTrace _) {}));
  }

  Future<VideoSessionSnapshot> startSession(VideoSessionPlan plan) =>
      _boundary(() => _startSession(plan));

  Future<VideoSessionSnapshot> _startSession(VideoSessionPlan plan) {
    if (_closed) _fail('disposed', '控制窗口所有者已关闭。');
    final device = _identifier(plan.deviceId, 'deviceId');
    final id = plan.sessionId == null
        ? _newId()
        : _identifier(plan.sessionId!, 'sessionId');
    final previous = _sessions[id];
    if (previous != null) {
      if (previous.deviceId != device ||
          previous.state.packageName != plan.packageName) {
        _fail('session_conflict', '窗口身份已用于另一次操作。');
      }
      return previous.starting ?? Future.value(previous.state);
    }
    if (_capacityUsed >= 16) {
      _fail('session_capacity', '控制窗口数量已达上限。');
    }
    final package = plan.packageName;
    if (package != null && (!_package(package))) {
      _fail('invalid_argument', '应用包名无效。');
    }
    _validateDisplaySize(plan.displaySize, minimum: package == null ? 320 : 2);
    final connection = _requireConnection(device);
    final quality = _quality(device);
    final slot = _LogicalSession(
      id,
      device,
      connection,
      VideoSessionSnapshot(
        sessionId: id,
        deviceId: device,
        name: plan.name ?? package ?? '手机屏幕',
        packageName: package,
        kind: package == null ? VideoSessionKind.screen : VideoSessionKind.app,
        status: VideoSessionStatus.starting,
        captureGeneration: 1,
        generation: 1,
        createdAt: _now().millisecondsSinceEpoch ~/ 1000,
        quality: quality,
        videoCodec: quality.codec,
        videoEncoder: quality.encoder,
        displayAuto: plan.displayAuto,
      ),
    );
    _sessions[id] = slot;
    _changed(slot, 'session.starting');
    final start = _track(slot, _begin(slot, plan, quality));
    slot.starting = start;
    return start;
  }

  Future<VideoSessionSnapshot> _begin(
    _LogicalSession slot,
    VideoSessionPlan plan,
    VideoQuality quality,
  ) async {
    try {
      onAudioEligibilityChanged?.call(slot.deviceId);
      final capture = await _spawn(
        slot,
        slot.initial,
        plan.displaySize,
        quality,
        1,
      );
      _check(slot, slot.initial);
      slot.current = capture;
      _install(slot, capture, quality);
      _observe(slot, capture);
      _changed(slot);
      return slot.state;
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
      slot.state = slot.state.copyWith(
        status: VideoSessionStatus.failed,
        failureCode: _code(error),
        reason: '$error',
      );
      if (slot.launchBegan) {
        slot.state = slot.state.copyWith(
          launchOutcome: VideoLaunchOutcome.unknown,
        );
      }
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
    VideoDisplaySize? size,
    VideoQuality quality,
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
    final package = slot.state.packageName;
    if (apiLevel == null || apiLevel < (package == null ? 21 : 29)) {
      _fail('unsupported', '这台设备的 Android 版本不支持该窗口。');
    }
    slot.state = slot.state.copyWith(apiLevel: apiLevel);
    if (package != null ||
        quality.codec.name != 'h264' ||
        quality.encoder != null) {
      _validateEncoder(
        quality,
        await _serverQueries.encoders(slot.connection, work.stop),
      );
      _check(slot, work);
    }
    ScrcpyDisplayOptions? display;
    if (package == null && generation == 1) {
      final dimensions = size;
      if (dimensions != null) {
        await _physicalDisplay(slot, work, dimensions.width, dimensions.height);
      }
    } else if (package != null) {
      final metrics = await shell.metrics(work.stop);
      final fitted = VirtualDisplayPolicy.fit((
        width: size?.width ?? metrics.width,
        height: size?.height ?? metrics.height,
      ), quality.maxSize);
      final width = fitted.width, height = fitted.height;
      display = ScrcpyDisplayOptions(
        width: width,
        height: height,
        density: scaledDisplayDensity(metrics, width, height),
      );
      slot.state = slot.state.copyWith(
        displayWidth: width,
        displayHeight: height,
        displayDensity: display.density,
      );
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
          videoCodec: ScrcpyVideoCodec.values.byName(quality.codec.name),
          videoEncoder: quality.encoder,
          maxSize: quality.maxSize,
          maxFps: quality.maxFps,
          videoBitRate: quality.bitRate,
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
        slot.state = slot.state.copyWith(taskId: retainedTask);
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
        slot.state = slot.state.copyWith(
          launchOperationId: slot.id,
          launchOutcome: VideoLaunchOutcome.sent,
        );
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
        slot.state = slot.state.copyWith(
          launchOutcome: VideoLaunchOutcome.observed,
        );
      }
      slot.state = slot.state.copyWith(displayId: displayId);
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

  void _install(_LogicalSession slot, _Capture capture, VideoQuality quality) {
    final info = capture.info!;
    slot.state = slot.state.copyWith(frameCount: null);
    slot.state = slot.state.copyWith(
      captureRef: capture.sdk.id,
      captureGeneration: capture.generation,
      videoSourceId: info.source!.sourceId,
      width: info.width,
      height: info.height,
      videoCodec: VideoCodec.values.byName(info.videoCodec.name),
      videoEncoder: quality.encoder,
      quality: quality,
      status: VideoSessionStatus.awaitingRenderer,
      awaitingSession: true,
      textureId: null,
      generation: capture.generation,
      processId: info.processId,
      processStarted: info.processStarted,
    );
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
    slot.state = slot.state.copyWith(status: VideoSessionStatus.stopping);
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
      slot.state = slot.state.copyWith(status: VideoSessionStatus.stopped);
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

bool _package(String value) =>
    value.length <= 230 &&
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')
        .hasMatch(value);

extension _SessionCommands on ControlSessionService {
  Future<T> _controlWork<T>(
    _LogicalSession slot, {
    required bool releasing,
    void Function()? validate,
    required Future<T> Function(_SessionWork work) action,
  }) {
    final work = _SessionWork();
    slot.works.add(work);
    return _track(slot, () async {
      try {
        _check(slot, work);
        validate?.call();
        if (slot.rebuilding && !releasing) {
          _fail('stale_capture', '画质正在重建，暂不接纳旧画面的输入。');
        }
        return await action(work);
      } catch (error, stack) {
        if (work.failure != null && !slot.revoked) {
          slot.state = slot.state.copyWith(
            status: VideoSessionStatus.failed,
            failureCode: work.failure,
            reason: '控制执行已撤销，远端动作结果需要核对。',
          );
          onAudioEligibilityChanged?.call(slot.deviceId);
          _changed(slot, 'session.failed');
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        slot.works.remove(work);
      }
    }());
  }

  Future<ControlReceipt> _launch(
    _LogicalSession slot,
    _Capture capture,
    _SessionWork work,
    String package,
  ) async {
    if (package.isEmpty ||
        package.contains('\x00') ||
        utf8.encode(package).length > 1024) {
      _fail('invalid_argument', '缺少有效的 packageName。');
    }
    if (!_package(package) ||
        slot.state.packageName != null && slot.state.packageName != package) {
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
      return ControlReceipt.applicationSubmitted(
        sessionId: slot.id,
        operationId: operation,
      );
    } catch (error, stack) {
      permit.cancel();
      await _launches.finish(
        operation,
        failureCode: submitted ? 'app_launch_unknown' : 'not_submitted',
      );
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _resize(
    _LogicalSession slot,
    _Capture capture,
    _SessionWork work,
    VideoDisplaySize size,
  ) async {
    if (slot.state.packageName == null) {
      final dimensions = (
        width: _range(size.width, 'displayWidth', 320, 4096),
        height: _range(size.height, 'displayHeight', 320, 4096),
      );
      await _physicalDisplay(slot, work, dimensions.width, dimensions.height);
      _check(slot, work);
      _changed(slot);
      return;
    }
    final fitted = VirtualDisplayPolicy.fit(size, slot.state.quality!.maxSize);
    final width = fitted.width, height = fitted.height;
    final display = slot.state.displayId;
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
    await _native(
      slot,
      work,
      capture,
      () => capture.sdk.sendControl(
        ScrcpyResizeDisplay(width: width, height: height),
      ),
      policy.controlTimeout,
    );
    slot.state = slot.state.copyWith(
      displayWidth: width,
      displayHeight: height,
      displayDensity: density,
    );
    _changed(slot);
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
      final lease = DisplayLease(
        slot.connection,
        timeout: policy.shellTimeout,
        onLost: () => _failedCapture(slot, 'display_supervision_lost'),
      );
      // 在第一个异步创建之前登记，失败启动和迟到回执都沿此精确所有者清理。
      slot.physicalDisplay = lease;
      try {
        await lease.start(width, height, cancellation: work.stop);
      } catch (error) {
        slot.state = slot.state.copyWith(
          displayOutcome: VideoDisplayOutcome.unknown,
          displayFailureCode: _code(error),
        );
        _changed(slot);
        rethrow;
      }
    } else {
      try {
        await previous.resize(width, height, cancellation: work.stop);
      } catch (error) {
        slot.state = slot.state.copyWith(
          displayOutcome: VideoDisplayOutcome.unknown,
          displayFailureCode: _code(error),
        );
        _changed(slot);
        rethrow;
      }
    }
    _check(slot, work);
    slot.state = slot.state.copyWith(
      displayWidth: width,
      displayHeight: height,
      displayOutcome: VideoDisplayOutcome.applied,
    );
    slot.state = slot.state.copyWith(displayFailureCode: null);
  }
}

int _range(int value, String key, int minimum, int maximum) {
  if (value < minimum || value > maximum) {
    _fail('invalid_argument', '$key 超出有效范围。');
  }
  return value;
}

void _text(String value) {
  if (value.contains('\x00') || utf8.encode(value).length > 256 * 1024) {
    _fail('invalid_argument', '文本超过限制或包含无效字符。');
  }
}

ControlPoint _point(
  _LogicalSession slot,
  ControlPoint point, {
  bool cleanup = false,
}) {
  final (:x, :y, :width, :height) = point;
  _range(width, 'screenWidth', 1, 65535);
  _range(height, 'screenHeight', 1, 65535);
  final changed = width != slot.state.width || height != slot.state.height;
  if (changed && !cleanup) _fail('stale_capture', '输入尺寸与当前精确捕获不一致。');
  _range(x, 'x', 0, width - 1);
  _range(y, 'y', 0, height - 1);
  if (!changed) return point;
  final currentWidth = slot.state.width!, currentHeight = slot.state.height!;
  return (
    x: x.clamp(0, currentWidth - 1),
    y: y.clamp(0, currentHeight - 1),
    width: currentWidth,
    height: currentHeight,
  );
}

bool _decoded(_LogicalSession slot, int? width, int? height) {
  if (width is int &&
      height is int &&
      width >= 1 &&
      height >= 1 &&
      width <= 16384 &&
      height <= 16384 &&
      width * height <= 67108864) {
    final changed = slot.state.width != width || slot.state.height != height;
    // 调用者已核验捕获、renderer 与纹理身份；当前解码尺寸才是 scrcpy 输入使用的几何。
    slot.state = slot.state.copyWith(
      width: width,
      height: height,
      decodedWidth: width,
      decodedHeight: height,
    );
    return changed;
  }
  return false;
}

extension _SessionQuality on ControlSessionService {
  VideoQuality _quality(
    String device, [
    VideoQualityPatch patch = const VideoQualityPatch(),
  ]) => VideoQualityPolicy.resolveQuality(_settings(), device, patch);

  void _validateEncoder(VideoQuality quality, List<VideoEncoder> encoders) {
    if (!encoders.any(
      (entry) =>
          entry.codec == quality.codec &&
          (quality.encoder == null || entry.name == quality.encoder),
    )) {
      _fail('encoder_unavailable', '设备没有枚举到所选格式与编码器组合，现有窗口保持运行。');
    }
  }

  Future<VideoCapture> _reconfigure(
    _LogicalSession slot,
    ControlTarget target,
    VideoQuality quality,
  ) {
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
        final old = _boundCapture(
          slot,
          target.captureRef,
          target.captureGeneration,
        );
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
        final snapshot = slot.state;
        final shell = SessionShell(slot.connection, policy.shellTimeout);
        final package = slot.state.packageName;
        int? task, oldDisplay;
        if (package != null) {
          oldDisplay = _range(
            slot.state.displayId ?? 0,
            'displayId',
            1,
            0x7fffffff,
          );
          task = await shell.task(package, oldDisplay, work.stop);
          if (slot.state.taskId != null && slot.state.taskId != task) {
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
        slot.state = slot.state.copyWith(
          qualityRebuilding: true,
          qualityRebuildTarget: generation,
          qualityRebuildOutcome: VideoQualityRebuildOutcome.rebuilding,
        );
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
            snapshot.displayWidth != null && snapshot.displayHeight != null
                ? (
                    width: snapshot.displayWidth!,
                    height: snapshot.displayHeight!,
                  )
                : null,
            quality,
            generation,
            retainedTask: task,
          );
          _check(slot, work);
          await _closeCapture(old);
          _check(slot, work);
          slot.current = candidate;
          _install(slot, candidate, quality);
          slot.state = slot.state.copyWith(
            qualityRebuilding: true,
            qualityRebuildTarget: generation,
            qualityRebuildOutcome: VideoQualityRebuildOutcome.awaitingRenderer,
            paused: snapshot.paused,
          );
          _observe(slot, candidate);
          _changed(slot);
          return _captureDescription(slot);
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
          slot.state = snapshot;
          slot.state = slot.state.copyWith(
            qualityRebuilding: false,
            qualityRebuildOutcome:
                old.closed || old.expectedStop || cleanup != null
                ? VideoQualityRebuildOutcome.failed
                : VideoQualityRebuildOutcome.restored,
            qualityRetryable: old.closed || old.expectedStop || cleanup != null,
            qualityFailureCode: _code(error),
            status: old.closed || old.expectedStop
                ? VideoSessionStatus.failed
                : snapshot.status,
            failureCode: old.closed || old.expectedStop
                ? 'capture_stopped'
                : snapshot.failureCode,
            reason: old.closed || old.expectedStop
                ? '原捕获已撤销准入，关闭结果尚需核对，不能恢复为可用窗口。'
                : snapshot.reason,
          );
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

String _identifier(String value, String key) {
  if (value.isEmpty ||
      value.contains('\x00') ||
      utf8.encode(value).length > 1024) {
    _fail('invalid_argument', '缺少有效的 $key。');
  }
  return value;
}

void _validateDisplaySize(VideoDisplaySize? size, {required int minimum}) {
  if (size == null) return;
  _range(size.width, 'displayWidth', minimum, 4096);
  _range(size.height, 'displayHeight', minimum, 4096);
}
