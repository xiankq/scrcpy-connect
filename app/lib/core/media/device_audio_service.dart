import 'audio_sources.dart';

import 'package:media_codec/media_codec.dart';

import 'package:scrcpy_connect/core/devices/device_connection.dart';

import 'dart:async';
import 'dart:math';

import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/application/request_failure.dart';

typedef AudioSourceJson = Map<String, Object?>;

/// 产品设备音源所有者；页面租约、质量交接资格和本机播放器分别由调用方持有。
/// 每台设备只有一份 output PCM，媒体内容直接经原生源 ABI 交给播放器。
final class DeviceAudioService {
  DeviceAudioService({
    required this.requireConnection,
    required this.scrcpy,
    required this.hasAudioOwner,
    required this.emit,
    this.deviceName,
    this.apiLevel,
  });

  final DeviceConnection Function(String) requireConnection;
  final ScrcpyClient scrcpy;
  final bool Function(String) hasAudioOwner;
  final void Function(String, String, AudioSourceJson) emit;
  final String Function(String)? deviceName;
  final int? Function(String)? apiLevel;
  final _current = <String, _DeviceAudioSource>{};
  final _retiring = <_DeviceAudioSource>[];
  final _generations = <String, int>{};
  final _random = Random.secure();
  bool _closed = false;
  Future<void>? _closing;

  /// 快照不暴露可写登记；退休记录只为保留未确认清理的精确责任。
  List<DeviceAudioSnapshot> snapshots({bool activeOnly = false}) => [
    for (final entry in _current.values) _snapshot(entry),
    if (!activeOnly)
      for (final entry in _retiring) _snapshot(entry),
  ];

  _DeviceAudioSource _select(DeviceAudioTarget target, {bool exact = false}) {
    if (target.deviceId.isEmpty) {
      throw const RequestFailure('invalid_argument', '缺少有效的设备标识。');
    }
    _checkOpen();
    final entry = _current[target.deviceId];
    if (entry == null) throw _sourceRequired();
    _checkCurrent(entry);
    if ((target.sourceId != null && target.sourceId != entry.id) ||
        (exact && target.sourceId != entry.id)) {
      throw _sourceChanged();
    }
    return entry;
  }

  DeviceAudioSnapshot preparePresentation(DeviceAudioTarget target) {
    final entry = _select(target);
    _requireAttached(entry);
    return _snapshot(entry);
  }

  AudioVolumeChange prepareVolume(
    DeviceAudioTarget target, {
    double? volume,
    bool? muted,
  }) {
    final entry = _select(target);
    final value = volume ?? entry.state.volume;
    if (!value.isFinite || value < 0 || value > 1) {
      throw const RequestFailure('invalid_argument', '音量或静音状态无效。');
    }
    return AudioVolumeChange(
      target: DeviceAudioTarget(deviceId: entry.deviceId, sourceId: entry.id),
      volume: value,
      muted: muted ?? entry.state.muted,
    );
  }

  DeviceAudioSnapshot acceptReady(AudioOutputReceipt receipt) {
    final entry = _select(
      DeviceAudioTarget(deviceId: receipt.deviceId, sourceId: receipt.sourceId),
      exact: true,
    );
    if (entry.source == null) {
      throw const RequestFailure('audio_not_ready', '设备音频捕获尚未就绪。');
    }
    entry.state = _applyReady(entry.state, receipt);
    _updated(entry);
    return _snapshot(entry);
  }

  DeviceAudioSnapshot acceptPresentation(AudioOutputReceipt receipt) {
    final entry = _select(
      DeviceAudioTarget(deviceId: receipt.deviceId, sourceId: receipt.sourceId),
      exact: true,
    );
    _requireAttached(entry);
    entry.state = _applyPresentation(entry.state, receipt);
    _updated(entry);
    return _snapshot(entry);
  }

  DeviceAudioSnapshot acceptVolume(AudioOutputReceipt receipt) {
    final entry = _select(
      DeviceAudioTarget(deviceId: receipt.deviceId, sourceId: receipt.sourceId),
      exact: true,
    );
    if (!receipt.applied) {
      throw const RequestFailure('audio_not_applied', '播放器尚未确认实际声音状态。');
    }
    if (!receipt.volume.isFinite || receipt.volume < 0 || receipt.volume > 1) {
      throw const RequestFailure('invalid_argument', '音量或静音状态无效。');
    }
    entry.state = entry.state.copyWith(
      volume: receipt.volume,
      muted: receipt.muted,
    );
    _updated(entry);
    return _snapshot(entry);
  }

  Future<DeviceAudioSnapshot> start(String deviceId) {
    _checkOpen();
    if (!hasAudioOwner(deviceId)) throw _sessionRequired();
    final connection = requireConnection(deviceId);
    final level = apiLevel?.call(deviceId);
    if (level != null && level < 30) {
      throw const RequestFailure('unsupported', '设备声音采集需要 Android 11 或更新版本。');
    }
    if (_current[deviceId] case final existing?) {
      if (!_sameConnection(existing.connection, connection)) {
        throw const RequestFailure('source_changed', '设备连接已替换，请先排空旧音源。');
      }
      if (!existing.state.nativeAttached) {
        throw const RequestFailure('audio_source_starting', '这台设备的音源正在连接。');
      }
      return Future.value(_snapshot(existing).copyWith(existing: true));
    }
    final generation = (_generations[deviceId] ?? 0) + 1;
    _generations[deviceId] = generation;
    final id = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final entry = _DeviceAudioSource(
      id,
      deviceId,
      generation,
      connection,
      DeviceAudioSnapshot(
        sourceId: id,
        deviceId: deviceId,
        generation: generation,
        name: deviceName?.call(deviceId) ?? deviceId,
        status: DeviceAudioStatus.starting,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    _current[deviceId] = entry;
    _updated(entry);
    return _start(entry);
  }

  Future<DeviceAudioSnapshot> _start(_DeviceAudioSource entry) async {
    try {
      // 清理首败不得由新启动绕过；不同设备互不等待。
      await _drain(entry.deviceId);
      _checkCurrent(entry);
      entry.creating = scrcpy.createSession(
        entry.connection.device,
        options: const ScrcpyOptions(
          logLevel: ScrcpyLogLevel.warn,
          video: false,
          audio: true,
          control: false,
          powerOn: false,
          clipboardAutosync: false,
        ),
      );
      // 不把取消令牌交给创建入口，先取得精确关闭权再判断迟到结果。
      final session = entry.session = await entry.creating!;
      _checkCurrent(entry);
      entry.observer = session.events.listen(
        (event) {
          if (event is ScrcpyStopped && !entry.retired) {
            _retire(entry, reason: event.reason);
            _backgroundDrain(entry);
          }
        },
        onError: (Object error) {
          if (!entry.retired) {
            _retire(entry, error: true, reason: error.toString());
            _backgroundDrain(entry);
          }
        },
        onDone: () {
          if (!entry.retired) {
            _retire(entry, error: true, reason: '声音捕获事件连接已结束。');
            _backgroundDrain(entry);
          }
        },
      );
      final info = await session.start();
      _checkCurrent(entry);
      final source = info.audioSource;
      if (!info.audioEnabled || !info.mediaReady || source == null) {
        throw const RequestFailure('audio_not_ready', '音频捕获尚未返回实际 PCM 来源。');
      }
      _validateSource(source);
      entry.source = source;
      entry.state = entry.state.copyWith(
        audioSourceId: source.sourceId,
        captureRef: session.id,
        nativeGeneration: source.generation,
        captureReady: true,
        mediaReady: info.mediaReady,
        processId: info.processId,
        processStarted: info.processStarted,
      );
      // 格式就绪不等于播放器收到数据；audio.ready 仍由真实输出回执确认。
      _updated(entry);
      return _snapshot(entry);
    } catch (error, stack) {
      final revoked = entry.retired;
      _retire(
        entry,
        error: !entry.retired,
        reason: entry.retired ? null : error.toString(),
      );
      try {
        await _cleanup(entry);
      } catch (_) {
        // 保留精确会话及 cleanupError，显式 stop/close 可以继续重试。
      }
      Error.throwWithStackTrace(
        revoked
            ? const RequestFailure('cancelled', '此设备音源已结束。')
            : _applicationError(error),
        stack,
      );
    }
  }

  /// 资格撤销在调用当下生效。质量交接是否仍有资格由会话所有者同步决定。
  Future<void> eligibilityChanged(String deviceId) {
    if (!hasAudioOwner(deviceId)) {
      if (_current[deviceId] case final entry?) {
        _retire(entry);
      }
    }
    return _drain(deviceId);
  }

  Future<String?> stop(String deviceId, {String? sourceId}) async {
    final current = _current[deviceId];
    if (current != null) {
      if (sourceId != null && sourceId != current.id) throw _sourceChanged();
      sourceId ??= current.id;
      _retire(current);
    }
    await _drain(deviceId, sourceId: sourceId);
    return sourceId;
  }

  /// 旧连接停止只能回收自己创建的音源，不能撤销后继连接的来源。
  Future<void> stopForConnection(String deviceId, DeviceConnection connection) {
    final current = _current[deviceId];
    if (current != null && _sameConnection(current.connection, connection)) {
      _retire(current);
    }
    return _drain(deviceId, connection: connection);
  }

  /// 读取当前实际原生来源；只返回 ABI 地址与格式，不制造包数或播放事实。
  Future<MediaCodecSource> openSource(
    String nativeSourceId, {
    int generation = 1,
  }) async {
    if (generation <= 0) {
      throw const RequestFailure('invalid_argument', '声音输出代次无效。');
    }
    final entry = _current.values
        .where((entry) => entry.source?.sourceId == nativeSourceId)
        .firstOrNull;
    if (entry == null) throw _sourceRequired();
    _checkCurrent(entry);
    final info = await scrcpy.api.inspect(
      entry.session!.id,
      generation: generation,
    );
    _checkCurrent(entry);
    final source = info.audioSource;
    if (info.id != entry.session!.id || source?.sourceId != nativeSourceId) {
      throw _sourceChanged();
    }
    _validateSource(source!);
    return MediaCodecSource(
      sourceId: source.sourceId,
      generation: source.generation,
      codec: source.codec,
      attachAddress: source.attachAddress,
      detachAddress: source.detachAddress,
    );
  }

  /// 查询当前来源的真实原生 sink 状态；包数不代表解码、扬声器或可闻声音。
  Future<ScrcpySourceStatus> sourceStatus(String nativeSourceId) async {
    final entry = _current.values
        .where((entry) => entry.source?.sourceId == nativeSourceId)
        .firstOrNull;
    if (entry == null) throw _sourceRequired();
    _checkCurrent(entry);
    try {
      final status = await scrcpy.sourceStatus(
        entry.connection.device,
        captureRef: entry.session!.id,
        sourceId: nativeSourceId,
      );
      _checkCurrent(entry);
      if (status.kind != ScrcpySourceKind.audio ||
          status.codec != 'pcm_s16le') {
        throw _sourceChanged();
      }
      return status;
    } on ScrcpyException catch (error, stack) {
      Error.throwWithStackTrace(_applicationError(error), stack);
    }
  }

  Future<void> close() {
    _closed = true;
    for (final entry in _current.values.toList()) {
      _retire(entry);
    }
    return _closing ??= _close();
  }

  Future<void> _close() async {
    try {
      await Future.wait([
        for (final entry in _retiring.toList()) _cleanup(entry),
      ]);
    } catch (_) {
      _closing = null;
      rethrow;
    }
  }

  void _retire(_DeviceAudioSource entry, {bool error = false, String? reason}) {
    if (entry.retired) return;
    entry.retired = true;
    if (identical(_current[entry.deviceId], entry)) {
      _current.remove(entry.deviceId);
    }
    _retiring.add(entry);
    entry.state = entry.state.copyWith(
      status: error ? DeviceAudioStatus.error : DeviceAudioStatus.stopped,
      nativeAttached: false,
      reason: reason ?? entry.state.reason,
    );
    _updated(entry);
  }

  Future<void> _drain(
    String deviceId, {
    String? sourceId,
    DeviceConnection? connection,
  }) => Future.wait([
    for (final entry in _retiring.toList())
      if (entry.deviceId == deviceId &&
          (sourceId == null || entry.id == sourceId) &&
          (connection == null || _sameConnection(entry.connection, connection)))
        _cleanup(entry),
  ]);

  void _backgroundDrain(_DeviceAudioSource entry) {
    unawaited(
      _cleanup(entry).catchError((Object _) {
        // cleanupError 已投影；失败仍登记，不能丢掉原生关闭权。
      }),
    );
  }

  Future<void> _cleanup(_DeviceAudioSource entry) =>
      entry.cleaning ??= _release(entry);

  Future<void> _release(_DeviceAudioSource entry) async {
    try {
      // 即使 Dart 请求已取消，也等待创建返回，不抛下尚未交付的原生登记。
      if (entry.session == null && entry.creating != null) {
        try {
          entry.session = await entry.creating;
        } on ScrcpyCreationCleanupFailure catch (error) {
          entry.session = error.session;
        } catch (_) {
          // create 未交付会话时由 SDK 保持其创建失败契约。
        }
      }
      await entry.session?.close();
      await entry.observer?.cancel();
      entry.observer = null;
      entry.state = entry.state.copyWith(
        cleanupError: null,
        localReleased: true,
      );
      _retiring.remove(entry);
    } catch (error, stack) {
      entry.cleaning = null;
      entry.state = entry.state.copyWith(
        cleanupError: AudioCleanupFailure(
          code: 'audio_cleanup_unconfirmed',
          reason: error.toString(),
        ),
      );
      _updated(entry);
      Error.throwWithStackTrace(_applicationError(error), stack);
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw const RequestFailure('disposed', '音源所有者已关闭。');
    }
  }

  void _checkCurrent(_DeviceAudioSource entry) {
    _checkOpen();
    if (entry.retired || !identical(_current[entry.deviceId], entry)) {
      throw const RequestFailure('cancelled', '此设备音源已结束。');
    }
    if (!hasAudioOwner(entry.deviceId)) throw _sessionRequired();
    if (!_sameConnection(requireConnection(entry.deviceId), entry.connection)) {
      throw _sourceChanged();
    }
  }

  void _updated(_DeviceAudioSource entry) {
    try {
      emit('audio.updated', entry.deviceId, _snapshot(entry).toJson());
    } catch (_) {
      // 投影消费者失败不能中断撤权或丢掉精确原生关闭权。
    }
  }

  DeviceAudioSnapshot _snapshot(_DeviceAudioSource entry) => entry.state;

  static bool _sameConnection(DeviceConnection a, DeviceConnection b) =>
      identical(a.client, b.client) && a.device.id == b.device.id;

  static void _requireAttached(_DeviceAudioSource entry) {
    if (!entry.state.nativeAttached) {
      throw const RequestFailure('audio_not_ready', '音频播放器尚未就绪。');
    }
  }

  static void _validateSource(ScrcpyNativeSource source) {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(source.sourceId) ||
        source.codec != 'pcm_s16le' ||
        source.generation <= 0 ||
        source.attachAddress <= 0 ||
        source.detachAddress <= 0) {
      throw const RequestFailure('invalid_endpoint', '原生音频来源格式或地址无效。');
    }
  }
}

final class _DeviceAudioSource {
  _DeviceAudioSource(
    this.id,
    this.deviceId,
    this.generation,
    this.connection,
    this.state,
  );
  final String id, deviceId;
  final int generation;
  final DeviceConnection connection;
  DeviceAudioSnapshot state;
  Future<ScrcpySession>? creating;
  ScrcpySession? session;
  ScrcpyNativeSource? source;
  StreamSubscription<ScrcpyEvent>? observer;
  Future<void>? cleaning;
  bool retired = false;
}

DeviceAudioSnapshot _applyReady(
  DeviceAudioSnapshot state,
  AudioOutputReceipt receipt,
) {
  if (receipt.backend != 'media_codec' ||
      !receipt.nativeReady ||
      !receipt.applied ||
      receipt.revision < 0 ||
      receipt.bytesWritten <= 0 ||
      receipt.playState == AudioPlayState.starting) {
    throw const RequestFailure('audio_not_ready', '原生音频输出尚未确认实际播放数据。');
  }
  if (state.nativeAttached) return _applyPresentation(state, receipt);
  return _copyPauseReasons(
    state.copyWith(
      backend: 'media_codec',
      nativeAttached: true,
      nativeRevision: receipt.revision,
      bytesWritten: receipt.bytesWritten,
      status: receipt.playState == AudioPlayState.playing
          ? DeviceAudioStatus.playing
          : DeviceAudioStatus.paused,
      playbackVerified: true,
    ),
    receipt,
  );
}

DeviceAudioSnapshot _applyPresentation(
  DeviceAudioSnapshot state,
  AudioOutputReceipt receipt,
) {
  if (receipt.revision < 0 ||
      !receipt.applied ||
      receipt.playState == AudioPlayState.starting) {
    throw const RequestFailure('audio_not_applied', '播放器尚未确认实际声音状态。');
  }
  if (receipt.revision < (state.nativeRevision ?? 0)) return state;
  return _copyPauseReasons(
    state.copyWith(
      nativeRevision: receipt.revision,
      status: receipt.playState == AudioPlayState.playing
          ? DeviceAudioStatus.playing
          : DeviceAudioStatus.paused,
      presentationOnly: false,
      playbackVerified: true,
      reason: String.fromCharCodes(receipt.reason.runes.take(1024)),
    ),
    receipt,
  );
}

DeviceAudioSnapshot _copyPauseReasons(
  DeviceAudioSnapshot state,
  AudioOutputReceipt receipt,
) => state.copyWith(
  manualPaused: receipt.manualPaused,
  focusPaused: receipt.focusPaused,
  backgroundPaused: receipt.backgroundPaused,
  requiresUserResume: receipt.requiresUserResume,
  focusSignal: receipt.focusSignal,
);

Object _applicationError(Object error) => error is ScrcpyException
    ? RequestFailure(error.code, error.message)
    : error;
RequestFailure _sessionRequired() =>
    const RequestFailure('session_required', '请先打开这台设备的远控画面或应用窗口。');
RequestFailure _sourceRequired() =>
    const RequestFailure('audio_source_required', '请先连接这台设备的音源。');
RequestFailure _sourceChanged() =>
    const RequestFailure('source_changed', '设备音源已重新连接。');
