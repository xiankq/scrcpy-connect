import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../interop_exception.dart';
import 'native_frame_trace.dart';
import 'native_video_readback.dart';
import 'video_player_port.dart';
import 'playback_confirmation.dart';
import 'video_player_operations.dart';

/// Playback uses public fvp APIs. Codec selection remains MDK's actual runtime
/// decision; videoDecoders is a priority list and is never reported as evidence.
class FvpVideoPlayer implements VideoPlayerPort {
  /// Explicit priorities support real backend comparisons. The list still is
  /// not evidence of which decoder MDK actually opens; observe decoder.video.
  factory FvpVideoPlayer({
    List<String>? videoDecoders,
    bool traceFrames = false,
  }) {
    if (_retiring.length >= 8) {
      throw const InteropException('resource_busy', '播放器资源仍在释放，请稍后重新打开画面。');
    }
    return FvpVideoPlayer._(
      videoDecoders == null ? null : List.unmodifiable(videoDecoders),
      traceFrames,
    );
  }
  FvpVideoPlayer._(this._videoDecoders, this._traceFrames);
  final List<String>? _videoDecoders;
  final bool _traceFrames;
  NativeFrameTrace? _frameTrace;
  NativeVideoReadback? _readback;
  int? _texture;

  /// Diagnostic snapshots and decoded observations share this native clock.
  VideoJson? get frameTrace {
    final trace = _frameTrace;
    return trace == null
        ? null
        : {...trace.metrics, 'undecodedBufferMs': _player.buffered()};
  }

  void _initialize() {
    if (_initialized) return;
    _initialized = true;
    _player
      ..activeAudioTracks = const []
      ..mute = true
      ..setBufferRange(min: 0, max: 150, drop: true)
      ..setProperty('avformat.input', 'matroska')
      ..setProperty('avformat.fpsprobesize', '0')
      // This player carries live video only. Present decoded frames immediately
      // instead of allowing playback-clock queues to backpressure decoding.
      ..setProperty('fps', '-1')
      // The relay supplies codec configuration and dimensions in its Matroska
      // header. Do not sample a large part of a mostly static live stream.
      // Keep the initial IDR buffered; +nobuffer can discard it during probing.
      ..setProperty('avformat.probesize', '32');
    // Public fvp currently exposes no getGlobalOption for MDK's runtime hint.
    // Use MDK's documented platform priorities; these are candidates, not proof
    // that any decoder can open this device's actual stream.
    // Frame threading queues additional frames. Slice threading preserves
    // within-frame parallelism without requiring later live frames to arrive.
    const software = 'FFmpeg:thread_type=slice';
    final decoders =
        _videoDecoders ??
        switch (defaultTargetPlatform) {
          // The fixed SDK used synchronous output when this option was absent.
          // Explicit async output removes that queue on supported Android APIs;
          // AImageReader's async acquisition is a separate setting.
          TargetPlatform.android => const [
            'AMediaCodec:async=1',
            software,
            'dav1d',
          ],
          TargetPlatform.iOS ||
          TargetPlatform.macOS => const ['VT', software, 'dav1d'],
          TargetPlatform.windows => const [
            'MFT:d3d=11',
            'D3D11',
            'DXVA',
            software,
            'dav1d',
          ],
          TargetPlatform.linux => const ['VAAPI', software, 'dav1d'],
          TargetPlatform.fuchsia => const [software, 'dav1d'],
        };
    _player.videoDecoders = decoders;
    _emit({
      'kind': 'diagnostic',
      'category': 'decoder.priority',
      'candidates': decoders,
      'runtimeSelectionVerified': false,
    });
    _confirmation = PlaybackConfirmation(
      changes: _player.onStateChanged.map((event) => event.newValue),
      request: (target) => _player.state = target,
      // Zero can block until EOF in this SDK; always use a positive bound.
      query: (target) => _player.waitFor(target, timeout: 1),
    );
    _subscriptions.add(
      _player.onStateChanged.listen((event) {
        _confirmedState = event.newValue;
        _emit({
          'kind': 'diagnostic',
          'category': 'playback.state',
          'old': '${event.oldValue}',
          'new': '${event.newValue}',
        });
      }),
    );
    _subscriptions.add(
      _player.onEvent.listen((event) {
        _emit({
          'kind': 'diagnostic',
          'category': event.category,
          'error': event.error,
          'detail': _bounded(event.detail),
        });
      }),
    );
    _subscriptions.add(
      _player.onMediaStatus.listen((event) {
        final invalid = event.newValue.test(mdk.MediaStatus.invalid);
        _emit({
          'kind': invalid ? 'failed' : 'status',
          'status': '${event.newValue}',
          if (invalid)
            'reason': 'MDK could not load or decode this media input.',
        });
      }),
    );
  }

  late final _player = mdk.Player();
  late final PlaybackConfirmation<mdk.PlaybackState> _confirmation;
  static final _retiring = <Future<VideoJson>>{};
  mdk.PlaybackState? _confirmedState;
  Future<int>? _creatingTexture;
  final _events = StreamController<VideoJson>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _operations = VideoPlayerOperations();
  bool _released = false;
  bool _initialized = false;
  Future<VideoJson>? _releaseFuture;
  @override
  Stream<VideoJson> get events => _events.stream;

  void _emit(VideoJson event) {
    if (!_released) _events.add(event);
  }

  String _bounded(String value) {
    final redacted = value.replaceAll(
      RegExp(r'http://127\.0\.0\.1:\d+/[a-fA-F0-9]{64}'),
      '<local-media>',
    );
    return redacted.length <= 1024
        ? redacted
        : '${redacted.substring(0, 1024)}…';
  }

  void _check() {
    if (_released) throw const InteropException('cancelled', '此视频输出已关闭。');
  }

  @override
  Future<VideoTexture> open(String url) async {
    _check();
    _initialize();
    final watch = Stopwatch()..start();
    _player.media = url;
    final prepared = await _player.prepare();
    _emit({
      'kind': 'diagnostic',
      'category': 'video.prepare',
      'elapsedMs': watch.elapsedMilliseconds,
    });
    _check();
    if (prepared < 0 || (_player.mediaInfo.video?.isEmpty ?? true)) {
      throw const InteropException('decoder_error', '播放器未取得有效视频信息。');
    }
    final creating = _player.updateTexture();
    _creatingTexture = creating;
    final int texture;
    try {
      texture = await creating;
      _emit({
        'kind': 'diagnostic',
        'category': 'video.texture',
        'elapsedMs': watch.elapsedMilliseconds,
      });
    } finally {
      _creatingTexture = null;
    }
    _check();
    final size = await _player.textureSize;
    _check();
    if (texture < 0 || size == null || size.width <= 0 || size.height <= 0) {
      throw const InteropException('decoder_error', '未能创建视频纹理。');
    }
    _texture = texture;
    if (_traceFrames) {
      _frameTrace = NativeFrameTrace(_player.nativeHandle);
      final parameters = _player.mediaInfo.video!.first.codec;
      final extra = parameters.extra;
      _emit({
        'kind': 'diagnostic',
        'category': 'video.frameTrace',
        'enabled': true,
        'codec': parameters.codec,
        'reportedBFrames': parameters.bFrames,
        if (extra != null && extra.length <= 4096)
          'codecExtraBase64': base64Encode(extra),
      });
    }
    return VideoTexture(texture, size.width.round(), size.height.round());
  }

  @override
  Future<void> setPaused(bool paused, {Future<void> Function()? onRequested}) =>
      _operations.run(() => _setPaused(paused, onRequested));

  Future<void> _setPaused(
    bool paused,
    Future<void> Function()? onRequested,
  ) async {
    _check();
    final target = paused
        ? mdk.PlaybackState.paused
        : mdk.PlaybackState.playing;
    final receipt = await _confirmation.set(target, onRequested: onRequested);
    _check();
    _emit({
      'kind': 'diagnostic',
      'category': 'playback.confirmation',
      'target': '$target',
      'lastCallback': '$_confirmedState',
      'mediaStatus': '${_player.mediaStatus}',
      'queries': receipt.queries,
      'maxQueryMs': receipt.maxQueryMs,
    });
  }

  @override
  Future<VideoPixels?> snapshot({required int width, required int height}) =>
      _operations.run(() => _snapshot(width: width, height: height));

  Future<VideoPixels?> _snapshot({
    required int width,
    required int height,
  }) async {
    _check();
    final watch = Stopwatch()..start();
    final trace = _frameTrace;
    if (trace != null && width <= 256 && height <= 256) {
      final pixels = await trace.snapshot(
        texture: _texture!,
        width: width,
        height: height,
      );
      _check();
      return pixels;
    }
    final readback = _readback ??= NativeVideoReadback(_player.nativeHandle);
    final pixels = await readback.snapshot(
      texture: _texture!,
      width: width,
      height: height,
    );
    _emit({
      'kind': 'diagnostic',
      'category': 'video.snapshot',
      'elapsedMs': watch.elapsedMilliseconds,
    });
    _check();
    return pixels;
  }

  @override
  Future<VideoJson> release() => _releaseFuture ??= _release();

  Future<VideoJson> _release() async {
    _released = true;
    final drained = _operations.close();
    if (!_initialized) {
      await drained;
      await _events.close();
      return {
        'resourceAllocated': false,
        'textureDetached': true,
        'disposeRequested': false,
        'nativeDeleteConfirmed': false,
      };
    }
    // Cancel native state queries immediately. Snapshot callbacks have no public
    // cancellation API: keep their handles alive until actual result delivery.
    final queriesClosed = _confirmation.close();
    var stopped = false;
    final cleanup = () async {
      await drained;
      await queriesClosed;
      _readback?.close();
      _readback = null;
      _frameTrace?.close();
      _frameTrace = null;
      final stoppedEvent = Completer<void>();
      final subscription = _player.onStateChanged.listen((event) {
        if (event.newValue == mdk.PlaybackState.stopped &&
            !stoppedEvent.isCompleted) {
          stoppedEvent.complete();
        }
      });
      try {
        _player.state = mdk.PlaybackState.stopped;
        try {
          await stoppedEvent.future.timeout(const Duration(seconds: 2));
          stopped = true;
        } on TimeoutException {
          /* Requested state is not a callback receipt. */
        }
      } finally {
        await subscription.cancel();
        for (final observer in _subscriptions) {
          await observer.cancel();
        }
        await _events.close();
      }
      // Never delete while native readback or createTexture still uses the
      // handle. A stalled callback remains admission-bounded in _retiring.
      try {
        await _creatingTexture;
      } catch (_) {
        // A settled create failure cannot still be using the native handle.
      }
      await _player.updateTexture(width: -1);
      _player.dispose(); // Public async-void request, no native delete receipt.
      return <String, dynamic>{
        'stoppedConfirmed': stopped,
        'textureDetached': true,
        'disposeRequested': true,
        'nativeDeleteConfirmed': false,
      };
    }();
    _retiring.add(cleanup);
    unawaited(
      cleanup.then<void>(
        (_) {
          _retiring.remove(cleanup);
        },
        onError: (Object _, StackTrace _) {
          _retiring.remove(cleanup);
        },
      ),
    );
    try {
      return await cleanup.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return {
        'stoppedConfirmed': stopped,
        'textureDetached': false,
        'disposeRequested': false,
        'disposeDeferred': true,
        'nativeDeleteConfirmed': false,
      };
    }
  }
}
