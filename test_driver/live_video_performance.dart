import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_driver/flutter_driver.dart';

import '../benchmark/live_video/android_screencap.dart';
import 'video_source_report.dart';

const _fixturePackage = 'dev.scrcpyconnect.videofixture';
const _requestTimeout = Duration(seconds: 45);
const _overallTimeout = Duration(minutes: 20);

/// Host for benchmark/live_video_performance.dart. Screenshots come from adb
/// after each timed app command, so capture/PNG validation adds no input latency.
Future<void> main() async {
  final environment = Platform.environment;
  final output = Directory(
    environment['CONNECT_E2E_CAPTURE_DIR'] ??
        '/tmp/connect-e2e/live-video-performance',
  );
  // Resolve dot segments before checking confinement. Also check the resolved
  // directory after creation, because an existing ancestor can be a symlink.
  if (!output.absolute.uri.normalizePath().toFilePath().startsWith('/tmp/')) {
    throw StateError('Keep evidence under /tmp.');
  }
  await output.create(recursive: true);
  if (!(await output.resolveSymbolicLinks()).startsWith('/tmp/')) {
    throw StateError('Keep evidence under /tmp, including symlink targets.');
  }

  final started = DateTime.now().toUtc();
  final clock = Stopwatch()..start();
  final progress = <String, dynamic>{
    'startedAt': started.toIso8601String(),
    'phase': 'initializing',
    'commands': <Map<String, dynamic>>[],
    'surfaces': <Map<String, dynamic>>[],
  };
  final report = <String, dynamic>{'videoPerformanceComplete': false};
  final cleanup = <String, dynamic>{
    'installationConfirmed': false,
    'uninstalled': false,
    'absent': false,
  };
  final errors = <String>[];
  FlutterDriver? driver;
  var installed = false;
  var installAttempted = false;
  List<int>? fixtureApkBytes;
  var appCleanupConfirmed = false;
  var driverCloseConfirmed = false;
  var fixturePreflightComplete = false;
  var targetFinalCaptured = false;
  var cleaningUp = false;

  Future<void> writeJson(String name, Object data) async {
    final temporary = File('${output.path}/$name.pending');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename('${output.path}/$name');
  }

  Future<void> persist() async {
    try {
      await writeJson('progress.json', progress);
    } catch (error) {
      if (!cleaningUp) rethrow;
      errors.add('Progress persistence: ${_safeError(error)}');
    }
  }

  Future<void> phase(String value) async {
    progress['phase'] = value;
    progress['elapsedMs'] = clock.elapsedMilliseconds;
    await persist();
    stdout.writeln('live video: $value');
  }

  Duration remaining(Duration limit) {
    final available = _overallTimeout - clock.elapsed;
    if (available <= Duration.zero) {
      throw TimeoutException('Overall benchmark deadline exceeded.');
    }
    return available < limit ? available : limit;
  }

  final adb = environment['CONNECT_E2E_ADB'];
  final target = environment['CONNECT_E2E_TARGET'];
  final controller = environment['CONNECT_E2E_DEVICE'];
  final apk = environment['CONNECT_E2E_VIDEO_FIXTURE'];
  final motion = environment['CONNECT_E2E_VIDEO_MOTION'] == 'true';
  final timelineEnabled = environment['CONNECT_E2E_VIDEO_TIMELINE'] == 'true';
  final timelineRun = 'live_${DateTime.now().microsecondsSinceEpoch}_$pid';
  final targetTimeline = <Map<String, dynamic>>[];
  String? targetTimelineError;
  final windowCapture = environment['CONNECT_E2E_SCREEN_CAPTURE'] ?? 'png';
  final diagnosticSurfaceMs = int.tryParse(
    environment['CONNECT_E2E_DIAGNOSTIC_SURFACE_MS'] ?? '3000',
  );

  Future<ProcessResult> adbRun(
    String serial,
    List<String> arguments, {
    bool binary = false,
    bool cleaning = false,
    Duration? timeoutLimit,
  }) async {
    final requested = timeoutLimit ?? _requestTimeout;
    final limit = cleaning ? requested : remaining(requested);
    return _runProcess(
      adb!,
      ['-s', serial, ...arguments],
      timeout: limit,
      binary: binary,
      onInterrupted: (evidence) {
        final records = progress.putIfAbsent(
          'interruptedAdbProcesses',
          () => <Map<String, Object?>>[],
        ) as List;
        evidence['operation'] = arguments.first;
        records.add(evidence);
      },
    );
  }

  Future<String> targetCommand(
    List<String> arguments, {
    bool cleaning = false,
  }) async {
    final result = await adbRun(target!, arguments, cleaning: cleaning);
    if (result.exitCode != 0) {
      throw StateError(
        'Target ${arguments.first} failed (${result.exitCode}).',
      );
    }
    return result.stdout as String;
  }

  Future<List<String>> fixturePaths({
    bool cleaning = false,
    Duration? timeoutLimit,
  }) async {
    final result = await adbRun(
      target!,
      ['shell', 'pm', 'path', _fixturePackage],
      cleaning: cleaning,
      timeoutLimit: timeoutLimit,
    );
    if (result.exitCode != 0 &&
        (result.exitCode != 1 || '${result.stderr}'.trim().isNotEmpty)) {
      throw StateError('Cannot inspect independent fixture ownership.');
    }
    final lines = const LineSplitter()
        .convert('${result.stdout}')
        .where((line) => line.trim().isNotEmpty);
    return lines.map((line) {
      if (!line.startsWith('package:')) {
        throw StateError('Unexpected fixture package path response.');
      }
      return line.substring('package:'.length).trim();
    }).toList();
  }

  Future<bool> fixtureExists({bool cleaning = false}) async =>
      (await fixturePaths(cleaning: cleaning)).isNotEmpty;

  Future<void> recoverUnknownInstallation() async {
    final evidence = <String, dynamic>{'attempts': <Map<String, dynamic>>[]};
    cleanup['installationRecovery'] = evidence;
    final deadline = Stopwatch()..start();
    Duration recoveryTimeLeft() {
      final left = const Duration(seconds: 15) - deadline.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException('Fixture ownership recovery deadline exceeded.');
      }
      return left < const Duration(seconds: 5)
          ? left
          : const Duration(seconds: 5);
    }

    // adb install can lose its acknowledgement after package manager committed
    // the transaction. Only identical APK bytes establish ownership here.
    for (var attempt = 1; attempt <= 3; attempt++) {
      final paths = await fixturePaths(
        cleaning: true,
        timeoutLimit: recoveryTimeLeft(),
      );
      (evidence['attempts'] as List).add({
        'attempt': attempt,
        'packagePresent': paths.isNotEmpty,
      });
      await persist();
      if (paths.isNotEmpty) {
        final safeBaseApk = RegExp(
          r'^/data/app/(?:~~[A-Za-z0-9_+=.-]+/)?'
          r'dev\.scrcpyconnect\.videofixture-[A-Za-z0-9_+=.-]+/base\.apk$',
        );
        if (paths.length != 1 || !safeBaseApk.hasMatch(paths.single)) {
          throw StateError('Fixture APK path cannot safely prove ownership.');
        }
        final result = await adbRun(
          target!,
          ['exec-out', 'cat', paths.single],
          binary: true,
          cleaning: true,
          timeoutLimit: recoveryTimeLeft(),
        );
        if (result.exitCode != 0) {
          throw StateError('Cannot read installed fixture APK for ownership.');
        }
        final actual = result.stdout as List<int>;
        final expected = fixtureApkBytes!;
        var matches = actual.length == expected.length;
        for (var index = 0; matches && index < actual.length; index++) {
          matches = actual[index] == expected[index];
        }
        evidence['apkBytesMatch'] = matches;
        if (!matches) {
          throw StateError('Unknown fixture differs from this invocation APK.');
        }
        installed = true;
        cleanup['ownershipConfirmedByApkBytes'] = true;
        await persist();
        return;
      }
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    cleanup['absent'] = true;
    evidence['absentAfterBoundedRecheck'] = true;
  }

  Future<List<int>> capture(
    String serial,
    String name, {
    bool cleaning = false,
    Duration? timeoutLimit,
  }) async {
    final result = await adbRun(
      serial,
      ['exec-out', 'screencap', '-p'],
      binary: true,
      cleaning: cleaning,
      timeoutLimit: timeoutLimit,
    );
    if (result.exitCode != 0) throw StateError('Cannot capture $name.');
    final bytes = result.stdout as List<int>;
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < signature.length ||
        List.generate(signature.length, (index) => bytes[index]).join(',') !=
            signature.join(',')) {
      throw StateError('Capture $name is not a PNG.');
    }
    await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
    return bytes;
  }

  Future<Uint8List> captureRaw(String name, Duration timeout) async {
    final result = await adbRun(
      controller!,
      ['exec-out', 'screencap'],
      binary: true,
      timeoutLimit: timeout,
    );
    if (result.exitCode != 0) throw StateError('Cannot capture $name.');
    final outputBytes = result.stdout as List<int>;
    final bytes = outputBytes is Uint8List
        ? outputBytes
        : Uint8List.fromList(outputBytes);
    // Preserve unsupported captures too; parsing must never guess a layout.
    // Full, unmodified actual window bytes, including the Android header.
    await File('${output.path}/$name.raw').writeAsBytes(bytes, flush: true);
    AndroidRgbaScreenshot.parse(bytes);
    return bytes;
  }

  Future<Map<String, dynamic>> request(
    String command, {
    Map<String, dynamic> arguments = const {},
    bool cleaning = false,
    Duration? timeoutLimit,
  }) async {
    final entry = <String, dynamic>{
      'command': command,
      'startedAtMs': clock.elapsedMilliseconds,
      // The PNG itself remains in its .png evidence file, never in JSON/logs.
      if (arguments.containsKey('pngBase64')) 'hasPng': true,
      if (arguments.containsKey('androidRawBase64')) 'hasAndroidRaw': true,
    };
    (progress['commands'] as List).add(entry);
    await persist();
    try {
      final requested = timeoutLimit ?? _requestTimeout;
      final timeout = cleaning ? requested : remaining(requested);
      final response = await driver!
          .requestData(
            jsonEncode({'command': command, ...arguments}),
            timeout: timeout,
          )
          .timeout(timeout);
      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('App $command response is not a JSON object.');
      }
      if (command == 'archive.read' && decoded['data'] is Map) {
        entry['response'] = {
          'ok': decoded['ok'],
          'data': {...decoded['data'] as Map}..remove('bytesBase64'),
        };
      } else {
        entry['response'] = decoded;
      }
      if (decoded['ok'] != true || decoded['data'] is! Map<String, dynamic>) {
        throw StateError('App rejected $command; see its saved response.');
      }
      return decoded['data'] as Map<String, dynamic>;
    } catch (error) {
      entry['error'] = _safeError(error);
      rethrow;
    } finally {
      entry['finishedAtMs'] = clock.elapsedMilliseconds;
      await persist();
    }
  }

  Future<void> surface(String name, Map<String, dynamic> preceding) async {
    final expected = preceding['expectedCounter'] ?? preceding['counter'];
    if (expected is! int) {
      throw StateError('$name did not provide an integer expected counter.');
    }
    final wait = Stopwatch()..start();
    final evidence = <String, dynamic>{
      'name': name,
      'expectedCounter': expected,
      'budgetMs': 3000,
      'collectionDeadlineMs': diagnosticSurfaceMs,
      'attempts': <Map<String, dynamic>>[],
    };
    (progress['surfaces'] as List).add(evidence);
    Duration surfaceTimeLeft() {
      final left = Duration(milliseconds: diagnosticSurfaceMs!) - wait.elapsed;
      if (left <= Duration.zero) {
        throw TimeoutException('Actual surface collection deadline exceeded.');
      }
      return left;
    }

    try {
      for (var attempt = 1; attempt <= 8; attempt++) {
        final file = '$name-attempt-$attempt';
        final attemptEvidence = <String, dynamic>{
          'file': '$file.${windowCapture == 'raw' ? 'raw' : 'png'}',
          'captureMode': windowCapture,
          'captureCompleted': false,
        };
        (evidence['attempts'] as List).add(attemptEvidence);
        final captureClock = Stopwatch()..start();
        late final List<int> bytes;
        try {
          bytes = windowCapture == 'raw'
              ? await captureRaw(file, surfaceTimeLeft())
              : await capture(
                  controller!,
                  file,
                  timeoutLimit: surfaceTimeLeft(),
                );
        } finally {
          attemptEvidence['captureAndPersistMs'] =
              captureClock.elapsedMilliseconds;
          await persist();
        }
        attemptEvidence['captureCompleted'] = true;
        attemptEvidence['bytes'] = bytes.length;
        final encodingClock = Stopwatch()..start();
        final encoded = base64Encode(bytes);
        attemptEvidence['payloadEncodingMs'] =
            encodingClock.elapsedMilliseconds;
        final validationClock = Stopwatch()..start();
        late final Map<String, dynamic> result;
        try {
          result = await request(
            'surface',
            arguments: {
              windowCapture == 'raw' ? 'androidRawBase64' : 'pngBase64':
                  encoded,
            },
            timeoutLimit: surfaceTimeLeft(),
          );
        } finally {
          attemptEvidence['validationRequestMs'] =
              validationClock.elapsedMilliseconds;
          await persist();
        }
        attemptEvidence.addAll({
          ...result,
          'elapsedMs': wait.elapsedMilliseconds,
        });
        if (result['captureFormat'] !=
            (windowCapture == 'raw' ? 'android-raw-rgba8888' : 'png')) {
          throw StateError('Unexpected actual window capture format.');
        }
        evidence['surfaceWaitMs'] = wait.elapsedMilliseconds;
        evidence['attemptCount'] = attempt;
        await persist();
        if (result['expectedCounter'] != expected) {
          throw StateError('Surface expected counter changed: $name.');
        }
        if (result['valid'] == true && result['counter'] == expected) {
          evidence['valid'] = true;
          return;
        }
        if (attempt < 8) {
          final left = surfaceTimeLeft();
          const interval = Duration(milliseconds: 30);
          await Future<void>.delayed(left < interval ? left : interval);
        }
      }
      throw StateError('Actual controller surface verification failed: $name.');
    } finally {
      evidence['surfaceWaitMs'] = wait.elapsedMilliseconds;
      evidence['budgetMet'] =
          evidence['valid'] == true && wait.elapsedMilliseconds <= 3000;
      await persist();
    }
  }

  await persist();
  try {
    if (diagnosticSurfaceMs == null ||
        diagnosticSurfaceMs < 3000 ||
        diagnosticSurfaceMs > 15000) {
      throw StateError('Diagnostic surface deadline must be 3000..15000 ms.');
    }
    if (windowCapture != 'png' && windowCapture != 'raw') {
      throw StateError('CONNECT_E2E_SCREEN_CAPTURE must be png or raw.');
    }
    if (adb == null ||
        adb.isEmpty ||
        target == null ||
        target.isEmpty ||
        controller == null ||
        controller.isEmpty ||
        target == controller ||
        apk == null ||
        apk.isEmpty) {
      throw StateError(
        'Set CONNECT_E2E_ADB, distinct DEVICE/TARGET, and '
        'CONNECT_E2E_VIDEO_FIXTURE.',
      );
    }
    if (!await File(apk).exists()) {
      throw StateError('Independent fixture APK does not exist.');
    }
    fixtureApkBytes = await File(apk).readAsBytes();
    await phase('fixture preflight');
    if (await fixtureExists()) {
      throw StateError('Refusing to replace an existing fixture installation.');
    }
    fixturePreflightComplete = true;
    cleanup['preexistingFixtureAbsent'] = true;
    progress['fixture'] = cleanup;
    installAttempted = true;
    cleanup['installAttempted'] = true;
    cleanup['installationOutcomeUnknown'] = true;
    await persist();
    final install = await targetCommand(['install', apk]);
    if (!install.contains('Success')) {
      throw StateError('Fixture installation was not confirmed.');
    }
    installed = true;
    cleanup['installationConfirmed'] = true;
    cleanup['installationOutcomeUnknown'] = false;
    await persist();
    await targetCommand([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$_fixturePackage/.VideoPatternActivity',
      '--ez',
      'motion',
      '$motion',
      if (timelineEnabled) ...['--es', 'timelineRun', timelineRun],
    ]);
    await capture(target, 'target-initial');
    await phase('connecting driver');
    var connectionExpired = false;
    final connection =
        FlutterDriver.connect(
          printCommunication: false,
          logCommunicationToFile: false,
        ).then((connected) async {
          if (connectionExpired) {
            await connected.close();
            throw TimeoutException(
              'Driver connection arrived after its deadline.',
            );
          }
          return connected;
        });
    try {
      driver = await connection.timeout(remaining(const Duration(seconds: 90)));
    } on TimeoutException {
      connectionExpired = true;
      rethrow;
    }
    await (() async {
      final setup = await request('setup');
      progress['setup'] = setup;
      if ((setup['clockBracketsRequested'] == true) != timelineEnabled) {
        throw StateError(
          'Match CONNECT_E2E_VIDEO_TIMELINE with CONNECT_PERF_TRACE_CLOCK.',
        );
      }
      final rounds = setup['roundCount'];
      final config = setup['config'];
      final transitions =
          setup['transitions'] ??
          (config is Map ? config['transitions'] : null);
      if (rounds is! int ||
          rounds < 1 ||
          transitions is! int ||
          transitions < 1) {
        throw StateError('Invalid setup roundCount/transitions.');
      }
      for (var round = 1; round <= rounds; round++) {
        await phase('round $round/$rounds');
        final start = await request('start');
        await surface('round-$round-start', start);
        for (var transition = 1; transition <= transitions; transition++) {
          final input = await request('input');
          await surface('round-$round-input-$transition', input);
        }
        if (setup['packetArchiveRequested'] == true) {
          await phase('exporting complete packet archive');
          final metadata = await request('archive.seal');
          final length = metadata['bytes'];
          if (metadata['complete'] != true ||
              length is! int ||
              length < 1 ||
              length > 32 * 1024 * 1024 ||
              metadata['frames'] is! List) {
            throw StateError('Incomplete packet archive metadata.');
          }
          final directory = await output.createTemp('round-$round-archive-');
          final file = File('${directory.path}/capture.mkv');
          final sink = await file.open(mode: FileMode.writeOnly);
          try {
            var offset = 0;
            while (offset < length) {
              final page = await request(
                'archive.read',
                arguments: {'offset': offset},
              );
              final bytes = base64Decode(page['bytesBase64'] as String);
              if (page['offset'] != offset ||
                  bytes.isEmpty ||
                  bytes.length > 65536 ||
                  page['bytes'] != bytes.length ||
                  page['nextOffset'] != offset + bytes.length ||
                  offset + bytes.length > length ||
                  page['eof'] != (offset + bytes.length == length)) {
                throw StateError('Invalid or incomplete packet archive page.');
              }
              await sink.writeFrom(bytes);
              offset += bytes.length;
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          await File('${directory.path}/archive.json')
              .writeAsString(jsonEncode(metadata), flush: true);
          final archives =
              report.putIfAbsent('packetArchives', () => <Object>[]) as List;
          archives.add({
            'round': round - 1,
            'directory': directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last,
            'bytes': length,
            'frames': (metadata['frames'] as List).length,
            'complete': true,
          });
        }
        final pause = await request('pause');
        if (pause['paused'] != true && pause['pauseConfirmed'] != true) {
          throw StateError('App did not confirm the paused state.');
        }
        await surface('round-$round-pause', pause);
        await request('stop');
      }
      await phase('finishing');
      report.addAll(await request('finish'));
      report['measurementLoopComplete'] = true;
      await persist();
    })();
  } catch (error) {
    errors.add(_safeError(error));
    progress['error'] = errors.last;
  } finally {
    cleaningUp = true;
    await phase('cleanup');
    if (driver != null) {
      try {
        final result = await request('cleanup', cleaning: true);
        report['appCleanup'] = result;
        appCleanupConfirmed = [
          'complete',
          'outputsDisposed',
          'deviceRemoved',
          'deviceDisconnected',
        ].every((key) => result[key] == true);
        if (!appCleanupConfirmed) {
          errors.add('App cleanup flags were not all confirmed.');
        }
      } catch (error) {
        errors.add('App cleanup: ${_safeError(error)}');
      } finally {
        try {
          await driver.close().timeout(_requestTimeout);
          driverCloseConfirmed = true;
        } catch (error) {
          errors.add('Driver close: ${_safeError(error)}');
        }
      }
    }
    if (installAttempted && !installed && fixturePreflightComplete) {
      try {
        await recoverUnknownInstallation();
      } catch (error) {
        cleanup['ownershipRecoveryError'] = _safeError(error);
        errors.add('Fixture ownership recovery: ${_safeError(error)}');
      }
    }
    if (installed) {
      if (timelineEnabled) {
        try {
          final text = await targetCommand([
            'logcat',
            '-d',
            '-v',
            'raw',
            '-s',
            'ConnectVideoClock:I',
            '*:S',
          ], cleaning: true);
          for (final line in const LineSplitter().convert(text)) {
            if (!line.startsWith('{')) continue;
            final record = jsonDecode(line) as Map<String, dynamic>;
            if (record['run'] == timelineRun) targetTimeline.add(record);
          }
        } catch (error) {
          targetTimelineError = _safeError(error);
          errors.add('Target timeline: $targetTimelineError');
        }
        try {
          // Even missing/partial logs must be persisted before uninstall, and
          // a diagnostic read/write failure must never prevent uninstall.
          await writeJson('target-timeline.json', targetTimeline);
        } catch (error) {
          targetTimelineError = _safeError(error);
          errors.add('Target timeline persistence: $targetTimelineError');
        }
      }
      try {
        await capture(target!, 'target-final', cleaning: true);
        targetFinalCaptured = true;
      } catch (error) {
        errors.add('Final target capture: ${_safeError(error)}');
      }
      try {
        final result = await targetCommand([
          'uninstall',
          _fixturePackage,
        ], cleaning: true);
        cleanup['uninstalled'] = result.contains('Success');
      } catch (error) {
        cleanup['uninstallError'] = _safeError(error);
        errors.add('Fixture uninstall: ${_safeError(error)}');
      }
      // Check absence independently even when the uninstall command failed.
      try {
        cleanup['absent'] = !await fixtureExists(cleaning: true);
      } catch (error) {
        cleanup['absenceError'] = _safeError(error);
        errors.add('Fixture absence check: ${_safeError(error)}');
      }
      if (cleanup['uninstalled'] != true || cleanup['absent'] != true) {
        errors.add('Independent fixture cleanup was not confirmed.');
      }
    }
    cleanup['complete'] =
        installed &&
        cleanup['uninstalled'] == true &&
        cleanup['absent'] == true;
    cleanup['preflightComplete'] = fixturePreflightComplete;
    report['appCleanupConfirmed'] = appCleanupConfirmed;
    report['driverCloseConfirmed'] = driverCloseConfirmed;
    report['fixtureCleanup'] = cleanup;
    report['fixtureCleanupConfirmed'] = cleanup['complete'];
    report['fixtureMotionEnabled'] = motion;
    report['windowCaptureMode'] = windowCapture;
    final setup = progress['setup'] as Map<String, dynamic>?;
    final clockRequested = setup?['clockBracketsRequested'] == true;
    final diagnosticOnly =
        diagnosticSurfaceMs != 3000 ||
        setup?['traceFrames'] == true ||
        clockRequested;
    report['diagnosticOnly'] = diagnosticOnly;
    if (timelineEnabled || clockRequested) {
      report['clockBracketsRequested'] = clockRequested;
      report['targetTimelineRun'] = timelineRun;
      report['targetTimeline'] = targetTimeline;
      if (targetTimelineError != null) {
        report['targetTimelineError'] = targetTimelineError;
      }
      try {
        report.addAll(
          videoSourceReport(
            (report['rounds'] as List? ?? const [])
                .cast<Map<String, dynamic>>(),
            targetTimeline,
          ),
        );
      } catch (error) {
        errors.add('Source diagnostics: ${_safeError(error)}');
      }
      if (targetTimelineError != null ||
          report['targetTimelineComplete'] != true) {
        errors.add('Target timeline does not cover every actual input.');
      }
      if (clockRequested &&
          (report['clockBounds'] as Map?)?['complete'] != true) {
        errors.add('Conditional source clock bounds incomplete.');
      }
    }
    report['surfaceBudgetMs'] = 3000;
    report['surfaceCollectionDeadlineMs'] = diagnosticSurfaceMs;
    final surfaces = progress['surfaces'] as List;
    final surfaceBudgetMet =
        surfaces.isNotEmpty &&
        surfaces.every((s) => (s as Map<String, dynamic>)['budgetMet'] == true);
    report['surfaceBudgetMet'] = surfaceBudgetMet;
    report['targetFinalCaptured'] = targetFinalCaptured;
    report['surfaces'] = progress['surfaces'];
    report['interruptedAdbProcesses'] = progress['interruptedAdbProcesses'];
    if (report['measurementLoopComplete'] != true) {
      errors.add('Video performance loop incomplete.');
    } else if (report['videoPerformanceComplete'] != true) {
      errors.add('Startup or input latency budget failed.');
    }
    if (diagnosticOnly) {
      errors.add('Diagnostic collection cannot certify video performance.');
    }
    if (!surfaceBudgetMet) {
      errors.add('Actual window did not meet its 3000ms budget.');
    }
    final complete =
        !diagnosticOnly &&
        surfaceBudgetMet &&
        report['videoPerformanceComplete'] == true &&
        appCleanupConfirmed &&
        driverCloseConfirmed &&
        cleanup['complete'] == true &&
        targetFinalCaptured &&
        errors.isEmpty;
    report['videoPerformanceComplete'] = complete;
    report['errors'] = errors;
    report['startedAt'] = started.toIso8601String();
    report['elapsedMs'] = clock.elapsedMilliseconds;
    progress['phase'] = complete ? 'complete' : 'failed';
    progress['errors'] = errors;
    progress['result'] = report;
    await persist();
    await writeJson('cleanup.json', cleanup);
    await writeJson('result.json', report);
    if (!complete) {
      stderr.writeln('live video failed; inspect ${output.path}/result.json');
      exitCode = 1;
    } else {
      stdout.writeln('live video complete: ${output.path}/result.json');
    }
  }
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  required bool binary,
  required void Function(Map<String, Object?> evidence) onInterrupted,
}) async {
  final elapsed = Stopwatch()..start();
  final process = await Process.start(executable, arguments);
  final stdoutBytes = <int>[];
  final stderrBytes = <int>[];
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  final outputSubscription = process.stdout.listen(
    stdoutBytes.addAll,
    onDone: stdoutDone.complete,
    onError: stdoutDone.completeError,
  );
  final errorSubscription = process.stderr.listen(
    stderrBytes.addAll,
    onDone: stderrDone.complete,
    onError: stderrDone.completeError,
  );
  final exited = process.exitCode;
  final completed = Future.wait<dynamic>([
    exited,
    stdoutDone.future,
    stderrDone.future,
  ]);
  try {
    final available = timeout - elapsed.elapsed;
    final values = await completed.timeout(
      available > Duration.zero ? available : Duration.zero,
    );
    return ProcessResult(
      process.pid,
      values.first as int,
      binary ? stdoutBytes : systemEncoding.decode(stdoutBytes),
      systemEncoding.decode(stderrBytes),
    );
  } catch (_) {
    final evidence = <String, Object?>{'pid': process.pid};
    onInterrupted(evidence);
    evidence['terminateSent'] = process.kill(ProcessSignal.sigterm);
    try {
      evidence['exitCode'] = await exited.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      evidence['killSent'] = process.kill(ProcessSignal.sigkill);
      try {
        evidence['exitCode'] = await exited.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        evidence['exitConfirmed'] = false;
        throw StateError('adb process exit could not be confirmed after kill.');
      }
    }
    evidence['exitConfirmed'] = true;
    try {
      // Drain both pipes after the child exits. A descendant inheriting a pipe
      // cannot keep the host alive: subscriptions are canceled below as well.
      await completed.timeout(const Duration(seconds: 2));
      evidence['streamsDrained'] = true;
    } catch (_) {
      evidence['streamsDrained'] = false;
    }
    rethrow;
  } finally {
    await Future.wait([outputSubscription.cancel(), errorSubscription.cancel()])
        .timeout(const Duration(seconds: 2));
  }
}

String _safeError(Object error) {
  // A driver exception can echo a command. Keep PNGs and token-like fields out
  // of error evidence, even if a transport unexpectedly includes the payload.
  final value = '$error'
      .replaceAll(RegExp(r'[A-Za-z0-9+/=]{120,}'), '<payload redacted>')
      .replaceAll(
        RegExp(r'(?i:token|password|secret)\s*[:=]\s*[^\s,}]+'),
        '<credential redacted>',
      );
  return value.length > 2000 ? value.substring(0, 2000) : value;
}
