library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import 'src/rust/api.dart' as core;
import 'src/rust/frb_generated.dart';
import 'src/media_intent.dart';
import 'src/media/portable_video.dart';
import 'src/media/portable_audio.dart';
import 'src/media/video_presentation.dart';
import 'src/media/media_snapshot.dart';
import 'src/state_recovery.dart';
import 'src/share_intake.dart';
import 'src/documents/documents_coordinator.dart';
import 'src/documents/system_delivery.dart';
import 'src/interop_exception.dart';

export 'src/interop_exception.dart';

/// The application never invokes an external adb process. This is its only
/// boundary to the persistent Rust runtime and ordinary platform permissions.
class InteropBridge {
  InteropBridge._(this._dataDirectory);

  final String _dataDirectory;

  static const _platform = MethodChannel('dev.scrcpyconnect/platform');
  static const _mediaEvents = EventChannel('dev.scrcpyconnect/media_events');
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _textures = <String, Map<String, dynamic>>{};
  final _videoMonitors = <String, Timer>{};
  final _videoPolling = <String>{};
  final _audioSources = <String, Map<String, dynamic>>{};
  final _mediaIntents = MediaIntents();
  bool _disposed = false;
  Future<void>? _disposing;
  late final _audioOutputs = PortableAudioOutputs(
    core: _invoke,
    platform: _audioPlatformRequest,
    emit: _handleAudioOutput,
    isDisposed: () => _disposed,
  );
  late final _videoOutputs = PortableVideoOutputs(
    core: _invoke,
    emit: _handleVideoOutput,
    isDisposed: () => _disposed,
  );
  late final _videoPresentation = VideoPresentation(
    core: _invoke,
    pauseOutput: _videoOutputs.pause,
    resumeOutput: _videoOutputs.resume,
  );
  late final _stateRecovery = StateRecovery(
    read: (current) => readMediaSnapshot(
      read: () => _invoke('state.snapshot', {}),
      videos: _textures,
      audios: _audioSources,
      closeVideo: _closeVideo,
      closeAudio: _closeAudio,
      current: current,
    ),
    emit: (event) {
      if (!_disposed) _events.add(event);
    },
    isDisposed: () => _disposed,
  );
  late final _shareIntake = ShareIntake(
    core: _invoke,
    platform: _platformRequest,
    isDisposed: () => _disposed,
  );
  late final _documents = DocumentsCoordinator(
    core: _invoke,
    platform: _platformRequest,
    isDisposed: () => _disposed,
  );
  late final _systemDelivery = SystemDelivery(
    core: _invoke,
    write: (params) => _documents.request('documents.export', params),
    cancelWrite: (id) =>
        _documents.request('documents.cancel', {'operationId': id}),
    onChanged: (source) {
      if (!_disposed) _events.add({'type': 'delivery.changed', 'data': source});
    },
  );
  String? _eventSubscriptionId;
  StreamSubscription<String>? _coreSubscription;
  StreamSubscription<dynamic>? _platformSubscription;

  static Future<InteropBridge>? _initializing;
  static InteropBridge? _active;

  static Future<InteropBridge> initialize({required String dataDirectory}) {
    if (_active case final existing? when !existing._disposed) {
      return Future.error(
        const InteropException(
          'bridge_already_initialized',
          '此引擎已有互联桥接，请复用现有实例。',
        ),
      );
    }
    return _initializing ??= _initialize(dataDirectory).whenComplete(() {
      _initializing = null;
    });
  }

  static Future<InteropBridge> _initialize(String dataDirectory) async {
    await RustLib.init();
    await core.initialize(dataDirectory: dataDirectory);
    final bridge = InteropBridge._(dataDirectory);
    try {
      bridge._eventSubscriptionId = await core.openEvents();
      bridge._coreSubscription = core
          .events(subscriptionId: bridge._eventSubscriptionId!)
          .listen((message) {
            final event = jsonDecode(message) as Map<String, dynamic>;
            bridge._handleCoreEvent(event);
          }, onError: bridge._events.addError);
      if (Platform.isAndroid) {
        bridge._platformSubscription = _mediaEvents
            .receiveBroadcastStream()
            .listen((event) {
              if (event is Map) {
                if (bridge._disposed) return;
                final message = Map<String, dynamic>.from(event);
                bridge._events.add(message);
                unawaited(
                  bridge._handleNativeEvent(message).catchError((Object error) {
                    if (!bridge._disposed) {
                      bridge._events.add({
                        'type': 'platform.failed',
                        'data': {'reason': '$error'},
                      });
                    }
                  }),
                );
              }
            }, onError: bridge._events.addError);
        final state = await bridge._platformRequest(
          'audio.platform.state',
          const {},
        );
        await bridge._audioOutputs.setVisible(state['visible'] == true);
        await bridge._shareIntake.configure();
        unawaited(
          bridge._shareIntake.attach().catchError((Object error) {
            if (!bridge._disposed) {
              bridge._events.add({
                'type': 'sharing.failed',
                'data': {'reason': '$error'},
              });
            }
          }),
        );
      }
      // An isolate restart loses Player objects and their one-use streams.
      // Retire orphaned captures rather than adopting an unverified playback.
      await bridge._retireUnownedAudio();
      final settings = await bridge._invoke('settings.get', const {});
      await bridge._audioOutputs.policy(settings['backgroundAudio'] == true);
      _active = bridge;
      return bridge;
    } catch (_) {
      // Failed attachment owns no new media. Detach these observers without
      // stopping an existing process-owned background source.
      bridge._disposed = true;
      await bridge._detachCoreEvents();
      await bridge._platformSubscription?.cancel();
      bridge._audioSources.clear();
      await bridge._audioOutputs.dispose();
      await bridge._events.close();
      rethrow;
    }
  }

  void _handleCoreEvent(Map<String, dynamic> event) {
    // Transport heartbeats detect a dead Dart port; they are not product state.
    if (_disposed || event['type'] == 'runtime.heartbeat') return;
    if (!_stateRecovery.accept(event)) return;
    _events.add(event);
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : const <String, dynamic>{};
    if (event['type'] == 'device.changed' &&
        data['status'] != 'connected' &&
        event['deviceId'] is String) {
      _mediaIntents.stopDevice(event['deviceId'] as String);
    }
    if (event['type'] == 'session.disconnected') {
      final id = data['sessionId'];
      if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
        debugPrint(
          '[connect.video] core ended session=$id reason=${data['reason']}',
        );
      }
      if (id is String) unawaited(_closeVideo(id));
    } else if (event['type'] == 'audio.updated' &&
        const [
          'stopped',
          'failed',
          'error',
          'closed',
        ].contains(data['status'])) {
      final id = data['sourceId'];
      if (id is String) unawaited(_closeAudio(id));
    }
  }

  Future<void> _handleNativeEvent(Map<String, dynamic> event) async {
    if (_disposed) return;
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : const <String, dynamic>{};
    if (event['type'] == 'share.platform.pending') {
      try {
        await _shareIntake.receive(data);
      } catch (error) {
        if (!_disposed) {
          _events.add({
            'type': 'sharing.failed',
            'data': {'reason': '$error'},
          });
        }
      }
    } else if (event['type']?.toString().startsWith('audio.platform.') ==
        true) {
      await _audioOutputs.handlePlatformEvent(event);
    } else if (event['type'] == 'connections.stopped') {
      _mediaIntents.cancelAll();
      await Future.wait(_textures.keys.toList().map(_closeVideo));
      await Future.wait(_audioSources.keys.toList().map(_closeAudio));
    }
  }

  Future<void> _closeVideo(String id) async {
    if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.video] close session=$id from=${StackTrace.current}',
      );
    }
    _videoMonitors.remove(id)?.cancel();
    _textures.remove(id);
    await _videoOutputs.stop(id);
  }

  void _handleVideoOutput(Map<String, dynamic> event) {
    if (_disposed) return;
    _events.add(event);
    if (event['type'] != 'session.output.changed') return;
    final data = Map<String, dynamic>.from(event['data'] as Map);
    final id = data['sessionId'];
    if (id is! String || !_textures.containsKey(id)) return;
    _textures[id] = mergeVideoOutputReceipt(_textures[id], data);
    unawaited(
      _invoke('session.ready', data).catchError((Object error) {
        // A stopped session cannot be revived by a late generation receipt.
        return <String, dynamic>{};
      }),
    );
  }

  void _monitorVideo(String id) {
    _videoMonitors.remove(id)?.cancel();
    late final Timer timer;
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_videoPolling.add(id)) return;
      unawaited(
        _pollVideo(id, timer).whenComplete(() => _videoPolling.remove(id)),
      );
    });
    _videoMonitors[id] = timer;
  }

  Future<void> _pollVideo(String id, Timer owner) async {
    bool current() => !_disposed && identical(_videoMonitors[id], owner);
    try {
      final texture = _textures[id];
      if (!current() || texture == null) return;
      final status = await _invoke('media.status', {
        'relayId': texture['relayId'],
      });
      if (!current()) return;
      if (status['endpoint'] is Map<Object?, Object?>) {
        final endpoint = Map<String, dynamic>.from(status['endpoint'] as Map);
        if ((endpoint['generation'] as num? ?? 0) >
            (texture['generation'] as num? ?? 0)) {
          await _videoOutputs.reattach(id, endpoint: endpoint);
          return;
        }
      }
      if (['closed', 'failed'].contains(status['status'])) {
        if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
          debugPrint('[connect.video] ended session=$id status=$status');
        }
        _events.add({
          'type': 'session.failed',
          'deviceId': texture['deviceId'],
          'data': {'sessionId': id, 'reason': status['reason'] ?? '远端视频输入已结束。'},
        });
        await _invoke('session.stop', {'sessionId': id});
        await _closeVideo(id);
      }
    } catch (error) {
      if (!current()) return;
      if (const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
        debugPrint('[connect.video] reattach failed: $error');
      }
      _events.add({
        'type': 'session.failed',
        'deviceId': _textures[id]?['deviceId'],
        'data': {'sessionId': id, 'reason': '画面恢复失败，请重新打开：$error'},
      });
      await _closeVideo(id);
      try {
        await _invoke('session.stop', {'sessionId': id});
      } catch (_) {
        /* A concurrent disconnect already ended this session. */
      }
    }
  }

  Future<void> _closeAudio(String id) async {
    _audioSources.remove(id);
    await _audioOutputs.stop(id);
  }

  void _handleAudioOutput(Map<String, dynamic> event) {
    if (_disposed) return;
    _events.add(event);
    final data = Map<String, dynamic>.from(event['data'] as Map);
    final id = data['sourceId'];
    final source = _audioSources[id];
    if (id is! String ||
        source == null ||
        data['deviceId'] != source['deviceId']) {
      return;
    }
    if (event['type'] == 'audio.output.failed' ||
        (event['type'] == 'audio.presentation' && _terminalAudioFocus(data))) {
      // Claim this exact owner before awaiting so duplicate/late focus events
      // cannot stop it twice or act on another device's replacement source.
      _audioSources.remove(id);
      _mediaIntents.stop(id, audio: true);
      unawaited(() async {
        try {
          await _invoke('audio.stop', {
            'sourceId': id,
            'deviceId': source['deviceId'],
          });
        } catch (_) {
          /* The exact source may already have ended; never stop by device alone. */
        } finally {
          await _closeAudio(id);
        }
      }());
    } else if (event['type'] == 'audio.presentation') {
      unawaited(
        _invoke(
          'audio.presentation',
          data,
        ).catchError((Object _) => <String, dynamic>{}),
      );
    }
  }

  bool _terminalAudioFocus(Map<String, dynamic> receipt) =>
      receipt['requiresUserResume'] == true &&
      ['permanentLoss', 'noisy'].contains(receipt['focusSignal']);

  Future<Map<String, dynamic>> _audioPlatformRequest(
    String command,
    Map<String, dynamic> params,
  ) async {
    if (!Platform.isAndroid) {
      return {
        'supported': false,
        'granted': false,
        'ready': false,
        'reason': '此平台的声音焦点和后台适配尚未完成运行验证。',
      };
    }
    try {
      return await _platformRequest(command, params);
    } on PlatformException catch (error) {
      throw InteropException(error.code, error.message ?? '系统声音操作未完成。');
    }
  }

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<Map<String, dynamic>> _platformRequest(
    String command,
    Map<String, dynamic> params,
  ) async {
    final result = await _platform.invokeMethod<Object?>(command, params);
    return result is Map<Object?, Object?>
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _videoCapabilities() async =>
      _videoOutputs.capabilities();

  Future<void> _retireUnownedAudio() async {
    final known =
        (await _invoke('audio.sources', const {}))['sources'] as List? ??
        const [];
    for (final source in known.whereType<Map<Object?, Object?>>()) {
      if (source['sourceId'] is String &&
          source['deviceId'] is String &&
          !['stopped', 'failed', 'error'].contains(source['status'])) {
        await _invoke('audio.stop', {
          'sourceId': source['sourceId'],
          'deviceId': source['deviceId'],
        });
      }
    }
  }

  Future<void> _ensureVideoDecoder(Map<String, dynamic> params) async {
    final settings = await _invoke('settings.get', const {});
    final overrides = settings['deviceQuality'] is Map
        ? (settings['deviceQuality'] as Map)[params['deviceId']]
        : null;
    final codec =
        params['videoCodec'] ??
        params['codec'] ??
        (overrides is Map ? overrides['videoCodec'] : null) ??
        settings['videoCodec'] ??
        'h264';
    final capabilities = await _videoCapabilities();
    final supported = (capabilities['codecs'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .any(
          (item) =>
              item['id'] == codec &&
              (item['available'] == true || item['canAttempt'] == true),
        );
    if (!supported) {
      throw InteropException(
        'decoder_unavailable',
        '本机尚未提供 $codec 解码器，请选择其他视频编码。',
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(
    String command,
    Map<String, dynamic> params,
  ) async {
    if (command == 'session.stop' &&
        const bool.fromEnvironment('CONNECT_DIAGNOSTICS')) {
      debugPrint(
        '[connect.video] stop params=$params from=${StackTrace.current}',
      );
    }
    final raw = await core.invoke(
      requestJson: jsonEncode({'command': command, 'params': params}),
    );
    final envelope = jsonDecode(raw) as Map<String, dynamic>;
    if (envelope['ok'] != true) {
      final error = envelope['error'] as Map<String, dynamic>? ?? const {};
      throw InteropException(
        error['code'] as String? ?? 'unknown',
        error['message'] as String? ?? '操作未完成。',
        error['details'],
      );
    }
    return Map<String, dynamic>.from(envelope['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> request(
    String command, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_disposed) throw const InteropException('disposed', '连接界面已关闭。');
    if (command == 'session.stop' && params['sessionId'] is String) {
      _mediaIntents.stop(params['sessionId'] as String, audio: false);
    } else if (command == 'audio.stop' && params['sourceId'] is String) {
      _mediaIntents.stop(params['sourceId'] as String, audio: true);
    } else if (command == 'audio.stop' && params['deviceId'] is String) {
      _mediaIntents.stopAudioDevice(params['deviceId'] as String);
    } else if (['devices.disconnect', 'devices.forget'].contains(command)) {
      _mediaIntents.stopDevice('${params['deviceId']}');
    } else if (command == 'activities.stop' && params['id'] is String) {
      final id = params['id'] as String;
      if (id.startsWith('session:')) {
        _mediaIntents.stop(id.substring(8), audio: false);
      }
      if (id.startsWith('audio:')) {
        _mediaIntents.stop(id.substring(6), audio: true);
      }
      if (id.startsWith('connection:')) {
        _mediaIntents.stopDevice(id.substring(11));
      }
    }
    final starts = [
      'session.start',
      'apps.launch',
      'audio.start',
    ].contains(command);
    final intent = starts
        ? _mediaIntents.begin(
            '${params['deviceId']}',
            audio: command == 'audio.start',
          )
        : null;
    try {
      return await _request(command, params, intent: intent);
    } finally {
      if (intent != null) _mediaIntents.finish(intent);
    }
  }

  Future<Map<String, dynamic>> _request(
    String command,
    Map<String, dynamic> params, {
    MediaIntent? intent,
  }) async {
    if (_disposed || intent?.cancelled == true) {
      throw const InteropException('cancelled', '已停止本次打开，不会重新启动画面或声音。');
    }
    if (command == 'state.reconcile') return _stateRecovery.refresh();
    if (_stateRecovery.pending && needsVerifiedState(command, params)) {
      throw const InteropException('state_unverified', '正在重新核验设备状态，完成后再操作。');
    }
    // Refreshing projections after a gap must not create a new helper. A
    // deliberate user verification may opt in with allowStart=true.
    if (_stateRecovery.hasSnapshot &&
        const [
          'notifications.list',
          'calls.list',
          'clipboard.get',
        ].contains(command) &&
        !params.containsKey('allowStart')) {
      params = {...params, 'allowStart': false};
    }
    final stoppingAudioIds = command == 'audio.stop'
        ? _audioSources.keys
              .where(
                (id) => params['sourceId'] is String
                    ? id == params['sourceId']
                    : _audioSources[id]?['deviceId'] == params['deviceId'],
              )
              .toList()
        : const <String>[];
    if (command == 'audio.status') {
      return _audioOutputs.status(params['sourceId'] as String?);
    }
    if (command == 'session.pause' || command == 'session.resume') {
      final receipt = await _videoPresentation.request(command, params);
      final id = receipt['sessionId'];
      if (command == 'session.resume' &&
          !_disposed &&
          id is String &&
          _textures.containsKey(id) &&
          receipt['firstFrameDecoded'] == true) {
        _textures[id] = mergeVideoOutputReceipt(_textures[id], receipt);
        _events.add({
          'type': 'session.output.resumed',
          'deviceId': receipt['deviceId'],
          'data': receipt,
        });
      }
      return receipt;
    }
    if (command == 'video.capabilities') {
      return _videoCapabilities();
    }
    if (['session.start', 'apps.launch', 'session.quality'].contains(command)) {
      await _ensureVideoDecoder(params);
    }
    if (command.startsWith('documents.')) {
      if (!Platform.isAndroid) {
        throw const InteropException(
          'platform_unavailable',
          '此平台请使用系统文件路径选择器。',
        );
      }
      if (command == 'documents.export') return _systemDelivery.save(params);
      if (command == 'documents.cancel' && params['operationId'] is String) {
        final cancelled = await _systemDelivery.cancel(
          params['operationId'] as String,
        );
        if (cancelled != null) return cancelled;
      }
      return _documents.request(command, params);
    }
    if (command == 'files.open') {
      final path = params['localPath'];
      if (path is! String || path.isEmpty) {
        throw const InteropException('invalid_path', '缺少本机文件位置。');
      }
      final opened = await OpenFilex.open(path);
      if (opened.type != ResultType.done) {
        throw InteropException('open_failed', opened.message);
      }
      return {'status': 'opened'};
    }
    if (command == 'session.screenshot' && params['sessionId'] is String) {
      final directory = await Directory('$_dataDirectory/screenshots')
          .create(recursive: true);
      return _videoOutputs.screenshot(
        params['sessionId'] as String,
        directory: directory.path,
      );
    }
    if (command == 'background.status' || command == 'background.request') {
      if (!Platform.isAndroid) {
        return {'supported': false, 'reason': '此平台的后台保持尚未完成运行验证。'};
      }
      return Map<String, dynamic>.from(
        await _platform.invokeMethod<Map<dynamic, dynamic>>(command, params) ??
            const {},
      );
    }
    if (command == 'devices.cancel' && Platform.isAndroid) {
      await _platform.invokeMethod<void>('usb.cancel', params);
    }
    if (command == 'devices.usb' &&
        Platform.isAndroid &&
        !params.containsKey('fd')) {
      final permission = await _platform.invokeMethod<Map<dynamic, dynamic>>(
        'usb.authorize',
        params,
      );
      if (permission == null) {
        throw const InteropException('cancelled', '尚未允许 USB 访问。');
      }
      params = {...params, ...Map<String, dynamic>.from(permission)};
    }
    if (command == 'audio.volume') {
      final proposed = await _invoke(command, params);
      final applied = await _audioOutputs.volume(
        proposed['sourceId'] as String,
        volume: (proposed['volume'] as num).toDouble(),
        muted: proposed['muted'] == true,
      );
      final updated = await _invoke(command, {
        ...params,
        ...proposed,
        ...applied,
      });
      return {...updated, ...applied};
    }
    if (command == 'audio.pause' || command == 'audio.resume') {
      final proposed = await _invoke(command, params);
      final id = proposed['sourceId'] as String;
      final applied = command == 'audio.pause'
          ? await _audioOutputs.pause(id)
          : await _audioOutputs.resume(id);
      final updated = await _invoke(command, {
        ...params,
        ...proposed,
        ...applied,
      });
      return {...updated, ...applied};
    }
    final Map<String, dynamic> result;
    try {
      if (_disposed || intent?.cancelled == true) {
        throw const InteropException('cancelled', '已停止本次打开，不会重新启动画面或声音。');
      }
      result = await _invoke(command, params);
    } finally {
      if (Platform.isAndroid &&
          command == 'devices.usb' &&
          params['usbLeaseId'] is String) {
        await _platform.invokeMethod<void>('usb.release', {
          'usbLeaseId': params['usbLeaseId'],
        });
      }
    }
    if (command == 'settings.get' || command == 'settings.update') {
      await _audioOutputs.policy(result['backgroundAudio'] == true);
    }
    if (command == 'session.quality.options') {
      final local = await _videoCapabilities();
      final decoders = (local['codecs'] as List? ?? const [])
          .whereType<Map<Object?, Object?>>();
      final choices = <Map<String, dynamic>>[];
      for (final entry
          in (result['codecs'] as List? ?? const [])
              .whereType<Map<Object?, Object?>>()) {
        final choice = Map<String, dynamic>.from(entry);
        final matching = decoders.where(
          (decoder) => decoder['id'] == choice['id'],
        );
        final decoder = matching.firstOrNull;
        final localAvailable =
            decoder?['available'] == true || decoder?['canAttempt'] == true;
        choices.add({
          ...choice,
          'targetStatus': choice['status'],
          'decoderStatus': decoder?['status'] ?? 'unknown',
          'decoders': decoder?['decoders'] ?? const <Object?>[],
          'available': choice['available'] == true && localAvailable,
          if (!localAvailable) 'reason': '本机没有可用解码器。',
        });
      }
      return {
        ...result,
        'codecs': choices,
        'codec': [
          for (final choice in choices)
            {...choice, 'label': choice['name'], 'value': choice['id']},
        ],
        'decoderProbe': local['probe'],
      };
    }
    if (result['audioPort'] is int &&
        result['sourceId'] is String &&
        result['audioToken'] is String) {
      intent?.bind('${result['sourceId']}');
      if (_disposed || intent?.cancelled == true) {
        await _invoke('audio.stop', {
          'deviceId': result['deviceId'],
          'sourceId': result['sourceId'],
        });
        throw const InteropException('cancelled', '已停止本次声音，不会重新启动。');
      }
      final id = result['sourceId'] as String;
      _audioSources[id] = result;
      try {
        final playback = await _audioOutputs.start(
          result,
          cancelled: () => _disposed || intent?.cancelled == true,
        );
        if (_disposed || intent?.cancelled == true) {
          throw const InteropException('cancelled', '已停止本次声音，不会重新启动。');
        }
        if (_terminalAudioFocus(playback)) {
          // The first actual playback may have lost focus before its ready
          // receipt arrived. Production capture still must stop in that case.
          throw const InteropException(
            'audio_focus_lost',
            '声音焦点已结束，请重新打开此设备声音。',
          );
        }
        final ready = await _invoke('audio.ready', {...result, ...playback});
        if (_disposed || intent?.cancelled == true) {
          throw const InteropException('cancelled', '已停止本次声音，不会重新启动。');
        }
        return {...ready, ...playback};
      } catch (_) {
        try {
          await _invoke('audio.stop', {
            'deviceId': result['deviceId'],
            'sourceId': id,
          });
        } finally {
          await _closeAudio(id);
        }
        rethrow;
      }
    }
    // State updates retain the port for diagnostics, but the one-use token is
    // only returned by a newly created stream. Pause/resume must reuse Texture.
    if (result['videoPort'] is int &&
        result['sessionId'] is String &&
        result['videoToken'] is String) {
      final id = result['sessionId'] as String;
      intent?.bind(id);
      if (_disposed || intent?.cancelled == true) {
        await _invoke('session.stop', {'sessionId': id});
        throw const InteropException('cancelled', '已停止本次画面，不会重新启动。');
      }
      try {
        final texture = await _videoOutputs.start(
          result,
          cancelled: () => _disposed || intent?.cancelled == true,
        );
        if (_disposed || intent?.cancelled == true) {
          throw const InteropException('cancelled', '已停止本次画面，不会重新启动。');
        }
        _textures[id] = {...texture, 'deviceId': result['deviceId']};
        await _invoke('session.ready', {'sessionId': id, ...texture});
        if (_disposed || intent?.cancelled == true) {
          throw const InteropException('cancelled', '已停止本次画面，不会重新启动。');
        }
        _monitorVideo(id);
        return {...result, ...texture, 'status': 'connected'};
      } catch (_) {
        try {
          await _invoke('session.stop', {'sessionId': id});
        } catch (_) {
          /* Preserve the original output failure. */
        }
        await _closeVideo(id);
        rethrow;
      }
    }
    if (command == 'session.list' && result['sessions'] is List) {
      return {
        ...result,
        'sessions': [
          for (final item in result['sessions'] as List)
            sessionWithVideoOutput(
              Map<String, dynamic>.from(item as Map),
              _textures[item['sessionId']],
            ),
        ],
      };
    }
    if (command == 'session.stop') {
      final id = result['sessionId'];
      if (id is String) _mediaIntents.stop(id, audio: false);
      if (id is String) await _closeVideo(id);
    }
    if (command == 'audio.stop') {
      for (final id in stoppingAudioIds) {
        await _closeAudio(id);
      }
    }
    if (command == 'devices.disconnect' || command == 'devices.forget') {
      final deviceId = params['deviceId'];
      for (final id
          in _textures.keys
              .where((id) => _textures[id]?['deviceId'] == deviceId)
              .toList()) {
        await _closeVideo(id);
      }
      for (final id
          in _audioSources.keys
              .where((id) => _audioSources[id]?['deviceId'] == deviceId)
              .toList()) {
        await _closeAudio(id);
      }
    }
    if (Platform.isAndroid &&
        (command == 'devices.connect' || command == 'devices.usb')) {
      final settings = await _invoke('settings.get', const {});
      if (settings['backgroundKeepAlive'] == true) {
        try {
          await _platform.invokeMethod<void>('background.request', {
            'enabled': true,
          });
        } catch (error) {
          if (!_disposed) {
            _events.add({
              'type': 'background.failed',
              'data': {'reason': '$error'},
            });
          }
        }
      }
    }
    return result;
  }

  Future<void> _detachCoreEvents() async {
    final id = _eventSubscriptionId;
    _eventSubscriptionId = null;
    if (id != null) await core.cancelEvents(subscriptionId: id);
    await _coreSubscription?.cancel();
    _coreSubscription = null;
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _systemDelivery.close();
    _stateRecovery.dispose();
    await _documents.dispose();
    _mediaIntents.cancelAll();
    final pending = _mediaIntents.active.toList();
    final videoIds = {
      ..._textures.keys,
      ...pending.where((i) => !i.audio).expand((i) => i.ids),
    };
    final audioIds = {
      ..._audioSources.keys,
      ...pending.where((i) => i.audio).expand((i) => i.ids),
    };
    if (Platform.isAndroid) await _shareIntake.detach();
    await _detachCoreEvents();
    await _platformSubscription?.cancel();
    for (final id in videoIds) {
      await _closeVideo(id);
    }
    await _videoOutputs.dispose();
    for (final id in audioIds) {
      final deviceId = _audioSources[id]?['deviceId'];
      if (deviceId is String) {
        try {
          await _invoke('audio.stop', {'sourceId': id, 'deviceId': deviceId});
        } catch (_) {}
      }
      await _closeAudio(id);
    }
    await _audioOutputs.dispose();
    _textures.clear();
    _audioSources.clear();
    try {
      await Future.wait(pending.map((i) => i.done))
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      /* In-flight core startup retains its own bounded cancellation cleanup. */
    }
    if (identical(_active, this)) _active = null;
    await _events.close();
  }
}
