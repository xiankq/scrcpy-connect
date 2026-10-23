import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:device_protocol/device_protocol.dart';
import 'package:runtime_diagnostics/runtime_diagnostics.dart';
import 'package:scrcpy_client/scrcpy_client.dart';

export 'package:scrcpy_client/scrcpy_client.dart';

/// Owns local video output only. Core remains the owner of the control session,
/// encoder process, input coordinates and session.ready/session.stop decisions.
class PortableVideoOutputs {
  PortableVideoOutputs({
    required this.core,
    required this.emit,
    required this.isDisposed,
    DiagnosticLog? diagnostics,
    VideoPlayerFactory? playerFactory,
    this.startTimeout = const Duration(seconds: 18),
    this.operationTimeout = const Duration(seconds: 6),
  }) : _diagnostics = DiagnosticReporter(diagnostics),
       _factory = playerFactory ?? CodecVideoPlayer.new;

  final VideoCoreRequest core;
  final void Function(VideoJson) emit;
  final bool Function() isDisposed;
  final DiagnosticReporter _diagnostics;
  final VideoPlayerFactory _factory;
  final Duration startTimeout, operationTimeout;
  final _entries = <String, _Output>{}, _pending = <String, _Output>{};
  final _stopped = <String>{}, _verifiedCodecs = <String>{};
  final _releases = <Future<VideoJson>>{};
  bool _disposed = false;
  Future<void>? _disposing;

  Future<VideoJson> start(
    VideoJson stream, {
    bool Function()? cancelled,
  }) async {
    final id = _text(stream, 'sessionId');
    final device = _text(stream, 'deviceId');
    _checkOwner();
    if (_stopped.contains(id) || cancelled?.call() == true) throw _cancelled();
    final existing = _entries[id];
    if (existing != null) {
      if (existing.device != device || existing.codec != _codec(stream)) {
        throw const InteropException('session_changed', '视频输出与现有会话不一致。');
      }
      final receipt = await existing.ready!;
      _check(existing);
      return {...receipt};
    }
    if (_entries.length + _pending.length >= 16) {
      throw const InteropException('resource_busy', '视频输出数量已达上限。');
    }
    final entry = _Output(
      id,
      device,
      _codec(stream),
      _generation(stream),
      _factory(),
      cancelled,
      captureGeneration: stream['captureGeneration'] as int? ?? 1,
    );
    _entries[id] = entry;
    _armStartup(entry);
    entry.ready = _start(entry, stream);
    return entry.ready!;
  }

  Future<VideoJson> _start(_Output entry, VideoJson stream) async {
    try {
      final source = _sourceId(stream);
      // A timeout cannot cancel a core Future. The late callback still closes
      // exactly the relay it created, never a replacement entry's relay.
      final opening = core('media.open', {
        'kind': 'video',
        'sourceId': source,
        'codec': entry.codec,
        'generation': entry.generation,
      });
      unawaited(
        opening.then<void>((endpoint) {
          final relay = endpoint['relayId'];
          if (relay is String && relay.isNotEmpty && relay.length <= 256) {
            entry.relay = relay;
            if (!_owns(entry) || entry.closed) {
              unawaited(_closeEntryRelay(entry, relay));
            }
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final endpoint = await _await(entry, opening);
      entry.relay = _text(endpoint, 'relayId');
      final receipt = await _prepare(entry, endpoint);
      emit({
        'type': 'session.output.ready',
        'deviceId': entry.device,
        'data': receipt,
      });
      return receipt;
    } catch (error) {
      _diagnostics.failure(DiagnosticArea.video, entry.id, error);
      if (identical(_entries[entry.id], entry)) _entries.remove(entry.id);
      await _release(entry);
      throw _failure(error, entry);
    }
  }

  Future<VideoJson> _prepare(_Output entry, VideoJson endpoint) async {
    _check(entry);
    entry.startupTimingMs['relayOpenedMs'] =
        entry.startupClock.elapsedMilliseconds;
    if ((endpoint['kind'] != null && endpoint['kind'] != 'video') ||
        (endpoint['codec'] != null && endpoint['codec'] != entry.codec)) {
      throw const InteropException('invalid_endpoint', '媒体输入类型或实际编码与视频输出不一致。');
    }
    _validateSource(endpoint);
    entry.observer = entry.player.events.listen((event) {
      if (!_owns(entry) || entry.closed || _disposed || isDisposed()) return;
      _diagnostics.playerEvent(
        DiagnosticArea.video,
        entry.id,
        event,
        generation: entry.generation,
      );
      if (entry.diagnostics.length < 24 && event['kind'] == 'diagnostic') {
        entry.diagnostics.add({...event});
      }
      if (event['kind'] == 'metadata' &&
          event['category'] == 'video.dimensions') {
        _dimensions(entry, event);
      }
      if (event['category'] == 'decoder.video') {
        entry.decoder = {
          ...entry.decoder,
          'decoderName': event['decoderName'],
          'hardwareAccelerated': event['hardwareAccelerated'],
          'hardwareVerification': event['hardwareVerification'],
          'backendHardwareFrames': event['backendHardwareFrames'],
        };
      }
      if (event['category'] == 'video.presentation' &&
          event['generation'] == entry.generation &&
          event['textureId'] == entry.texture?.id) {
        entry.decoder = {
          ...entry.decoder,
          'platformTexturePrepared': event['platformTexturePrepared'] == true,
          'presentedSequence': event['presentedSequence'],
          'presentationPath': event['presentationPath'],
        };
        if (identical(_entries[entry.id], entry) &&
            !_pending.containsKey(entry.id)) {
          emit({
            'type': 'session.frame',
            'deviceId': entry.device,
            'data': {..._receipt(entry), 'metadataOnly': true},
          });
        }
      }
      final elapsed = event['elapsedMs'];
      if (event['kind'] == 'diagnostic' &&
          const {
            'video.prepare',
            'video.texture',
          }.contains(event['category']) &&
          elapsed is int) {
        entry.startupTimingMs[event['category'] as String] = elapsed;
      }
      if (event['kind'] == 'failed' && entry.texture != null) {
        emit({
          'type': 'session.output.failed',
          'deviceId': entry.device,
          'data': {
            'sessionId': entry.id,
            'generation': entry.generation,
            'reason': event['reason'] ?? '视频输入已结束。',
            'backend': 'media_codec',
          },
        });
      }
    });
    final opening = entry.player.open(endpoint);
    // Native creation may detach its input before its MethodChannel failure
    // reaches Dart. Keep that late creation failure even if core teardown wins
    // the pending await; a generic cancellation is not its diagnosis.
    unawaited(
      opening.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          if (entry.closed &&
              error is PlatformException &&
              error.code == 'media_codec_create') {
            _diagnostics.failure(
              DiagnosticArea.video,
              entry.id,
              _failure(error, entry),
              stage: 'video_open',
            );
          }
        },
      ),
    );
    final texture = await _await(entry, opening);
    entry.startupTimingMs['openedMs'] = entry.startupClock.elapsedMilliseconds;
    _check(entry);
    if (texture.id < 0 ||
        texture.width < 1 ||
        texture.height < 1 ||
        texture.width > 16384 ||
        texture.height > 16384) {
      throw const InteropException('decoder_error', '播放器返回无效的视频尺寸或纹理。');
    }
    entry.texture = texture;
    await _await(entry, entry.player.setPaused(false));
    entry.startupTimingMs['playingMs'] = entry.startupClock.elapsedMilliseconds;
    await _verifyFrame(entry);
    entry.startupTimingMs['verifiedFrameMs'] =
        entry.startupClock.elapsedMilliseconds;
    _check(entry);
    _verifiedCodecs.add(entry.codec);
    entry.startTimer?.cancel();
    return _receipt(entry);
  }

  void _dimensions(_Output entry, VideoJson event) {
    final texture = entry.texture;
    final width = event['width'], height = event['height'];
    final frames = event['frameCount'];
    if (texture == null ||
        event['generation'] != entry.generation ||
        event['textureId'] != texture.id ||
        width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        frames is! int ||
        frames <= entry.frameCount) {
      return;
    }
    entry.frameCount = frames;
    if (width == texture.width && height == texture.height) return;
    entry.texture = VideoTexture(texture.id, width, height);
    // Candidates and the previous generation during handover cannot publish
    // presentation state. Their eventual committed receipt carries the size.
    if (!identical(_entries[entry.id], entry) ||
        _pending.containsKey(entry.id) ||
        entry.decodedReceipts == 0) {
      return;
    }
    emit({
      'type': 'session.frame',
      'deviceId': entry.device,
      'data': {
        ..._receipt(entry),
        'metadataOnly': true,
        'evidence': 'media_codec.decodedFrame',
      },
    });
  }

  /// Consume the replacement capture's one-use input while retaining the
  /// existing logical output and its last verified texture until handover.
  Future<VideoJson> reconfigure(VideoJson stream) async {
    final id = _text(stream, 'sessionId');
    final old = _entry(id);
    _check(old);
    if (_text(stream, 'deviceId') != old.device) {
      throw const InteropException('session_changed', '新视频输入不属于当前设备。');
    }
    final generation = math.max(_generation(stream), old.generation + 1);
    final captureGeneration =
        stream['captureGeneration'] as int? ?? old.captureGeneration + 1;
    if (captureGeneration <= old.captureGeneration) {
      throw const InteropException('generation_changed', '新视频输入归属已经过期。');
    }
    final source = _sourceId(stream);
    final opening = core('media.open', {
      'kind': 'video',
      'sourceId': source,
      'codec': _codec(stream),
      'generation': generation,
    });
    var accepted = false;
    var abandoned = false;
    unawaited(
      opening.then<void>((endpoint) {
        if (!accepted &&
            (abandoned ||
                !_owns(old) ||
                old.closed ||
                _disposed ||
                isDisposed())) {
          final relay = endpoint['relayId'];
          if (relay is String) {
            unawaited(
              core('media.close', {
                'relayId': relay,
              }).catchError((Object _) => <String, dynamic>{}),
            );
          }
        }
      }, onError: (Object _, StackTrace _) {}),
    );
    VideoJson? endpoint;
    try {
      endpoint = await opening.timeout(operationTimeout);
      _check(old);
      accepted = true;
      return await reattach(
        id,
        endpoint: endpoint,
        codec: _codec(stream),
        captureGeneration: captureGeneration,
      );
    } catch (_) {
      abandoned = true;
      final relay = endpoint?['relayId'];
      if (relay is String) {
        try {
          await core('media.close', {'relayId': relay});
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Attach a new core-owned generation without launching or stopping an app.
  /// The previous texture survives candidate failure and is released only after
  /// the candidate produces a verified decoded image.
  Future<VideoJson> reattach(
    String id, {
    required VideoJson endpoint,
    String? codec,
    int? captureGeneration,
  }) async {
    final old = _entry(id);
    _check(old);
    final generation = _generation(endpoint);
    if (generation <= old.generation || _pending.containsKey(id)) {
      throw const InteropException(
        'generation_changed',
        '请等待当前重配置，或提供更新的画面版本。',
      );
    }
    final actualCodec = endpoint['codec'];
    if (actualCodec != null && actualCodec is! String) {
      throw const InteropException('invalid_codec', '媒体输入没有有效的实际视频编码。');
    }
    final nextCodec = codec ?? (actualCodec as String?) ?? old.codec;
    _validateCodec(nextCodec);
    final candidate = _Output(
      id,
      old.device,
      nextCodec,
      generation,
      _factory(),
      old.cancelled,
      playback: old.playback,
      captureGeneration: captureGeneration ?? old.captureGeneration,
    );
    candidate.relay = _text(endpoint, 'relayId');
    candidate.ownsRelay = candidate.relay != old.relay;
    _pending[id] = candidate;
    _armStartup(candidate);
    try {
      await _prepare(candidate, endpoint);
      _check(candidate);
      if (!identical(_entries[id], old)) throw _cancelled();
      // Presentation belongs to the logical session. A resume may still be
      // awaiting the retired player's state callback or snapshot at this point.
      var appliedPaused = false;
      while (appliedPaused != candidate.playback.paused) {
        appliedPaused = candidate.playback.paused;
        await _await(candidate, _setPaused(candidate, appliedPaused));
      }
      _check(candidate);
      _pending.remove(id);
      _entries[id] = candidate;
      if (candidate.relay == old.relay) {
        old.ownsRelay = false;
        candidate.ownsRelay = true;
      }
      final receipt = _receipt(candidate);
      candidate.ready = Future.value(receipt);
      emit({
        'type': 'session.output.changed',
        'deviceId': old.device,
        'data': receipt,
      });
      await _release(old);
      _check(candidate);
      return receipt;
    } catch (error) {
      if (identical(_pending[id], candidate)) _pending.remove(id);
      await _release(candidate);
      throw _failure(error, candidate);
    }
  }

  Future<VideoJson> pause(String id) => _presentation(id, true);
  Future<VideoJson> resume(String id) => _presentation(id, false);
  Future<VideoJson> _presentation(String id, bool paused) {
    final playback = _entry(id).playback;
    if (++playback.queuedControls > 8) {
      playback.queuedControls--;
      throw const InteropException('renderer_busy', '视频状态操作过于频繁，请稍后再试。');
    }
    final operation = playback.control.then((_) async {
      playback.paused = paused;
      // Generation replacement must remain independent of a blocked old player.
      // Follow only replacements of this session, never a stop/re-created owner.
      for (var attempt = 0; attempt < 8; attempt++) {
        final entry = _entry(id);
        if (!identical(entry.playback, playback)) throw _cancelled();
        try {
          return await _applyPresentation(entry, paused);
        } catch (_) {
          final current = _entries[id];
          if (current == null ||
              identical(current, entry) ||
              !identical(current.playback, playback)) {
            rethrow;
          }
        }
      }
      throw const InteropException('renderer_busy', '画面正在连续调整，请稍后重试。');
    });
    playback.control = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation.whenComplete(() => playback.queuedControls--);
  }

  Future<VideoJson> _applyPresentation(_Output entry, bool paused) async {
    _check(entry);
    // A previous request may have timed out before its state callback. Ask
    // the player to confirm even an apparently unchanged requested state.
    await _await(entry, _setPaused(entry, paused), operationTimeout);
    _check(entry);
    if (!paused) await _verifyFrame(entry);
    _check(entry);
    return {..._receipt(entry), 'paused': paused, 'applied': true};
  }

  Future<void> _setPaused(_Output entry, bool paused) =>
      entry.player.setPaused(paused);

  Future<void> _verifyFrame(_Output entry) async {
    // open() confirms decoding and gives Flutter the texture it needs to mount.
    // Lazy import cannot be awaited here: the raster consumer does not exist
    // before this receipt. Its later success/failure is separate evidence.
    // Snapshot readback remains an explicit screenshot operation.
    _check(entry);
    entry.decodedReceipts++;
  }

  Future<VideoPixels?> _pixels(_Output entry, int width, int height) async {
    _check(entry);
    if (entry.snapshotBusy) {
      throw const InteropException('renderer_busy', '正在读取当前画面，请稍后再试。');
    }
    entry.snapshotBusy = true;
    final pending = Future<VideoPixels?>.sync(
      () => entry.player.snapshot(width: width, height: height),
    );
    // A timed-out readback still owns native resources. Timing out does not
    // cancel its native callback; never issue a second request into that slot.
    unawaited(
      pending.then<void>(
        (_) {
          entry.snapshotBusy = false;
        },
        onError: (Object _, StackTrace _) {
          entry.snapshotBusy = false;
        },
      ),
    );
    final pixels = await _await(entry, pending, operationTimeout);
    if (pixels?.valid == true) entry.snapshotReceipts++;
    return pixels;
  }

  /// Caller supplies an app-owned directory. A fresh subdirectory avoids
  /// replacing existing user files; the result states any resolution reduction.
  Future<VideoJson> screenshot(String id, {required String directory}) async {
    final entry = _entry(id);
    _check(entry);
    final size = entry.texture;
    if (size == null || entry.decodedReceipts == 0) {
      throw const InteropException('no_frame', '当前没有可保存的画面。');
    }
    final root = Directory(directory);
    if (!root.isAbsolute || !await root.exists()) {
      throw const InteropException('invalid_path', '截图目录尚未准备好。');
    }
    _check(entry);
    final factor = math.min(
      1.0,
      math.min(
        4096 / math.max(size.width, size.height),
        math.sqrt(8 * 1024 * 1024 / (size.width * size.height)),
      ),
    );
    final width = math.max(1, (size.width * factor).floor()),
        height = math.max(1, (size.height * factor).floor());
    final pixels = await _pixels(entry, width, height);
    if (pixels == null || !pixels.valid) {
      throw const InteropException('capture_failed', '未能读取实际视频帧。');
    }
    final png = await _await(entry, _png(pixels), operationTimeout);
    _check(entry);
    Directory? owned;
    try {
      owned = await root.createTemp('capture-');
      _check(entry);
      final file = File('${owned.path}${Platform.pathSeparator}frame.png');
      await _await(
        entry,
        file.writeAsBytes(png, flush: true),
        operationTimeout,
      );
      _check(entry);
      return {
        'status': 'completed',
        'sessionId': id,
        'generation': entry.generation,
        'localPath': file.path,
        'mime': 'image/png',
        'width': width,
        'height': height,
        'scaled': factor < 1,
        'evidence': 'media_codec.snapshot',
      };
    } catch (_) {
      if (owned != null) await owned.delete(recursive: true);
      rethrow;
    }
  }

  VideoJson capabilities() => {
    'backend': 'media_codec',
    'probe': 'runtimeDecodeRequired',
    'codecs': [
      for (final codec in const ['h264', 'h265', 'av1', 'vp8', 'vp9'])
        {
          'id': codec,
          'available': _verifiedCodecs.contains(codec) ? true : null,
          'status': _verifiedCodecs.contains(codec) ? 'available' : 'unknown',
          'canAttempt': true,
          'reason': _verifiedCodecs.contains(codec)
              ? '本进程已取得该编码的实际解码帧。'
              : '需打开实际视频流后确认本机解码能力。',
        },
    ],
    'frameEvidence': 'decodedFrameAndPlatformTexture',
    'continuousFrameTelemetry': false,
  };

  Future<VideoJson> stop(String id, {InteropException? failure}) async {
    _stopped.add(id);
    if (_stopped.length > 4096) _stopped.remove(_stopped.first);
    final entries = [
      _entries.remove(id),
      _pending.remove(id),
    ].whereType<_Output>().toList();
    for (final entry in entries) {
      entry.terminalFailure ??= failure;
      entry.cancel();
    }
    final cleanup = await Future.wait(entries.map(_release));
    return {'sessionId': id, 'status': 'stopped', 'outputs': cleanup};
  }

  Future<void> stopDevice(String deviceId) async {
    final ids = {..._entries.values, ..._pending.values}
        .where((entry) => entry.device == deviceId)
        .map((entry) => entry.id)
        .toSet();
    await Future.wait(ids.map(stop));
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    await Future.wait({..._entries.keys, ..._pending.keys}.map(stop));
    await Future.wait(_releases.toList());
  }

  Future<VideoJson> _release(_Output entry) {
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

  Future<VideoJson> _releaseOnce(_Output entry) async {
    entry.cancel();
    await entry.observer?.cancel();
    final closing = entry.relay == null || !entry.ownsRelay
        ? Future<void>.value()
        : _closeEntryRelay(entry, entry.relay!);
    VideoJson released;
    try {
      released = await entry.player.release().timeout(
        const Duration(seconds: 6),
      );
    } catch (_) {
      released = {
        'disposeRequested': true,
        'nativeDeleteConfirmed': false,
        'cleanupUnconfirmed': true,
      };
    }
    _diagnostics.release(DiagnosticArea.video, entry.id, released);
    await closing;
    return released;
  }

  Future<void> _closeEntryRelay(_Output entry, String relay) async {
    if (!entry.closedRelays.add(relay)) return;
    await _closeRelay(relay);
  }

  Future<void> _closeRelay(String relay) async {
    try {
      await core('media.close', {
        'relayId': relay,
      }).timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Core owns bounded relay retirement; do not reopen or stop another session. */
    }
  }

  Future<T> _await<T>(
    _Output entry,
    Future<T> future, [
    Duration? timeout,
  ]) async {
    _check(entry);
    final interruption = Completer<T>();
    final observer = entry.cancellation.stream.listen((_) {
      if (!interruption.isCompleted) {
        interruption.completeError(_aborted(entry));
      }
    });
    try {
      final value = await Future.any<T>([future, interruption.future])
          .timeout(timeout ?? startTimeout);
      _check(entry);
      return value;
    } on TimeoutException catch (error) {
      throw _failure(error, entry);
    } finally {
      await observer.cancel();
    }
  }

  bool _owns(_Output entry) =>
      identical(_entries[entry.id], entry) ||
      identical(_pending[entry.id], entry);
  void _checkOwner() {
    if (_disposed || isDisposed()) throw _cancelled();
  }

  void _check(_Output entry) {
    _checkOwner();
    if (entry.terminalFailure case final failure?) throw failure;
    if (entry.timedOut) throw _aborted(entry);
    if (entry.closed || !_owns(entry) || entry.cancelled?.call() == true) {
      throw _cancelled();
    }
  }

  void _armStartup(_Output entry) {
    entry.startTimer = Timer(startTimeout, () {
      entry.timedOut = true;
      entry.cancel();
    });
  }

  InteropException _aborted(_Output entry) =>
      entry.terminalFailure ??
      (entry.timedOut
          ? InteropException('video_timeout', '视频准备超过时限，已有画面保持不变。', {
              'diagnostics': entry.diagnostics,
            })
          : _cancelled());
  InteropException _failure(Object error, _Output entry) =>
      error is InteropException
      ? error
      : error is PlatformException &&
            const {
              'media_codec_create',
              'media_codec_handle',
              'media_codec_operation',
            }.contains(error.code)
      ? InteropException(error.code, '本机视频输出未能初始化或完成操作。')
      : InteropException(
          error is TimeoutException ? 'video_timeout' : 'decoder_error',
          error is TimeoutException ? '视频输出未在时限内确认。' : '视频输出未能完成，请检查实际媒体输入。',
          {'diagnostics': entry.diagnostics},
        );

  _Output _entry(String id) {
    _checkOwner();
    return _entries[id] ??
        (throw const InteropException('session_required', '该视频输出已结束。'));
  }

  VideoJson _receipt(_Output entry) => {
    ...entry.decoder,
    'sessionId': entry.id,
    'deviceId': entry.device,
    'relayId': entry.relay,
    'textureId': entry.texture!.id,
    'decodedWidth': entry.texture!.width,
    'decodedHeight': entry.texture!.height,
    'codec': entry.codec,
    'generation': entry.generation,
    'captureGeneration': entry.captureGeneration,
    'paused': entry.playback.paused,
    if (entry.frameCount > 0) 'frameCount': entry.frameCount,
    'backend': 'media_codec',
    'firstFrameDecoded': true,
    'evidence': 'media_codec.decodedFrame',
    'decodedReceipts': entry.decodedReceipts,
    'snapshotReceipts': entry.snapshotReceipts,
    'presentedToWidget': false,
    'continuousFrameTelemetry': false,
    'outputStartupTimingMs': {...entry.startupTimingMs},
  };
}

class _Output {
  _Output(
    this.id,
    this.device,
    this.codec,
    this.generation,
    this.player,
    this.cancelled, {
    _Playback? playback,
    this.captureGeneration = 1,
  }) : playback = playback ?? _Playback();
  final String id, device, codec;
  final int generation, captureGeneration;
  final VideoPlayerPort player;
  final bool Function()? cancelled;
  final _Playback playback;
  final cancellation = StreamController<void>.broadcast(sync: true);
  final diagnostics = <VideoJson>[];
  VideoJson decoder = const {};
  final startupClock = Stopwatch()..start();
  final startupTimingMs = <String, int>{};
  final closedRelays = <String>{};
  Future<VideoJson>? ready, releasing;
  String? relay;
  StreamSubscription<VideoJson>? observer;
  VideoTexture? texture;
  InteropException? terminalFailure;
  bool closed = false, snapshotBusy = false;
  bool ownsRelay = true;
  bool timedOut = false;
  Timer? startTimer;
  int snapshotReceipts = 0, decodedReceipts = 0, frameCount = 0;
  void cancel() {
    startTimer?.cancel();
    if (closed) return;
    closed = true;
    cancellation.add(null);
    unawaited(cancellation.close());
  }
}

class _Playback {
  bool paused = false;
  int queuedControls = 0;
  Future<void> control = Future.value();
}

InteropException _cancelled() =>
    const InteropException('cancelled', '此视频操作已结束，不会恢复旧画面。');
String _text(VideoJson data, String key) {
  final value = data[key];
  if (value is! String || value.isEmpty || value.length > 256) {
    throw InteropException('invalid_endpoint', '缺少有效媒体参数：$key。');
  }
  return value;
}

String _codec(VideoJson stream) {
  final codec = _text(stream, 'codec');
  _validateCodec(codec);
  return codec;
}

void _validateCodec(String codec) {
  if (!const ['h264', 'h265', 'av1', 'vp8', 'vp9'].contains(codec)) {
    throw const InteropException('invalid_codec', '未知视频编码。');
  }
}

int _generation(VideoJson value) {
  final generation = value['generation'] ?? 1;
  if (generation is! int || generation < 1) {
    throw const InteropException('invalid_endpoint', '视频版本无效。');
  }
  return generation;
}

String _sourceId(VideoJson stream) {
  final id = stream['videoSourceId'];
  if (id is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(id)) {
    throw const InteropException('invalid_endpoint', '缺少有效的原生视频源。');
  }
  return id;
}

void _validateSource(VideoJson endpoint) {
  if (endpoint['container'] != 'packet' ||
      endpoint['sourceId'] is! String ||
      endpoint['attachAddress'] is! int ||
      endpoint['detachAddress'] is! int ||
      (endpoint['attachAddress'] as int) <= 0 ||
      (endpoint['detachAddress'] as int) <= 0) {
    throw const InteropException('invalid_endpoint', '媒体输入不是有效的原生数据源。');
  }
}

Future<List<int>> _png(VideoPixels pixels) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels.rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: pixels.width,
    height: pixels.height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const InteropException('capture_failed', '截图编码未完成。');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}
