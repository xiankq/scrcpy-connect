import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';
import 'package:path/path.dart' as p;

import 'video_clock_bounds.dart';

Future<void> main() async {
  const package = 'dev.scrcpyconnect.videofixture';
  final environment = Platform.environment;
  final adb = environment['CONNECT_E2E_ADB'];
  final target = environment['CONNECT_E2E_TARGET'];
  final controller = environment['CONNECT_E2E_DEVICE'];
  final apk = environment['CONNECT_E2E_VIDEO_FIXTURE'];
  final fixtureMotion = environment['CONNECT_E2E_VIDEO_MOTION'] == 'true';
  final timelineEnabled = environment['CONNECT_E2E_VIDEO_TIMELINE'] == 'true';
  final timelineRun = 'video_${DateTime.now().microsecondsSinceEpoch}_$pid';
  List<Map<String, dynamic>>? targetTimeline;
  String? targetTimelineError;
  if (adb == null ||
      target == null ||
      controller == null ||
      target == controller ||
      apk == null) {
    throw StateError(
      'Set CONNECT_E2E_ADB, distinct DEVICE/TARGET, and CONNECT_E2E_VIDEO_FIXTURE.',
    );
  }
  final output = Directory(
    environment['CONNECT_E2E_CAPTURE_DIR'] ??
        p.join(Directory.systemTemp.path, 'connect-e2e', 'video-performance'),
  );
  final temporaryRoots = [
    Directory.systemTemp.absolute.path,
    if (!Platform.isWindows) '/tmp',
    if (Platform.isMacOS) '/private/tmp',
  ];
  if (!temporaryRoots.any((root) => p.isWithin(root, output.absolute.path))) {
    throw StateError('Keep evidence in the system temporary directory.');
  }
  await output.create(recursive: true);
  Future<String> command(List<String> args) async {
    final result = await Process.run(adb, [
      '-s',
      target,
      ...args,
    ]).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw StateError('Target ${args.first} failed: ${result.stderr}');
    }
    return result.stdout as String;
  }

  Future<bool> fixtureExists() async {
    final result = await Process.run(adb, [
      '-s',
      target,
      'shell',
      'pm',
      'path',
      package,
    ]).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0 &&
        (result.exitCode != 1 || '${result.stderr}'.trim().isNotEmpty)) {
      throw StateError('Cannot inspect fixture ownership: ${result.stderr}');
    }
    return '${result.stdout}'.trim().isNotEmpty;
  }

  if (await fixtureExists()) {
    throw StateError(
      'Refusing to replace an existing independent fixture installation.',
    );
  }
  var installed = false;
  Future<void> capture(String serial, String name) async {
    final result = await Process.run(adb, [
      '-s',
      serial,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) throw StateError('Cannot capture $name.');
    await File('${output.path}/$name.png')
        .writeAsBytes(result.stdout as List<int>);
  }

  Future<void> cleanupFixture() async {
    if (!installed) return;
    final cleanup = <String, Object?>{};
    if (installed) {
      if (timelineEnabled) {
        try {
          final log = await command([
            'logcat',
            '-d',
            '-v',
            'raw',
            '-s',
            'ConnectVideoClock:I',
            '*:S',
          ]);
          final records = <Map<String, dynamic>>[];
          for (final line in const LineSplitter().convert(log)) {
            if (!line.startsWith('{')) continue;
            final record = jsonDecode(line) as Map<String, dynamic>;
            if (record['run'] == timelineRun) records.add(record);
          }
          // Preserve even a partial/empty timeline after an early native crash.
          // Successful samples are checked below, after uninstall completes.
          targetTimeline = records;
          await File('${output.path}/target-timeline.json')
              .writeAsString(jsonEncode(records));
        } catch (error) {
          // A missing observation must still uninstall this invocation's APK.
          cleanup['timelineError'] = '$error';
          targetTimelineError = '$error';
        }
      }
      try {
        await capture(target, 'target-final');
      } catch (error) {
        cleanup['captureError'] = '$error';
      }
      cleanup['uninstalled'] = (await command(['uninstall', package]))
          .contains('Success');
      cleanup['absent'] = !await fixtureExists();
      await command([
        'shell',
        'am',
        'start',
        '-a',
        'android.settings.SETTINGS',
      ]);
    }
    await File('${output.path}/cleanup.json')
        .writeAsString(jsonEncode(cleanup));
    if (cleanup['uninstalled'] != true || cleanup['absent'] != true) {
      throw StateError('Independent fixture cleanup not confirmed.');
    }
    installed = false;
  }

  try {
    final install = await command(['install', apk]);
    if (!install.contains('Success')) {
      throw StateError('Fixture installation not confirmed.');
    }
    installed = true;
    await command([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$package/.VideoPatternActivity',
      '--ez',
      'motion',
      '$fixtureMotion',
      if (timelineEnabled) ...['--es', 'timelineRun', timelineRun],
    ]);
    await capture(target, 'target-initial');
    final driver = await FlutterDriver.connect();
    final response = await driver.serviceClient.callServiceExtension(
      'ext.connect.videoPerformance',
      isolateId: driver.appIsolate.id,
      args: {'ready': 'true'},
    );
    if (response.json?['ready'] != true) {
      throw StateError('App did not acknowledge fixture readiness.');
    }
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      onScreenshot: (name, bytes, [args]) async {
        final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        await File('${output.path}/$safe.png').writeAsBytes(bytes);
        return true;
      },
      responseDataCallback: (data) async {
        // integrationDriver exits the VM, so finally alone cannot clean up.
        await cleanupFixture();
        final report = {...?data}..remove('screenshots');
        report['fixtureCleanupConfirmed'] = true;
        report['fixtureMotionEnabled'] = fixtureMotion;
        if (timelineEnabled) {
          report['targetTimeline'] = targetTimeline;
          if (targetTimelineError != null) {
            report['targetTimelineError'] = targetTimelineError;
          }
          final missing = <int>[];
          final segments = <Map<String, dynamic>>[];
          for (final round in (report['rounds'] as List? ?? const [])) {
            for (final sample in [
              ...round['samples'] as List,
              ...round['pauseSamples'] as List? ?? const [],
            ]) {
              final sequence = sample['fixtureSequence'];
              // A failed pause may never have sent its next input. Preserve
              // that original failure rather than failing this postprocessor.
              if (sequence is! int) continue;
              final counter = sample['counter'] ?? sample['expectedCounter'];
              final inputs = (targetTimeline ?? const <Map<String, dynamic>>[])
                  .where(
                    (r) => r['sequence'] == sequence && r['kind'] == 'input',
                  )
                  .toList();
              final draws = (targetTimeline ?? const <Map<String, dynamic>>[])
                  .where(
                    (r) => r['sequence'] == sequence && r['kind'] == 'draw',
                  )
                  .toList();
              if (inputs.length != 1 ||
                  draws.length != 1 ||
                  inputs.single['counter'] != counter ||
                  draws.single['counter'] != counter) {
                missing.add(sequence);
                continue;
              }
              final input = inputs.single, draw = draws.single;
              final wait =
                  (draw['drawStartUs'] as int) - (input['nanoUs'] as int);
              final duration =
                  (draw['nanoUs'] as int) - (draw['drawStartUs'] as int);
              if (wait < 0 || duration < 0) missing.add(sequence);
              segments.add({
                'sequence': sequence,
                'counter': counter,
                'inputToDrawStartUs': wait,
                'drawCallbackUs': duration,
              });
            }
          }
          report['targetDrawSegments'] = segments;
          report['missingTargetSequences'] = missing;
          report['targetTimelineComplete'] =
              targetTimelineError == null &&
              missing.isEmpty &&
              segments.isNotEmpty;
        }
        if (report['clockBracketsRequested'] == true) {
          report['clockBounds'] = videoClockBounds(
            (report['rounds'] as List).cast<ClockJson>(),
            targetTimeline ?? const [],
          );
        }
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report));
        if (report['videoPerformanceComplete'] != true) {
          throw StateError('Video performance loop incomplete.');
        }
        if (timelineEnabled && report['targetTimelineComplete'] != true) {
          throw StateError(
            'Target timeline does not cover every actual input.',
          );
        }
        if (report['clockBracketsRequested'] == true &&
            (report['clockBounds'] as ClockJson)['complete'] != true) {
          throw StateError(
            'Conditional clock bounds are incomplete; see raw probes.',
          );
        }
      },
    );
  } finally {
    await cleanupFixture();
  }
}
