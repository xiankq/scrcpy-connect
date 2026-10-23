import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_bindings.g.dart';

/// Borrows a platform-owned Rust decoder. Only the platform may destroy it.
/// Addresses are capabilities for this process and never enter public status.
final class NativeControls {
  NativeControls(Map<String, dynamic> created) {
    final decoder = created['decoderAddress'];
    final api = created['nativeApi'];
    if (decoder is! int || decoder <= 0 || api is! Map) {
      throw StateError('Native decoder controls are unavailable');
    }
    final addresses = <String, int>{};
    for (final entry in const {
      'mc_get_status': 'getStatusAddress',
      'mc_set_paused': 'setPausedAddress',
      'mc_set_volume': 'setVolumeAddress',
    }.entries) {
      final address = api[entry.value];
      if (address is! int || address <= 0) {
        throw StateError('Native decoder controls are incomplete');
      }
      addresses[entry.key] = address;
    }
    _decoder = Pointer<mc_decoder>.fromAddress(decoder);
    _api = MediaCodecNative.fromLookup(
      <T extends NativeType>(String symbol) =>
          Pointer<T>.fromAddress(addresses[symbol]!),
    );
    _status = calloc<mc_status>();
  }

  late final Pointer<mc_decoder> _decoder;
  late final MediaCodecNative _api;
  Pointer<mc_status>? _status;

  Map<String, dynamic> readStatus() {
    final status = _status;
    if (status == null) throw StateError('Native controls were released');
    _api.mc_get_status(_decoder, status);
    final value = status.ref;
    String text(Array<Char> bytes, int limit) {
      final values = <int>[];
      for (var index = 0; index < limit && bytes[index] != 0; index++) {
        values.add(bytes[index] & 0xff);
      }
      return utf8.decode(values, allowMalformed: true);
    }

    return {
      'width': value.width,
      'height': value.height,
      'frameCount': value.frame_count,
      'presentedFrameCount': value.presented_frame_count,
      'presentedSequence': value.presented_sequence,
      'presentationPath': text(value.presentation_path, 96),
      'presentationError': text(value.presentation_error, 192),
      'audioPlayedFrames': value.audio_played_frames,
      'audioQueuedFrames': value.audio_queued_frames,
      'audioDroppedFrames': value.audio_dropped_frames,
      'bytesWritten': value.bytes_written,
      'positionMs': value.position_us ~/ 1000,
      'hardwareAccelerated': value.hardware_accelerated != 0,
      'backendHardwareFrames': value.backend_hardware_frames != 0,
      'hardwareVerification': switch (value.hardware_verification) {
        1 => 'hardware',
        0 => 'software',
        _ => 'unknown',
      },
      'nativeReady': value.native_ready != 0,
      'firstFrame': value.frame_count > 0,
      'paused': value.paused != 0,
      'ended': value.ended != 0,
      'errorCode': value.error_code,
      'decoderName': text(value.decoder_name, 96),
      'error': text(value.error, 192),
    };
  }

  void setPaused(bool paused) {
    if (_status == null) throw StateError('Native controls were released');
    _api.mc_set_paused(_decoder, paused ? 1 : 0);
  }

  void setVolume(double volume) {
    if (_status == null) throw StateError('Native controls were released');
    _api.mc_set_volume(_decoder, volume);
  }

  void release() {
    final status = _status;
    _status = null;
    if (status != null) calloc.free(status);
  }
}
