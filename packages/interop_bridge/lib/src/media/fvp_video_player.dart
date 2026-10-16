import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import '../interop_exception.dart';
import 'video_player_port.dart';
import 'playback_confirmation.dart';

/// Uses only public fvp APIs. Codec selection remains MDK's actual runtime
/// decision; videoDecoders is a priority list and is never reported as evidence.
class FvpVideoPlayer implements VideoPlayerPort {
  factory FvpVideoPlayer() {
    if (_retiring.length >= 8) {
      throw const InteropException('resource_busy', '播放器资源仍在释放，请稍后重新打开画面。');
    }
    return FvpVideoPlayer._();
  }
  FvpVideoPlayer._();

  void _initialize() {
    if (_initialized) return;
    _initialized = true;
    _player
      ..activeAudioTracks = const []
      ..mute = true
      ..setBufferRange(min: 0, max: 150, drop: true)
      ..setProperty('avformat.input', 'matroska')
      ..setProperty('avformat.fpsprobesize', '0');
    // Public fvp currently exposes no getGlobalOption for MDK's runtime hint.
    // Use MDK's documented platform priorities; these are candidates, not proof
    // that any decoder can open this device's actual stream.
    final decoders = switch (defaultTargetPlatform) {
      TargetPlatform.android => const ['AMediaCodec', 'FFmpeg', 'dav1d'],
      TargetPlatform.iOS ||
      TargetPlatform.macOS => const ['VT', 'FFmpeg', 'dav1d'],
      TargetPlatform.windows => const [
        'MFT:d3d=11',
        'D3D11',
        'DXVA',
        'FFmpeg',
        'dav1d',
      ],
      TargetPlatform.linux => const ['VAAPI', 'FFmpeg', 'dav1d'],
      TargetPlatform.fuchsia => const ['FFmpeg', 'dav1d'],
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
    if (texture < 0 || size == null || size.width <= 0 || size.height <= 0) {
      throw const InteropException('decoder_error', '未能创建视频纹理。');
    }
    return VideoTexture(texture, size.width.round(), size.height.round());
  }

  @override
  Future<void> setPaused(bool paused) async {
    _check();
    final target = paused
        ? mdk.PlaybackState.paused
        : mdk.PlaybackState.playing;
    final receipt = await _confirmation.set(target);
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
  Future<VideoPixels?> snapshot({
    required int width,
    required int height,
  }) async {
    _check();
    final watch = Stopwatch()..start();
    final pixels = await _player.snapshot(width: width, height: height);
    _emit({
      'kind': 'diagnostic',
      'category': 'video.snapshot',
      'elapsedMs': watch.elapsedMilliseconds,
    });
    _check();
    if (pixels == null) return null;
    return VideoPixels(width, height, pixels);
  }

  @override
  Future<VideoJson> release() => _releaseFuture ??= _release();

  Future<VideoJson> _release() async {
    _released = true;
    if (!_initialized) {
      await _events.close();
      return {
        'resourceAllocated': false,
        'textureDetached': true,
        'disposeRequested': false,
        'nativeDeleteConfirmed': false,
      };
    }
    // Cancel and drain native state queries before any handle can be deleted.
    await _confirmation.close();
    var stopped = false;
    final stoppedEvent = Completer<void>();
    final subscription = _player.onStateChanged.listen((event) {
      if (event.newValue == mdk.PlaybackState.stopped &&
          !stoppedEvent.isCompleted) {
        stoppedEvent.complete();
      }
    });
    try {
      _player.state = mdk.PlaybackState.stopped;
      if (!stopped) {
        try {
          await stoppedEvent.future.timeout(const Duration(seconds: 2));
          stopped = true;
        } on TimeoutException {
          /* Requested state is not a callback receipt. */
        }
      }
    } finally {
      await subscription.cancel();
      for (final observer in _subscriptions) {
        await observer.cancel();
      }
      await _events.close();
    }
    // Never delete a handle while createTexture still uses it. Failed prepare
    // may also leave textureSize pending: keep that cleanup observable and
    // admission-bounded instead of inventing a private-handle cancellation API.
    final cleanup = () async {
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
