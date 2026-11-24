import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/audio_player.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_pixels.dart';
import 'package:scrcpy_connect/core/media/models/video_texture.dart';
import 'package:scrcpy_connect/core/media/video_output_service.dart';
import 'package:scrcpy_connect/core/media/video_player.dart';
import 'package:scrcpy_connect/core/settings/models/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('截图回执使用实际 PNG 尺寸，只读像素不受来源改写影响', () async {
    final fixture = _Fixture(operationTimeout: const Duration(seconds: 3));
    final directory = await Directory.systemTemp.createTemp(
      'video-screenshot-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final original = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]);
    fixture.player.snapshotPixels = VideoPixels(2, 1, original);
    original.fillRange(0, original.length, 0);
    await fixture.service.start(_capture);
    final receipt = await fixture.service.screenshot(
      'session',
      directory: directory.path,
    );
    expect(receipt.width, 2);
    expect(receipt.height, 1);
    expect(receipt.generation, _capture.generation);
    final codec = await ui.instantiateImageCodec(
      await File(receipt.localPath).readAsBytes(),
    );
    addTearDown(codec.dispose);
    final image = (await codec.getNextFrame()).image;
    addTearDown(image.dispose);
    expect(image.width, receipt.width);
    expect(image.height, receipt.height);
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes), [
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
    ]);
  });

  test('未打开的真实播放器可关闭，不创建原生输出并返回实际空资源证据', () async {
    final audio = AudioPlayer();
    final video = VideoPlayer();
    for (final receipt in [await audio.release(), await video.release()]) {
      expect(receipt.confirmed, isTrue);
      expect(receipt.resourceAllocated, isFalse);
    }
    expect(audio.outputStatus.nativeReady, isFalse);
    expect(audio.outputStatus.bytesWritten, 0);
  });

  test('原生回执解码保留代次、呈现和解码证据，不将未知消息或缺失释放事实当成成功', () {
    final decoded = MediaPlayerEvent.decode({
      'kind': 'diagnostic',
      'category': 'decoder.video',
      'decoderName': 'h264/videotoolbox',
      'hardwareAccelerated': false,
      'hardwareVerification': 'unverified',
      'backendHardwareFrames': true,
      'runtimeSelectionVerified': true,
    }) as MediaDecoderSelected;
    expect(decoded.hardwareAccelerated, isFalse);
    expect(decoded.backendHardwareFrames, isTrue);
    expect(decoded.toDiagnosticFields()['hardwareVerification'], 'unverified');
    final presented = MediaPlayerEvent.decode({
      'kind': 'diagnostic',
      'category': 'video.presentation',
      'generation': 2,
      'textureId': 7,
      'presentedSequence': 3,
      'platformTexturePrepared': true,
      'presentedToWidget': false,
      'presentationPath': 'apple-texture',
    }) as VideoPlayerPresented;
    expect(presented.generation, 2);
    expect(presented.textureId, 7);
    expect(presented.presentedToWidget, isFalse);
    expect(MediaPlayerEvent.decode({'kind': 'unknown'}), isNull);
    expect(MediaOutputRelease.fromProtocol({}).confirmed, isFalse);
    expect(
      MediaOutputRelease.fromProtocol({
        'nativeDeleteConfirmed': true,
        'cleanupUnconfirmed': true,
      }).confirmed,
      isFalse,
    );
  });

  test('只有同代次同纹理的新帧和呈现事实可以更新输出', () async {
    final fixture = _Fixture();
    await fixture.service.start(_capture);
    fixture.player.eventsController.add(
      const VideoPlayerDimensions(
        generation: 1,
        textureId: 7,
        width: 480,
        height: 640,
        frameCount: 1,
      ),
    );
    final resized = fixture.events.whereType<VideoOutputFrame>().single.output;
    expect(resized.decodedWidth, 480);
    expect(resized.decodedHeight, 640);
    fixture.player.eventsController.add(
      const VideoPlayerDimensions(
        generation: 2,
        textureId: 7,
        width: 800,
        height: 600,
        frameCount: 2,
      ),
    );
    fixture.player.eventsController.add(
      const VideoPlayerDimensions(
        generation: 1,
        textureId: 99,
        width: 800,
        height: 600,
        frameCount: 2,
      ),
    );
    fixture.player.eventsController.add(
      const VideoPlayerDimensions(
        generation: 1,
        textureId: 7,
        width: 800,
        height: 600,
        frameCount: 1,
      ),
    );
    expect(fixture.events.whereType<VideoOutputFrame>(), hasLength(1));
    fixture.player.eventsController.add(
      const VideoPlayerPresented(
        generation: 2,
        textureId: 7,
        platformTexturePrepared: true,
      ),
    );
    expect(fixture.events.whereType<VideoOutputFrame>(), hasLength(1));
    fixture.player.eventsController.add(
      const VideoPlayerPresented(
        generation: 1,
        textureId: 7,
        platformTexturePrepared: true,
        presentedSequence: 9,
        presentationPath: 'apple-texture',
      ),
    );
    final presented = fixture.events.whereType<VideoOutputFrame>().last.output;
    expect(presented.decoder.presentedSequence, 9);
    expect(presented.decoder.platformTexturePrepared, isTrue);
    expect(presented.decodedWidth, 480);
  });

  test('准备中的播放器事件失败结束等待，迟到创建仍交给同一输出释放', () async {
    final fixture = _Fixture();
    final opening = fixture.player.opening = Completer<VideoTexture>();
    final starting = fixture.service.start(_capture);
    final checked = expectLater(
      starting,
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'video_failed',
        ),
      ),
    );
    await _tick();
    fixture.player.eventsController.addError(
      StateError('invalid native metadata'),
    );
    await _tick();
    expect(fixture.player.releases, 1);
    opening.complete(const VideoTexture(7, 640, 480));
    await checked;
    expect(fixture.events.whereType<VideoOutputReady>(), isEmpty);
    expect(fixture.player.releases, 1);
  });

  test('画质变化继续使用独立窗口的播放器', () async {
    final fixture = _Fixture();
    final windowPlayers = <_VideoPlayer>[];
    await fixture.service.start(
      _capture,
      playerFactory: () {
        final player = _VideoPlayer();
        windowPlayers.add(player);
        return player;
      },
    );

    final changed = await fixture.service.reconfigure(
      _capture.copyWith(captureGeneration: 2, generation: 2),
    );

    expect(changed.generation, 2);
    expect(windowPlayers, hasLength(2));
    expect(windowPlayers.first.releases, 1);
    expect(fixture.player.releases, 0);
    expect((await fixture.service.stop('session')).confirmed, isTrue);
    expect(windowPlayers.last.releases, 1);
  });

  test('释放超时保留原输出与真实 Future，迟到确认前重试不重复删除', () async {
    final fixture = _Fixture();
    await fixture.service.start(_capture);
    final releasing = fixture.player.releasing =
        Completer<MediaOutputRelease>();
    final stop = await fixture.service.stop('session');
    expect(stop.confirmed, isFalse);
    await expectLater(
      fixture.service.dispose(),
      throwsA(
        isA<RequestFailure>().having(
          (error) => error.code,
          'code',
          'video_cleanup_unconfirmed',
        ),
      ),
    );
    expect(fixture.player.releases, 1);
    releasing.complete(const MediaOutputRelease(nativeDeleteConfirmed: true));
    await _tick();
    await fixture.service.dispose();
    expect(fixture.player.releases, 1);
  });

  test('原生未确认释放保持可重试，重试使用同一播放器', () async {
    final fixture = _Fixture();
    await fixture.service.start(_capture);
    fixture.player.releaseReceipt = const MediaOutputRelease(
      nativeDeleteConfirmed: false,
      cleanupUnconfirmed: true,
    );
    expect((await fixture.service.stop('session')).confirmed, isFalse);
    fixture.player.releaseReceipt = const MediaOutputRelease(
      nativeDeleteConfirmed: true,
    );
    await fixture.service.dispose();
    expect(fixture.player.releases, 2);
  });
}

const _capture = VideoCapture(
  sessionId: 'session',
  deviceId: 'device',
  captureRef: 'capture',
  captureGeneration: 1,
  generation: 1,
  videoSourceId:
      '0000000000000000000000000000000000000000000000000000000000000001',
  codec: VideoCodec.h264,
  width: 640,
  height: 480,
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

final class _Fixture {
  _Fixture({Duration operationTimeout = const Duration(milliseconds: 20)}) {
    service = VideoOutputService(
      emit: events.add,
      isDisposed: () => false,
      playerFactory: () => player,
      openSource:
          ({
            required captureRef,
            required sourceId,
            required generation,
          }) async => MediaCodecSource(
            sourceId: sourceId,
            generation: generation,
            codec: 'h264',
            attachAddress: 1,
            detachAddress: 1,
          ),
      operationTimeout: operationTimeout,
    );
    addTearDown(() async {
      final pending = player.releasing;
      if (pending != null && !pending.isCompleted) {
        pending.complete(const MediaOutputRelease(nativeDeleteConfirmed: true));
      }
      player.releaseReceipt = const MediaOutputRelease(
        nativeDeleteConfirmed: true,
      );
      await service.dispose();
    });
  }
  final player = _VideoPlayer();
  final events = <VideoOutputEvent>[];
  late final VideoOutputService service;
}

final class _VideoPlayer implements VideoPlayer {
  final eventsController = StreamController<MediaPlayerEvent>.broadcast(
    sync: true,
  );
  Completer<VideoTexture>? opening;
  Completer<MediaOutputRelease>? releasing;
  VideoPixels? snapshotPixels;
  var releases = 0;
  MediaOutputRelease releaseReceipt = const MediaOutputRelease(
    nativeDeleteConfirmed: true,
  );
  @override
  Stream<MediaPlayerEvent> get events => eventsController.stream;
  @override
  Future<VideoTexture> open(MediaCodecSource source) async =>
      opening?.future ?? const VideoTexture(7, 640, 480);
  @override
  Future<void> setPaused(bool paused) async {}
  @override
  Future<VideoPixels?> snapshot({
    required int width,
    required int height,
  }) async => snapshotPixels;
  @override
  Future<MediaOutputRelease> release() async {
    releases++;
    if (opening != null) await opening!.future;
    final receipt = releasing == null
        ? releaseReceipt
        : await releasing!.future;
    if (receipt.confirmed) await eventsController.close();
    return receipt;
  }
}
