// Lab-only raw H264 drain on one explicitly authorized target.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../support.dart';
import '../../src/process.dart';

class ExactReader {
  ExactReader(Socket socket) : _iterator = StreamIterator(socket);
  final StreamIterator<Uint8List> _iterator;
  List<int> _buffer = [];
  int _offset = 0;
  Duration timeout = const Duration(seconds: 8);
  Future<Uint8List> exact(int size) async {
    final output = BytesBuilder(copy: false);
    while (output.length < size) {
      if (_offset == _buffer.length) {
        if (!await _iterator.moveNext().timeout(timeout)) {
          throw StateError('incomplete scrcpy packet');
        }
        _buffer = _iterator.current;
        _offset = 0;
      }
      final count = min(size - output.length, _buffer.length - _offset);
      output.add(_buffer.sublist(_offset, _offset + count));
      _offset += count;
    }
    return output.takeBytes();
  }
}

String shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
String runId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = bytes[6] & 15 | 64;
  bytes[8] = bytes[8] & 63 | 128;
  return bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}

Future<int> capture(List<String> arguments) async {
  final args = parse(
    options(['adb', 'target', 'jar', 'fixture', 'out']),
    arguments,
  );
  final directory = Directory(args['out'] as String);
  if (directory.existsSync()) {
    throw FileSystemException(
      'Output directory already exists',
      directory.path,
    );
  }
  directory.createSync();
  const package = 'dev.scrcpyconnect.videofixture';
  final run = runId();
  final name = 'interop.firstcounter.$run';
  final remote = '/data/local/tmp/interop-firstcounter-$run.jar';
  final scid = int.parse(
    run.substring(0, 7),
    radix: 16,
  ).toRadixString(16).padLeft(8, '0');
  final clock = Stopwatch()..start();
  int nowUs() => clock.elapsedMicroseconds;
  int? port;
  Process? process;
  int? processStatus;
  Socket? video;
  Socket? control;
  Future<void>? reader;
  Future<void>? logDrain;
  var installed = false;
  var closing = false;
  final packets = <Json>[];
  final errors = <String>[];
  final result = <String, dynamic>{
    'run': run,
    'jarSha256': sha256
        .convert(File(args['jar'] as String).readAsBytesSync())
        .toString(),
    'scope': 'host raw drain, not Flutter or real wireless latency acceptance',
    'quality': {'maxSize': 1280, 'maxFps': 60, 'bitRate': 8000000},
    'inputs': <Json>[],
    'measurementComplete': false,
    'complete': false,
    'cleanupErrors': <String, dynamic>{},
  };
  Future<ProcessResult> adbResult(List<String> command) => runProcess(
    args['adb'] as String,
    ['-s', args['target'] as String, ...command],
    timeout: const Duration(seconds: 20),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  Future<String> adb(List<String> command, {bool check = true}) async {
    final completed = await adbResult(command);
    if (check && completed.exitCode != 0) {
      throw ProcessException(
        args['adb'] as String,
        command,
        completed.stderr as String,
        completed.exitCode,
      );
    }
    return (completed.stdout as String).trim();
  }

  Future<bool> succeeds(List<String> command) async =>
      (await adbResult(command)).exitCode == 0;
  Future<List<Json>> clocks() async {
    final values = <Json>[];
    for (var i = 0; i < 3; i++) {
      final before = nowUs();
      final uptime = (await adb(['exec-out', 'cat', '/proc/uptime']))
          .split(RegExp(r'\s+'))
          .first
          .split('.');
      final after = nowUs();
      if (uptime.length != 2 || uptime[1].length != 2) {
        throw StateError('Unexpected target uptime quantization');
      }
      values.add({
        'hostBeforeUs': before,
        'hostAfterUs': after,
        'targetBootUs':
            int.parse(uptime[0]) * 1000000 + int.parse(uptime[1]) * 10000,
      });
    }
    return values;
  }

  Future<void> read(ExactReader stream) async {
    RandomAccessFile? output;
    try {
      final device = await stream.exact(64);
      result['deviceName'] = utf8.decode(
        device.takeWhile((v) => v != 0).toList(),
      );
      if (!sameList(await stream.exact(4), ascii.encode('h264'))) {
        throw StateError('Expected H264 stream');
      }
      var offset = 0;
      final file = File(p.join(directory.path, 'capture.h264'))
        ..createSync(exclusive: true);
      output = file.openSync(mode: FileMode.writeOnly);
      while (!closing) {
        final header = await stream.exact(12);
        final bytes = ByteData.sublistView(header);
        final high = bytes.getUint32(0);
        final low = bytes.getUint32(4);
        final size = bytes.getUint32(8);
        if ((high & 0x80000000) != 0) {
          if (packets.isNotEmpty || result.containsKey('width')) {
            throw StateError('capture generation changed');
          }
          result['width'] = low;
          result['height'] = size;
          continue;
        }
        if (size <= 0 || size > 16 * 1024 * 1024) {
          throw StateError('Invalid scrcpy packet length');
        }
        final data = await stream.exact(size);
        final received = nowUs();
        if (offset + size > 128 * 1024 * 1024) {
          throw StateError('Capture byte limit exceeded');
        }
        output.writeFromSync(data);
        packets.add({
          'offset': offset,
          'size': size,
          'config': high & 0x40000000 != 0,
          'keyframe': high & 0x20000000 != 0,
          'sourcePtsUs': (high & 0x1fffffff) * 0x100000000 + low,
          'receivedHostUs': received,
        });
        offset += size;
      }
    } catch (error) {
      if (!closing) errors.add('$error');
    } finally {
      output?.closeSync();
    }
  }

  Future<void> wait(double seconds) async {
    final end = nowUs() + (seconds * 1000000).round();
    while (nowUs() < end) {
      if (errors.isNotEmpty) throw StateError('$errors');
      if (process != null && processStatus != null) {
        throw StateError('server exited before drain completed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  try {
    if ((await adb([
      'shell',
      'pm',
      'path',
      package,
    ], check: false)).isNotEmpty) {
      throw StateError('fixture already installed');
    }
    await adb(['install', '--no-streaming', args['fixture'] as String]);
    installed = true;
    await adb([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$package/.VideoPatternActivity',
      '--ez',
      'motion',
      'true',
      '--es',
      'timelineRun',
      run,
    ]);
    await adb(['push', args['jar'] as String, remote]);
    port = int.parse(
      await adb(['forward', 'tcp:0', 'localabstract:scrcpy_$scid']),
    );
    final serverOptions = [
      'app_process',
      '/',
      '--nice-name=$name',
      'com.genymobile.scrcpy.Server',
      '5.0.1',
      'scid=$scid',
      'log_level=info',
      'video=true',
      'audio=false',
      'control=true',
      'video_codec=h264',
      'video_encoder=c2.android.avc.encoder',
      'max_size=1280',
      'max_fps=60',
      'video_bit_rate=8000000',
      'video_codec_options=repeat-previous-frame-after:long=33334',
      'tunnel_forward=true',
      'cleanup=true',
      'clipboard_autosync=false',
      'power_on=false',
      'send_dummy_byte=true',
      'send_device_meta=true',
      'send_stream_meta=true',
      'send_frame_meta=true',
    ];
    final command =
        'CLASSPATH=${shellQuote(remote)} exec ${serverOptions.map(shellQuote).join(' ')}';
    final logFile = File(p.join(directory.path, 'server.log'))
      ..createSync(exclusive: true);
    final log = logFile.openWrite();
    process = await Process.start(args['adb'] as String, [
      '-s',
      args['target'] as String,
      'shell',
      command,
    ]);
    unawaited(
      process.exitCode.then((v) {
        processStatus = v;
      }),
    );
    logDrain = Future.wait([
      process.stdout.forEach(log.add),
      process.stderr.forEach(log.add),
    ]).then((_) => log.close());
    final end = nowUs() + 10000000;
    ExactReader? stream;
    while (nowUs() < end) {
      Socket? attempt;
      try {
        attempt = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(seconds: 1),
        );
        final candidate = ExactReader(attempt)
          ..timeout = const Duration(seconds: 3);
        if ((await candidate.exact(1)).single != 0) {
          throw StateError('Invalid scrcpy dummy byte');
        }
        video = attempt;
        stream = candidate..timeout = const Duration(seconds: 8);
        break;
      } catch (_) {
        attempt?.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (video == null || stream == null) {
      throw StateError('Failed to connect scrcpy video socket');
    }
    control = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(seconds: 3),
    );
    reader = read(stream);
    await wait(2);
    result['clockBefore'] = await clocks();
    for (var sequence = 1; sequence <= 8; sequence++) {
      final before = nowUs();
      for (final action in [0, 1]) {
        final packet = ByteData(14)
          ..setUint8(0, 0)
          ..setUint8(1, action)
          ..setUint32(2, 20)
          ..setUint32(6, 0)
          ..setUint32(10, 0);
        control.add(packet.buffer.asUint8List());
        await control.flush();
      }
      (result['inputs'] as List).add({
        'sequence': sequence,
        'counter': sequence,
        'hostBeforeSendUs': before,
        'hostAfterSendUs': nowUs(),
      });
      await wait(1.5);
    }
    result['clockAfter'] = await clocks();
    await wait(.5);
    result['measurementComplete'] = true;
  } catch (error) {
    result['error'] = '$error';
  } finally {
    Future<void> cleanup(
      String label,
      FutureOr<dynamic> Function() operation,
    ) async {
      try {
        result[label] = await operation();
      } catch (error) {
        result['cleanupErrors'][label] = '$error';
        result[label] = false;
      }
    }

    closing = true;
    video?.destroy();
    control?.destroy();
    if (reader != null) {
      await cleanup('readerStopped', () async {
        await reader!.timeout(const Duration(seconds: 10));
        return true;
      });
    }
    if (process != null) {
      await cleanup('serverShellExit', () async {
        try {
          await process!.exitCode.timeout(const Duration(seconds: 8));
        } on TimeoutException {
          process!.kill();
          try {
            await process.exitCode.timeout(const Duration(seconds: 3));
          } on TimeoutException {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode.timeout(const Duration(seconds: 3));
          }
        }
        await logDrain;
        return processStatus;
      });
    }
    await cleanup('timelineWritten', () async {
      final timeline = <dynamic>[];
      final log = await adb([
        'logcat',
        '-d',
        '-v',
        'brief',
        'ConnectVideoClock:I',
        '*:S',
      ]);
      File(p.join(directory.path, 'target-logcat.txt')).writeAsStringSync(log);
      for (final line in const LineSplitter().convert(log)) {
        final start = line.indexOf('{"run":');
        if (start >= 0) {
          final event = jsonDecode(line.substring(start));
          if (event['run'] == run) timeline.add(event);
        }
      }
      writeJson(p.join(directory.path, 'target-timeline.json'), timeline);
      return true;
    });
    await cleanup('packetLedgerWritten', () {
      writeJson(p.join(directory.path, 'packets.json'), {
        'width': result['width'],
        'height': result['height'],
        'packets': packets,
      });
      return true;
    });
    if (port != null) {
      await cleanup(
        'forwardRemoved',
        () => succeeds(['forward', '--remove', 'tcp:$port']),
      );
    }
    await cleanup(
      'remoteRemoveAttempted',
      () => succeeds(['shell', 'rm', '-f', remote]),
    );
    await cleanup(
      'processAbsent',
      () async => (await adb(['shell', 'pidof', name], check: false)).isEmpty,
    );
    await cleanup(
      'jarAbsent',
      () => succeeds(['shell', 'test', '!', '-e', remote]),
    );
    if (installed) {
      await cleanup('uninstall', () => adb(['uninstall', package]));
    }
    await cleanup(
      'fixtureAbsent',
      () async =>
          (await adb(['shell', 'pm', 'path', package], check: false)).isEmpty,
    );
    await cleanup(
      'settingsRestored',
      () => succeeds([
        'shell',
        'am',
        'start',
        '-W',
        '-a',
        'android.settings.SETTINGS',
      ]),
    );
    result['readerErrors'] = errors;
    const required = [
      'measurementComplete',
      'readerStopped',
      'processAbsent',
      'fixtureAbsent',
      'jarAbsent',
      'forwardRemoved',
      'timelineWritten',
      'packetLedgerWritten',
    ];
    result['complete'] =
        required.every((key) => result[key] == true) &&
        result['serverShellExit'] == 0 &&
        errors.isEmpty &&
        (result['cleanupErrors'] as Map).isEmpty;
    writeJson(p.join(directory.path, 'result.json'), result);
  }
  stdout.writeln(pretty.convert(result));
  return result['complete'] == true ? 0 : 1;
}

Future<void> main(List<String> arguments) => cli(() async {
  exitCode = await capture(arguments);
});
