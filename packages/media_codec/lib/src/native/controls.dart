import 'dart:ffi';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'generated/api.dart';
import 'generated/frb_generated.dart';

// 每个 isolate、每个原生库独立登记；与 ADB/scrcpy 同时初始化时也必须保留。
final _shutdownWatchers = <int, _ShutdownWatcher>{};
Future<void>? _initializing;
int? _libraryAnchor;

final class _ShutdownWatcher implements Finalizable {
  _ShutdownWatcher(Pointer<NativeFinalizerFunction> callback)
    : _finalizer = NativeFinalizer(callback) {
    _finalizer.attach(this, nullptr);
  }
  final NativeFinalizer _finalizer;
}

Future<void> _initialize(String path, int anchor) async {
  // 生成器提供的 mock 不加载原生库；生产实现始终核对平台返回的同库锚点。
  if (MediaCodecRustLib.instance.initialized && _initializing == null) {
    return;
  }
  if (_libraryAnchor != null && _libraryAnchor != anchor) {
    throw StateError('Media controls belong to a different native library');
  }
  _libraryAnchor = anchor;
  await (_initializing ??= Future<void>.microtask(() async {
    try {
      final library = ExternalLibrary.open(path);
      final dynamicLibrary = library.ffiDynamicLibrary;
      if (dynamicLibrary.lookup<Void>('frb_get_rust_content_hash').address !=
          anchor) {
        throw StateError('Media controls do not match the platform library');
      }
      final createCallback = dynamicLibrary
          .lookup<NativeFunction<Pointer<NativeFinalizerFunction> Function()>>(
            'frb_create_shutdown_callback',
          );
      _shutdownWatchers.putIfAbsent(
        createCallback.address,
        () => _ShutdownWatcher(
          createCallback
              .asFunction<Pointer<NativeFinalizerFunction> Function()>()(),
        ),
      );
      await MediaCodecRustLib.init(externalLibrary: library);
    } catch (_) {
      _initializing = null;
      _libraryAnchor = null;
      rethrow;
    }
  }));
}

/// 借用平台持有的 Rust 解码器，仅平台可销毁。
final class NativeControls {
  NativeControls._(this._controlId);

  static Future<NativeControls> connect(Map<String, dynamic> created) async {
    final id = created['controlId'];
    final path = created['nativeLibraryPath'];
    final anchor = created['frbAnchorAddress'];
    if (id is! int ||
        id <= 0 ||
        path is! String ||
        path.isEmpty ||
        anchor is! int ||
        anchor == 0) {
      throw StateError('Native decoder controls are unavailable');
    }
    await _initialize(path, anchor);
    return NativeControls._(id);
  }

  int? _controlId;
  int get _id =>
      _controlId ?? (throw StateError('Native controls were released'));

  Map<String, dynamic> readStatus() {
    final value = mediaStatus(controlId: _id);
    return {
      'width': value.width,
      'height': value.height,
      'frameCount': value.frameCount,
      'presentedFrameCount': value.presentedFrameCount,
      'presentedSequence': value.presentedSequence,
      'presentationPath': value.presentationPath,
      'presentationError': value.presentationError,
      'audioPlayedFrames': value.audioPlayedFrames,
      'audioQueuedFrames': value.audioQueuedFrames,
      'audioDroppedFrames': value.audioDroppedFrames,
      'bytesWritten': value.bytesWritten,
      'positionMs': value.positionMs,
      'hardwareAccelerated': value.hardwareAccelerated,
      'backendHardwareFrames': value.backendHardwareFrames,
      'hardwareVerification': switch (value.hardwareVerification) {
        1 => 'hardware',
        0 => 'software',
        _ => 'unknown',
      },
      'nativeReady': value.nativeReady,
      'firstFrame': value.firstFrame,
      'paused': value.paused,
      'ended': value.ended,
      'errorCode': value.errorCode,
      'decoderName': value.decoderName,
      'error': value.error,
    };
  }

  void setPaused(bool paused) => mediaSetPaused(controlId: _id, paused: paused);
  void setVolume(double volume) =>
      mediaSetVolume(controlId: _id, volume: volume);
  void release() => _controlId = null;
}
