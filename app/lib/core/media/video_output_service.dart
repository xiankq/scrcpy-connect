import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:media_codec/media_codec.dart';
import 'package:scrcpy_connect/core/control/models/video_capture.dart';
import 'package:scrcpy_connect/core/control/video_quality.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_log.dart';
import 'package:scrcpy_connect/core/diagnostics/diagnostic_reporter.dart';
import 'package:scrcpy_connect/core/diagnostics/models/diagnostic_record.dart';
import 'package:scrcpy_connect/core/errors/request_failure.dart';
import 'package:scrcpy_connect/core/media/models/video_output.dart';
import 'package:scrcpy_connect/core/media/models/video_pixels.dart';
import 'package:scrcpy_connect/core/media/models/video_texture.dart';
import 'package:scrcpy_connect/core/media/video_player.dart';
import 'package:scrcpy_connect/core/media/video_screenshots.dart';

/// 持有本机视频输出及未确认释放的旧输出；捕获协调器拥有远端控制会话与编码进程。
class VideoOutputService {
  VideoOutputService({
    required this.emit,
    required this.isDisposed,
    required this.openSource,
    DiagnosticLog? diagnostics,
    VideoPlayerFactory? playerFactory,
    this.startTimeout = const Duration(seconds: 18),
    this.operationTimeout = const Duration(seconds: 6),
  }) : _diagnostics = DiagnosticReporter(diagnostics),
       _factory = playerFactory ?? VideoPlayer.new;

  final Future<MediaCodecSource> Function({
    required String captureRef,
    required String sourceId,
    required int generation,
  })
  openSource;
  final void Function(VideoOutputEvent) emit;
  final bool Function() isDisposed;
  final DiagnosticReporter _diagnostics;
  final VideoPlayerFactory _factory;
  final Duration startTimeout, operationTimeout;
  final _entries = <String, _Output>{}, _pending = <String, _Output>{};
  final _stopped = <String>{}, _verifiedCodecs = <String>{};
  final _retiring = <_Output>{};
  bool _disposed = false;
  Future<void>? _disposing;

  Future<VideoOutputReceipt> start(
    VideoCapture stream, {
    bool Function()? cancelled,
    VideoPlayerFactory? playerFactory,
  }) async {
    _validateCapture(stream);
    final id = stream.sessionId;
    final device = stream.deviceId;
    _checkOwner();
    if (_stopped.contains(id) || cancelled?.call() == true) throw _cancelled();
    final existing = _entries[id];
    if (existing != null) {
      if (existing.device != device || existing.codec != stream.codec.name) {
        throw const RequestFailure('session_changed', '视频输出与现有会话不一致。');
      }
      final receipt = await existing.ready!;
      _check(existing);
      return receipt;
    }
    if (_entries.length + _pending.length + _retiring.length >= 16) {
      throw const RequestFailure('resource_busy', '视频输出数量已达上限。');
    }
    final entry = _Output(
      id,
      device,
      stream.codec.name,
      stream.generation,
      playerFactory ?? _factory,
      cancelled,
      captureGeneration: stream.captureGeneration,
    );
    _entries[id] = entry;
    _armStartup(entry);
    entry.ready = _start(entry, stream);
    return entry.ready!;
  }

  Future<VideoOutputReceipt> _start(_Output entry, VideoCapture stream) async {
    try {
      // 查询只借用精确捕获描述；实际附着和分离由播放器持有。
      final opening = openSource(
        captureRef: stream.captureRef,
        sourceId: stream.videoSourceId,
        generation: entry.generation,
      );
      final endpoint = await _await(entry, opening);
      entry.relay = endpoint.sourceId;
      final receipt = await _prepare(entry, endpoint);
      emit(VideoOutputReady(receipt));
      return receipt;
    } catch (error) {
      _diagnostics.failure(DiagnosticArea.video, entry.id, error);
      if (identical(_entries[entry.id], entry)) _entries.remove(entry.id);
      await _release(entry);
      throw _failure(error, entry);
    }
  }

  Future<VideoOutputReceipt> _prepare(
    _Output entry,
    MediaCodecSource endpoint,
  ) async {
    _check(entry);
    entry.startupTimingMs['relayOpenedMs'] =
        entry.startupClock.elapsedMilliseconds;
    if (endpoint.codec != entry.codec) {
      throw const RequestFailure('invalid_endpoint', '媒体输入类型或实际编码与视频输出不一致。');
    }
    entry.observer = entry.player.events.listen(
      (event) {
        if (!_owns(entry) || entry.closed || _disposed || isDisposed()) return;
        _diagnostics.playerEvent(
          DiagnosticArea.video,
          entry.id,
          event,
          generation: entry.generation,
        );
        if (entry.diagnostics.length < 24 && event.diagnostic) {
          entry.diagnostics.add(event);
        }
        switch (event) {
          case VideoPlayerDimensions():
            _dimensions(entry, event);
          case MediaDecoderSelected(audio: false):
            entry.decoder = entry.decoder.copyWith(
              decoderName: event.decoderName,
              hardwareAccelerated: event.hardwareAccelerated,
              hardwareVerification: event.hardwareVerification,
              backendHardwareFrames: event.backendHardwareFrames,
            );
          case VideoPlayerPresented():
            if (event.generation != entry.generation ||
                event.textureId != entry.texture?.id) {
              return;
            }
            entry.decoder = entry.decoder.copyWith(
              platformTexturePrepared: event.platformTexturePrepared,
              presentedSequence: event.presentedSequence,
              presentationPath: event.presentationPath,
            );
            if (identical(_entries[entry.id], entry) &&
                !_pending.containsKey(entry.id)) {
              emit(VideoOutputFrame(_receipt(entry)));
            }
          case VideoPlayerTiming(elapsedMs: final elapsed?):
            entry.startupTimingMs[event.diagnosticCategory] = elapsed;
          case MediaPlayerFailed():
            _playerFailed(entry, event.reason ?? '视频输入已结束。');
          default:
            break;
        }
      },
      onError: (Object _, StackTrace _) {
        _playerFailed(entry, '视频播放器事件连接已中断或数据无效。');
      },
    );
    final opening = entry.player.open(endpoint);
    // 原生创建可能先分离输入，MethodChannel 错误随后才到达 Dart。
    // 即使捕获清理先结束等待，也保留迟到创建的真实错误，不能用通用取消掩盖诊断。
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
      throw const RequestFailure('decoder_error', '播放器返回无效的视频尺寸或纹理。');
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

  void _playerFailed(_Output entry, String reason) {
    if (!_owns(entry) || entry.closed || _disposed || isDisposed()) return;
    entry.terminalFailure = RequestFailure('video_failed', reason);
    entry.cancel();
    if (entry.texture != null) {
      emit(
        VideoOutputFailed(
          sessionId: entry.id,
          deviceId: entry.device,
          generation: entry.generation,
          captureGeneration: entry.captureGeneration,
          reason: reason,
        ),
      );
    }
  }

  void _dimensions(_Output entry, VideoPlayerDimensions event) {
    final texture = entry.texture;
    final width = event.width, height = event.height;
    final frames = event.frameCount;
    if (texture == null ||
        event.generation != entry.generation ||
        event.textureId != texture.id ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        frames <= entry.frameCount) {
      return;
    }
    entry.frameCount = frames;
    if (width == texture.width && height == texture.height) return;
    entry.texture = VideoTexture(texture.id, width, height);
    // 交接中的候选和旧代际不能发布呈现状态；最终提交的回执携带尺寸。
    if (!identical(_entries[entry.id], entry) ||
        _pending.containsKey(entry.id) ||
        entry.decodedReceipts == 0) {
      return;
    }
    emit(VideoOutputFrame(_receipt(entry)));
  }

  /// 消费替换捕获的一次性输入；交接前保留逻辑输出及最后核验的纹理。
  Future<VideoOutputReceipt> reconfigure(VideoCapture stream) async {
    _validateCapture(stream);
    final id = stream.sessionId;
    final old = _entry(id);
    _check(old);
    if (stream.deviceId != old.device) {
      throw const RequestFailure('session_changed', '新视频输入不属于当前设备。');
    }
    final generation = math.max(stream.generation, old.generation + 1);
    final captureGeneration = stream.captureGeneration;
    if (captureGeneration <= old.captureGeneration) {
      throw const RequestFailure('generation_changed', '新视频输入归属已经过期。');
    }
    final opening = openSource(
      captureRef: stream.captureRef,
      sourceId: stream.videoSourceId,
      generation: generation,
    );
    final endpoint = await opening.timeout(operationTimeout);
    _check(old);
    return _reattach(
      id,
      endpoint: endpoint,
      codec: stream.codec.name,
      captureGeneration: captureGeneration,
    );
  }

  /// 附着捕获所有者提供的新代际，不启动或停止应用。
  /// 候选生成核验通过的解码图像后才释放旧纹理，候选失败保留旧纹理。
  Future<VideoOutputReceipt> _reattach(
    String id, {
    required MediaCodecSource endpoint,
    String? codec,
    int? captureGeneration,
  }) async {
    final old = _entry(id);
    _check(old);
    final generation = endpoint.generation;
    if (generation <= old.generation || _pending.containsKey(id)) {
      throw const RequestFailure('generation_changed', '请等待当前重配置，或提供更新的画面版本。');
    }
    final nextCodec = codec ?? endpoint.codec;
    _validateCodec(nextCodec);
    if (_entries.length + _pending.length + _retiring.length >= 16) {
      throw const RequestFailure('resource_busy', '视频输出数量已达上限。');
    }
    final candidate = _Output(
      id,
      old.device,
      nextCodec,
      generation,
      old.createPlayer,
      old.cancelled,
      playback: old.playback,
      captureGeneration: captureGeneration ?? old.captureGeneration,
    );
    candidate.relay = endpoint.sourceId;
    _pending[id] = candidate;
    _armStartup(candidate);
    try {
      await _prepare(candidate, endpoint);
      _check(candidate);
      if (!identical(_entries[id], old)) throw _cancelled();
      // 呈现属于逻辑会话；恢复可能仍在等待旧播放器状态回调或快照，代际替换不能被旧播放器阻塞。
      var appliedPaused = false;
      while (appliedPaused != candidate.playback.paused) {
        appliedPaused = candidate.playback.paused;
        await _await(candidate, _setPaused(candidate, appliedPaused));
      }
      _check(candidate);
      _pending.remove(id);
      _entries[id] = candidate;
      final receipt = _receipt(candidate);
      candidate.ready = Future.value(receipt);
      emit(VideoOutputChanged(receipt));
      await _release(old);
      _check(candidate);
      return receipt;
    } catch (error) {
      if (identical(_pending[id], candidate)) _pending.remove(id);
      await _release(candidate);
      throw _failure(error, candidate);
    }
  }

  Future<VideoOutputReceipt> pause(String id) => _presentation(id, true);
  Future<VideoOutputReceipt> resume(String id) => _presentation(id, false);
  Future<VideoOutputReceipt> _presentation(String id, bool paused) {
    final playback = _entry(id).playback;
    if (++playback.queuedControls > 8) {
      playback.queuedControls--;
      throw const RequestFailure('renderer_busy', '视频状态操作过于频繁，请稍后再试。');
    }
    final operation = playback.control.then((_) async {
      playback.paused = paused;
      // 代际替换不能被阻塞的旧播放器阻挡。
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
      throw const RequestFailure('renderer_busy', '画面正在连续调整，请稍后重试。');
    });
    playback.control = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation.whenComplete(() => playback.queuedControls--);
  }

  Future<VideoOutputReceipt> _applyPresentation(
    _Output entry,
    bool paused,
  ) async {
    _check(entry);
    // 前次请求可能在状态回调前超时；即使请求状态看似不变，也要求播放器确认。
    await _await(entry, _setPaused(entry, paused), operationTimeout);
    _check(entry);
    if (!paused) await _verifyFrame(entry);
    _check(entry);
    return _receipt(entry);
  }

  Future<void> _setPaused(_Output entry, bool paused) =>
      entry.player.setPaused(paused);

  Future<void> _verifyFrame(_Output entry) async {
    // open() 确认解码并返回 Flutter 挂载所需纹理。
    // 光栅消费者在此回执后才存在，不能在此等待延迟导入；后续成功或失败单独取证。
    _check(entry);
    entry.decodedReceipts++;
  }

  Future<VideoPixels?> _pixels(_Output entry, int width, int height) async {
    _check(entry);
    if (entry.snapshotBusy) {
      throw const RequestFailure('renderer_busy', '正在读取当前画面，请稍后再试。');
    }
    entry.snapshotBusy = true;
    final pending = Future<VideoPixels?>.sync(
      () => entry.player.snapshot(width: width, height: height),
    );
    // 超时回读仍持有原生资源；超时不会取消原生回调，不能向同一槽位再次请求。
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

  /// 调用方提供应用持有的目录；新子目录避免覆盖用户文件，结果中说明任何分辨率缩减。
  Future<VideoScreenshot> screenshot(
    String id, {
    required String directory,
  }) async {
    final entry = _entry(id);
    _check(entry);
    final size = entry.texture;
    if (size == null || entry.decodedReceipts == 0) {
      throw const RequestFailure('no_frame', '当前没有可保存的画面。');
    }
    final root = Directory(directory);
    if (!root.isAbsolute || !await root.exists()) {
      throw const RequestFailure('invalid_path', '截图目录尚未准备好。');
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
      throw const RequestFailure('capture_failed', '未能读取实际视频帧。');
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
      return VideoScreenshot(
        sessionId: id,
        deviceId: entry.device,
        generation: entry.generation,
        localPath: file.path,
        width: pixels.width,
        height: pixels.height,
        scaled: factor < 1,
        paused: entry.playback.paused,
      );
    } catch (_) {
      if (owned != null) await owned.delete(recursive: true);
      rethrow;
    }
  }

  List<VideoDecoderCapability> capabilities() => List.unmodifiable([
    for (final codec in VideoCodec.values)
      VideoDecoderCapability(
        codec: codec,
        evidence: _verifiedCodecs.contains(codec.name) ? .verified : .unknown,
        canAttempt: true,
        reason: _verifiedCodecs.contains(codec.name)
            ? '本进程已取得该编码的实际解码帧。'
            : '需打开实际视频流后确认本机解码能力。',
      ),
  ]);

  Future<MediaOutputStop> stop(String id, {RequestFailure? failure}) async {
    _stopped.add(id);
    if (_stopped.length > 4096) _stopped.remove(_stopped.first);
    final entries = [
      _entries.remove(id),
      _pending.remove(id),
      ..._retiring.where((entry) => entry.id == id),
    ].whereType<_Output>().toSet();
    for (final entry in entries) {
      entry.terminalFailure ??= failure;
      entry.cancel();
    }
    final cleanup = await Future.wait(entries.map(_release));
    return MediaOutputStop(id, cleanup);
  }

  Future<void> stopDevice(String deviceId) async {
    final ids = {..._entries.values, ..._pending.values, ..._retiring}
        .where((entry) => entry.device == deviceId)
        .map((entry) => entry.id)
        .toSet();
    await Future.wait(ids.map(stop));
    _checkReleased(deviceId);
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    try {
      await Future.wait(
        {
          ..._entries.keys,
          ..._pending.keys,
          ..._retiring.map((entry) => entry.id),
        }.map(stop),
      );
      _checkReleased();
    } catch (_) {
      _disposing = null;
      rethrow;
    }
  }

  void _checkReleased([String? device]) {
    if (_retiring.any((entry) => device == null || entry.device == device)) {
      throw const RequestFailure(
        'video_cleanup_unconfirmed',
        '视频输出尚未确认释放，请沿原所有者重试。',
      );
    }
  }

  Future<MediaOutputRelease> _release(_Output entry) {
    entry.cancel();
    _retiring.add(entry);
    final future = entry.releasing ??= _releaseOnce(entry).then((receipt) {
      entry.releasing = null;
      if (receipt.confirmed) {
        _retiring.remove(entry);
      }
      return receipt;
    });
    // 等待期限只约束调用方；真实释放仍在登记中，迟到回执前不能重复启动。
    return future.timeout(
      operationTimeout,
      onTimeout: () => const MediaOutputRelease.unknown(disposeRequested: true),
    );
  }

  Future<MediaOutputRelease> _releaseOnce(_Output entry) async {
    var released =
        entry.releaseReceipt ??
        const MediaOutputRelease.unknown(disposeRequested: true);
    var failed = false;
    try {
      await Future.wait([
        Future<void>.sync(() async {
          await entry.observer?.cancel();
          entry.observer = null;
        }),
        Future<void>.sync(() async {
          if (entry.releaseReceipt != null) return;
          released = await entry.player.release();
          if (released.confirmed) {
            entry.releaseReceipt = released;
          }
        }),
      ]);
    } catch (_) {
      failed = true;
    }
    if (failed || !released.nativeDeleteConfirmed) {
      released = released.markUnconfirmed();
    }
    _diagnostics.release(DiagnosticArea.video, entry.id, released);
    return released;
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

  RequestFailure _aborted(_Output entry) =>
      entry.terminalFailure ??
      (entry.timedOut
          ? RequestFailure('video_timeout', '视频准备超过时限，已有画面保持不变。', {
              'diagnostics': [
                for (final event in entry.diagnostics)
                  event.toDiagnosticFields(),
              ],
            })
          : _cancelled());
  RequestFailure _failure(Object error, _Output entry) =>
      error is RequestFailure
      ? error
      : error is PlatformException &&
            const {
              'media_codec_create',
              'media_codec_handle',
              'media_codec_operation',
            }.contains(error.code)
      ? RequestFailure(error.code, '本机视频输出未能初始化或完成操作。')
      : RequestFailure(
          error is TimeoutException ? 'video_timeout' : 'decoder_error',
          error is TimeoutException ? '视频输出未在时限内确认。' : '视频输出未能完成，请检查实际媒体输入。',
          {
            'diagnostics': [
              for (final event in entry.diagnostics) event.toDiagnosticFields(),
            ],
          },
        );

  _Output _entry(String id) {
    _checkOwner();
    return _entries[id] ??
        (throw const RequestFailure('session_required', '该视频输出已结束。'));
  }

  VideoOutputReceipt _receipt(_Output entry) => VideoOutputReceipt(
    decoder: entry.decoder,
    sessionId: entry.id,
    deviceId: entry.device,
    relayId: entry.relay!,
    textureId: entry.texture!.id,
    decodedWidth: entry.texture!.width,
    decodedHeight: entry.texture!.height,
    codec: entry.codec,
    generation: entry.generation,
    captureGeneration: entry.captureGeneration,
    paused: entry.playback.paused,
    frameCount: entry.frameCount > 0 ? entry.frameCount : null,
    decodedReceipts: entry.decodedReceipts,
    snapshotReceipts: entry.snapshotReceipts,
    startupTimingMs: Map.unmodifiable(entry.startupTimingMs),
  );
}

class _Output {
  _Output(
    this.id,
    this.device,
    this.codec,
    this.generation,
    this.createPlayer,
    this.cancelled, {
    _Playback? playback,
    this.captureGeneration = 1,
  }) : player = createPlayer(),
       playback = playback ?? _Playback();
  final String id, device, codec;
  final int generation, captureGeneration;
  final VideoPlayerFactory createPlayer;
  final VideoPlayer player;
  final bool Function()? cancelled;
  final _Playback playback;
  final cancellation = StreamController<void>.broadcast(sync: true);
  final diagnostics = <MediaPlayerEvent>[];
  VideoDecoderMetadata decoder = const VideoDecoderMetadata();
  final startupClock = Stopwatch()..start();
  final startupTimingMs = <String, int>{};
  Future<VideoOutputReceipt>? ready;
  Future<MediaOutputRelease>? releasing;
  MediaOutputRelease? releaseReceipt;
  String? relay;
  StreamSubscription<MediaPlayerEvent>? observer;
  VideoTexture? texture;
  RequestFailure? terminalFailure;
  bool closed = false, snapshotBusy = false;
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

RequestFailure _cancelled() =>
    const RequestFailure('cancelled', '此视频操作已结束，不会恢复旧画面。');
void _validateCapture(VideoCapture stream) {
  if ([stream.sessionId, stream.deviceId, stream.captureRef].any(
    (value) => value.isEmpty || value.length > 256 || value.contains('\u0000'),
  )) {
    throw const RequestFailure('invalid_endpoint', '视频源身份无效。');
  }
  if (stream.generation < 1 || stream.captureGeneration < 1) {
    throw const RequestFailure('invalid_endpoint', '视频版本无效。');
  }
  if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(stream.videoSourceId)) {
    throw const RequestFailure('invalid_endpoint', '缺少有效的原生视频源。');
  }
}

void _validateCodec(String codec) {
  if (!VideoCodec.values.any((item) => item.name == codec)) {
    throw const RequestFailure('invalid_codec', '未知视频编码。');
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
      throw const RequestFailure('capture_failed', '截图编码未完成。');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
}
