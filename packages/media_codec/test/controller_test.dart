import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_codec/media_codec.dart';
import 'package:media_codec/src/native_bindings.g.dart';

final source = MediaCodecSource(
  sourceId: 'process-local-source',
  generation: 1,
  codec: 'h264',
  attachAddress: 1,
  detachAddress: 2,
  width: 320,
  height: 720,
);

class FakeNative {
  FakeNative() {
    read =
        NativeCallable<
          Void Function(Pointer<mc_decoder>, Pointer<mc_status>)
        >.isolateLocal((
          Pointer<mc_decoder> decoder,
          Pointer<mc_status> status,
        ) {
          expect(destroyed, isFalse, reason: 'read after native destroy');
          observedDecoder = decoder.address;
          reads++;
          status.ref
            ..width = width
            ..height = height
            ..frame_count = frameCount
            ..presented_frame_count = preparedSequence > 0 ? 1 : 0
            ..presented_sequence = preparedSequence
            ..bytes_written = 1920
            ..position_us = 123000
            ..hardware_accelerated = hardware ? 1 : 0
            ..native_ready = 1
            ..paused = paused ? 1 : 0
            ..error_code = errorCode
            ..ended = ended ? 1 : 0;
          for (var index = 0; index < decoderName.length; index++) {
            status.ref.decoder_name[index] = decoderName.codeUnitAt(index);
          }
          for (var index = 0; index < error.length; index++) {
            status.ref.error[index] = error.codeUnitAt(index);
          }
          status.ref.error[error.length] = 0;
          status.ref.presentation_error[presentationError.length] = 0;
          for (var index = 0; index < presentationError.length; index++) {
            status.ref.presentation_error[index] = presentationError.codeUnitAt(
              index,
            );
          }
        });
    pause =
        NativeCallable<Void Function(Pointer<mc_decoder>, Int32)>.isolateLocal((
          Pointer<mc_decoder> decoder,
          int value,
        ) {
          expect(destroyed, isFalse, reason: 'control after native destroy');
          observedDecoder = decoder.address;
          paused = value != 0;
        });
    volume =
        NativeCallable<Void Function(Pointer<mc_decoder>, Double)>.isolateLocal(
          (Pointer<mc_decoder> decoder, double value) {
            expect(destroyed, isFalse, reason: 'volume after native destroy');
            observedDecoder = decoder.address;
            lastVolume = value;
          },
        );
  }
  late final NativeCallable<
    Void Function(Pointer<mc_decoder>, Pointer<mc_status>)
  >
  read;
  late final NativeCallable<Void Function(Pointer<mc_decoder>, Int32)> pause;
  late final NativeCallable<Void Function(Pointer<mc_decoder>, Double)> volume;
  final memory = calloc<Uint8>();
  bool destroyed = false, paused = false;
  int reads = 0, frameCount = 4, width = 320, height = 720;
  int? decoderAddressOverride, observedDecoder;
  int preparedSequence = 0;
  String presentationError = '', error = '';
  int errorCode = 0;
  bool ended = false;
  bool hardware = true;
  String decoderName = 'test_h264';
  double lastVolume = 1;
  Map<String, Object> get created => {
    'handle': 42,
    'textureId': 7,
    'width': 320,
    'height': 720,
    'decoderAddress': decoderAddressOverride ?? memory.address,
    'nativeApi': {
      'getStatusAddress': read.nativeFunction.address,
      'setPausedAddress': pause.nativeFunction.address,
      'setVolumeAddress': volume.nativeFunction.address,
    },
  };
  void close() {
    read.close();
    pause.close();
    volume.close();
    calloc.free(memory);
  }
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
    native.close();
  });

  test(
    'Android arm64 tagged decoder reaches the first frame without detaching',
    () async {
      // JNI jlong and StandardMethodCodec preserve this non-null pointer's bits
      // as a negative Dart int. The native callbacks treat the decoder as opaque,
      // so this exercises the real FFI handoff without dereferencing ARM TBI
      // addresses on a host which does not implement TBI.
      final tagged = native.memory.address | 0xb400000000000000;
      expect(tagged, isNegative);
      native.decoderAddressOverride = tagged;
      await controller.open(source);
      final frame = await controller.waitForFrame();
      expect(frame['firstFrame'], true);
      expect(native.observedDecoder, tagged);
      expect(calls, ['createVideo']);
      expect(native.destroyed, false);
      await controller.setPaused(true);
      expect(native.observedDecoder, tagged);
      expect(native.paused, true);
      await controller.setPaused(false);
      expect(native.observedDecoder, tagged);
      expect(native.paused, false);
      await controller.setVolume(.4);
      expect(native.observedDecoder, tagged);
      expect(native.lastVolume, .4);
      await controller.dispose();
      await controller.dispose();
      expect(calls, ['createVideo', 'dispose']);
      expect(native.destroyed, true);
    },
    skip: sizeOf<IntPtr>() != 8
        ? 'Android arm64 pointer-width regression'
        : false,
  );

  test(
    'null decoder is rejected and the platform output is released once',
    () async {
      native.decoderAddressOverride = 0;
      await expectLater(controller.open(source), throwsStateError);
      await controller.dispose();
      expect(native.reads, 0);
      expect(native.destroyed, true);
      expect(calls, ['createVideo', 'dispose']);
    },
  );

  test('reads status and applies controls through generated FFI', () async {
    await controller.open(source);
    expect(controller.currentStatus, containsPair('decoderName', 'test_h264'));
    expect(controller.currentStatus, containsPair('hardwareAccelerated', true));
    expect(controller.positionMs, 123);
    expect(controller.currentStatus.containsKey('decoderAddress'), isFalse);
    expect(controller.currentStatus.containsKey('nativeApi'), isFalse);
    await controller.setPaused(true);
    expect(native.paused, isTrue);
    expect(controller.currentStatus['paused'], isTrue);
    await controller.setVolume(.7, muted: true);
    expect(native.lastVolume, 0);
    await controller.setVolume(.7);
    expect(native.lastVolume, .7);
    await controller.refresh();
    expect(calls, ['createVideo']);
    await controller.dispose();
    expect(calls, ['createVideo', 'dispose']);
    await controller.dispose();
    expect(calls.where((value) => value == 'dispose'), hasLength(1));
  });

  test('publishes decoder selection only after actual video output', () async {
    final events = <Map<String, dynamic>>[];
    final subscription = controller.events.listen(events.add);
    native.frameCount = 0;
    await controller.open(source);
    await Future<void>.delayed(Duration.zero);
    expect(events.where((event) => event['kind'] == 'diagnostic'), isEmpty);

    // The selected name can stay identical when the first frame arrives.
    native.frameCount = 1;
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single['runtimeSelectionVerified'], true);
    expect(events.single['hardwareAccelerated'], true);

    // FFmpeg may then fall back internally; report the actual output change.
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
    'failure events retain native evidence with stable codes and stages',
    () async {
      final events = <Map<String, dynamic>>[];
      final subscription = controller.events.listen(events.add);
      await controller.open(source);
      native.errorCode = -1094995529;
      native.error = 'Invalid data found when processing input';
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event['kind'] == 'failed').last, {
        'kind': 'failed',
        'code': 'decoder_error',
        'stage': 'video_decode',
        'nativeError': -1094995529,
        'reason': 'Invalid data found when processing input',
      });
      native.presentationError = 'Native window post failed';
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event['kind'] == 'failed').last, {
        'kind': 'failed',
        'code': 'presentation_error',
        'stage': 'video_presentation',
        'nativeError': -1094995529,
        'reason': 'Native window post failed',
      });
      native.errorCode = 0;
      native.presentationError = '';
      native.ended = true;
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event['kind'] == 'failed').last, {
        'kind': 'failed',
        'code': 'media_source_ended',
        'stage': 'video_decode',
        'reason': 'Native packet source ended',
      });
      await subscription.cancel();
    },
  );

  test(
    'PCM failures identify the audio output without a fabricated native code',
    () async {
      await controller.dispose();
      native.destroyed = false;
      controller = MediaCodecController.audio(channel: channel);
      final events = <Map<String, dynamic>>[];
      final subscription = controller.events.listen(events.add);
      await controller.open(
        MediaCodecSource(
          sourceId: source.sourceId,
          generation: source.generation,
          codec: 'pcm_s16le',
          attachAddress: source.attachAddress,
          detachAddress: source.detachAddress,
        ),
      );
      native.presentationError = 'PCM write failed';
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event['kind'] == 'failed').last, {
        'kind': 'failed',
        'code': 'presentation_error',
        'stage': 'audio_output',
        'reason': 'PCM write failed',
      });
      native.presentationError = '';
      native.errorCode = -5;
      native.error = 'PCM sink rejected frames';
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event['kind'] == 'failed').last, {
        'kind': 'failed',
        'code': 'decoder_error',
        'stage': 'audio_output',
        'nativeError': -5,
        'reason': 'PCM sink rejected frames',
      });
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
      // Dimensions without a newer decoded frame are not sufficient evidence.
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

  test(
    'late create is drained once without dereferencing its decoder',
    () async {
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
    },
  );

  test(
    'invalid address table drains the successfully created output',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'createVideo') return {'handle': 42};
        if (call.method == 'dispose') {
          native.destroyed = true;
          return null;
        }
        fail('Unexpected platform round trip: ${call.method}');
      });
      await expectLater(controller.open(source), throwsStateError);
      await controller.dispose();
      expect(calls, ['createVideo', 'dispose']);
      expect(native.reads, 0);
    },
  );

  test(
    'generated ABI controls an actual Rust decoder',
    () async {
      final api = MediaCodecNative(
        DynamicLibrary.open(Platform.environment['MEDIA_CODEC_TEST_LIBRARY']!),
      );
      final config = calloc<mc_config>();
      config.ref
        ..struct_size = sizeOf<mc_config>()
        ..codec = 100
        ..generation = 1;
      final decoder = api.mc_create(config);
      calloc.free(config);
      expect(decoder.address, isNonZero);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'createVideo') {
          return {
            'handle': 42,
            'textureId': -1,
            'decoderAddress': decoder.address,
            'nativeApi': {
              'getStatusAddress': api.addresses.mc_get_status.address,
              'setPausedAddress': api.addresses.mc_set_paused.address,
              'setVolumeAddress': api.addresses.mc_set_volume.address,
            },
          };
        }
        if (call.method == 'dispose') {
          api.mc_destroy(decoder);
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
    },
    skip: Platform.environment['MEDIA_CODEC_TEST_LIBRARY'] == null
        ? 'Build Rust native core and set MEDIA_CODEC_TEST_LIBRARY for ABI integration.'
        : false,
  );
}
