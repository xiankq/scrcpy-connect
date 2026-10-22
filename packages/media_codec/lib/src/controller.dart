import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// A process-local native producer. Payload bytes never enter the Dart isolate.
/// Function addresses and source capabilities must not be persisted or logged.
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

/// Owns one decoder and texture, or one PCM output. The producer owns capture.
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
    final created = await _channel.invokeMapMethod<String, dynamic>(
      _audio ? 'createAudio' : 'createVideo',
      source.toMap(),
    );
    final handle = created?['handle'];
    if (handle is! int || handle <= 0)
      throw StateError('Invalid native output');
    _handle = handle;
    _status = {...?created};
    if (_disposed)
      return; // dispose waits for this creation and then drains it.
    await refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_disposed && !_polling) {
        unawaited(
          refresh().catchError((Object error) {
            if (!_disposed) _events.add({'kind': 'failed', 'reason': '$error'});
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
      final value = await _channel.invokeMapMethod<String, dynamic>('status', {
        'handle': _handle,
      });
      if (_disposed) return currentStatus;
      final previous = _status;
      _status = {..._status, ...?value};
      if ((_status['errorCode'] as int? ?? 0) != 0) {
        _events.add({
          'kind': 'failed',
          'reason': _status['error'] ?? 'Native decoder failed',
        });
      } else if (_status['ended'] == true && previous['ended'] != true) {
        _events.add({'kind': 'failed', 'reason': 'Native packet source ended'});
      }
      if (previous['decoderName'] != _status['decoderName'] ||
          previous['hardwareAccelerated'] != _status['hardwareAccelerated']) {
        _events.add({
          'kind': 'diagnostic',
          'category': 'decoder.video',
          'decoderName': _status['decoderName'],
          'hardwareAccelerated': _status['hardwareAccelerated'],
          'runtimeSelectionVerified': true,
        });
      }
      return currentStatus;
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
      if ((value['errorCode'] as int? ?? 0) != 0 || value['ended'] == true) {
        throw StateError('Native source failed before the first frame');
      }
      if ((value['frameCount'] as int? ?? 0) > 0 && width > 0 && height > 0)
        return value;
      if (watch.elapsed >= timeout)
        throw TimeoutException('No decoded frame', timeout);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Media output disposed');
  }

  Future<void> setPaused(bool paused) =>
      _control('setPaused', {'paused': paused});
  Future<void> setVolume(double volume, {bool muted = false}) {
    if (!volume.isFinite || volume < 0 || volume > 1)
      throw ArgumentError.value(volume, 'volume');
    return _control('setVolume', {'volume': volume, 'muted': muted});
  }

  Future<void> _control(String method, Map<String, Object> parameters) async {
    if (_disposed || _handle == null)
      throw StateError('Media output is not open');
    await _channel.invokeMethod<void>(method, {
      'handle': _handle,
      ...parameters,
    });
    await refresh();
  }

  Future<MediaCodecImage?> snapshot({
    required int width,
    required int height,
  }) async {
    if (_disposed || _handle == null)
      throw StateError('Media output is not open');
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
  }

  /// A late create is drained too. Return only after native source detachment.
  Future<Map<String, dynamic>> dispose() => _disposing ??= _dispose();
  Future<Map<String, dynamic>> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    try {
      await _opening;
    } catch (_) {
      /* A failed create owns no output. */
    }
    final handle = _handle;
    _handle = null;
    try {
      if (handle == null)
        return {'resourceAllocated': false, 'nativeDeleteConfirmed': true};
      return await _channel.invokeMapMethod<String, dynamic>('dispose', {
            'handle': handle,
          }) ??
          {'resourceAllocated': true, 'nativeDeleteConfirmed': true};
    } finally {
      await _events.close();
    }
  }
}
