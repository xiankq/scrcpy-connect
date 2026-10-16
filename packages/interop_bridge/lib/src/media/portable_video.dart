import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../interop_exception.dart';
import 'fvp_video_player.dart';
import 'video_player_port.dart';

export 'video_player_port.dart';

/// Owns local video output only. Core remains the owner of the control session,
/// encoder process, input coordinates and session.ready/session.stop decisions.
class PortableVideoOutputs {
  PortableVideoOutputs({
    required this.core,
    required this.emit,
    required this.isDisposed,
    VideoPlayerFactory? playerFactory,
    this.startTimeout = const Duration(seconds: 18),
    this.operationTimeout = const Duration(seconds: 6),
  }) : _factory = playerFactory ?? FvpVideoPlayer.new;

  final VideoCoreRequest core;
  final void Function(VideoJson) emit;
  final bool Function() isDisposed;
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
    );
    _entries[id] = entry;
    _armStartup(entry);
    entry.ready = _start(entry, stream);
    return entry.ready!;
  }

  Future<VideoJson> _start(_Output entry, VideoJson stream) async {
    try {
      final port = stream['videoPort'];
      final token = stream['videoToken'];
      if (port is! int ||
          port < 1 ||
          port > 65535 ||
          token is! String ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
        throw const InteropException('invalid_endpoint', '视频输入缺少有效的一次性连接信息。');
      }
      // A timeout cannot cancel a core Future. The late callback still closes
      // exactly the relay it created, never a replacement entry's relay.
      final opening = core('media.open', {
        'kind': 'video',
        'port': port,
        'token': token,
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
      if (identical(_entries[entry.id], entry)) _entries.remove(entry.id);
      await _release(entry);
      throw _failure(error, entry);
    }
  }

  Future<VideoJson> _prepare(_Output entry, VideoJson endpoint) async {
    _check(entry);
    if ((endpoint['kind'] != null && endpoint['kind'] != 'video') ||
        (endpoint['codec'] != null && endpoint['codec'] != entry.codec)) {
      throw const InteropException('invalid_endpoint', '媒体输入类型或实际编码与视频输出不一致。');
    }
    final url = _url(endpoint);
    entry.observer = entry.player.events.listen((event) {
      if (!_owns(entry) || entry.closed || _disposed || isDisposed()) return;
      if (entry.diagnostics.length < 24 && event['kind'] == 'diagnostic') {
        entry.diagnostics.add({...event});
      }
      if (event['kind'] == 'failed' && entry.texture != null) {
        emit({
          'type': 'session.output.failed',
          'deviceId': entry.device,
          'data': {
            'sessionId': entry.id,
            'generation': entry.generation,
            'reason': event['reason'] ?? '视频输入已结束。',
            'backend': 'fvp',
          },
        });
      }
    });
    final texture = await _await(entry, entry.player.open(url));
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
    await _verifyFrame(entry);
    _check(entry);
    _verifiedCodecs.add(entry.codec);
    entry.startTimer?.cancel();
    return _receipt(entry);
  }

  /// Attach a new core-owned generation without launching or stopping an app.
  /// The previous texture survives candidate failure and is released only after
  /// the candidate produces a verified decoded image.
  Future<VideoJson> reattach(
    String id, {
    required VideoJson endpoint,
    String? codec,
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
    );
    candidate.relay = _text(endpoint, 'relayId');
    candidate.ownsRelay = candidate.relay != old.relay;
    _pending[id] = candidate;
    _armStartup(candidate);
    try {
      final receipt = await _prepare(candidate, endpoint);
      _check(candidate);
      if (!identical(_entries[id], old)) throw _cancelled();
      candidate.paused = old.paused;
      if (old.paused) await _await(candidate, candidate.player.setPaused(true));
      _check(candidate);
      _pending.remove(id);
      _entries[id] = candidate;
      if (candidate.relay == old.relay) {
        old.ownsRelay = false;
        candidate.ownsRelay = true;
      }
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
    final entry = _entry(id);
    final revision = ++entry.presentationRevision;
    if (++entry.queuedControls > 8) {
      entry.queuedControls--;
      throw const InteropException('renderer_busy', '视频状态操作过于频繁，请稍后再试。');
    }
    final operation = entry.control.then((_) async {
      _check(entry);
      // A previous request may have timed out before its state callback. Ask
      // the player to confirm even an apparently unchanged requested state.
      final changing = _await(
        entry,
        entry.player.setPaused(paused),
        operationTimeout,
      );
      // A static stream may have no next packet to let the reader acknowledge
      // pause. RESET_VIDEO refreshes this same encoder, without app/input side
      // effects. The caller must keep capture running until local pause ACK.
      unawaited(
        changing.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      if (paused) {
        await _await(
          entry,
          core('session.refresh', {'sessionId': id}),
          operationTimeout,
        );
      }
      await changing;
      _check(entry);
      entry.paused = paused;
      if (!paused) await _verifyFrame(entry);
      _check(entry);
      if (revision != entry.presentationRevision) throw _cancelled();
      return {..._receipt(entry), 'paused': paused, 'applied': true};
    });
    entry.control = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation.whenComplete(() => entry.queuedControls--);
  }

  Future<void> _verifyFrame(_Output entry) async {
    final pixels = await _pixels(entry, 32, 32);
    if (pixels == null || !pixels.valid) {
      throw const InteropException('no_frame', '尚未取得可读取的实际视频帧。');
    }
    entry.snapshotReceipts++;
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
    // MDK has one outstanding snapshot slot. Timing out our receipt does not
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
    return _await(entry, pending, operationTimeout);
  }

  /// Caller supplies an app-owned directory. A fresh subdirectory avoids
  /// replacing existing user files; the result states any resolution reduction.
  Future<VideoJson> screenshot(String id, {required String directory}) async {
    final entry = _entry(id);
    _check(entry);
    final size = entry.texture;
    if (size == null || entry.snapshotReceipts == 0) {
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
        'evidence': 'mdk.snapshot',
      };
    } catch (_) {
      if (owned != null) await owned.delete(recursive: true);
      rethrow;
    }
  }

  VideoJson capabilities() => {
    'backend': 'fvp',
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
    'frameEvidence': 'snapshotOnly',
    'continuousFrameTelemetry': false,
  };

  Future<VideoJson> stop(String id) async {
    _stopped.add(id);
    if (_stopped.length > 4096) _stopped.remove(_stopped.first);
    final entries = [
      _entries.remove(id),
      _pending.remove(id),
    ].whereType<_Output>().toList();
    for (final entry in entries) {
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

  InteropException _aborted(_Output entry) => entry.timedOut
      ? InteropException('video_timeout', '视频准备超过时限，已有画面保持不变。', {
          'diagnostics': entry.diagnostics,
        })
      : _cancelled();
  InteropException _failure(Object error, _Output entry) =>
      error is InteropException
      ? error
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
    'sessionId': entry.id,
    'deviceId': entry.device,
    'relayId': entry.relay,
    'textureId': entry.texture!.id,
    'decodedWidth': entry.texture!.width,
    'decodedHeight': entry.texture!.height,
    'codec': entry.codec,
    'generation': entry.generation,
    'backend': 'fvp',
    'firstFrameDecoded': true,
    'evidence': 'mdk.snapshot',
    'snapshotReceipts': entry.snapshotReceipts,
    'presentedToWidget': false,
    'continuousFrameTelemetry': false,
  };
}

class _Output {
  _Output(
    this.id,
    this.device,
    this.codec,
    this.generation,
    this.player,
    this.cancelled,
  );
  final String id, device, codec;
  final int generation;
  final VideoPlayerPort player;
  final bool Function()? cancelled;
  final cancellation = StreamController<void>.broadcast(sync: true);
  final diagnostics = <VideoJson>[];
  final closedRelays = <String>{};
  Future<VideoJson>? ready, releasing;
  String? relay;
  StreamSubscription<VideoJson>? observer;
  VideoTexture? texture;
  bool closed = false, paused = false, snapshotBusy = false;
  bool ownsRelay = true;
  bool timedOut = false;
  Timer? startTimer;
  int snapshotReceipts = 0, presentationRevision = 0, queuedControls = 0;
  Future<void> control = Future.value();
  void cancel() {
    startTimer?.cancel();
    if (closed) return;
    closed = true;
    cancellation.add(null);
    unawaited(cancellation.close());
  }
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

String _url(VideoJson endpoint) {
  final value = endpoint['url'];
  final url = value is String ? Uri.tryParse(value) : null;
  if (url == null ||
      url.scheme != 'http' ||
      url.host != '127.0.0.1' ||
      !url.hasPort ||
      url.port < 1 ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      !RegExp(r'^/[a-fA-F0-9]{64}$').hasMatch(url.path)) {
    throw const InteropException('invalid_endpoint', '媒体输入不是授权的本机流。');
  }
  return value as String;
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
