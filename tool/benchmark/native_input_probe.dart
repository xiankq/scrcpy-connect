// PROTOTYPE: isolated HTTP versus MDK memory-input experiment. Never imported
// by the product. Preload the recorded fixture into application support and
// supply only its metadata through --dart-define-from-file.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:interop_bridge/src/media/native_frame_trace.dart';
import 'package:interop_bridge/src/rust/frb_generated.dart';
import 'package:path_provider/path_provider.dart';

import 'live_video/pixel_pattern.dart';

const _asset = 'package:interop_bridge/src/rust/frb_generated.io.dart';

@Native<Uint64 Function(Uint64, Int32, Int32, Pointer<Uint8>, Uint32)>(
  symbol: 'input_probe_open',
  assetId: _asset,
)
external int _open(
  int player,
  int version,
  int mode,
  Pointer<Uint8> data,
  int size,
);

@Native<Int32 Function(Uint64)>(symbol: 'input_probe_start', assetId: _asset)
external int _start(int token);

@Native<Int32 Function(Uint64, Pointer<Uint8>, Uint32)>(
  symbol: 'input_probe_metrics',
  assetId: _asset,
)
external int _metrics(int token, Pointer<Uint8> data, int capacity);

@Native<Int32 Function(Uint64)>(symbol: 'input_probe_cancel', assetId: _asset)
external int _cancel(int token);

@Native<Int32 Function(Uint64)>(symbol: 'input_probe_release', assetId: _asset)
external int _release(int token);

void main() {
  final probe = InputProbe();
  enableFlutterDriverExtension(handler: probe.handle);
  runApp(
    ProviderScope(
      child: MaterialApp(home: ProbePage(probe: probe)),
    ),
  );
}

class InputProbe extends ChangeNotifier {
  int? texture;
  double aspectRatio = 1;
  String label = 'Native input experiment';
  mdk.Player? _player;
  NativeFrameTrace? _trace;
  int? _token;
  bool _busy = false;
  final _decoded = <String, Map<String, dynamic>>{};
  final _events = <Map<String, dynamic>>[];
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _buffer = calloc<Uint8>(2 * 1024 * 1024);
  List<int>? _loadedFixture;

  Map<String, dynamic> _native() {
    final count = _metrics(_token!, _buffer, 2 * 1024 * 1024);
    if (count <= 0 || count > 2 * 1024 * 1024) {
      throw StateError('Native input metrics failed: $count');
    }
    return jsonDecode(utf8.decode(_buffer.asTypedList(count)))
        as Map<String, dynamic>;
  }

  Map<String, dynamic> _collect() {
    final state = _trace!.metrics;
    for (final raw in state['decoded'] as List) {
      final frame = (raw as Map).cast<String, dynamic>();
      _decoded['${frame['track']}:${frame['ptsSeconds']}:${frame['elapsedUs']}'] =
          frame;
    }
    return state;
  }

  Future<String> handle(String? message) async {
    final request = jsonDecode(message ?? '{}') as Map<String, dynamic>;
    final command = request['command'];
    if (command == 'state') {
      return jsonEncode({'busy': _busy, 'texture': texture, 'label': label});
    }
    if (_busy) return jsonEncode({'complete': false, 'error': 'Probe busy'});
    _busy = true;
    try {
      if (command == 'cleanup') {
        return jsonEncode({'complete': true, 'cleanup': await _cleanup()});
      }
      if (command != 'run') throw ArgumentError('Unknown probe command');
      return jsonEncode(await _run(request));
    } catch (error, stack) {
      return jsonEncode({
        'complete': false,
        'error': '$error',
        'stack': '$stack',
        if (_token != null) 'native': _native(),
        if (_trace != null) 'trace': _trace!.metrics,
        'decoded': _decoded.values.toList(),
        'events': _events,
      });
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>> _run(Map<String, dynamic> request) async {
    final mode = request['mode'];
    if (mode != 'http' && mode != 'append') {
      throw ArgumentError('mode must be http or append');
    }
    final previousCleanup = await _cleanup();
    await RustLib.init();
    final support = await getApplicationSupportDirectory();
    final fixture = _loadedFixture ??= await File(
      '${support.path}/native-input-fixture.mdkp',
    ).readAsBytes();
    final expectedHash = const String.fromEnvironment(
      'nativeInputFixtureSha256',
    );
    if (fixture.isEmpty || sha256.convert(fixture).toString() != expectedHash) {
      throw StateError('Missing or mismatched experimental fixture');
    }
    _decoded.clear();
    _events.clear();
    final player = mdk.Player();
    _player = player;
    player
      ..activeAudioTracks = const []
      ..mute = true
      ..videoDecoders = const [
        'AMediaCodec:async=1',
        'FFmpeg:thread_type=slice',
      ]
      ..setBufferRange(min: 0, max: 150, drop: true)
      ..setProperty('avformat.input', 'matroska')
      ..setProperty('avformat.fpsprobesize', '0')
      ..setProperty('avformat.probesize', '32')
      ..setProperty('fps', '-1');
    _subscriptions.add(
      player.onEvent.listen((event) {
        if (_events.length < 100) {
          _events.add({
            'category': event.category,
            'detail': event.detail,
            'error': event.error,
          });
        }
      }),
    );
    final input = calloc<Uint8>(fixture.length);
    try {
      input.asTypedList(fixture.length).setAll(0, fixture);
      _token = _open(
        player.nativeHandle,
        mdk.version(),
        mode == 'http' ? 0 : 1,
        input,
        fixture.length,
      );
    } finally {
      calloc.free(input);
    }
    if (_token == 0) {
      _token = null;
      throw StateError('Native probe rejected handle, ABI or fixture');
    }
    // Install the decoded observer before preparing either input. It observes
    // the same MDK callback on one Rust monotonic clock in both groups.
    _trace = NativeFrameTrace(player.nativeHandle);
    final initial = _native();
    player.media = mode == 'http' ? initial['url'] as String : 'stream:';
    label = '$mode / round ${request['round']}';
    notifyListeners();
    final beforeRss = ProcessInfo.currentRss;
    final beforeTicks = _cpuTicks();
    var peakRss = beforeRss;
    var maxBufferedMs = 0;
    final watch = Stopwatch()..start();
    if (_start(_token!) != 1) throw StateError('Native worker did not start');
    final prepared = await player.prepare().timeout(
      const Duration(seconds: 12),
    );
    final prepareMs = watch.elapsedMilliseconds;
    if (prepared < 0) throw StateError('MDK failed to prepare $mode');
    final id = await player.updateTexture().timeout(const Duration(seconds: 8));
    if (id < 0) throw StateError('MDK did not create a texture');
    final size = await player.textureSize;
    texture = id;
    aspectRatio = size!.width / size.height;
    notifyListeners();
    final textureMs = watch.elapsedMilliseconds;
    player.state = mdk.PlaybackState.playing;
    Map<String, dynamic> native;
    final durationUs = const int.fromEnvironment(
      'nativeInputFixtureDurationUs',
    );
    const runUs = int.fromEnvironment(
      'nativeInputRunUs',
      defaultValue: 15000000,
    );
    if (runUs < 5000000 || runUs >= durationUs - 1000000) {
      throw StateError('Measurement window needs a continuing source after it');
    }
    while (true) {
      _collect();
      native = _native();
      peakRss = peakRss < ProcessInfo.currentRss
          ? ProcessInfo.currentRss
          : peakRss;
      final buffered = player.buffered();
      if (buffered > maxBufferedMs) maxBufferedMs = buffered;
      if (native['error'] != null) throw StateError('${native['error']}');
      final traceState = _trace!.metrics;
      final nowUs =
          (traceState['clockOriginUs'] as int) +
          (traceState['nowElapsedUs'] as int);
      final startedUs = native['startedUs'] as int;
      if (startedUs > 0 && nowUs - startedUs >= runUs) {
        break;
      }
      if (watch.elapsed >
          Duration(microseconds: runUs) + const Duration(seconds: 15)) {
        throw TimeoutException(
          'Continuing source measurement window not reached',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (native['rejected'] != 0) {
      throw StateError('MDK rejected one or more input chunks');
    }
    final measuredTicks = _cpuTicks() - beforeTicks;
    final measuredWallUs = watch.elapsedMicroseconds;
    final measuredRss = ProcessInfo.currentRss;
    final frameMetrics = _collect();
    if (_decoded.length < 20) throw StateError('Too few real decoded frames');
    // Read pixels only after timing/CPU measurement while the source continues.
    // Finite-source EOF behavior is outside this live input comparison.
    final pixels = await _trace!
        .snapshot(texture: id, width: 64, height: 64)
        .timeout(const Duration(seconds: 6));
    if (pixels == null || !pixels.valid) {
      throw StateError('No actual rendered pixels');
    }
    final counter = pixelPattern(pixels.rgba, pixels.width, pixels.height);
    if (counter == null) {
      throw StateError('Rendered frame failed the fixture color oracle');
    }
    final receipt = _collect();
    final snapshot = receipt['snapshot'] as Map<String, dynamic>?;
    if (snapshot == null ||
        !_decoded.values.any(
          (frame) =>
              ((frame['ptsSeconds'] as num) - (snapshot['ptsSeconds'] as num))
                  .abs() <
              .000002,
        )) {
      throw StateError('Rendered pixels have no matching decoded PTS');
    }
    return {
      'complete': true,
      'prototype': true,
      'mode': mode,
      'measurementWindowUs': runUs,
      'finiteStreamCompletionVerified': false,
      'round': request['round'],
      'fixtureSha256': expectedHash,
      'captureSha256': const String.fromEnvironment('nativeInputCaptureSha256'),
      'mdkVersion': mdk.version(),
      'prepareMs': prepareMs,
      'textureMs': textureMs,
      'native': native,
      'decoded': _decoded.values.toList(),
      'clockOriginUs': frameMetrics['clockOriginUs'],
      'traceDrops': frameMetrics['drops'],
      'summary': _summary(native, frameMetrics, _decoded.values.toList()),
      'cpuTicks': measuredTicks,
      'wallUs': measuredWallUs,
      'rssBeforeBytes': beforeRss,
      'rssAfterBytes': measuredRss,
      'rssPeakBytes': peakRss,
      'maxBufferedMs': maxBufferedMs,
      'pixels': {
        'counter': counter,
        'rgbaSha256': sha256.convert(pixels.rgba).toString(),
        'snapshot': snapshot,
        'physicalDisplayScanoutMeasured': false,
      },
      'texture': id,
      'events': List.of(_events),
      'previousCleanup': previousCleanup,
    };
  }

  Future<Map<String, dynamic>> _cleanup() async {
    final player = _player;
    if (player == null) return {'nothingToRelease': true};
    final token = _token;
    if (token != null) {
      _cancel(token);
      final wait = Stopwatch()..start();
      while (_native()['finished'] != true) {
        if (wait.elapsed > const Duration(seconds: 6)) {
          throw StateError(
            'Native worker not drained; borrowed player retained',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (_release(token) != 1) {
        throw StateError('Native worker release not confirmed');
      }
      _token = null;
    }
    texture = null;
    notifyListeners();
    await WidgetsBinding.instance.endOfFrame;
    await player.updateTexture(width: -1).timeout(const Duration(seconds: 5));
    player.state = mdk.PlaybackState.stopped;
    final wait = Stopwatch()..start();
    while (!player.waitFor(mdk.PlaybackState.stopped, timeout: 1)) {
      if (wait.elapsed > const Duration(seconds: 6)) {
        throw StateError('MDK stopped state not confirmed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _trace?.close();
    _trace = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    player.dispose();
    _player = null;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return {
      'workerDrained': true,
      'textureDetached': true,
      'stoppedConfirmed': true,
      'disposeRequested': true,
      'nativeDeleteConfirmed': false,
    };
  }
}

int _cpuTicks() {
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]);
}

Map<String, dynamic> _summary(
  Map<String, dynamic> native,
  Map<String, dynamic> trace,
  List<Map<String, dynamic>> decoded,
) {
  final origin = trace['clockOriginUs'] as int;
  final matched = <Map<String, dynamic>>[];
  var ambiguous = 0;
  for (final raw in native['sends'] as List) {
    final sent = (raw as Map).cast<String, dynamic>();
    if (sent['index'] == 0) continue;
    final pts = sent['ptsUs'] as int;
    final frames = decoded.where(
      (frame) => ((frame['ptsSeconds'] as num) * 1000000 - pts).abs() < 2,
    );
    if (frames.length != 1) {
      ambiguous++;
      continue;
    }
    final callback = origin + (frames.single['elapsedUs'] as int);
    final entered = sent['enteredUs'] as int;
    if (callback < entered) throw StateError('Frame/clock identity reversed');
    matched.add({'ptsUs': pts, 'inputToDecodedUs': callback - entered});
  }
  final steady =
      matched
          .where((frame) => (frame['ptsUs'] as int) >= 3000000)
          .map((frame) => frame['inputToDecodedUs'] as int)
          .toList()
        ..sort();
  if (matched.isEmpty || steady.isEmpty) {
    throw StateError('No usable same-PTS samples');
  }
  int percentile(double p) => steady[((steady.length - 1) * p).round()];
  return {
    'matchedFrames': matched.length,
    'unmatchedOrAmbiguousFrames': ambiguous,
    'firstInputToDecodedUs': matched.first['inputToDecodedUs'],
    'steadyInputToDecodedP50Us': percentile(.5),
    'steadyInputToDecodedP95Us': percentile(.95),
    'steadySamples': steady.length,
    'samples': matched,
    'metric': 'player-input-to-MDK-onVideo; not input-to-display latency',
  };
}

class ProbePage extends StatelessWidget {
  const ProbePage({required this.probe, super.key});
  final InputProbe probe;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: probe,
    builder: (context, _) => Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Text(probe.label, style: const TextStyle(color: Colors.white)),
            Expanded(
              child: Center(
                child: probe.texture == null
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                        aspectRatio: probe.aspectRatio,
                        child: Texture(textureId: probe.texture!),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
