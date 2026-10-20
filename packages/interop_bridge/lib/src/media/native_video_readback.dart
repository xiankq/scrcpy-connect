import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'video_player_port.dart';

const _asset = 'package:interop_bridge/src/rust/frb_generated.io.dart';

@Native<Uint64 Function(Uint64, Int32)>(
  symbol: 'readback_open',
  assetId: _asset,
)
external int _open(int player, int version);

@Native<Uint64 Function(Uint64, Uint64, Uint64, Int32, Int32)>(
  symbol: 'readback_snapshot',
  assetId: _asset,
)
external int _snapshot(
  int player,
  int token,
  int renderer,
  int width,
  int height,
);

@Native<Int32 Function(Uint64, Uint64, Pointer<Uint8>, Uint32)>(
  symbol: 'trace_poll',
  assetId: _asset,
)
external int _poll(int token, int request, Pointer<Uint8> output, int capacity);

@Native<Void Function(Uint64, Uint64)>(symbol: 'trace_close', assetId: _asset)
external void _close(int player, int token);

/// Bounded MDK renderer readback with native ownership and null-result checks.
/// A failed native snapshot is an ordinary missing frame, including when a
/// remote source ends during readback. Decoder tracing remains opt-in.
final class NativeVideoReadback {
  NativeVideoReadback(int player)
    : _player = player,
      _token = _open(player, mdk.version()) {
    if (_token == 0) {
      throw StateError(
        'Native video readback unavailable for this MDK version.',
      );
    }
  }

  final int _player, _token;
  bool _closed = false;
  bool _pending = false;

  // fvp's pinned Android adapter associates the renderer with a Flutter
  // texture. Other hosts use MDK's default renderer.
  static final _androidRenderer = Platform.isAndroid
      ? DynamicLibrary.open('libfvp.so').lookupFunction<
          Pointer<Void> Function(Int64),
          Pointer<Void> Function(int)
        >('MdkGetPlayerVid')
      : null;

  Future<VideoPixels?> snapshot({
    required int texture,
    required int width,
    required int height,
  }) async {
    if (_closed || _pending) {
      throw StateError('Native video readback closed or already pending.');
    }
    if (width <= 0 ||
        height <= 0 ||
        width > 4096 ||
        height > 4096 ||
        width * height > 8 * 1024 * 1024) {
      throw ArgumentError('Video readback exceeds the bounded image size.');
    }
    final renderer = _androidRenderer?.call(texture).address ?? 0;
    if (Platform.isAndroid && renderer == 0) {
      throw StateError('Native video renderer unavailable.');
    }
    final capacity = width * height * 4;
    final pixels = calloc<Uint8>(capacity);
    _pending = true;
    try {
      final request = _snapshot(_player, _token, renderer, width, height);
      if (request == 0) throw StateError('Native video readback rejected.');
      while (!_closed) {
        final length = _poll(_token, request, pixels, capacity);
        if (length == 0 || length == -4) {
          // A caller timeout cannot cancel MDK's callback. The player owner
          // retains this operation until native completion before disposal.
          await Future<void>.delayed(
            Duration(milliseconds: length == -4 ? 16 : 1),
          );
          continue;
        }
        if (length == -2) return null;
        if (length < 0 || length != capacity) {
          throw StateError('Native video readback failed: $length');
        }
        return VideoPixels(
          width,
          height,
          Uint8List.fromList(pixels.asTypedList(length)),
        );
      }
      return null;
    } finally {
      _pending = false;
      calloc.free(pixels);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // The player owner drains snapshots before closing. No Dart buffer is
    // retained by the native callback; it copies into owned Rust storage.
    _close(_player, _token);
  }
}
