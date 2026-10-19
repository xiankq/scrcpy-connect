// Keep the migrated command's existing spelling for external callers.
// ignore_for_file: file_names

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../../tooling.dart';

typedef Json = Map<String, dynamic>;

class JarProcess {
  JarProcess(this.process) {
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    errors = process.stderr
        .transform(utf8.decoder)
        .listen((value) => stderrText += value);
    unawaited(
      process.exitCode.then((value) {
        status = value;
      }),
    );
  }
  final Process process;
  late final StreamIterator<String> lines;
  late final StreamSubscription<String> errors;
  String stderrText = '';
  int? status;

  Future<String> line() async {
    final available = await lines.moveNext().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError('temporary JAR output timed out'),
    );
    require(
      available,
      'temporary JAR exited: ${stderrText.length > 2048 ? stderrText.substring(stderrText.length - 2048) : stderrText}',
    );
    return lines.current.trim();
  }

  Future<void> stop({bool quit = false, bool requireSuccess = false}) async {
    try {
      if (quit && status == null) {
        process.stdin.writeln('quit');
        await process.stdin.flush();
      }
      final code = await process.exitCode.timeout(const Duration(seconds: 10));
      require(
        !requireSuccess || code == 0,
        'socket EOF unregisters listeners and exits: $stderrText',
      );
    } on TimeoutException {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          throw StateError('Temporary JAR process did not exit');
        },
      );
      require(!requireSuccess, 'temporary JAR did not exit after socket EOF');
    } finally {
      await lines.cancel();
      await errors.cancel();
      await process.stdin.close();
    }
  }
}

class Probe {
  Probe(
    this.adbExecutable,
    this.serial, {
    required this.calls,
    required this.skipReceiver,
    required this.fixtureFile,
  });
  final String adbExecutable;
  final String serial;
  final bool calls;
  final bool skipReceiver;
  final File fixtureFile;
  final events = <Json>[];
  final random = Random.secure();
  final clock = Stopwatch()..start();
  final ownedCalls = <String>{};
  final pushed = <String>[];
  JarProcess? process;
  JarProcess? fixture;
  Socket? socket;
  StreamIterator<String>? responses;
  int? port;
  int counter = 0;

  String randomHex(int length) => List.generate(
    length,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Future<ProcessResult> adb(List<String> arguments, {bool check = true}) =>
      run(adbExecutable, ['-s', serial, ...arguments], check: check);
  Future<JarProcess> startJar(String command) async => JarProcess(
    await Process.start(adbExecutable, ['-s', serial, 'shell', command]),
  );
  Json decode(String line) => jsonDecode(line) as Json;
  Future<Json> response() async {
    require(
      await responses!.moveNext().timeout(const Duration(seconds: 15)),
      'Companion socket closed',
    );
    return decode(responses!.current);
  }

  Future<Json> request(String command, [Json params = const {}]) async {
    final id = '${++counter}';
    socket!.writeln(
      jsonEncode({'requestId': id, 'command': command, ...params}),
    );
    await socket!.flush();
    while (true) {
      final result = await response();
      if (result['requestId'] == id) return result;
      events.add(result);
    }
  }

  Future<Json> success(String command, [Json params = const {}]) async {
    final result = await request(command, params);
    require(
      !result.containsKey('error'),
      result['error'] as Object? ?? 'Missing result',
    );
    return result['result'] as Json;
  }

  Future<void> rejected(String command, String code, Json params) async {
    final result = await request(command, params);
    require((result['error'] as Json?)?['code'] == code, result);
  }

  Future<void> execute() async {
    final root = Directory(
      p.join(repositoryRoot().path, 'servers', 'companion'),
    );
    final id = randomHex(16);
    final name = 'interop-companion-$id';
    final secret = randomHex(32);
    final companionPath = '/data/local/tmp/interop-companion-probe-$id.jar';
    final fixturePath = '/data/local/tmp/interop-companion-fixture-$id.jar';
    // Register each path before push, so partial failed transfers are cleaned too.
    pushed.add(companionPath);
    await adb(['push', p.join(root.path, 'companion.jar'), companionPath]);
    pushed.add(fixturePath);
    await adb(['push', fixtureFile.path, fixturePath]);
    process = await startJar(
      'CLASSPATH=$companionPath app_process / com.interop.companion.Main $name $secret',
    );
    require(
      (await process!.line()).startsWith('INTEROP_COMPANION_READY '),
      'Missing companion ready marker',
    );
    final forward = await adb(['forward', 'tcp:0', 'localabstract:$name']);
    port = int.parse((forward.stdout as String).trim());
    socket = await Socket.connect(
      '127.0.0.1',
      port!,
      timeout: const Duration(seconds: 10),
    );
    responses = StreamIterator(
      socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    socket!.writeln(jsonEncode({'token': secret}));
    await socket!.flush();
    late Json ready;
    while (true) {
      final value = await response();
      if (value['event'] == 'ready') {
        ready = value;
        break;
      }
      events.add(value);
    }
    require(ready['uid'] == 2000 && ready['protocol'] == 1, ready);
    require(
      (ready['notifications'] as Json)['status'] == 'stopped' &&
          (ready['notifications'] as Json)['live'] == false &&
          (ready['calls'] as Json)['live'] == false,
      ready,
    );
    final started = await success('observation.set', {
      'enabled': true,
      'epoch': 1,
    });
    require(
      (started['notifications'] as Json)['status'] == 'available',
      started,
    );
    fixture = await startJar(
      'CLASSPATH=$fixturePath app_process / com.interop.companion.Fixture',
    );
    final fixtureReady = decode(await fixture!.line());
    require(fixtureReady['event'] == 'fixture.ready', fixtureReady);
    final tag = fixtureReady['tag'] as String;
    final deadline = clock.elapsed + const Duration(seconds: 10);
    late Map<int, Json> own;
    while (true) {
      final notifications =
          (await success('notifications.list'))['notifications']
              as List<dynamic>;
      own = {
        for (final item in notifications.cast<Json>())
          if ((item['title'] as String).startsWith(tag))
            int.parse((item['title'] as String).split('-').last): item,
      };
      if (own.length == 4) break;
      require(clock.elapsed < deadline, 'all fixture notifications visible');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    require(own[0]!['canReply'] == true && own[1]!['canReply'] == false, own);
    require(
      events.any((item) => item['event'] == 'notifications.changed'),
      'real Binder callback',
    );
    const text = '真实 RemoteInput interoperability';
    final reply = await success('notifications.reply', {
      'notificationId': own[0]!['id'],
      'text': text,
    });
    require(
      reply['acceptedBySystem'] == true && reply['delivered'] == null,
      reply,
    );
    if (!skipReceiver) {
      late Json received;
      try {
        received = decode(await fixture!.line());
      } catch (_) {
        final dump = const LineSplitter().convert(
          (await adb(['shell', 'dumpsys', 'activity', 'broadcasts'])).stdout
              as String,
        );
        final selected = <int>{};
        for (var index = 0; index < dump.length; index++) {
          if (dump[index].contains(tag)) {
            selected.addAll([
              for (
                var i = max(0, index - 4);
                i < min(dump.length, index + 12);
                i++
              )
                i,
            ]);
          }
        }
        stdout.writeln(
          'Receiver timeout for $tag; fixture exit=${fixture!.status}',
        );
        stdout.writeln(
          selected.isEmpty
              ? 'No matching fixture receiver or queued broadcast was present.'
              : (selected.toList()..sort())
                    .map((index) => dump[index])
                    .join('\n'),
        );
        final log = const LineSplitter().convert(
          (await adb(['logcat', '-d', '-t', '500'])).stdout as String,
        );
        stdout.writeln(
          log
              .where((value) => value.contains('registerReceiverWithFeature'))
              .join('\n'),
        );
        rethrow;
      }
      require(
        sameJson(received, {'event': 'reply.received', 'text': text}),
        received,
      );
    }
    await rejected('notifications.reply', 'reply_unavailable', {
      'notificationId': own[1]!['id'],
      'text': 'must not send',
    });
    await rejected('notifications.reply', 'authentication_required', {
      'notificationId': own[2]!['id'],
      'text': 'must not bypass auth',
    });
    await rejected('notifications.open', 'notification_expired', {
      'notificationId': own[3]!['id'],
    });
    final opened = await success('notifications.open', {
      'notificationId': own[0]!['id'],
    });
    require(
      opened['acceptedBySystem'] == true &&
          opened['located'] == true &&
          opened['applicationConfirmed'] == false,
      opened,
    );
    final foreground =
        (await adb(['shell', 'dumpsys', 'activity', 'activities'])).stdout
            as String;
    require(
      foreground.contains('com.android.settings/.Settings') ||
          foreground.contains('com.android.settings.Settings'),
      'Settings was not foreground',
    );
    await success('notifications.dismiss', {'notificationId': own[0]!['id']});
    final dismissDeadline = clock.elapsed + const Duration(seconds: 5);
    while (((await success('notifications.list'))['notifications']
            as List<dynamic>)
        .cast<Json>()
        .any((item) => item['id'] == own[0]!['id'])) {
      require(
        clock.elapsed < dismissDeadline,
        'remote notification actually cleared',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await rejected('notifications.open', 'notification_expired', {
      'notificationId': own[0]!['id'],
    });
    stdout.writeln(
      'PASS: UID2000 live Binder notifications, original PendingIntent, RemoteInput submitted'
      '${skipReceiver ? ' (standalone receiver delivery NOT verified)' : ' and received'}, '
      'immutable/auth/cancelled/stale rejection, actual remote dismissal',
    );
    if (calls) await checkCalls();
    final stopped = await success('observation.set', {
      'enabled': false,
      'epoch': 2,
    });
    require(
      stopped['cleanupConfirmed'] == true &&
          (stopped['notifications'] as Json)['live'] == false &&
          (stopped['calls'] as Json)['live'] == false,
      stopped,
    );
    require(
      (await success('notifications.list'))['status'] == 'stopped',
      'notifications must stop',
    );
    await rejected('observation.set', 'stale_observation', {
      'enabled': true,
      'epoch': 1,
    });
    require((await success('calls.list'))['live'] == false, 'calls must stop');
  }

  Future<void> modemState(int wanted) async {
    final deadline = clock.elapsed + const Duration(seconds: 10);
    while (true) {
      final dump =
          (await adb(['shell', 'dumpsys', 'telephony.registry'])).stdout
              as String;
      final matches = const LineSplitter()
          .convert(dump)
          .any((line) => line.trim() == 'mCallState=$wanted');
      var idle = wanted != 0;
      if (!idle) {
        final telecom =
            (await adb(['shell', 'dumpsys', 'telecom'])).stdout as String;
        require(
          telecom.contains('  mCalls:') &&
              telecom.contains('  mCallAudioManager:'),
          'Unknown Telecom dump shape',
        );
        idle = telecom
            .split('  mCalls:')[1]
            .split('  mCallAudioManager:')[0]
            .trim()
            .isEmpty;
      }
      if (matches && idle) return;
      require(clock.elapsed < deadline, 'actual virtual modem state');
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<Json?> callState(String wanted) async {
    final deadline = clock.elapsed + const Duration(seconds: 20);
    while (true) {
      final value = await success('calls.list');
      final current = (value['calls'] as List<dynamic>).cast<Json>();
      if (current.isEmpty && wanted == 'idle') return null;
      if (current.isNotEmpty && current.first['state'] == wanted) {
        return current.first;
      }
      require(clock.elapsed < deadline, 'call state $wanted: $value');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> checkCalls() async {
    require(
      ((await success('calls.list'))['calls'] as List<dynamic>).isEmpty,
      'harness does not disturb an existing call',
    );
    ownedCalls.add('5550101234');
    await adb(['emu', 'gsm', 'call', '5550101234']);
    final ringing = (await callState('ringing'))!;
    for (final action in ['answer', 'reject', 'hangup']) {
      await rejected('calls.action', 'call_targeting_unavailable', {
        'callId': ringing['id'],
        'action': action,
      });
    }
    require(
      (await callState('ringing'))!['id'] == ringing['id'],
      'unsafe action changed the call',
    );
    await adb(['emu', 'gsm', 'cancel', '5550101234']);
    await modemState(0);
    ownedCalls.add('5550101235');
    await adb(['emu', 'gsm', 'call', '5550101235']);
    await modemState(1);
    await callState('ringing');
    await rejected('calls.action', 'call_targeting_unavailable', {
      'callId': ringing['id'],
      'action': 'reject',
    });
    await callState('ringing');
    for (final number in ownedCalls) {
      await adb(['emu', 'gsm', 'cancel', number]);
    }
    await callState('idle');
    require(
      events.any((item) => item['event'] == 'calls.incoming'),
      'real TelephonyRegistry callback',
    );
    stdout.writeln(
      'PASS: real virtual-modem callbacks, rapid replacement remains ringing after old action; '
      'all unsafe aggregate controls refused; no call-audio claim',
    );
  }

  Future<void> cleanup() async {
    final failures = <Object>[];
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failures.add(error);
      }
    }

    for (final number in ownedCalls) {
      await attempt(() async {
        await adb(['emu', 'gsm', 'cancel', number]);
      });
    }
    if (fixture != null) await attempt(() => fixture!.stop(quit: true));
    socket?.destroy();
    if (responses != null) await attempt(() => responses!.cancel());
    if (process != null) {
      await attempt(() => process!.stop(requireSuccess: true));
    }
    if (port != null) {
      await attempt(() async {
        await adb(['forward', '--remove', 'tcp:$port']);
      });
    }
    if (pushed.isNotEmpty) {
      await attempt(() async {
        await adb(['shell', 'rm', '-f', ...pushed]);
      });
    }
    require(failures.isEmpty, 'Probe cleanup failed: $failures');
  }
}

Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addOption('adb')
    ..addOption('serial')
    ..addFlag('calls', negatable: false)
    ..addFlag(
      'skip-receiver',
      negatable: false,
      help: 'Do not assert receiver delivery; PI submission is still tested',
    )
    ..addOption(
      'fixture',
      defaultsTo: p.join(
        Directory.systemTemp.path,
        'interop-companion-fixture.jar',
      ),
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    stdout.writeln(
      'Official-adb test harness for an explicit target AVD.\n${parser.usage}',
    );
    return;
  }
  require(options.rest.isEmpty, 'Unexpected positional arguments');
  require(
    options['adb'] != null && options['serial'] != null,
    '--adb and --serial are required',
  );
  final serial = options['serial'] as String;
  require(
    serial.startsWith('emulator-'),
    'This harness only creates calls on an explicit Android emulator',
  );
  final probe = Probe(
    options['adb'] as String,
    serial,
    calls: options['calls'] as bool,
    skipReceiver: options['skip-receiver'] as bool,
    fixtureFile: File(options['fixture'] as String).absolute,
  );
  Object? failure;
  StackTrace? stack;
  try {
    await probe.execute();
  } catch (error, trace) {
    failure = error;
    stack = trace;
  } finally {
    try {
      await probe.cleanup();
    } catch (error, trace) {
      if (failure != null) stderr.writeln(error);
      failure ??= error;
      stack ??= trace;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, stack!);
});
