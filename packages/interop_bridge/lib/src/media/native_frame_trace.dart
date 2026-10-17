import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'video_player_port.dart';

const _asset = 'package:interop_bridge/src/rust/frb_generated.io.dart';

@Native<Uint64 Function(Uint64, Int32)>(symbol: 'trace_open', assetId: _asset)
external int _open(int player, int version);

@Native<Void Function(Uint64, Uint64)>(symbol: 'trace_close', assetId: _asset)
external void _close(int player, int token);

@Native<Uint64 Function(Uint64, Uint64, Uint64, Int32, Int32)>(
  symbol: 'trace_snapshot',
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

@Native<Int32 Function(Uint64, Pointer<Uint8>, Uint32)>(
  symbol: 'trace_metrics',
  assetId: _asset,
)
external int _metrics(int token, Pointer<Uint8> output, int capacity);

/// Opt-in measurement of MDK decoded frames and renderer snapshots on one Rust
/// monotonic clock. No Dart callbacks run on decoder/render threads.
///
/// The pinned fvp 0.39.1 native renderer export is used only by this diagnostic
/// adapter; ordinary playback and snapshots use public Dart APIs. A successful
/// snapshot is a renderer observation, not a physical display scan-out time.
final class NativeFrameTrace {
  NativeFrameTrace(int player)
    : _player = player,
      _token = _open(player, mdk.version()) {
    if (_token == 0) {
      throw StateError('Native frame trace unavailable for this MDK version.');
    }
    _pixels = calloc<Uint8>(_pixelCapacity);
    _json = calloc<Uint8>(_jsonCapacity);
  }

  static const _pixelCapacity = 256 * 256 * 4;
  static const _jsonCapacity = 64 * 1024;
  final int _player, _token;
  late final Pointer<Uint8> _pixels, _json;
  bool _closed = false;
  bool _snapshotPending = false;

  // Matches fvp 0.39.1's renderer selection. Other platforms use MDK's default
  // renderer; Android has one native surface per Flutter texture.
  static final _androidRenderer = Platform.isAndroid
      ? DynamicLibrary.open('libfvp.so').lookupFunction<
          Pointer<Void> Function(Int64),
          Pointer<Void> Function(int)
        >('MdkGetPlayerVid')
      : null;

  VideoJson get metrics {
    if (_closed) throw StateError('Native frame trace closed.');
    final length = _metrics(_token, _json, _jsonCapacity);
    if (length <= 0 || length > _jsonCapacity) {
      throw StateError('Native frame trace metrics failed: $length');
    }
    return jsonDecode(utf8.decode(_json.asTypedList(length))) as VideoJson;
  }

  Future<VideoPixels?> snapshot({
    required int texture,
    required int width,
    required int height,
  }) async {
    if (_closed || _snapshotPending) {
      throw StateError('Native frame trace closed or snapshot pending.');
    }
    if (width <= 0 || height <= 0 || width > 256 || height > 256) {
      throw ArgumentError('Diagnostic snapshots require dimensions in 1..256.');
    }
    final renderer = _androidRenderer?.call(texture).address ?? 0;
    if (Platform.isAndroid && renderer == 0) {
      throw StateError('Native frame trace renderer unavailable.');
    }
    _snapshotPending = true;
    try {
      final request = _snapshot(_player, _token, renderer, width, height);
      if (request == 0) throw StateError('Native snapshot request rejected.');
      final watch = Stopwatch()..start();
      while (!_closed) {
        final length = _poll(_token, request, _pixels, _pixelCapacity);
        if (length < 0) throw StateError('Native snapshot failed: $length');
        if (length > 0) {
          if (length != width * height * 4 || length > _pixelCapacity) {
            throw StateError('Native snapshot returned unexpected dimensions.');
          }
          return VideoPixels(
            width,
            height,
            Uint8List.fromList(_pixels.asTypedList(length)),
          );
        }
        // Rust polls reclaim a missing callback after five seconds. If even
        // that contract fails, revoke the trace so no orphan request can block
        // all subsequent snapshots on this player.
        if (watch.elapsed > const Duration(seconds: 6)) {
          close();
          throw TimeoutException('Native diagnostic snapshot timed out.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return null;
    } finally {
      _snapshotPending = false;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    // Rust owns callback storage. Revoking the token makes late native calls
    // harmless; these Dart-owned output buffers never reach a native callback.
    _close(_player, _token);
    calloc.free(_pixels);
    calloc.free(_json);
  }
}
