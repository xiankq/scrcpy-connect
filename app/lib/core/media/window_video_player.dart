import 'dart:async';
import 'dart:isolate';

import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/video_pixels.dart';
import 'package:scrcpy_connect/core/media/models/video_texture.dart';
import 'package:scrcpy_connect/core/media/video_player.dart';
import 'package:scrcpy_connect/core/platform/window_isolate_port.dart';

/// Decoding and texture registration must use the child engine's messenger.
final class WindowVideoPlayers {
  WindowVideoPlayers() {
    _owner = WindowIsolateOwner(this);
  }

  late final WindowIsolateOwner<WindowVideoPlayers> _owner;
  final _players = <int, (VideoPlayer, StreamSubscription<MediaPlayerEvent>)>{};
  SendPort get port => _owner.port;

  Future<VideoTexture> open(int id, MediaCodecSource source, SendPort events) {
    final player = VideoPlayer();
    _players[id] = (player, player.events.listen(events.send));
    return player.open(source);
  }

  Future<void> setPaused(int id, bool paused) =>
      _players[id]!.$1.setPaused(paused);

  Future<VideoPixels?> snapshot(int id, int width, int height) =>
      _players[id]!.$1.snapshot(width: width, height: height);

  Future<MediaOutputRelease> release(int id) async {
    final entry = _players[id];
    if (entry == null) {
      return const MediaOutputRelease(nativeDeleteConfirmed: true);
    }
    final result = await entry.$1.release();
    if (result.confirmed) {
      _players.remove(id);
      await entry.$2.cancel();
    }
    return result;
  }

  void dispose() {
    _owner.dispose();
  }
}

final class WindowVideoPlayer implements VideoPlayer {
  WindowVideoPlayer(SendPort port, this.rendererDestroyed)
    : _host = WindowIsolatePort<WindowVideoPlayers>(port),
      _id = _nextId++;

  static int _nextId = 0;
  final WindowIsolatePort<WindowVideoPlayers> _host;
  final int _id;
  final _events = ReceivePort();
  final Future<void> rendererDestroyed;

  @override
  Stream<MediaPlayerEvent> get events => _events.cast<MediaPlayerEvent>();

  @override
  Future<VideoTexture> open(MediaCodecSource source) => Future.any([
    _host.call(
      (owner, request) => owner.open(request.$1, request.$2, request.$3),
      (_id, source, _events.sendPort),
    ),
    rendererDestroyed.then<VideoTexture>((_) {
      throw const RequestFailure('window_unavailable', '远控窗口已经关闭。');
    }),
  ]);

  @override
  Future<void> setPaused(bool paused) => _host.call(
    (owner, request) => owner.setPaused(request.$1, request.$2),
    (_id, paused),
  );

  @override
  Future<VideoPixels?> snapshot({required int width, required int height}) =>
      _host.call(
        (owner, request) => owner.snapshot(request.$1, request.$2, request.$3),
        (_id, width, height),
      );

  @override
  Future<MediaOutputRelease> release() async {
    final result = await Future.any([
      _host.call((owner, id) => owner.release(id), _id),
      rendererDestroyed.then(
        (_) => const MediaOutputRelease(nativeDeleteConfirmed: true),
      ),
    ]);
    if (result.confirmed) _events.close();
    return result;
  }
}
