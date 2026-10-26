import 'dart:async';
import 'dart:math';

import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';

typedef AudioSourceJson = Map<String, Object?>;

/// 产品设备音源所有者；页面租约、质量交接资格和本机播放器分别由调用方持有。
/// 每台设备只有一份 output PCM，媒体内容直接经原生源 ABI 交给播放器。
final class DeviceAudioSourceCoordinator {
  DeviceAudioSourceCoordinator({
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
  List<AudioSourceJson> snapshots({bool activeOnly = false}) => [
    for (final entry in _current.values) _snapshot(entry),
    if (!activeOnly)
      for (final entry in _retiring) _snapshot(entry),
  ];

  Future<AudioSourceJson> command(String command, AudioSourceJson params) {
    if (command == 'audio.sources') {
      return Future.value({'sources': snapshots()});
    }
    final device = _required(params, 'deviceId');
    if (command == 'audio.start') return start(device);
    if (command == 'audio.stop') {
      final source = params['sourceId'];
      if (source != null && (source is! String || source.isEmpty)) {
        throw const ApplicationCommandException(
          'invalid_argument',
          '声音来源身份无效。',
        );
      }
      return stop(device, sourceId: source as String?);
    }
    _checkOpen();
    final entry = _current[device];
    if (entry == null) throw _sourceRequired();
    _checkCurrent(entry);
    final expected = params['sourceId'];
    if (expected != null && expected != entry.id) throw _sourceChanged();
    // 提议可按设备选择；异步播放器回执必须绑定精确来源，不能写入后继。
    if ((params['applied'] == true ||
            command == 'audio.ready' ||
            command == 'audio.presentation') &&
        expected != entry.id) {
      throw _sourceChanged();
    }
    switch (command) {
      case 'audio.ready':
        if (entry.source == null) {
          throw const ApplicationCommandException(
            'audio_not_ready',
            '设备音频捕获尚未就绪。',
          );
        }
        _applyReady(entry.state, params);
      case 'audio.presentation':
        _requireAttached(entry);
        _applyPresentation(entry.state, params);
      case 'audio.pause' || 'audio.resume':
        _requireAttached(entry);
        if (params['applied'] != true) {
          return Future.value({
            'deviceId': device,
            'sourceId': entry.id,
            'nativeApplyRequired': true,
            'paused': command == 'audio.pause',
          });
        }
        _applyPresentation(entry.state, params);
      case 'audio.volume':
        final volume = params.containsKey('volume')
            ? params['volume']
            : entry.state['volume'];
        final muted = params.containsKey('muted')
            ? params['muted']
            : entry.state['muted'];
        if (volume is! num ||
            !volume.isFinite ||
            volume < 0 ||
            volume > 1 ||
            muted is! bool) {
          throw const ApplicationCommandException(
            'invalid_argument',
            '音量或静音状态无效。',
          );
        }
        if (params['applied'] != true) {
          return Future.value({
            'deviceId': device,
            'sourceId': entry.id,
            'volume': volume.toDouble(),
            'muted': muted,
            'nativeApplyRequired': true,
          });
        }
        entry.state['volume'] = volume.toDouble();
        entry.state['muted'] = muted;
      default:
        throw const ApplicationCommandException('unknown_command', '音源操作无效。');
    }
    _updated(entry);
    return Future.value(_snapshot(entry));
  }

  Future<AudioSourceJson> start(String deviceId) {
    _checkOpen();
    if (!hasAudioOwner(deviceId)) throw _sessionRequired();
    final connection = requireConnection(deviceId);
    final level = apiLevel?.call(deviceId);
    if (level != null && level < 30) {
      throw const ApplicationCommandException(
        'unsupported',
        '设备声音采集需要 Android 11 或更新版本。',
      );
    }
    if (_current[deviceId] case final existing?) {
      if (!_sameConnection(existing.connection, connection)) {
        throw const ApplicationCommandException(
          'source_changed',
          '设备连接已替换，请先排空旧音源。',
        );
      }
      if (existing.state['nativeAttached'] != true) {
        throw const ApplicationCommandException(
          'audio_source_starting',
          '这台设备的音源正在连接。',
        );
      }
      return Future.value({..._snapshot(existing), 'existing': true});
    }
    final generation = (_generations[deviceId] ?? 0) + 1;
    _generations[deviceId] = generation;
    final id = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final entry = _DeviceAudioSource(id, deviceId, generation, connection, {
      'sourceId': id,
      'deviceId': deviceId,
      'generation': generation,
      'name': deviceName?.call(deviceId) ?? deviceId,
      'status': 'starting',
      'codec': 'pcm_s16le',
      'sampleRate': 48000,
      'channels': 2,
      'bytesPerSample': 2,
      'volume': 1.0,
      'muted': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'nativeAttached': false,
      'playbackVerified': false,
      'speakerSamplesVerified': false,
      'audibleContentVerified': false,
      'captureSource': 'output',
      'callAudioSupported': false,
      'remoteExitVerified': false,
    });
    _current[deviceId] = entry;
    _updated(entry);
    return _start(entry);
  }

  Future<AudioSourceJson> _start(_DeviceAudioSource entry) async {
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
        throw const ApplicationCommandException(
          'audio_not_ready',
          '音频捕获尚未返回实际 PCM 来源。',
        );
      }
      _validateSource(source);
      entry.source = source;
      entry.state.addAll({
        'audioSourceId': source.sourceId,
        'captureRef': session.id,
        'nativeGeneration': source.generation,
        'captureReady': true,
        'mediaReady': info.mediaReady,
        if (info.processId != null) 'processId': info.processId,
        if (info.processStarted != null) 'processStarted': info.processStarted,
      });
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
            ? const ApplicationCommandException('cancelled', '此设备音源已结束。')
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

  Future<AudioSourceJson> stop(String deviceId, {String? sourceId}) async {
    final current = _current[deviceId];
    if (current != null) {
      if (sourceId != null && sourceId != current.id) throw _sourceChanged();
      sourceId ??= current.id;
      _retire(current);
    }
    await _drain(deviceId, sourceId: sourceId);
    return {'deviceId': deviceId, 'sourceId': sourceId, 'status': 'stopped'};
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
  Future<AudioSourceJson> openSource(
    String nativeSourceId, {
    int generation = 1,
  }) async {
    if (generation <= 0) {
      throw const ApplicationCommandException('invalid_argument', '声音输出代次无效。');
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
    return {
      'sourceId': source.sourceId,
      'relayId': source.sourceId,
      'generation': source.generation,
      'container': 'packet',
      'kind': 'audio',
      'codec': source.codec,
      'sampleRate': 48000,
      'channels': 2,
      'bytesPerSample': 2,
      'attachAddress': source.attachAddress,
      'detachAddress': source.detachAddress,
    };
  }

  /// 查询当前来源的真实原生 sink 状态；包数不代表解码、扬声器或可闻声音。
  Future<AudioSourceJson> sourceStatus(String nativeSourceId) async {
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
      return {
        'sourceId': status.sourceId,
        'relayId': status.sourceId,
        'captureRef': status.captureRef,
        'generation': status.generation,
        'kind': status.kind.name,
        'codec': status.codec,
        'status': status.status.name,
        'packets': status.packets,
        'bytes': status.bytes,
      };
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
    entry.state['status'] = error ? 'error' : 'stopped';
    entry.state['nativeAttached'] = false;
    if (reason != null) entry.state['reason'] = reason;
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
      entry.state.remove('cleanupError');
      entry.state['localReleased'] = true;
      _retiring.remove(entry);
    } catch (error, stack) {
      entry.cleaning = null;
      entry.state['cleanupError'] = Map<String, Object?>.unmodifiable({
        'code': 'audio_cleanup_unconfirmed',
        'reason': error.toString(),
      });
      _updated(entry);
      Error.throwWithStackTrace(_applicationError(error), stack);
    }
  }

  void _checkOpen() {
    if (_closed) {
      throw const ApplicationCommandException('disposed', '音源所有者已关闭。');
    }
  }

  void _checkCurrent(_DeviceAudioSource entry) {
    _checkOpen();
    if (entry.retired || !identical(_current[entry.deviceId], entry)) {
      throw const ApplicationCommandException('cancelled', '此设备音源已结束。');
    }
    if (!hasAudioOwner(entry.deviceId)) throw _sessionRequired();
    if (!_sameConnection(requireConnection(entry.deviceId), entry.connection)) {
      throw _sourceChanged();
    }
  }

  void _updated(_DeviceAudioSource entry) {
    try {
      emit('audio.updated', entry.deviceId, _snapshot(entry));
    } catch (_) {
      // 投影消费者失败不能中断撤权或丢掉精确原生关闭权。
    }
  }

  AudioSourceJson _snapshot(_DeviceAudioSource entry) =>
      Map<String, Object?>.unmodifiable(entry.state);

  static bool _sameConnection(DeviceConnection a, DeviceConnection b) =>
      identical(a.client, b.client) && a.device.id == b.device.id;

  static void _requireAttached(_DeviceAudioSource entry) {
    if (entry.state['nativeAttached'] != true) {
      throw const ApplicationCommandException('audio_not_ready', '音频播放器尚未就绪。');
    }
  }

  static void _validateSource(ScrcpyNativeSource source) {
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(source.sourceId) ||
        source.codec != 'pcm_s16le' ||
        source.generation <= 0 ||
        source.attachAddress <= 0 ||
        source.detachAddress <= 0) {
      throw const ApplicationCommandException(
        'invalid_endpoint',
        '原生音频来源格式或地址无效。',
      );
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
  final AudioSourceJson state;
  Future<ScrcpySession>? creating;
  ScrcpySession? session;
  ScrcpyNativeSource? source;
  StreamSubscription<ScrcpyEvent>? observer;
  Future<void>? cleaning;
  bool retired = false;
}

void _applyReady(AudioSourceJson state, AudioSourceJson params) {
  if (params['backend'] != 'media_codec' ||
      params['nativeReady'] != true ||
      params['applied'] != true ||
      params['revision'] is! int ||
      (params['revision'] as int) < 0 ||
      params['bytesWritten'] is! int ||
      (params['bytesWritten'] as int) <= 0 ||
      !const ['playing', 'paused'].contains(params['playState'])) {
    throw const ApplicationCommandException(
      'audio_not_ready',
      '原生音频输出尚未确认实际播放数据。',
    );
  }
  if (state['nativeAttached'] == true) {
    _applyPresentation(state, params);
    return;
  }
  state.addAll({
    'backend': 'media_codec',
    'nativeAttached': true,
    'nativeRevision': params['revision'],
    'bytesWritten': params['bytesWritten'],
    'status': params['playState'],
    'playbackVerified': true,
  });
  _copyPauseReasons(state, params);
}

void _applyPresentation(AudioSourceJson state, AudioSourceJson params) {
  final revision = params['revision'];
  if (revision is! int ||
      revision < 0 ||
      params['applied'] != true ||
      !const ['playing', 'paused'].contains(params['playState'])) {
    throw const ApplicationCommandException(
      'audio_not_applied',
      '播放器尚未确认实际声音状态。',
    );
  }
  if (revision < (state['nativeRevision'] as int? ?? 0)) return;
  state.addAll({
    'nativeRevision': revision,
    'status': params['playState'],
    'presentationOnly': false,
    'playbackVerified': true,
  });
  _copyPauseReasons(state, params);
  final reason = params['reason'];
  if (reason is String) {
    state['reason'] = String.fromCharCodes(reason.runes.take(1024));
  } else {
    state.remove('reason');
  }
}

void _copyPauseReasons(AudioSourceJson state, AudioSourceJson params) {
  for (final key in [
    'manualPaused',
    'focusPaused',
    'backgroundPaused',
    'requiresUserResume',
  ]) {
    if (params[key] is bool) state[key] = params[key];
  }
  if (params['focusSignal'] is String) {
    state['focusSignal'] = params['focusSignal'];
  }
}

String _required(AudioSourceJson params, String key) {
  final value = params[key];
  if (value is! String || value.isEmpty) {
    throw ApplicationCommandException('invalid_argument', '缺少有效的$key。');
  }
  return value;
}

Object _applicationError(Object error) => error is ScrcpyException
    ? ApplicationCommandException(error.code, error.message)
    : error;
ApplicationCommandException _sessionRequired() =>
    const ApplicationCommandException(
      'session_required',
      '请先打开这台设备的远控画面或应用窗口。',
    );
ApplicationCommandException _sourceRequired() =>
    const ApplicationCommandException('audio_source_required', '请先连接这台设备的音源。');
ApplicationCommandException _sourceChanged() =>
    const ApplicationCommandException('source_changed', '设备音源已重新连接。');
