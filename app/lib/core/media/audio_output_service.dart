import 'dart:async';

import 'package:media_codec/media_codec.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/core/media/audio_platform.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_player.dart';
import 'package:scrcpy_connect/core/media/models/audio_output_event.dart';
import 'package:scrcpy_connect/core/media/remote_audio.dart';

/// 进程或引擎范围内的输出所有者；捕获协调器持有远端捕获，平台持有系统焦点及前台服务资格。
/// PCM 数据包不进入 Dart。
class AudioOutputService {
  AudioOutputService({
    required this.openSource,
    required this.sourceStatus,
    required this.platform,
    required this.emit,
    required this.isDisposed,
    DiagnosticLog? diagnostics,
    AudioPlayerFactory? playerFactory,
    this.startTimeout = const Duration(seconds: 18),
    this.operationTimeout = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 50),
  }) : _diagnostics = DiagnosticReporter(diagnostics),
       _factory = playerFactory ?? AudioPlayer.new;

  final Future<MediaCodecSource> Function(String sourceId, int generation)
  openSource;
  final Future<ScrcpySourceStatus> Function(String sourceId) sourceStatus;
  final AudioPlatform platform;
  static int _nextOwner = 0;
  final String _ownerId =
      'audio-${DateTime.now().microsecondsSinceEpoch}-${_nextOwner++}';
  final void Function(AudioOutputEvent) emit;
  final bool Function() isDisposed;
  final DiagnosticReporter _diagnostics;
  final AudioPlayerFactory _factory;
  final Duration startTimeout, operationTimeout, pollInterval;
  final _entries = <String, _AudioOutput>{};
  final _stopped = <String>{};
  final _retiring = <_AudioOutput>{};
  final _releasedEpochs = <int>{};
  final _pendingEpochReleases = <int>{};
  final _epochReleases = <int, Future<void>>{};
  int? _epoch;
  int _lastEpoch = -1, _focusGeneration = 0, _policyRevision = 0;
  AudioFocusSignal _focusSignal = .none;
  Future<void>? _acquiring, _backgroundSync, _disposing;
  bool _disposed = false, _visible = false;
  bool _backgroundAllowed = false, _backgroundReady = false;
  bool? _backgroundRequested;
  bool _backgroundUsed = false;

  Future<AudioOutputReceipt> start(
    DeviceAudioSnapshot stream, {
    bool Function()? cancelled,
  }) async {
    _checkOwner();
    final id = stream.sourceId, device = stream.deviceId;
    if (id.isEmpty ||
        id.length > 256 ||
        device.isEmpty ||
        device.length > 256) {
      throw const RequestFailure('invalid_argument', '声音身份无效。');
    }
    if (_stopped.contains(id) || cancelled?.call() == true) throw _cancelled();
    if (_entries[id] case final existing?) {
      if (existing.device != device) {
        throw const RequestFailure('source_changed', '声音输出不属于这台设备。');
      }
      await existing.ready;
      _check(existing);
      return _receipt(existing);
    }
    _input(stream);
    if (_retiring.any((entry) => entry.id == id)) {
      throw const RequestFailure(
        'audio_cleanup_unconfirmed',
        '原声音输出尚未确认释放，请先重试停止。',
      );
    }
    if (_entries.length + _retiring.length >= 16) {
      throw const RequestFailure('resource_busy', '声音输出数量已达上限。');
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

  Future<AudioOutputReceipt> _start(
    _AudioOutput entry,
    DeviceAudioSnapshot stream,
  ) async {
    try {
      await _await(entry, _syncBackground());
      while (!_eligible) {
        await _delay(entry);
      }
      await _await(entry, _ensureFocus());
      final opening = openSource(stream.audioSourceId!, 1);
      final endpoint = await _await(entry, opening);
      entry.relay = endpoint.sourceId;
      if (endpoint.codec != 'pcm_s16le' ||
          endpoint.attachAddress <= 0 ||
          endpoint.detachAddress <= 0) {
        throw const RequestFailure('invalid_endpoint', '声音输入不是有效的原生数据源。');
      }
      entry.observer = entry.player.events.listen(
        (event) {
          if (!_owns(entry) || entry.closed) return;
          _diagnostics.playerEvent(DiagnosticArea.audio, entry.id, event);
          if (event.diagnostic && entry.diagnostics.length < 24) {
            entry.diagnostics.add(event);
          } else if (event is MediaPlayerFailed) {
            _fail(
              entry,
              const RequestFailure('audio_failed', '声音播放器报告媒体输入失败。'),
            );
          }
        },
        onError: (Object _, StackTrace _) {
          _fail(entry, const RequestFailure('audio_failed', '声音播放器事件连接已中断。'));
        },
      );
      final format = await _await(entry, entry.player.open(endpoint));
      if (format.codec != 'pcm_s16le' ||
          format.sampleRate != 48000 ||
          format.channels != 2) {
        throw const RequestFailure('audio_format', '播放器没有返回所需的 48kHz 双声道 PCM。');
      }
      entry.mediaInfoReady = entry.opened = true;
      await _await(entry, entry.player.volume(entry.volume, entry.muted));
      await _settle(entry, 'startup');
      while (!entry.sourcePcmReceived ||
          !entry.clockAdvanced ||
          !_nativeOutputReady(entry)) {
        _check(entry);
        final relay = await _await(entry, sourceStatus(entry.relay!));
        if (relay.status == ScrcpySourceState.closed) {
          throw const RequestFailure('audio_input_closed', '声音输入已结束，尚未完成播放确认。');
        }
        final packets = relay.packets;
        if (packets > 0) {
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
        if (!entry.sourcePcmReceived ||
            !entry.clockAdvanced ||
            !_nativeOutputReady(entry)) {
          await _delay(entry);
        }
      }
      // 首次实际播放后焦点或后台资格可能已变化，应核对最新原因并返回其 revision，暂停时也不例外。
      await _settle(entry, 'ready');
      _check(entry);
      entry.evidenceReady = true;
      entry.startTimer?.cancel();
      return _receipt(entry);
    } catch (error) {
      _diagnostics.failure(DiagnosticArea.audio, entry.id, error);
      final failure = _failure(error, entry);
      if (_owns(entry)) _entries.remove(entry.id);
      _invalidateEmptyFocus();
      await _release(entry);
      await _retireUnused();
      throw failure;
    }
  }

  Future<AudioOutputReceipt> pause(String id) {
    final entry = _entry(id);
    entry.manualPaused = true;
    return _userApply(entry, 'manual_pause', ++entry.manualRevision);
  }

  Future<AudioOutputReceipt> resume(String id) async {
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

  Future<AudioOutputReceipt> _userApply(
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
      } on RequestFailure catch (error) {
        _check(entry);
        if (current?.call() == false) throw _cancelled();
        if (error.code != 'cancelled') rethrow;
      }
    }
  }

  Future<AudioOutputReceipt> _schedule(_AudioOutput entry, String reason) {
    final revision = ++entry.requestRevision;
    if (++entry.queued > 12) {
      entry.queued--;
      throw const RequestFailure('resource_busy', '声音状态更新过于频繁，请稍后再试。');
    }
    final operation = entry.control.then((_) async {
      _check(entry);
      if (revision != entry.requestRevision) throw _cancelled();
      if (!entry.opened) return _receipt(entry);
      final focusPaused =
          _focusSignal != AudioFocusSignal.granted || entry.requiresUserResume;
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
      if (entry.evidenceReady) {
        _emit(AudioPresentationChanged(receipt));
      }
      return receipt;
    });
    entry.control = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation.whenComplete(() => entry.queued--);
  }

  Future<AudioOutputReceipt> volume(
    String id, {
    required double volume,
    required bool muted,
  }) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw const RequestFailure('invalid_argument', '音量必须在 0 到 1 之间。');
    }
    final entry = _entry(id);
    if (++entry.queued > 12) {
      entry.queued--;
      throw const RequestFailure('resource_busy', '声音状态更新过于频繁，请稍后再试。');
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
        return _receipt(entry)
            .copyWith(volumeConfigured: true, volumeOutputVerified: false);
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

  Future<void> policy(bool backgroundAllowed) async {
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
      if (error is RequestFailure) rethrow;
      throw const RequestFailure(
        'audio_background_unavailable',
        '系统尚未确认媒体后台运行资格。',
      );
    }
    await _reconcile('background_policy');
    _checkOwner();
    if (revision != _policyRevision) throw _cancelled();
  }

  Future<void> setVisible(bool visible) async {
    _checkOwner();
    if (_visible == visible) return;
    _visible = visible;
    await _reconcile('visibility');
  }

  Future<void> handlePlatformEvent(AudioPlatformEvent event) async {
    if (_disposed || isDisposed()) return;
    if (event case AudioVisibilityChanged(:final visible)) {
      await setVisible(visible);
      return;
    }
    if (event case AudioBackgroundChanged(:final ownerId, :final ready)
        when ownerId == _ownerId) {
      _backgroundReady = _backgroundAllowed && ready;
      await _reconcile('background_service');
      return;
    }
    if (event is! AudioFocusChanged ||
        event.epoch != _epoch ||
        _epoch == null) {
      return;
    }
    final signal = event.signal;
    if (signal == AudioFocusSignal.granted ||
        signal == AudioFocusSignal.transientLoss) {
      if (_focusSignal == signal) return;
      _focusSignal = signal;
      await _reconcile(signal.name);
    } else if (signal == AudioFocusSignal.permanentLoss ||
        signal == AudioFocusSignal.noisy) {
      final epoch = _epoch!;
      _epoch = null;
      _focusSignal = signal;
      _focusGeneration++;
      for (final entry in _entries.values) {
        entry.requiresUserResume = true;
        // 启动尚未取得播放证据也必须保留用户恢复要求；超时清理不能让页面自动重开。
        _emit(
          AudioResumeRequired(
            sourceId: entry.id,
            deviceId: entry.device,
            focusSignal: signal,
          ),
        );
      }
      await _reconcile(signal.name);
      await _releaseEpoch(epoch);
    }
  }

  bool get _eligible => _visible || (_backgroundAllowed && _backgroundReady);

  Future<void> _ensureFocus() async {
    while (true) {
      // 此所有者的重叠请求可能收到相同的原生 epoch。
      await _drainFocusReleases();
      if (_epoch != null) {
        return; // 短暂丢失焦点不能授权主动夺回焦点。
      }
      var operation = _acquiring;
      if (operation == null) {
        operation = _acquireFocus();
        _acquiring = operation;
        final owned = operation;
        void clear() {
          if (identical(_acquiring, owned)) _acquiring = null;
        }

        unawaited(
          operation.then<void>(
            (_) => clear(),
            onError: (Object _, StackTrace _) => clear(),
          ),
        );
      }
      try {
        await operation.timeout(operationTimeout);
      } on RequestFailure catch (error) {
        if (error.code != 'cancelled' ||
            _disposed ||
            isDisposed() ||
            _entries.isEmpty) {
          rethrow;
        }
        // 旧源取消后先等待清理，再为剩余源取得新租约，不能使剩余源一起失败。
      }
      if (_disposed || isDisposed() || _entries.isEmpty) throw _cancelled();
    }
  }

  Future<void> _acquireFocus() async {
    final generation = _focusGeneration;
    // 调用方超时不能将操作从 _acquiring 分离；平台迟到回复仍可能携带需要精确清理的存活租约。
    final result = await platform.acquireFocus(_ownerId);
    final epoch = result.epoch;
    if (_disposed ||
        isDisposed() ||
        _entries.isEmpty ||
        generation != _focusGeneration) {
      if (result.granted && epoch != null) await _releaseEpoch(epoch);
      throw _cancelled();
    }
    if (!result.granted || epoch == null || epoch < 0 || epoch <= _lastEpoch) {
      if (result.granted && epoch != null && epoch >= 0) {
        await _releaseEpoch(epoch);
      }
      throw const RequestFailure('audio_focus_denied', '系统没有确认新的声音焦点，尚未开始播放。');
    }
    _epoch = epoch;
    _lastEpoch = epoch;
    _focusSignal = .granted;
  }

  Future<void> _releaseEpoch(int epoch) async {
    if (_releasedEpochs.contains(epoch)) return;
    _pendingEpochReleases.add(epoch);
    final operation = _epochReleases.putIfAbsent(epoch, () async {
      await platform.releaseFocus(_ownerId, epoch);
      _pendingEpochReleases.remove(epoch);
      _releasedEpochs.add(epoch);
      if (_releasedEpochs.length > 4096) {
        _releasedEpochs.remove(_releasedEpochs.first);
      }
    });
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_epochReleases[epoch], operation)) {
            _epochReleases.remove(epoch);
          }
        },
        onError: (Object _, StackTrace _) {
          // 保留原代次的清理责任，后继申请或关闭只能重试这一原租约。
          if (identical(_epochReleases[epoch], operation)) {
            _epochReleases.remove(epoch);
          }
        },
      ),
    );
    try {
      await operation.timeout(operationTimeout);
    } catch (_) {
      throw const RequestFailure(
        'audio_focus_cleanup_unconfirmed',
        '声音焦点租约尚未确认释放，请重试关闭。',
      );
    }
  }

  Future<void> _drainFocusReleases() async {
    while (_pendingEpochReleases.isNotEmpty) {
      await Future.wait(_pendingEpochReleases.toList().map(_releaseEpoch));
    }
  }

  Future<void> _drainFocus() async {
    if (_acquiring case final acquiring?) {
      try {
        await acquiring.timeout(operationTimeout);
      } catch (_) {
        if (identical(_acquiring, acquiring)) {
          throw const RequestFailure(
            'audio_focus_cleanup_unconfirmed',
            '原声音焦点申请尚未结束，请重试关闭。',
          );
        }
        // 申请已结束；失败或取消不代表其迟到租约已经释放，继续排空原代次。
      }
    }
    await _drainFocusReleases();
  }

  Future<void> _syncBackground() {
    var operation = _backgroundSync;
    if (operation == null) {
      final owned = Future<void>.microtask(_runBackground);
      _backgroundSync = operation = owned;
      void clear() {
        if (identical(_backgroundSync, owned)) _backgroundSync = null;
      }

      unawaited(
        owned.then<void>(
          (_) => clear(),
          onError: (Object _, StackTrace _) => clear(),
        ),
      );
    }
    // 只结束调用方等待；原请求及其迟到禁用仍属于同一所有者。
    return operation.timeout(operationTimeout);
  }

  Future<void> _drainBackground() async {
    if (!_backgroundUsed && _backgroundSync == null) return;
    try {
      if (_backgroundSync case final pending?) {
        try {
          await pending.timeout(operationTimeout);
        } catch (_) {
          if (identical(_backgroundSync, pending)) rethrow;
        }
      }
      await _syncBackground();
    } catch (_) {
      throw const RequestFailure(
        'audio_background_cleanup_unconfirmed',
        '原后台声音请求尚未确认结束，请重试关闭。',
      );
    }
  }

  Future<void> _runBackground() async {
    while (true) {
      final enabled = !_disposed && _backgroundAllowed && _entries.isNotEmpty;
      if (_backgroundRequested == enabled) return;
      _backgroundUsed = true;
      _backgroundRequested = null;
      final result = await platform.setBackground(_ownerId, enabled);
      final ready = result.ready;
      _backgroundRequested = enabled;
      _backgroundReady = enabled && ready;
      // 明确的宿主能力限制仍允许前台播放；支持的服务若就绪失败，则不能准入。
      if (enabled &&
          !ready &&
          result.supported &&
          !_disposed &&
          _backgroundAllowed &&
          _entries.isNotEmpty) {
        throw const RequestFailure(
          'audio_background_unavailable',
          '系统尚未确认媒体前台服务，声音不会在后台播放。',
        );
      }
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

  void _fail(_AudioOutput entry, RequestFailure failure) {
    if (!_owns(entry) || entry.closed) return;
    entry.failure = failure;
    _entries.remove(entry.id);
    _invalidateEmptyFocus();
    entry.cancel();
    if (!_disposed && !isDisposed()) {
      _emit(
        AudioOutputFailed(
          sourceId: entry.id,
          deviceId: entry.device,
          code: failure.code,
          reason: failure.message,
        ),
      );
    }
    unawaited(
      _release(entry)
          .then((_) => _retireUnused())
          .catchError((Object error, StackTrace stack) {
            _diagnostics.failure(DiagnosticArea.audio, entry.id, error);
          }),
    );
  }

  Future<MediaOutputStop> stop(String id) async {
    _stopped.add(id);
    if (_stopped.length > 4096) _stopped.remove(_stopped.first);
    final entry =
        _entries.remove(id) ??
        _retiring.where((entry) => entry.id == id).firstOrNull;
    _invalidateEmptyFocus();
    entry?.cancel();
    final cleanup = entry == null ? null : await _release(entry);
    await _retireUnused();
    return MediaOutputStop(id, [?cleanup]);
  }

  Future<void> stopDevice(String deviceId) async {
    await Future.wait(
      {..._entries.values, ..._retiring}
          .where((entry) => entry.device == deviceId)
          .map((entry) => entry.id)
          .toList()
          .map(stop),
    );
    _checkReleased(deviceId);
  }

  Future<void> _retireUnused() async {
    if (_entries.isNotEmpty) return;
    final epoch = _epoch;
    _epoch = null;
    _focusSignal = .none;
    _focusGeneration++;
    if (epoch != null) await _releaseEpoch(epoch);
    await _drainFocus();
    await _drainBackground();
  }

  void _invalidateEmptyFocus() {
    if (_entries.isEmpty) {
      _focusGeneration++;
    }
  }

  Future<void> dispose() =>
      _disposing ??= _dispose().catchError((Object error, StackTrace stack) {
        _disposing = null;
        Error.throwWithStackTrace(error, stack);
      });
  Future<void> _dispose() async {
    _disposed = true;
    _focusGeneration++;
    await Future.wait([
      for (final id in {
        ..._entries.keys,
        for (final entry in _retiring) entry.id,
      })
        Future<void>.sync(() async {
          await stop(id);
        }),
      Future<void>.sync(_retireUnused),
      Future<void>.sync(_drainFocus),
      Future<void>.sync(_drainBackground),
    ]);
    _checkReleased();
  }

  void _checkReleased([String? device]) {
    if (_retiring.any((entry) => device == null || entry.device == device)) {
      throw const RequestFailure(
        'audio_cleanup_unconfirmed',
        '声音输出尚未确认释放，请重试关闭。',
      );
    }
  }

  Future<MediaOutputRelease> _release(_AudioOutput entry) {
    // 同步保存具体输出并撤销准入；等待超时不等于实际清理操作结束。
    _retiring.add(entry);
    if (_owns(entry)) _entries.remove(entry.id);
    _invalidateEmptyFocus();
    entry.cancel();
    var operation = entry.releasing;
    if (operation == null) {
      operation = Future<MediaOutputRelease>.microtask(
        () => _releaseOnce(entry),
      );
      entry.releasing = operation;
      final owned = operation;
      unawaited(
        owned.then<void>(
          (receipt) {
            if (receipt.confirmed) _retiring.remove(entry);
            if (identical(entry.releasing, owned)) entry.releasing = null;
          },
          onError: (Object _, StackTrace _) {
            if (identical(entry.releasing, owned)) entry.releasing = null;
          },
        ),
      );
    }
    return operation.timeout(operationTimeout, onTimeout: _unknownCleanup);
  }

  Future<MediaOutputRelease> _releaseOnce(_AudioOutput entry) async {
    var observerConfirmed = true;
    MediaOutputRelease receipt = entry.playerRelease ?? _unknownCleanup();
    await Future.wait<void>([
      () async {
        final observer = entry.observer;
        if (observer == null) return;
        try {
          await observer.cancel();
          entry.observer = null;
        } catch (_) {
          observerConfirmed = false;
        }
      }(),
      () async {
        // 观察清理失败仍须释放播放器；后续重试不能再次删除已经确认释放的输出。
        if (entry.playerRelease != null) return;
        try {
          receipt = await entry.player.release();
          if (receipt.confirmed) entry.playerRelease = receipt;
        } catch (_) {
          receipt = _unknownCleanup();
        }
      }(),
    ]);
    if (!observerConfirmed || !receipt.confirmed) {
      receipt = receipt.markUnconfirmed();
    }
    _diagnostics.release(DiagnosticArea.audio, entry.id, receipt);
    return receipt;
  }

  static MediaOutputRelease _unknownCleanup() =>
      const MediaOutputRelease.unknown();

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
      throw const RequestFailure('audio_source_required', '声音输出已结束。');
    }
    _check(entry);
    return entry;
  }

  RequestFailure _abort(_AudioOutput entry) => entry.timedOut
      ? const RequestFailure('audio_timeout', '尚未取得完整的真实声音播放证据。')
      : _cancelled();
  RequestFailure _failure(Object error, _AudioOutput entry) =>
      error is RequestFailure
      ? error
      : RequestFailure(
          error is TimeoutException ? 'audio_timeout' : 'audio_failed',
          '声音输出尚未完成确认。',
          {
            'diagnostics': [
              for (final event in entry.diagnostics) event.toDiagnosticFields(),
            ],
          },
        );
  void _emit(AudioOutputEvent event) {
    if (!_disposed && !isDisposed()) {
      emit(event);
    }
  }

  bool _nativeOutputReady(_AudioOutput entry) {
    final status = entry.player.outputStatus;
    return status.nativeReady && status.bytesWritten > 0;
  }

  AudioOutputReceipt _receipt(_AudioOutput entry) => AudioOutputReceipt(
    sourceId: entry.id,
    deviceId: entry.device,
    relayId: entry.relay,
    backend: 'media_codec',
    nativeReady: entry.player.outputStatus.nativeReady,
    bytesWritten: entry.player.outputStatus.bytesWritten,
    revision: entry.appliedRevision,
    applied: entry.appliedState != null,
    playState: AudioPlayState.values.byName(entry.appliedState ?? 'starting'),
    manualPaused: entry.appliedManual,
    focusPaused: entry.appliedFocus,
    backgroundPaused: entry.appliedBackground,
    requiresUserResume: entry.requiresUserResume,
    reason: entry.reason,
    sampleRate: 48000,
    channels: 2,
    mediaInfoReady: entry.mediaInfoReady,
    playingConfirmed: entry.playingConfirmed,
    sourcePcmReceived: entry.sourcePcmReceived,
    sourcePcmPackets: entry.pcmPackets,
    playbackClockAdvanced: entry.clockAdvanced,
    clockStartMs: entry.clockStart,
    clockEndMs: entry.clockEnd,
    positionMs: entry.opened && !entry.closed ? entry.player.positionMs : null,
    volume: entry.volume,
    muted: entry.muted,
    focusEpoch: _epoch,
    focusSignal: _focusSignal,
    audibleContentVerified: false,
    speakerSamplesVerified: false,
  );
}

class _AudioOutput {
  _AudioOutput(this.id, this.device, this.player, this.cancelled);
  final String id, device;
  final AudioPlayer player;
  final bool Function()? cancelled;
  final cancellation = StreamController<void>.broadcast(sync: true);
  final diagnostics = <MediaPlayerEvent>[];
  Future<AudioOutputReceipt>? ready;
  Future<MediaOutputRelease>? releasing;
  MediaOutputRelease? playerRelease;
  Future<void> control = Future.value();
  StreamSubscription<MediaPlayerEvent>? observer;
  Timer? startTimer;
  String? relay, appliedState;
  String reason = 'starting';
  RequestFailure? failure;
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

RequestFailure _cancelled() => const RequestFailure('cancelled', '此声音操作已结束。');
void _input(DeviceAudioSnapshot stream) {
  final source = stream.audioSourceId;
  if (source is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(source)) {
    throw const RequestFailure('invalid_endpoint', '缺少有效的原生声音源。');
  }
}
