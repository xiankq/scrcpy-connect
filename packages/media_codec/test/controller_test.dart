import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_codec/media_codec.dart';
import 'package:media_codec/src/native/generated/api.dart';
import 'package:media_codec/src/native/generated/frb_generated.dart';

final source = MediaCodecSource(
  sourceId: 'process-local-source',
  generation: 1,
  codec: 'h264',
  attachAddress: 1,
  detachAddress: 2,
  width: 320,
  height: 720,
);

class FakeNative implements MediaCodecRustLibApi {
  bool destroyed = false, paused = false;
  int reads = 0, frameCount = 4, width = 320, height = 720;
  int controlId = 9;
  int preparedSequence = 0;
  String presentationError = '';
  bool hardware = true;
  String decoderName = 'test_h264';
  double lastVolume = 1;

  void observe(int id) {
    expect(destroyed, isFalse, reason: 'FRB control after native destroy');
    expect(id, controlId);
  }

  @override
  MediaStatus crateApiMediaStatus({required int controlId}) {
    observe(controlId);
    reads++;
    return MediaStatus(
      width: width,
      height: height,
      frameCount: frameCount,
      presentedFrameCount: preparedSequence > 0 ? 1 : 0,
      presentedSequence: preparedSequence,
      presentationPath: '',
      presentationError: presentationError,
      audioPlayedFrames: 0,
      audioQueuedFrames: 0,
      audioDroppedFrames: 0,
      bytesWritten: 1920,
      positionMs: 123,
      hardwareAccelerated: hardware,
      backendHardwareFrames: false,
      hardwareVerification: -1,
      nativeReady: true,
      firstFrame: frameCount > 0,
      paused: paused,
      ended: false,
      errorCode: 0,
      decoderName: decoderName,
      error: '',
    );
  }

  @override
  void crateApiMediaSetPaused({required int controlId, required bool paused}) {
    observe(controlId);
    this.paused = paused;
  }

  @override
  void crateApiMediaSetVolume({
    required int controlId,
    required double volume,
  }) {
    observe(controlId);
    lastVolume = volume;
  }

  Map<String, Object> get created => {
    'handle': 42,
    'textureId': 7,
    'width': 320,
    'height': 720,
    'controlId': controlId,
    'nativeLibraryPath': '/mock/media_codec_plugin.so',
    'frbAnchorAddress': 1,
  };
}

// Only the platform-owned decoder fixture uses C ABI; all status and controls
// below go through the generated FRB bridge.
final class DecoderConfig extends Struct {
  @Uint32()
  external int structSize;
  @Uint32()
  external int codec;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint64()
  external int generation;
  @Array(9)
  external Array<Pointer<Void>> callbacks;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('media_codec_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeNative native;
  late MediaCodecController controller;
  late List<String> calls;

  setUp(() {
    native = FakeNative();
    MediaCodecRustLib.initMock(api: native);
    calls = [];
    controller = MediaCodecController.video(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'createVideo' || call.method == 'createAudio') {
        return native.created;
      }
      if (call.method == 'dispose') {
        native.destroyed = true;
        return null;
      }
      fail('Unexpected platform round trip: ${call.method}');
    });
  });
  tearDown(() async {
    await controller.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    MediaCodecRustLib.dispose();
  });

  test(
    'FRB controls keep the platform decoder identity through disposal',
    () async {
      await controller.open(source);
      final frame = await controller.waitForFrame();
      expect(frame['firstFrame'], true);
      await controller.setPaused(true);
      expect(native.paused, true);
      await controller.setPaused(false);
      expect(native.paused, false);
      await controller.setVolume(.4);
      expect(native.lastVolume, .4);
      await controller.dispose();
      await controller.dispose();
      expect(calls, ['createVideo', 'dispose']);
    },
  );

  test('invalid FRB control ID releases the platform output once', () async {
    native.controlId = 0;
    await expectLater(controller.open(source), throwsStateError);
    await controller.dispose();
    expect(native.reads, 0);
    expect(native.destroyed, true);
    expect(calls, ['createVideo', 'dispose']);
  });

  test(
    'paused event listeners cannot delay native disposal confirmation',
    () async {
      final subscription = controller.events.listen((_) {});
      subscription.pause();
      try {
        await controller.open(source);
        final receipt = await controller.dispose().timeout(
          const Duration(milliseconds: 100),
        );
        expect(native.destroyed, isTrue);
        expect(receipt['nativeDeleteConfirmed'], isTrue);
        expect(calls, ['createVideo', 'dispose']);
      } finally {
        await subscription.cancel();
      }
    },
  );

  test('publishes decoder selection only after actual video output', () async {
    final events = <Map<String, dynamic>>[];
    final subscription = controller.events.listen(events.add);
    native.frameCount = 0;
    await controller.open(source);
    await Future<void>.delayed(Duration.zero);
    expect(events.where((event) => event['kind'] == 'diagnostic'), isEmpty);

    // 首帧到达时，所选名称可能保持不变。
    native.frameCount = 1;
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single['runtimeSelectionVerified'], true);
    expect(events.single['hardwareAccelerated'], true);

    // FFmpeg 随后可能内部回退；应报告实际输出变化。
    native.decoderName = 'software_h264';
    native.hardware = false;
    native.frameCount = 2;
    await controller.refresh();
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(2));
    expect(events.last['hardwareAccelerated'], false);
    await subscription.cancel();
  });

  test(
    'decoded frame and platform texture preparation are separate evidence',
    () async {
      final events = <Map<String, dynamic>>[];
      final subscription = controller.events.listen(events.add);
      await controller.open(source);
      await controller.waitForFrame();
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where((event) => event['category'] == 'video.presentation'),
        isEmpty,
      );
      native.preparedSequence = 4;
      await controller.waitForPresentation();
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final presentation = events
          .where((event) => event['category'] == 'video.presentation')
          .single;
      expect(presentation['platformTexturePrepared'], true);
      expect(presentation['presentedToWidget'], false);
      expect(presentation['presentedSequence'], 4);
      await subscription.cancel();
    },
  );

  test(
    'platform import failure is reported even after successful decoding',
    () async {
      final events = <Map<String, dynamic>>[];
      final subscription = controller.events.listen(events.add);
      await controller.open(source);
      native.presentationError = 'EGL import failed';
      await expectLater(controller.waitForPresentation(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where((event) => event['kind'] == 'failed').last['reason'],
        'EGL import failed',
      );
      await subscription.cancel();
    },
  );

  test(
    'reports only new decoded dimensions, never per-frame or pre-frame',
    () async {
      final events = <Map<String, dynamic>>[];
      final subscription = controller.events.listen(events.add);
      native.frameCount = 0;
      await controller.open(source);
      native.frameCount = 1;
      await controller.refresh();
      native.width = 720;
      native.height = 320;
      // 没有更新的解码帧时，仅尺寸不足以构成证据。
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event['kind'] == 'metadata'), isEmpty);
      native.frameCount = 2;
      await controller.refresh();
      native.frameCount = 3;
      await controller.refresh();
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final dimensions = events.where((event) => event['kind'] == 'metadata');
      expect(dimensions, hasLength(1));
      expect(dimensions.single, {
        'kind': 'metadata',
        'category': 'video.dimensions',
        'generation': 1,
        'textureId': 7,
        'width': 720,
        'height': 320,
        'frameCount': 2,
      });
      await subscription.cancel();
    },
  );

  test(
    'dispose rejects queued control before releasing native memory',
    () async {
      await controller.open(source);
      final pending = controller.setPaused(true);
      final rejected = expectLater(pending, throwsStateError);
      await controller.dispose();
      await rejected;
      expect(native.paused, isFalse);
      final reads = native.reads;
      await controller.refresh();
      expect(native.reads, reads);
      await expectLater(controller.setVolume(.5), throwsStateError);
    },
  );

  for (final unconfirmed in [false, true]) {
    test(unconfirmed ? '销毁未确认时保留原句柄供重试' : '销毁失败后重试原输出且合并并发关闭', () async {
      var attempts = 0;
      final retry = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'createVideo') return native.created;
        if (call.method == 'dispose') {
          expect(call.arguments, {'handle': 42});
          if (++attempts == 1) {
            if (unconfirmed) return {'nativeDeleteConfirmed': false};
            throw PlatformException(code: 'dispose_failed');
          }
          await retry.future;
          native.destroyed = true;
          return null;
        }
        fail('Unexpected platform round trip: ${call.method}');
      });
      await controller.open(source);
      await expectLater(controller.dispose(), throwsA(anything));
      expect(native.destroyed, isFalse);
      final reads = native.reads;
      await controller.refresh();
      await expectLater(controller.setPaused(true), throwsStateError);
      expect(native.reads, reads);
      final first = controller.dispose();
      final second = controller.dispose();
      expect(identical(first, second), isTrue);
      retry.complete();
      final receipt = await first;
      expect(receipt['nativeDeleteConfirmed'], isTrue);
      await second;
      await controller.dispose();
      expect(attempts, 2);
      expect(native.destroyed, isTrue);
    });
  }

  test('创建后控制句柄无效且清理失败仍保留输出供关闭重试', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'createVideo') return {'handle': 42};
      if (call.method == 'dispose') {
        expect(call.arguments, {'handle': 42});
        if (++attempts == 1) throw PlatformException(code: 'dispose_failed');
        native.destroyed = true;
        return null;
      }
      fail('Unexpected platform round trip: ${call.method}');
    });
    await expectLater(
      controller.open(source),
      throwsA(isA<PlatformException>()),
    );
    expect(native.destroyed, isFalse);
    await controller.dispose();
    expect(native.destroyed, isTrue);
    expect(native.reads, 0);
    expect(attempts, 2);
  });

  test(
    'dispose waits for snapshot already using the native resource',
    () async {
      final snapshotStarted = Completer<void>();
      final snapshotReply = Completer<Map<String, Object>>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'createVideo' || call.method == 'createAudio') {
          return native.created;
        }
        if (call.method == 'snapshot') {
          snapshotStarted.complete();
          return snapshotReply.future;
        }
        if (call.method == 'dispose') {
          native.destroyed = true;
          return null;
        }
        fail('Unexpected platform round trip: ${call.method}');
      });
      await controller.open(source);
      final snapshot = controller.snapshot(width: 1, height: 1);
      await snapshotStarted.future;
      final disposing = controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(native.destroyed, isFalse);
      snapshotReply.complete({'width': 1, 'height': 1, 'rgba': Uint8List(4)});
      expect(await snapshot, isNotNull);
      await disposing;
      expect(native.destroyed, isTrue);
      expect(calls, ['createVideo', 'snapshot', 'dispose']);
    },
  );

  test('late create is drained once without borrowing FRB controls', () async {
    final created = Completer<Map<String, Object>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'createVideo') return created.future;
      if (call.method == 'dispose') {
        native.destroyed = true;
        return null;
      }
      fail('Unexpected platform round trip: ${call.method}');
    });
    final opening = controller.open(source);
    final disposing = controller.dispose();
    created.complete(native.created);
    await opening;
    await disposing;
    expect(native.reads, 0);
    expect(calls, ['createVideo', 'dispose']);
  });

  test(
    'FRB controls the platform-owned Rust decoder and rejects its stale ID',
    () async {
      MediaCodecRustLib.dispose();
      final path = Platform.environment['MEDIA_CODEC_TEST_LIBRARY']!;
      final library = DynamicLibrary.open(path);
      final create = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<DecoderConfig>),
            Pointer<Void> Function(Pointer<DecoderConfig>)
          >('mc_create');
      final destroy = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('mc_destroy');
      final getControlId = library
          .lookupFunction<
            Uint64 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('mc_control_id');
      final config = calloc<DecoderConfig>();
      config.ref
        ..structSize = sizeOf<DecoderConfig>()
        ..codec = 100
        ..generation = 1;
      final decoder = create(config);
      calloc.free(config);
      expect(decoder.address, isNonZero);
      final controlId = getControlId(decoder);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'createVideo') {
          return {
            'handle': 42,
            'textureId': -1,
            'controlId': controlId,
            'nativeLibraryPath': path,
            'frbAnchorAddress': library
                .lookup<Void>('frb_get_rust_content_hash')
                .address,
          };
        }
        if (call.method == 'dispose') {
          destroy(decoder);
          return null;
        }
        fail('Unexpected platform round trip: ${call.method}');
      });
      await controller.open(source);
      expect(controller.currentStatus['decoderName'], 'pcm_s16le');
      expect(controller.currentStatus['nativeReady'], isFalse);
      await controller.setPaused(true);
      expect(controller.currentStatus['paused'], isTrue);
      await controller.setPaused(false);
      expect(controller.currentStatus['paused'], isFalse);
      await controller.setVolume(.3);
      await controller.dispose();
      expect(calls, ['createVideo', 'dispose']);
      expect(() => mediaStatus(controlId: controlId), throwsA(anything));
    },
    skip: Platform.environment['MEDIA_CODEC_TEST_LIBRARY'] == null
        ? 'Build the Rust native core and set MEDIA_CODEC_TEST_LIBRARY for FRB integration.'
        : false,
  );
}
