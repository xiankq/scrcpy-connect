import 'dart:async';

import '../interop_exception.dart';
import 'audio_player_port.dart';
import 'fvp_audio_player.dart';

export 'audio_player_port.dart';

/// Process/engine-scoped output owner. Core owns remote capture; the platform
/// owns OS focus and foreground-service eligibility. No per-packet Dart PCM.
class PortableAudioOutputs {
  PortableAudioOutputs({
    required this.core,
    required this.platform,
    required this.emit,
    required this.isDisposed,
    AudioPlayerFactory? playerFactory,
    this.startTimeout = const Duration(seconds: 18),
    this.operationTimeout = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 50),
  }) : _factory = playerFactory ?? FvpAudioPlayer.new;

  final AudioRequest core, platform;
  final void Function(AudioJson) emit;
  final bool Function() isDisposed;
  final AudioPlayerFactory _factory;
  final Duration startTimeout, operationTimeout, pollInterval;
  final _entries = <String, _AudioOutput>{};
  final _stopped = <String>{};
  final _releases = <Future<AudioJson>>{};
  final _releasedEpochs = <int>{};
  int? _epoch;
  int _lastEpoch = -1, _focusGeneration = 0, _policyRevision = 0;
  String _focusSignal = 'none';
  Future<void>? _acquiring, _backgroundSync, _disposing;
  bool _disposed = false, _visible = false;
  bool _backgroundAllowed = false, _backgroundReady = false;
  bool? _backgroundRequested;

  Future<AudioJson> start(
    AudioJson stream, {
    bool Function()? cancelled,
  }) async {
    _checkOwner();
    final id = _text(stream, 'sourceId'), device = _text(stream, 'deviceId');
    if (_stopped.contains(id) || cancelled?.call() == true) throw _cancelled();
    if (_entries[id] case final existing?) {
      if (existing.device != device) {
        throw const InteropException('source_changed', '声音输出不属于这台设备。');
      }
      await existing.ready;
      _check(existing);
      return _receipt(existing);
    }
    _input(stream);
    if (_entries.length >= 16) {
      throw const InteropException('resource_busy', '声音输出数量已达上限。');
    }
    final entry = _AudioOutput(id, device, _factory(), cancelled);
    _entries[id] = entry;
    entry.startTimer = Timer(startTimeout, () {
      entry.timedOut = true;
      entry.cancel();
    });
    entry.ready = _start(entry, stream);
    return entry.ready!;
  }

  Future<AudioJson> _start(_AudioOutput entry, AudioJson stream) async {
    try {
      await _await(entry, _syncBackground());
      while (!_eligible) {
        await _delay(entry);
      }
      await _await(entry, _ensureFocus());
      final opening = core('media.open', {
        'kind': 'audio',
        'port': stream['audioPort'],
        'token': stream['audioToken'],
        'generation': 1,
      });
      unawaited(
        opening.then<void>((endpoint) {
          final relay = endpoint['relayId'];
          if (relay is String && relay.isNotEmpty && relay.length <= 256) {
            entry.relay = relay;
            if (!_owns(entry) || entry.closed) unawaited(_closeRelay(entry));
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final endpoint = await _await(entry, opening);
      entry.relay = _text(endpoint, 'relayId');
      final url = _url(endpoint);
      entry.observer = entry.player.events.listen(
        (event) {
          if (!_owns(entry) || entry.closed) return;
          if (event['kind'] == 'diagnostic' && entry.diagnostics.length < 24) {
            entry.diagnostics.add({...event});
          } else if (event['kind'] == 'failed') {
            _fail(
              entry,
              const InteropException('audio_failed', '声音播放器报告媒体输入失败。'),
            );
          }
        },
        onError: (Object _, StackTrace _) {
          _fail(entry, const InteropException('audio_failed', '声音播放器事件连接已中断。'));
        },
      );
      final format = await _await(entry, entry.player.open(url));
      if (format.codec != 'pcm_s16le' ||
          format.sampleRate != 48000 ||
          format.channels != 2) {
        throw const InteropException(
          'audio_format',
          '播放器没有返回所需的 48kHz 双声道 PCM。',
        );
      }
      entry.mediaInfoReady = entry.opened = true;
      await _await(entry, entry.player.volume(entry.volume, entry.muted));
      await _settle(entry, 'startup');
      while (!entry.sourcePcmReceived || !entry.clockAdvanced) {
        _check(entry);
        final relay = await _await(
          entry,
          core('media.status', {'relayId': entry.relay}),
        );
        if (relay['status'] == 'failed' || relay['status'] == 'closed') {
          throw const InteropException(
            'audio_input_closed',
            '声音输入已结束，尚未完成播放确认。',
          );
        }
        final packets = relay['packets'];
        if (packets is int && packets > 0) {
          entry.sourcePcmReceived = true;
          entry.pcmPackets = packets;
        }
        if (entry.appliedState == 'playing') {
          final position = entry.player.positionMs;
          if (position >= 0) {
            entry.clockStart ??= position;
            if (position > entry.clockStart!) {
              entry.clockEnd = position;
              entry.clockAdvanced = true;
            }
          }
        }
        if (!entry.sourcePcmReceived || !entry.clockAdvanced) {
          await _delay(entry);
        }
      }
      // Focus/background may have changed after the first genuine playback.
      // Confirm the latest reasons and return their revision, even if paused.
      await _settle(entry, 'ready');
      _check(entry);
      entry.evidenceReady = true;
      entry.startTimer?.cancel();
      return _receipt(entry);
    } catch (error) {
      final failure = _failure(error, entry);
      if (_owns(entry)) _entries.remove(entry.id);
      _invalidateEmptyFocus();
      await _release(entry);
      await _retireUnused();
      throw failure;
    }
  }

  Future<AudioJson> pause(String id) {
    final entry = _entry(id);
    entry.manualPaused = true;
    return _userApply(entry, 'manual_pause', ++entry.manualRevision);
  }

  Future<AudioJson> resume(String id) async {
    final entry = _entry(id);
    final revision = ++entry.manualRevision;
    entry.manualPaused = false;
    entry.requiresUserResume = false;
    if (_eligible) {
      try {
        await _await(entry, _ensureFocus());
      } catch (_) {
        entry.requiresUserResume = true;
        rethrow;
      }
    }
    if (entry.manualRevision != revision) throw _cancelled();
    return _userApply(entry, 'manual_resume', revision);
  }

  Future<AudioJson> _userApply(
    _AudioOutput entry,
    String reason,
    int manualRevision,
  ) async {
    try {
      await _settle(
        entry,
        reason,
        current: () => entry.manualRevision == manualRevision,
      );
      if (entry.manualRevision != manualRevision) throw _cancelled();
      return _receipt(entry);
    } catch (error) {
      final failure = _failure(error, entry);
      if (failure.code != 'cancelled') _fail(entry, failure);
      throw failure;
    }
  }

  Future<void> _settle(
    _AudioOutput entry,
    String reason, {
    bool Function()? current,
  }) async {
    while (true) {
      _check(entry);
      if (current?.call() == false) throw _cancelled();
      try {
        await _schedule(entry, reason);
        return;
      } on InteropException catch (error) {
        _check(entry);
        if (current?.call() == false) throw _cancelled();
        if (error.code != 'cancelled') rethrow;
      }
    }
  }

  Future<AudioJson> _schedule(_AudioOutput entry, String reason) {
    final revision = ++entry.requestRevision;
    if (++entry.queued > 12) {
      entry.queued--;
      throw const InteropException('resource_busy', '声音状态更新过于频繁，请稍后再试。');
    }
    final operation = entry.control.then((_) async {
      _check(entry);
      if (revision != entry.requestRevision) throw _cancelled();
      if (!entry.opened) return _receipt(entry);
      final focusPaused = _focusSignal != 'granted' || entry.requiresUserResume;
      final backgroundPaused =
          !_visible && !(_backgroundAllowed && _backgroundReady);
      final manualPaused = entry.manualPaused;
      final paused = manualPaused || focusPaused || backgroundPaused;
      await _await(entry, entry.player.setPaused(paused), operationTimeout);
      _check(entry);
      if (revision != entry.requestRevision) throw _cancelled();
      entry
        ..appliedRevision = revision
        ..appliedState = paused ? 'paused' : 'playing'
        ..appliedManual = manualPaused
        ..appliedFocus = focusPaused
        ..appliedBackground = backgroundPaused
        ..reason = reason;
      if (!paused) entry.playingConfirmed = true;
      final receipt = _receipt(entry);
      if (entry.evidenceReady) _emit('audio.presentation', entry, receipt);
      return receipt;
    });
    entry.control = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation.whenComplete(() => entry.queued--);
  }

  Future<AudioJson> volume(
    String id, {
    required double volume,
    required bool muted,
  }) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const InteropException('invalid_argument', '音量必须在 0 到 1 之间。');
    }
    final entry = _entry(id);
    if (++entry.queued > 12) {
      entry.queued--;
      throw const InteropException('resource_busy', '声音状态更新过于频繁，请稍后再试。');
    }
    try {
      await entry.ready;
      _check(entry);
      final operation = entry.control.then((_) async {
        _check(entry);
        await _await(
          entry,
          entry.player.volume(volume, muted),
          operationTimeout,
        );
        entry
          ..volume = volume
          ..muted = muted;
        return {
          ..._receipt(entry),
          'volumeConfigured': true,
          'volumeOutputVerified': false,
        };
      });
      entry.control = operation.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      return await operation;
    } finally {
      entry.queued--;
    }
  }

  AudioJson status([String? id]) {
    _checkOwner();
    if (id != null) return _receipt(_entry(id));
    return {
      'sources': [for (final entry in _entries.values) _receipt(entry)],
      'visible': _visible,
      'backgroundAllowed': _backgroundAllowed,
      'backgroundReady': _backgroundReady,
      'focusEpoch': _epoch,
      'focusSignal': _focusSignal,
    };
  }

  Future<AudioJson> policy(bool backgroundAllowed) async {
    _checkOwner();
    final revision = ++_policyRevision;
    final previous = _backgroundAllowed;
    _backgroundAllowed = backgroundAllowed;
    if (!backgroundAllowed) _backgroundReady = false;
    try {
      await _reconcile('background_pending');
      await _syncBackground();
      _checkOwner();
      if (revision != _policyRevision) throw _cancelled();
    } catch (error) {
      if (revision == _policyRevision) {
        _backgroundAllowed = previous;
        _backgroundReady = false;
        await _reconcile('background_unavailable');
      }
      if (error is InteropException) rethrow;
      throw const InteropException(
        'audio_background_unavailable',
        '系统尚未确认媒体后台运行资格。',
      );
    }
    await _reconcile('background_policy');
    _checkOwner();
    if (revision != _policyRevision) throw _cancelled();
    return {
      'backgroundAllowed': _backgroundAllowed,
      'backgroundReady': _backgroundReady,
    };
  }

  Future<void> setVisible(bool visible) async {
    _checkOwner();
    if (_visible == visible) return;
    _visible = visible;
    await _reconcile('visibility');
  }

  Future<void> handlePlatformEvent(AudioJson event) async {
    if (_disposed || isDisposed()) return;
    final raw = event['data'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : event;
    if (event['type'] == 'audio.platform.visibility' &&
        data['visible'] is bool) {
      await setVisible(data['visible'] as bool);
      return;
    }
    if (event['type'] != 'audio.platform.focus' ||
        data['epoch'] != _epoch ||
        _epoch == null) {
      return;
    }
    final signal = data['signal'];
    if (signal == 'granted' || signal == 'transientLoss') {
      if (_focusSignal == signal) return;
      _focusSignal = signal as String;
      await _reconcile(signal);
    } else if (signal == 'permanentLoss' || signal == 'noisy') {
      final epoch = _epoch!;
      _epoch = null;
      _focusSignal = signal as String;
      _focusGeneration++;
      for (final entry in _entries.values) {
        entry.requiresUserResume = true;
      }
      await _reconcile(signal);
      await _releaseEpoch(epoch);
    }
  }

  bool get _eligible => _visible || (_backgroundAllowed && _backgroundReady);

  Future<void> _ensureFocus() async {
    if (_epoch != null) {
      return; // Transient loss is not permission to steal focus back.
    }
    final pending = _acquiring;
    if (pending != null) return pending;
    final operation = _acquireFocus();
    _acquiring = operation;
    try {
      await operation;
    } finally {
      if (identical(_acquiring, operation)) _acquiring = null;
    }
  }

  Future<void> _acquireFocus() async {
    final generation = _focusGeneration;
    final request = platform('audio.platform.focus.acquire', {});
    var expired = false;
    unawaited(
      request.then<void>((result) {
        final epoch = result['epoch'];
        if (result['granted'] == true &&
            epoch is int &&
            (expired ||
                _disposed ||
                isDisposed() ||
                _entries.isEmpty ||
                generation != _focusGeneration)) {
          unawaited(_releaseEpoch(epoch));
        }
      }, onError: (Object _, StackTrace _) {}),
    );
    final AudioJson result;
    try {
      result = await request.timeout(operationTimeout);
    } on TimeoutException {
      expired = true;
      rethrow;
    }
    final epoch = result['epoch'];
    if (_disposed ||
        isDisposed() ||
        _entries.isEmpty ||
        generation != _focusGeneration) {
      if (result['granted'] == true && epoch is int) await _releaseEpoch(epoch);
      throw _cancelled();
    }
    if (result['granted'] != true ||
        epoch is! int ||
        epoch < 0 ||
        epoch <= _lastEpoch) {
      if (result['granted'] == true && epoch is int && epoch >= 0) {
        await _releaseEpoch(epoch);
      }
      throw const InteropException(
        'audio_focus_denied',
        '系统没有确认新的声音焦点，尚未开始播放。',
      );
    }
    _epoch = epoch;
    _lastEpoch = epoch;
    _focusSignal = 'granted';
  }

  Future<void> _releaseEpoch(int epoch) async {
    if (!_releasedEpochs.add(epoch)) return;
    if (_releasedEpochs.length > 4096) {
      _releasedEpochs.remove(_releasedEpochs.first);
    }
    try {
      await platform('audio.platform.focus.release', {
        'epoch': epoch,
      }).timeout(operationTimeout);
    } catch (_) {
      /* Never acquire a replacement lease while cleaning up an old one. */
    }
  }

  Future<void> _syncBackground() async {
    if (_backgroundSync case final pending?) return pending;
    final operation = _runBackground();
    _backgroundSync = operation;
    try {
      await operation;
    } finally {
      if (identical(_backgroundSync, operation)) _backgroundSync = null;
    }
  }

  Future<void> _runBackground() async {
    while (true) {
      final enabled = !_disposed && _backgroundAllowed && _entries.isNotEmpty;
      if (_backgroundRequested == enabled) return;
      final request = platform('audio.platform.background', {
        'enabled': enabled,
      });
      unawaited(
        request.then<void>((_) {
          if (enabled &&
              (_disposed || !_backgroundAllowed || _entries.isEmpty)) {
            unawaited(
              platform('audio.platform.background', {'enabled': false})
                  .timeout(operationTimeout)
                  .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
            );
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final result = await request.timeout(operationTimeout);
      final ready =
          result['ready'] == true || result['mediaPlaybackReady'] == true;
      if (enabled && !ready) {
        throw const InteropException(
          'audio_background_unavailable',
          '系统尚未确认媒体前台服务，声音不会在后台播放。',
        );
      }
      _backgroundRequested = enabled;
      _backgroundReady = enabled && ready;
    }
  }

  Future<void> _reconcile(String reason) async {
    await Future.wait(
      _entries.values.toList().map((entry) async {
        try {
          await _schedule(entry, reason);
        } catch (error) {
          final failure = _failure(error, entry);
          if (failure.code != 'cancelled') _fail(entry, failure);
        }
      }),
    );
  }

  void _fail(_AudioOutput entry, InteropException failure) {
    if (!_owns(entry) || entry.closed) return;
    entry.failure = failure;
    _entries.remove(entry.id);
    _invalidateEmptyFocus();
    entry.cancel();
    if (!_disposed && !isDisposed()) {
      _emit('audio.output.failed', entry, {
        'sourceId': entry.id,
        'deviceId': entry.device,
        'code': failure.code,
        'reason': failure.message,
        'backend': 'fvp',
      });
    }
    unawaited(_release(entry).then((_) => _retireUnused()));
  }

  Future<AudioJson> stop(String id) async {
    _stopped.add(id);
    if (_stopped.length > 4096) _stopped.remove(_stopped.first);
    final entry = _entries.remove(id);
    _invalidateEmptyFocus();
    entry?.cancel();
    final cleanup = entry == null ? <String, dynamic>{} : await _release(entry);
    await _retireUnused();
    return {'sourceId': id, 'status': 'stopped', 'cleanup': cleanup};
  }

  Future<void> stopDevice(String deviceId) async {
    await Future.wait(
      _entries.values
          .where((entry) => entry.device == deviceId)
          .map((entry) => entry.id)
          .toList()
          .map(stop),
    );
  }

  Future<void> _retireUnused() async {
    if (_entries.isNotEmpty) return;
    final epoch = _epoch;
    _epoch = null;
    _focusSignal = 'none';
    _focusGeneration++;
    if (epoch != null) await _releaseEpoch(epoch);
    try {
      await _syncBackground();
    } catch (_) {
      /* Cleanup does not enable background playback. */
    }
  }

  void _invalidateEmptyFocus() {
    if (_entries.isEmpty) {
      _focusGeneration++;
      _acquiring = null;
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _focusGeneration++;
    await Future.wait(_entries.keys.toList().map(stop));
    await Future.wait(_releases.toList());
    await _retireUnused();
  }

  Future<AudioJson> _release(_AudioOutput entry) {
    if (entry.releasing case final existing?) return existing;
    final future = _releaseOnce(entry);
    entry.releasing = future;
    _releases.add(future);
    unawaited(
      future.then<void>(
        (_) {
          _releases.remove(future);
        },
        onError: (Object _, StackTrace _) {
          _releases.remove(future);
        },
      ),
    );
    return future;
  }

  Future<AudioJson> _releaseOnce(_AudioOutput entry) async {
    entry.cancel();
    await entry.observer?.cancel();
    final closing = _closeRelay(entry);
    AudioJson receipt;
    try {
      receipt = await entry.player.release().timeout(
        const Duration(seconds: 7),
      );
    } catch (_) {
      receipt = {
        'disposeRequested': false,
        'nativeDeleteConfirmed': false,
        'cleanupUnconfirmed': true,
      };
    }
    await closing;
    return receipt;
  }

  Future<void> _closeRelay(_AudioOutput entry) async {
    final relay = entry.relay;
    if (relay == null || !entry.closedRelays.add(relay)) return;
    try {
      await core('media.close', {'relayId': relay}).timeout(operationTimeout);
    } catch (_) {
      /* Core owns retirement; never stop a different remote source. */
    }
  }

  Future<void> _delay(_AudioOutput entry) =>
      _await(entry, Future<void>.delayed(pollInterval));
  Future<T> _await<T>(
    _AudioOutput entry,
    Future<T> work, [
    Duration? timeout,
  ]) async {
    _check(entry);
    final cancelled = Completer<T>();
    final subscription = entry.cancellation.stream.listen((_) {
      if (!cancelled.isCompleted) cancelled.completeError(_abort(entry));
    });
    try {
      final result = await Future.any([work, cancelled.future])
          .timeout(timeout ?? startTimeout);
      _check(entry);
      return result;
    } on TimeoutException catch (error) {
      throw _failure(error, entry);
    } finally {
      await subscription.cancel();
    }
  }

  bool _owns(_AudioOutput entry) => identical(_entries[entry.id], entry);
  void _checkOwner() {
    if (_disposed || isDisposed()) throw _cancelled();
  }

  void _check(_AudioOutput entry) {
    _checkOwner();
    if (entry.failure case final failure?) throw failure;
    if (entry.timedOut) throw _abort(entry);
    if (entry.closed || !_owns(entry) || entry.cancelled?.call() == true) {
      throw _cancelled();
    }
  }

  _AudioOutput _entry(String id) {
    _checkOwner();
    final entry = _entries[id];
    if (entry == null) {
      throw const InteropException('audio_source_required', '声音输出已结束。');
    }
    _check(entry);
    return entry;
  }

  InteropException _abort(_AudioOutput entry) => entry.timedOut
      ? const InteropException('audio_timeout', '尚未取得完整的真实声音播放证据。')
      : _cancelled();
  InteropException _failure(Object error, _AudioOutput entry) =>
      error is InteropException
      ? error
      : InteropException(
          error is TimeoutException ? 'audio_timeout' : 'audio_failed',
          '声音输出尚未完成确认。',
          {'diagnostics': entry.diagnostics},
        );
  void _emit(String type, _AudioOutput entry, AudioJson data) {
    if (!_disposed && !isDisposed()) {
      emit({'type': type, 'deviceId': entry.device, 'data': data});
    }
  }

  AudioJson _receipt(_AudioOutput entry) => {
    'sourceId': entry.id,
    'deviceId': entry.device,
    'relayId': entry.relay,
    'backend': 'fvp',
    'revision': entry.appliedRevision,
    'applied': entry.appliedState != null,
    'playState': entry.appliedState ?? 'starting',
    'manualPaused': entry.appliedManual,
    'focusPaused': entry.appliedFocus,
    'backgroundPaused': entry.appliedBackground,
    'requiresUserResume': entry.requiresUserResume,
    'reason': entry.reason,
    'sampleRate': 48000,
    'channels': 2,
    'mediaInfoReady': entry.mediaInfoReady,
    'playingConfirmed': entry.playingConfirmed,
    'sourcePcmReceived': entry.sourcePcmReceived,
    'sourcePcmPackets': entry.pcmPackets,
    'playbackClockAdvanced': entry.clockAdvanced,
    'clockStartMs': entry.clockStart,
    'clockEndMs': entry.clockEnd,
    'positionMs': entry.opened && !entry.closed
        ? entry.player.positionMs
        : null,
    'volume': entry.volume,
    'muted': entry.muted,
    'focusEpoch': _epoch,
    'focusSignal': _focusSignal,
    'audibleContentVerified': false,
    'speakerSamplesVerified': false,
  };
}

class _AudioOutput {
  _AudioOutput(this.id, this.device, this.player, this.cancelled);
  final String id, device;
  final AudioPlayerPort player;
  final bool Function()? cancelled;
  final cancellation = StreamController<void>.broadcast(sync: true);
  final diagnostics = <AudioJson>[];
  final closedRelays = <String>{};
  Future<AudioJson>? ready, releasing;
  Future<void> control = Future.value();
  StreamSubscription<AudioJson>? observer;
  Timer? startTimer;
  String? relay, appliedState;
  String reason = 'starting';
  InteropException? failure;
  bool closed = false, timedOut = false, opened = false, evidenceReady = false;
  bool mediaInfoReady = false,
      playingConfirmed = false,
      sourcePcmReceived = false,
      clockAdvanced = false;
  bool manualPaused = false, requiresUserResume = false;
  bool appliedManual = false, appliedFocus = true, appliedBackground = true;
  bool muted = false;
  double volume = 1;
  int requestRevision = 0,
      manualRevision = 0,
      appliedRevision = 0,
      queued = 0,
      pcmPackets = 0;
  int? clockStart, clockEnd;
  void cancel() {
    startTimer?.cancel();
    if (closed) return;
    closed = true;
    cancellation.add(null);
    unawaited(cancellation.close());
  }
}

InteropException _cancelled() =>
    const InteropException('cancelled', '此声音操作已结束。');
String _text(AudioJson data, String key) {
  final value = data[key];
  if (value is! String || value.isEmpty || value.length > 256) {
    throw InteropException('invalid_argument', '声音参数无效：$key。');
  }
  return value;
}

void _input(AudioJson stream) {
  final port = stream['audioPort'], token = stream['audioToken'];
  if (port is! int ||
      port < 1 ||
      port > 65535 ||
      token is! String ||
      !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
    throw const InteropException('invalid_endpoint', '声音输入缺少有效的一次性连接信息。');
  }
}

String _url(AudioJson endpoint) {
  final value = endpoint['url'];
  final uri = value is String ? Uri.tryParse(value) : null;
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      !uri.hasPort ||
      uri.port < 1 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !RegExp(r'^/[a-fA-F0-9]{64}$').hasMatch(uri.path) ||
      (endpoint['kind'] != null && endpoint['kind'] != 'audio')) {
    throw const InteropException('invalid_endpoint', '声音输入不是授权的本机媒体流。');
  }
  return value as String;
}
