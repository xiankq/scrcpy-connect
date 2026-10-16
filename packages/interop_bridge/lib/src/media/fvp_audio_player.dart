import 'dart:async';

import 'package:fvp/mdk.dart' as mdk;

import '../interop_exception.dart';
import 'audio_player_port.dart';
import 'playback_confirmation.dart';

/// Audio-only MDK output. Never creates a Flutter texture, parses PCM, or
/// requests system focus. State receipts use callbacks/native waitFor, not the
/// Dart state getter (which is synchronously overwritten by its setter).
class FvpAudioPlayer implements AudioPlayerPort {
  factory FvpAudioPlayer({
    int bufferMilliseconds = 150,
    Map<String, String> demuxOptions = const {'avformat.fpsprobesize': '0'},
  }) {
    if (_retiring.length >= 8) {
      throw const InteropException('resource_busy', '声音播放器仍在释放，请稍后再试。');
    }
    if (bufferMilliseconds < 20 ||
        bufferMilliseconds > 1000 ||
        demuxOptions.entries.any(
          (e) =>
              !const {
                'avformat.fpsprobesize',
                'avformat.probesize',
                'avformat.analyzeduration',
                'avformat.fflags',
              }.contains(e.key) ||
              e.value.length > 128,
        )) {
      throw const InteropException('invalid_argument', '声音缓冲或媒体探测设置无效。');
    }
    return FvpAudioPlayer._(bufferMilliseconds, Map.unmodifiable(demuxOptions));
  }
  FvpAudioPlayer._(this._bufferMilliseconds, this._demuxOptions);
  final int _bufferMilliseconds;
  final Map<String, String> _demuxOptions;

  static final _retiring = <Future<AudioJson>>{};
  late final _player = mdk.Player();
  final _events = StreamController<AudioJson>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _initialized = false, _closed = false, _hasPlayed = false;
  Future<AudioJson>? _releasing;
  late final _confirmation = _newConfirmation();

  @override
  Stream<AudioJson> get events => _events.stream;

  void _check() {
    if (_closed) throw const InteropException('cancelled', '此声音输出已结束。');
  }

  void _initialize() {
    if (_initialized) return;
    _initialized = true;
    _player
      ..setProperty('avformat.input', 'matroska')
      ..setBufferRange(min: 0, max: _bufferMilliseconds, drop: true);
    for (final option in _demuxOptions.entries) {
      _player.setProperty(option.key, option.value);
    }
    _subscriptions.add(
      _player.onStateChanged.listen((event) {
        if (!_closed &&
            _hasPlayed &&
            event.newValue == mdk.PlaybackState.stopped) {
          _events.add({'kind': 'failed', 'reason': '声音播放器已经停止接收此媒体输入。'});
        }
      }),
    );
    _subscriptions.add(
      _player.onEvent.listen((event) {
        final text = event.detail.replaceAll(
          RegExp(r'http://127\.0\.0\.1:\d+/[a-fA-F0-9]{64}'),
          '<local-media>',
        );
        if (!_closed) {
          _events.add({
            'kind': 'diagnostic',
            'category': event.category,
            'error': event.error,
            'detail': text.length <= 1024 ? text : text.substring(0, 1024),
          });
        }
      }),
    );
    _subscriptions.add(
      _player.onMediaStatus.listen((event) {
        if (!_closed && event.newValue.test(mdk.MediaStatus.invalid)) {
          _events.add({'kind': 'failed', 'reason': '声音媒体输入未能加载或解码。'});
        }
      }),
    );
  }

  @override
  Future<AudioFormat> open(String url) async {
    _check();
    _initialize();
    _player
      ..media = url
      ..activeVideoTracks = const []
      ..activeSubtitleTracks = const []
      ..activeAudioTracks = const [0];
    final result = await _player.prepare();
    _check();
    final tracks = _player.mediaInfo.audio;
    if (result < 0 || tracks == null || tracks.isEmpty) {
      throw const InteropException('audio_not_ready', '播放器尚未取得有效的音频轨。');
    }
    final format = tracks.first.codec;
    return AudioFormat(format.codec, format.sampleRate, format.channels);
  }

  PlaybackConfirmation<mdk.PlaybackState> _newConfirmation() =>
      PlaybackConfirmation(
        changes: _player.onStateChanged.map((event) => event.newValue),
        request: (target) => _player.state = target,
        // Zero/default waitFor blocked the isolate in the Android probe.
        // Query only after a request, with an explicitly positive timeout.
        query: (target) => _player.waitFor(target, timeout: 1),
      );

  Future<void> _state(mdk.PlaybackState target) async {
    _check();
    await _confirmation.set(target);
  }

  @override
  Future<void> setPaused(bool paused) async {
    _checkLoaded();
    await _state(paused ? mdk.PlaybackState.paused : mdk.PlaybackState.playing);
    _check();
    if (_player.mediaStatus.test(mdk.MediaStatus.invalid)) {
      throw const InteropException('audio_failed', '声音媒体输入已失效。');
    }
    if (!paused) _hasPlayed = true;
  }

  @override
  Future<void> volume(double value, bool muted) async {
    _checkLoaded();
    _player
      ..volume = value
      ..mute = muted;
  }

  @override
  int get positionMs {
    _checkLoaded();
    return _player.position;
  }

  void _checkLoaded() {
    _check();
    if (!_initialized) {
      throw const InteropException('audio_not_ready', '声音媒体尚未打开。');
    }
  }

  @override
  Future<AudioJson> release() => _releasing ??= _release();
  Future<AudioJson> _release() async {
    _closed = true;
    if (!_initialized) {
      await _events.close();
      return {
        'resourceAllocated': false,
        'disposeRequested': false,
        'nativeDeleteConfirmed': false,
      };
    }
    // Cancel and drain all playback waiters before entering shutdown. The
    // dedicated shutdown confirmation is itself drained before native dispose.
    await _confirmation.close();
    final shutdown = _newConfirmation();
    var stopped = false;
    try {
      await shutdown.set(mdk.PlaybackState.stopped);
      stopped = true;
    } catch (_) {
      // A request or a late callback is not an actual stopped-state receipt.
    } finally {
      await shutdown.close();
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      await _events.close();
    }
    final cleanup = () async {
      // Loaded audio-only media completes textureSize with a dummy size. This
      // releases no texture and guards failed/unfinished prepare honestly.
      await _player.updateTexture(width: -1);
      _player.dispose();
      return <String, dynamic>{
        'stoppedConfirmed': stopped,
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
      return await cleanup.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return {
        'stoppedConfirmed': stopped,
        'disposeRequested': false,
        'disposeDeferred': true,
        'nativeDeleteConfirmed': false,
      };
    }
  }
}
