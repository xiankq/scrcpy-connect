import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:interop_bridge/src/media/fvp_video_player.dart';
import 'package:interop_bridge/src/media/portable_video.dart';
import 'package:interop_bridge/src/media/video_presentation.dart';
import 'package:interop_bridge/src/rust/api.dart' as core;
import 'package:interop_bridge/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

import 'pixel_pattern.dart';

/// Agent-runnable measurement of the production ADB/media adapters with normal
/// Flutter frame scheduling. Driver screenshots arrive from the actual window;
/// this harness never pumps or rerasterizes the Texture to obtain them.
class LiveVideoBenchmark {
  static const roundCount = int.fromEnvironment(
    'CONNECT_PERF_ROUNDS',
    defaultValue: 3,
  );
  static const transitions = int.fromEnvironment(
    'CONNECT_PERF_TRANSITIONS',
    defaultValue: 4,
  );
  static const maxSize = int.fromEnvironment(
    'CONNECT_PERF_MAX_SIZE',
    defaultValue: 1280,
  );
  static const maxFps = int.fromEnvironment(
    'CONNECT_PERF_MAX_FPS',
    defaultValue: 60,
  );
  static const bitRate = int.fromEnvironment(
    'CONNECT_PERF_BIT_RATE',
    defaultValue: 8000000,
  );
  static const maxStartMs = int.fromEnvironment(
    'CONNECT_PERF_MAX_START_MS',
    defaultValue: 1000,
  );
  static const maxP50Ms = int.fromEnvironment(
    'CONNECT_PERF_MAX_P50_MS',
    defaultValue: 200,
  );
  static const maxP95Ms = int.fromEnvironment(
    'CONNECT_PERF_MAX_P95_MS',
    defaultValue: 300,
  );
  static const traceFrames = bool.fromEnvironment('CONNECT_PERF_TRACE_FRAMES');
  static const decoderPolicy = String.fromEnvironment(
    'CONNECT_PERF_DECODER',
    defaultValue: 'native',
  );

  final texture = ValueNotifier<VideoTexture?>(null);
  final textureKey = GlobalKey();
  final rounds = <VideoJson>[];
  final _decoderEvents = <VideoJson>[];
  late final _outputs = PortableVideoOutputs(
    core: _request,
    emit: (_) {},
    isDisposed: () => _disposed,
    playerFactory: () {
      final player = FvpVideoPlayer(
        traceFrames: traceFrames,
        videoDecoders: switch (decoderPolicy) {
          'native' => const ['AMediaCodec'],
          'native-async' => const ['AMediaCodec:async=1'],
          'software' => const ['FFmpeg:thread_type=slice'],
          _ => null,
        },
      );
      player.events.listen((event) {
        if (event['category'] == 'decoder.video' ||
            event['category'] == 'video.frameTrace') {
          _decoderEvents.add({...event});
        }
      });
      return _player = player;
    },
  );
  late final _presentation = VideoPresentation(
    core: _request,
    pauseOutput: _outputs.pause,
    resumeOutput: _outputs.resume,
  );
  FvpVideoPlayer? _player;
  String? _device, _session;
  VideoJson? _active, _ready;
  bool _busy = false, _initialized = false, _disposed = false;
  bool _releaseUnconfirmed = false;
  bool _closing = false;
  Future<void> _idle = Future<void>.value();
  Future<VideoJson>? _cleanupFuture;
  int _expected = 0;
  VideoJson? _cleanupReceipt;

  Future<String> handle(String? message) async {
    Completer<void>? operation;
    try {
      final command = jsonDecode(message ?? '{}') as VideoJson;
      if (command['command'] == 'cleanup') {
        // Host timeouts cannot cancel a native call. Queue cleanup behind its
        // actual completion, retaining this continuation if the host goes away.
        _closing = true;
        final pending = _cleanupFuture ??= () async {
          await _idle;
          return _cleanup();
        }();
        return jsonEncode({'ok': true, 'data': await pending});
      }
      _require(
        !_busy && !_closing,
        'A prior command is in flight or cleanup has begun.',
      );
      operation = Completer<void>();
      _idle = operation.future;
      _busy = true;
      final data = switch (command['command']) {
        'setup' => await _setup(),
        'start' => await _start(),
        'input' => await _input(),
        'pause' => await _pause(),
        'surface' => await _surface(command),
        'stop' => await _stop(),
        'finish' => _finish(),
        _ => throw StateError('Unknown benchmark command.'),
      };
      return jsonEncode({'ok': true, 'data': data});
    } catch (error) {
      // Never include one-time relay URLs/tokens in host artifacts.
      final detail = '$error'.replaceAll(
        RegExp(r'http://127\.0\.0\.1:\d+/[a-fA-F0-9]{64}'),
        '<local-media>',
      );
      return jsonEncode({'ok': false, 'error': detail});
    } finally {
      if (operation != null) {
        _busy = false;
        operation.complete();
      }
    }
  }

  Future<VideoJson> _request(
    String command, [
    VideoJson params = const {},
  ]) async {
    final result = jsonDecode(
      await core.invoke(
        requestJson: jsonEncode({
          'command': command,
          'params': {
            ...params,
            if (traceFrames &&
                (command == 'session.start' || command == 'media.open'))
              'traceFrames': true,
          },
        }),
      ),
    ) as VideoJson;
    if (result['ok'] != true) throw StateError('$command: ${result['error']}');
    return result['data'] as VideoJson;
  }

  Future<VideoJson> _setup() async {
    _require(!_initialized && !_disposed, 'Setup may run once.');
    _require(
      roundCount > 0 &&
          roundCount <= 20 &&
          transitions >= 2 &&
          transitions <= 100,
      'Invalid sample count.',
    );
    _require(
      maxSize >= 320 &&
          maxSize <= 4096 &&
          maxFps >= 1 &&
          maxFps <= 120 &&
          bitRate >= 500000 &&
          bitRate <= 50000000,
      'Invalid quality.',
    );
    _require(
      const [
        'native',
        'native-async',
        'software',
        'default',
      ].contains(decoderPolicy),
      'Unknown decoder policy.',
    );
    await RustLib.init();
    final directory = await getApplicationSupportDirectory();
    await core.initialize(
      dataDirectory: '${directory.path}/live-video-performance',
    );
    _initialized = true;
    final existing = (await _request('devices.list'))['devices'] as List;
    _require(
      existing.isEmpty ||
          const bool.fromEnvironment('CONNECT_PERF_RECOVER_RECORDS'),
      'Prior benchmark device records remain; inspect them before reusing this isolated directory.',
    );
    // Explicit recovery is confined to this benchmark's isolated runtime, never
    // the product's saved devices. Keep prior failed-run evidence untouched.
    for (final previous in existing.cast<VideoJson>()) {
      await _request('devices.disconnect', {'deviceId': previous['id']});
      await _request('devices.forget', {'deviceId': previous['id']});
    }
    await _request('settings.update', {'adbBurstMode': false});
    final added = await _request('devices.add', {
      'address': const String.fromEnvironment(
        'CONNECT_E2E_ADDRESS',
        defaultValue: '10.0.2.2',
      ),
      'port': const int.fromEnvironment(
        'CONNECT_E2E_PORT',
        defaultValue: 25556,
      ),
    });
    _device = (added['device'] as VideoJson)['id'] as String;
    return {
      'binding': WidgetsBinding.instance.runtimeType.toString(),
      'framePolicy': 'normal-driver-binding',
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'roundCount': roundCount,
      'transitions': transitions,
      'traceFrames': traceFrames,
      'decoderPolicy': decoderPolicy,
      'recoveredPriorDevices': existing.length,
      'quality': {'maxSize': maxSize, 'maxFps': maxFps, 'bitRate': bitRate},
      'budgetsMs': {
        'start': maxStartMs,
        'inputP50': maxP50Ms,
        'inputP95': maxP95Ms,
      },
    };
  }

  Future<VideoJson> _start() async {
    _require(
      _initialized &&
          !_disposed &&
          _session == null &&
          rounds.length < roundCount,
      'Cannot start this round.',
    );
    final evidence = <String, dynamic>{
      'round': rounds.length,
      'inputs': <VideoJson>[],
      'surfaces': <VideoJson>[],
    };
    rounds.add(evidence);
    _active = evidence;
    _decoderEvents.clear();
    final connecting = Stopwatch()..start();
    final connection = await _request('devices.connect', {'deviceId': _device});
    _require(
      connection['adbBurstActive'] == false,
      'Unexpected transport negotiation.',
    );
    evidence['connectMs'] = connecting.elapsedMilliseconds;
    final watch = Stopwatch()..start();
    final stream = await _request('session.start', {
      'deviceId': _device,
      'videoCodec': 'h264',
      'maxSize': maxSize,
      'maxFps': maxFps,
      'bitRate': bitRate,
    });
    _session = stream['sessionId'] as String;
    evidence.addAll({
      'sessionId': _session,
      'coreStartMs': watch.elapsedMilliseconds,
      'coreStartupTimingMs': stream['captureStartupTimingMs'],
      'quality': stream['quality'],
    });
    final VideoJson ready;
    try {
      ready = await _outputs.start(stream);
    } catch (_) {
      // PortableVideoOutputs releases a failed candidate internally, without a
      // receipt here. Do not infer confirmed disposal from its removed entry.
      _releaseUnconfirmed = true;
      rethrow;
    }
    evidence['startToDecodedMs'] = watch.elapsedMilliseconds;
    if (traceFrames) {
      final before = watch.elapsedMicroseconds;
      final trace = _player!.frameTrace;
      final after = watch.elapsedMicroseconds;
      evidence['startupFrameTrace'] = {
        'watchBeforeUs': before,
        'watchAfterUs': after,
        'metrics': trace,
      };
    }
    evidence.addAll({
      'outputStartupTimingMs': ready['outputStartupTimingMs'],
      'decodedWidth': ready['decodedWidth'],
      'decodedHeight': ready['decodedHeight'],
      'decoderEvents': [..._decoderEvents],
    });
    if (decoderPolicy == 'native' || decoderPolicy == 'native-async') {
      _require(
        _decoderEvents.any(
          (e) =>
              e['category'] == 'decoder.video' && e['detail'] == 'AMediaCodec',
        ),
        'No actual AMediaCodec open receipt.',
      );
    }
    if (decoderPolicy == 'software') {
      _require(
        _decoderEvents.any(
          (e) => e['category'] == 'decoder.video' && e['detail'] == 'FFmpeg',
        ),
        'No actual FFmpeg open receipt.',
      );
    }
    _ready = ready;
    await _request('session.ready', {
      'sessionId': _session,
      'textureId': ready['textureId'],
    });
    texture.value = VideoTexture(
      ready['textureId'] as int,
      ready['decodedWidth'] as int,
      ready['decodedHeight'] as int,
    );
    // One naturally requested UI update; no repeated pumps or forced draws.
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 3),
    );
    evidence['widgetFrameMs'] = watch.elapsedMilliseconds;
    await _waitPixels(_expected);
    evidence['initialCounter'] = _expected;
    return {...evidence, 'expectedCounter': _expected};
  }

  Future<VideoJson> _input() async {
    final active = _round();
    _require(
      active['lastPresentedCounter'] == _expected,
      'Verify the actual window before the next input.',
    );
    final inputs = active['inputs'] as List<VideoJson>;
    _require(
      inputs.length < transitions && !active.containsKey('pause'),
      'Input out of order.',
    );
    _expected = (_expected + 1) & 15;
    final watch = Stopwatch()..start();
    await _request('session.key', {
      'sessionId': _session,
      'keyCode': 20,
      'action': 'press',
    });
    final controlMs = watch.elapsedMilliseconds;
    final reads = await _waitPixels(_expected);
    final elapsed = watch.elapsedMilliseconds;
    final sample = <String, dynamic>{
      'counter': _expected,
      'expectedCounter': _expected,
      'controlMs': controlMs,
      'inputToDecodedMs': elapsed,
      'snapshotMs': reads,
    };
    if (traceFrames) {
      final trace = _player!.frameTrace!;
      final snap = trace['snapshot'] as VideoJson;
      final pts = snap['ptsSeconds'] as num;
      final decoded = (trace['decoded'] as List)
          .cast<VideoJson>()
          .where((f) => ((f['ptsSeconds'] as num) - pts).abs() < .000001)
          .toList();
      _require(
        decoded.length == 1,
        'Snapshot PTS must uniquely match a recorded decoded callback.',
      );
      final status = await _request('media.status', {
        'relayId': _ready!['relayId'],
      });
      final relay = (status['frameTrace'] as List)
          .cast<VideoJson>()
          .where((f) => ((f['ptsUs'] as num) - pts * 1000000).abs() <= 1.1)
          .toList();
      _require(
        relay.length == 1,
        'Snapshot PTS must uniquely match a recorded relay packet.',
      );
      sample.addAll({
        'nativeFrameTrace': trace,
        'relayFrame': relay.single,
        'decodeToSnapshotUs':
            (snap['elapsedUs'] as int) - (decoded.single['elapsedUs'] as int),
      });
    }
    inputs.add(sample);
    return sample;
  }

  Future<List<int>> _waitPixels(int expected) async {
    final watch = Stopwatch()..start();
    final reads = <int>[];
    while (true) {
      final reading = Stopwatch()..start();
      final pixels = await _player!
          .snapshot(width: 64, height: 64)
          .timeout(const Duration(seconds: 3));
      reads.add(reading.elapsedMilliseconds);
      if (pixels != null && pixelPattern(pixels.rgba, 64, 64) == expected) {
        return reads;
      }
      _require(
        watch.elapsed < const Duration(seconds: 3),
        'Expected fixture pixels did not arrive.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<VideoJson> _pause() async {
    final active = _round();
    _require(
      active['lastPresentedCounter'] == _expected,
      'Verify the actual window before pausing.',
    );
    _require(
      (active['inputs'] as List).length == transitions &&
          !active.containsKey('pause'),
      'Pause out of order.',
    );
    final sample = <String, dynamic>{'stage': 'pause'};
    active['pause'] = sample;
    final watch = Stopwatch()..start();
    final paused = await _presentation.request('session.pause', {
      'sessionId': _session,
    });
    sample['pauseMs'] = watch.elapsedMilliseconds;
    _require(
      paused['capturePaused'] == true &&
          paused['captureStateConfirmed'] == true,
      'Capture pause not acknowledged.',
    );
    _expected = (_expected + 1) & 15;
    await _request('session.key', {
      'sessionId': _session,
      'keyCode': 20,
      'action': 'press',
    });
    sample['stage'] = 'resume';
    watch.reset();
    final resumed = await _presentation.request('session.resume', {
      'sessionId': _session,
    });
    sample['resumeMs'] = watch.elapsedMilliseconds;
    _require(
      resumed['capturePaused'] == false && resumed['firstFrameDecoded'] == true,
      'Capture resume not verified.',
    );
    await _waitPixels(_expected);
    sample.addAll({
      'stage': 'complete',
      'resumeToFreshMs': watch.elapsedMilliseconds,
      'expectedCounter': _expected,
      'pauseConfirmed': true,
      'capturePausedAck': true,
      'captureResumedAck': true,
    });
    return sample;
  }

  Future<VideoJson> _surface(VideoJson command) async {
    final active = _round();
    final encoded = command['pngBase64'];
    _require(
      encoded is String && encoded.length <= 16 * 1024 * 1024,
      'Expected bounded actual-window PNG.',
    );
    final codec = await ui.instantiateImageCodec(
      base64Decode(encoded as String),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData();
        _require(data != null, 'Window image has no RGBA data.');
        final context = textureKey.currentContext;
        if (context == null || !context.mounted) {
          throw StateError('Texture is not mounted.');
        }
        final box = context.findRenderObject()! as RenderBox;
        final view = View.of(context);
        final logicalSize = view.physicalSize / view.devicePixelRatio;
        final origin = box.localToGlobal(Offset.zero);
        final region = ui.Rect.fromLTWH(
          origin.dx * frame.image.width / logicalSize.width,
          origin.dy * frame.image.height / logicalSize.height,
          box.size.width * frame.image.width / logicalSize.width,
          box.size.height * frame.image.height / logicalSize.height,
        );
        final observed = pixelPattern(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          frame.image.width,
          frame.image.height,
          region: region,
        );
        if (observed == _expected) active['lastPresentedCounter'] = observed;
        final sample = <String, dynamic>{
          'expectedCounter': _expected,
          'counter': observed,
          'valid': observed == _expected,
          'width': frame.image.width,
          'height': frame.image.height,
          'region': [region.left, region.top, region.width, region.height],
        };
        (active['surfaces'] as List<VideoJson>).add(sample);
        return sample;
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<VideoJson> _stop() async {
    final active = _round();
    _require(
      active['lastPresentedCounter'] == _expected,
      'Verify the resumed actual window before stopping.',
    );
    _require(
      active['pause'] is Map &&
          (active['pause'] as VideoJson)['stage'] == 'complete',
      'Round pause must complete.',
    );
    final receipt = await _stopSession();
    active['stop'] = receipt;
    return receipt;
  }

  Future<VideoJson> _stopSession() async {
    final id = _session;
    if (id == null) return {'complete': true};
    texture.value = null;
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 3),
    );
    final local = await _outputs.stop(id);
    final releases = (local['outputs'] as List).cast<VideoJson>();
    final clean = releases.every(
      (r) =>
          r['textureDetached'] == true &&
          r['cleanupUnconfirmed'] != true &&
          r['disposeDeferred'] != true,
    );
    // Save this before any remote await can fail. A later empty output list is
    // not proof that an earlier deferred native release has completed.
    _releaseUnconfirmed |= !clean;
    // Always stop the remote process even if the local release is deferred.
    await _request('session.stop', {'sessionId': id});
    await _request('devices.disconnect', {'deviceId': _device});
    _session = null;
    _ready = null;
    _require(clean, 'Local media release is unconfirmed.');
    return {'complete': true, 'sessionId': id, 'outputs': releases};
  }

  VideoJson _finish() {
    _require(
      _session == null &&
          rounds.length == roundCount &&
          rounds.every((r) => r['stop'] is Map),
      'Benchmark rounds incomplete.',
    );
    final times = [
      for (final r in rounds)
        for (final s in r['inputs'] as List<VideoJson>)
          s['inputToDecodedMs'] as int,
    ]..sort();
    final p50 = times[(times.length * .5).ceil() - 1],
        p95 = times[(times.length * .95).ceil() - 1];
    final startup = rounds.every(
      (r) => (r['startToDecodedMs'] as int) <= maxStartMs,
    );
    return {
      'videoPerformanceComplete': startup && p50 <= maxP50Ms && p95 <= maxP95Ms,
      'decoderPolicy': decoderPolicy,
      'binding': WidgetsBinding.instance.runtimeType.toString(),
      'framePolicy': 'normal-driver-binding',
      'startupBudgetMet': startup,
      'inputLatencyBudgetMet': p50 <= maxP50Ms && p95 <= maxP95Ms,
      'inputToDecodedP50Ms': p50,
      'inputToDecodedP95Ms': p95,
      'budgetsMs': {
        'start': maxStartMs,
        'inputP50': maxP50Ms,
        'inputP95': maxP95Ms,
      },
      'rounds': rounds,
    };
  }

  Future<VideoJson> _cleanup() async {
    if (_cleanupReceipt case final receipt?) return receipt;
    final failures = <String>[];
    Future<bool> attempt(Future<void> Function() operation) async {
      try {
        await operation();
        return true;
      } catch (error) {
        failures.add('$error');
        return false;
      }
    }

    final stopped = await attempt(() async {
      await _stopSession();
    });
    final outputs = await attempt(_outputs.dispose);
    _disposed = true;
    final device = _device;
    final disconnected =
        device == null ||
        await attempt(() async {
          await _request('devices.disconnect', {'deviceId': device});
        });
    final removed =
        device == null ||
        await attempt(() async {
          await _request('devices.forget', {'deviceId': device});
          final devices = (await _request('devices.list'))['devices'] as List;
          _require(
            !devices.cast<VideoJson>().any((d) => d['id'] == device),
            'Benchmark device record remains.',
          );
        });
    return _cleanupReceipt = {
      'complete':
          stopped && outputs && disconnected && removed && !_releaseUnconfirmed,
      'outputsDisposed': outputs && stopped && !_releaseUnconfirmed,
      'deviceDisconnected': disconnected,
      'deviceRemoved': removed,
      'failures': failures,
    };
  }

  VideoJson _round() {
    _require(
      _session != null && _active != null && _ready != null && !_disposed,
      'No live benchmark round.',
    );
    return _active!;
  }

  static void _require(bool value, String message) {
    if (!value) throw StateError(message);
  }
}
