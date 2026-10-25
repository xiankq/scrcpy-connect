import 'dart:async';

import 'package:flutter/services.dart';

import 'native/controls.dart';

/// 进程内的原生媒体生产者；负载字节不进入 Dart isolate。
/// 函数地址和源能力不能持久化或写入日志。
class MediaCodecSource {
  MediaCodecSource({
    required this.sourceId,
    required this.generation,
    required this.codec,
    required this.attachAddress,
    required this.detachAddress,
    this.width = 0,
    this.height = 0,
  }) {
    if (sourceId.isEmpty ||
        sourceId.length > 256 ||
        generation < 1 ||
        attachAddress <= 0 ||
        detachAddress <= 0 ||
        !const [
          'h264',
          'h265',
          'av1',
          'vp8',
          'vp9',
          'pcm_s16le',
        ].contains(codec) ||
        width < 0 ||
        height < 0 ||
        width > 16384 ||
        height > 16384) {
      throw ArgumentError('Invalid native media source');
    }
  }

  factory MediaCodecSource.fromMap(Map<String, dynamic> value) =>
      MediaCodecSource(
        sourceId: value['sourceId'] as String,
        generation: value['generation'] as int,
        codec: value['codec'] as String,
        attachAddress: value['attachAddress'] as int,
        detachAddress: value['detachAddress'] as int,
        width: value['width'] as int? ?? 0,
        height: value['height'] as int? ?? 0,
      );

  final String sourceId, codec;
  final int generation, attachAddress, detachAddress, width, height;
  Map<String, Object> toMap() => {
    'sourceId': sourceId,
    'generation': generation,
    'codec': codec,
    'attachAddress': attachAddress,
    'detachAddress': detachAddress,
    'width': width,
    'height': height,
  };
}

class MediaCodecImage {
  const MediaCodecImage(this.width, this.height, this.rgba);
  final int width, height;
  final Uint8List rgba;
}

/// 持有一个解码器及纹理，或一个 PCM 输出；捕获由生产者持有。
class MediaCodecController {
  MediaCodecController.video({MethodChannel? channel})
    : _audio = false,
      _channel = channel ?? const MethodChannel('media_codec');
  MediaCodecController.audio({MethodChannel? channel})
    : _audio = true,
      _channel = channel ?? const MethodChannel('media_codec');

  final bool _audio;
  final MethodChannel _channel;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic> _status = const {};
  Stream<Map<String, dynamic>> get events => _events.stream;
  Map<String, dynamic> get currentStatus => Map.unmodifiable(_status);
  int? get textureId => _status['textureId'] as int?;
  int get width => _status['width'] as int? ?? 0;
  int get height => _status['height'] as int? ?? 0;
  int get positionMs => _status['positionMs'] as int? ?? 0;
  int? _handle;
  NativeControls? _native;
  (String, bool, String?)? _publishedSelection;
  (int, int)? _decodedDimensions;
  int _observedFrameCount = 0, _generation = 0, _presentedSequence = 0;
  Future<void> _operations = Future<void>.value();
  bool _disposed = false, _polling = false;
  Timer? _timer;
  Future<void>? _opening;
  Future<Map<String, dynamic>>? _disposing;

  Future<void> open(MediaCodecSource source) {
    if (_disposed || _opening != null || _handle != null) {
      throw StateError('This media output has already been opened or disposed');
    }
    return _opening = _open(source);
  }

  Future<void> _open(MediaCodecSource source) async {
    _generation = source.generation;
    final created = await _channel.invokeMapMethod<String, dynamic>(
      _audio ? 'createAudio' : 'createVideo',
      source.toMap(),
    );
    final handle = created?['handle'];
    if (handle is! int || handle <= 0) {
      throw StateError('Invalid native output');
    }
    _handle = handle;
    _status = {...?created}
      ..removeWhere(
        (key, _) => const {
          'controlId',
          'nativeLibraryPath',
          'frbAnchorAddress',
        }.contains(key),
      );
    if (_disposed) {
      return; // dispose 会等待本次创建，然后排空输出。
    }
    try {
      _native = await NativeControls.connect(created!);
    } catch (_) {
      _disposed = true;
      await _releaseOutput();
      rethrow;
    }
    await refresh();
    if (_disposed) return;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_disposed && !_polling) {
        unawaited(
          refresh().catchError((Object error) {
            if (!_disposed) {
              _events.add({
                'kind': 'failed',
                'code': 'native_status_error',
                'stage': 'status_poll',
                'reason': '$error',
              });
            }
            return <String, dynamic>{};
          }),
        );
      }
    });
  }

  Future<Map<String, dynamic>> refresh() async {
    if (_disposed || _handle == null || _polling) return currentStatus;
    _polling = true;
    try {
      final value = await _run(() => _native!.readStatus());
      if (_disposed) return currentStatus;
      final previous = _status;
      _status = {..._status, ...value};
      final nativeError = _status['errorCode'] as int? ?? 0;
      final presentationError = _status['presentationError'] as String? ?? '';
      if (nativeError != 0 || presentationError.isNotEmpty) {
        final presentation = presentationError.isNotEmpty;
        _events.add({
          'kind': 'failed',
          'code': presentation ? 'presentation_error' : 'decoder_error',
          'stage': _audio
              ? 'audio_output'
              : presentation
              ? 'video_presentation'
              : 'video_decode',
          if (nativeError != 0) 'nativeError': nativeError,
          'reason': presentation
              ? presentationError
              : _status['error'] ?? 'Native decoder failed',
        });
      } else if (_status['ended'] == true && previous['ended'] != true) {
        _events.add({
          'kind': 'failed',
          'code': 'media_source_ended',
          'stage': _audio ? 'audio_output' : 'video_decode',
          'reason': 'Native packet source ended',
        });
      }
      final presented = _status['presentedSequence'] as int? ?? 0;
      if (!_audio && presented > _presentedSequence) {
        _presentedSequence = presented;
        _events.add({
          'kind': 'diagnostic',
          'category': 'video.presentation',
          'generation': _generation,
          'textureId': textureId,
          'presentedSequence': presented,
          'presentedFrameCount': _status['presentedFrameCount'],
          'presentationPath': _status['presentationPath'],
          'platformTexturePrepared': true,
          'presentedToWidget': false,
        });
      }
      final decoder = _status['decoderName'];
      final hasOutput = _audio
          ? _status['nativeReady'] == true
          : (_status['frameCount'] as int? ?? 0) > 0;
      final hardware = _status['hardwareAccelerated'] == true;
      final verification = _status['hardwareVerification'] as String?;
      if (hasOutput &&
          decoder is String &&
          decoder.isNotEmpty &&
          _publishedSelection != (decoder, hardware, verification)) {
        _publishedSelection = (decoder, hardware, verification);
        _events.add({
          'kind': 'diagnostic',
          'category': _audio ? 'decoder.audio' : 'decoder.video',
          'decoderName': _status['decoderName'],
          'hardwareAccelerated': _status['hardwareAccelerated'],
          'hardwareVerification': verification,
          'backendHardwareFrames': _status['backendHardwareFrames'],
          'runtimeSelectionVerified': true,
        });
      }
      if (!_audio && hasOutput) {
        final count = _status['frameCount'] as int;
        final w = width, h = height;
        if (count > _observedFrameCount && w > 0 && h > 0) {
          final dimensions = (w, h);
          final changed =
              _decodedDimensions != null && _decodedDimensions != dimensions;
          _observedFrameCount = count;
          _decodedDimensions = dimensions;
          if (changed) {
            _events.add({
              'kind': 'metadata',
              'category': 'video.dimensions',
              'generation': _generation,
              'textureId': textureId,
              'width': w,
              'height': h,
              'frameCount': count,
            });
          }
        }
      }
      return currentStatus;
    } catch (_) {
      if (_disposed) return currentStatus;
      rethrow;
    } finally {
      _polling = false;
    }
  }

  Future<Map<String, dynamic>> waitForFrame({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final watch = Stopwatch()..start();
    while (!_disposed) {
      final value = await refresh();
      if ((value['errorCode'] as int? ?? 0) != 0 ||
          (value['presentationError'] as String? ?? '').isNotEmpty ||
          value['ended'] == true) {
        throw StateError('Native source failed before the first frame');
      }
      if ((value['frameCount'] as int? ?? 0) > 0 && width > 0 && height > 0) {
        return value;
      }
      if (watch.elapsed >= timeout) {
        throw TimeoutException('No decoded frame', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Media output disposed');
  }

  /// 挂载 Texture 后调用；部分平台直到光栅化时才导入纹理。
  Future<Map<String, dynamic>> waitForPresentation({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final watch = Stopwatch()..start();
    while (!_disposed) {
      final value = await refresh();
      if ((value['presentationError'] as String? ?? '').isNotEmpty ||
          (value['errorCode'] as int? ?? 0) != 0 ||
          value['ended'] == true) {
        throw StateError('Native presentation failed');
      }
      if ((value['presentedFrameCount'] as int? ?? 0) > 0) return value;
      if (watch.elapsed >= timeout) {
        throw TimeoutException('No prepared platform texture', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Media output disposed');
  }

  Future<void> setPaused(bool paused) => _run(() {
    _native!.setPaused(paused);
    _status = {..._status, ..._native!.readStatus()};
  });

  Future<void> setVolume(double volume, {bool muted = false}) {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw ArgumentError.value(volume, 'volume');
    }
    return _run(() => _native!.setVolume(muted ? 0 : volume));
  }

  Future<T> _run<T>(FutureOr<T> Function() operation) {
    final result = _operations.then((_) {
      if (_disposed || _handle == null || _native == null) {
        throw StateError('Media output is not open');
      }
      return operation();
    });
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<MediaCodecImage?> snapshot({
    required int width,
    required int height,
  }) => _run(() async {
    if (width < 1 ||
        height < 1 ||
        width > 4096 ||
        height > 4096 ||
        width * height > 8 * 1024 * 1024) {
      throw ArgumentError('Snapshot dimensions exceed the readback limit');
    }
    final value = await _channel.invokeMapMethod<String, dynamic>('snapshot', {
      'handle': _handle,
      'width': width,
      'height': height,
    });
    if (value == null) return null;
    final w = value['width'] as int, h = value['height'] as int;
    final rgba = value['rgba'];
    if (rgba is! Uint8List ||
        w < 1 ||
        h < 1 ||
        w > 4096 ||
        h > 4096 ||
        w * h > 8 * 1024 * 1024 ||
        rgba.length != w * h * 4) {
      throw StateError('Invalid native snapshot');
    }
    return MediaCodecImage(w, h, rgba);
  });

  /// 迟到的创建也必须回收；原生媒体源分离后才能返回，失败保留同一输出供重试。
  Future<Map<String, dynamic>> dispose() => _disposing ??= _dispose();
  Future<Map<String, dynamic>> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    try {
      try {
        await _opening;
      } catch (_) {
        // 创建失败仍可能留有未确认释放的输出，继续按原句柄回收。
      }
      await _operations;
      final receipt = await _releaseOutput();
      // 暂停的外部订阅可延迟 done，不能延迟已确认的原生释放回执。
      unawaited(_events.close());
      return receipt;
    } catch (_) {
      _disposing = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _releaseOutput() async {
    // 停止借用 FRB 后仍保留平台句柄，只有平台销毁确认才能撤销清理责任。
    _native?.release();
    _native = null;
    final handle = _handle;
    if (handle == null) {
      return {'resourceAllocated': false, 'nativeDeleteConfirmed': true};
    }
    final receipt =
        await _channel.invokeMapMethod<String, dynamic>('dispose', {
          'handle': handle,
        }) ??
        {'resourceAllocated': true, 'nativeDeleteConfirmed': true};
    if (receipt['nativeDeleteConfirmed'] == false ||
        receipt['cleanupUnconfirmed'] == true) {
      throw StateError('Native media output disposal is unconfirmed');
    }
    _handle = null;
    return receipt;
  }
}
