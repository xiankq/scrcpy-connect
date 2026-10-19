import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

// Host for the experimental native_input_probe. Screenshots are evidence only;
// collecting one does not establish pixel correctness or display latency.
Future<void> main() async {
  final environment = Platform.environment;
  final adb = environment['CONNECT_E2E_ADB'];
  final device = environment['CONNECT_E2E_DEVICE'];
  final bundle = environment['CONNECT_MDK_INPUT_BUNDLE'];
  if (adb == null ||
      device == null ||
      bundle == null ||
      !File(bundle).existsSync()) {
    throw StateError(
      'Set CONNECT_E2E_ADB, CONNECT_E2E_DEVICE and CONNECT_MDK_INPUT_BUNDLE.',
    );
  }
  const package = 'dev.scrcpyconnect.scrcpy_connect';
  final remoteFixture = '/data/local/tmp/connect-mdk-input-$pid.mdkp';
  var fixtureAttempted = false;
  Future<void> adbRun(List<String> arguments) async {
    final result = await Process.run(adb, [
      '-s',
      device,
      ...arguments,
    ]).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('Fixture adb operation failed: ${result.stderr}');
    }
  }

  final output = Directory(
    environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-mdk-input',
  ).absolute;
  if (!output.uri.normalizePath().toFilePath().startsWith('/tmp/')) {
    throw StateError('Keep native-input evidence under /tmp.');
  }
  await output.create(recursive: true);
  if (!(await output.resolveSymbolicLinks()).startsWith('/tmp/')) {
    throw StateError('Evidence directory resolves outside /tmp.');
  }
  final order =
      (environment['CONNECT_MDK_INPUT_ORDER'] ??
              'http,append,append,http,http,append')
          .split(',');
  final configuredCases = environment['CONNECT_MDK_INPUT_CASES'];
  final cases = configuredCases == null
      ? order.map((mode) => <String, dynamic>{'mode': mode}).toList()
      : (jsonDecode(configuredCases) as List<dynamic>)
            .cast<Map<String, dynamic>>();
  final seconds = int.parse(
    environment['CONNECT_MDK_INPUT_TIMEOUT_SECONDS'] ?? '90',
  );
  if (cases.isEmpty ||
      cases.length > 24 ||
      cases.any(
        (value) => value['mode'] != 'http' && value['mode'] != 'append',
      ) ||
      seconds < 1 ||
      seconds > 600) {
    throw StateError('Invalid order or timeout.');
  }
  final timeout = Duration(seconds: seconds);
  final maxP95 = environment['CONNECT_MDK_INPUT_MAX_P95_US'] == null
      ? null
      : int.parse(environment['CONNECT_MDK_INPUT_MAX_P95_US']!);
  if (maxP95 != null && maxP95 <= 0) {
    throw ArgumentError('Invalid latency budget');
  }
  final runDirectory = await output.createTemp('run-');
  final report = <String, dynamic>{
    'complete': false,
    'order': cases.map((value) => value['mode']).toList(),
    'cases': cases,
    'maxInputToDecodedP95Us': maxP95,
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'screenshotsAreCaptureOnly': true,
    'runs': <Map<String, dynamic>>[],
  };
  FlutterDriver? driver;
  Object? failure;
  StackTrace? failureStack;
  Future<void> persist() =>
      File('${runDirectory.path}/result.json')
          .writeAsString(jsonEncode(report), flush: true);
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> command,
    String name,
  ) async {
    final raw = await driver!.requestData(
      jsonEncode(command),
      timeout: timeout,
    );
    // Persist exact response text before parsing or interpreting success flags.
    await File('${runDirectory.path}/$name.json')
        .writeAsString(raw, flush: true);
    final response = jsonDecode(raw);
    if (response is! Map<String, dynamic>) {
      throw StateError('Probe $name did not return a JSON object.');
    }
    if ((command['command'] == 'run' || command['command'] == 'cleanup') &&
        response['complete'] != true) {
      throw StateError('Probe $name reported failure; see saved response.');
    }
    return response;
  }

  await persist();
  try {
    driver = await FlutterDriver.connect(
      printCommunication: false,
      logCommunicationToFile: false,
    ).timeout(timeout);
    // Install data after flutter drive installs the APK. A prior invocation may
    // have removed its test package; preloading before install is insufficient.
    fixtureAttempted = true;
    await adbRun(['push', bundle, remoteFixture]);
    await adbRun(['shell', 'run-as', package, 'mkdir', '-p', 'files']);
    await adbRun([
      'shell',
      'run-as',
      package,
      'cp',
      remoteFixture,
      'files/native-input-fixture.mdkp',
    ]);
    report['initialState'] = await request({
      'command': 'state',
    }, 'state-before');
    final rounds = <String, int>{'http': 0, 'append': 0};
    for (var index = 0; index < cases.length; index++) {
      final configuration = cases[index];
      final mode = configuration['mode'] as String;
      final round = rounds.update(mode, (value) => value + 1);
      final name = '${index + 1}-$mode-$round';
      final evidence = <String, dynamic>{
        'index': index,
        'mode': mode,
        'round': round,
      };
      (report['runs'] as List).add(evidence);
      await persist();
      evidence['response'] = await request({
        ...configuration,
        'command': 'run',
        'mode': mode,
        'round': round,
      }, name);
      await persist();
      if (maxP95 != null) {
        final response = evidence['response'] as Map<String, dynamic>;
        final summary = response['summary'] as Map<String, dynamic>;
        if ((summary['steadyInputToDecodedP95Us'] as int) > maxP95) {
          throw StateError('Player input-to-onVideo P95 exceeded $maxP95 us');
        }
      }
      final screenshot = await driver.screenshot().timeout(timeout);
      await File('${runDirectory.path}/$name.png')
          .writeAsBytes(screenshot, flush: true);
      evidence['screenshot'] = '$name.png';
      evidence['capturedOnly'] = true;
      evidence['stateAfter'] = await request({
        'command': 'state',
      }, '$name-state');
      await persist();
    }
    report['measurementComplete'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    failure = error;
    failureStack = stack;
  } finally {
    if (driver != null) {
      try {
        report['cleanup'] = await request({'command': 'cleanup'}, 'cleanup');
        report['cleanupComplete'] = true;
      } catch (error, stack) {
        report['cleanupComplete'] = false;
        report['cleanupError'] = '$error';
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (fixtureAttempted) {
      try {
        await adbRun([
          'shell',
          'run-as',
          package,
          'rm',
          '-f',
          'files/native-input-fixture.mdkp',
        ]);
        await adbRun(['shell', 'rm', '-f', remoteFixture]);
        report['fixtureRemoved'] = true;
      } catch (error, stack) {
        report['fixtureRemoved'] = false;
        failure ??= error;
        failureStack ??= stack;
      }
    }
    try {
      await driver?.close().timeout(timeout);
      report['driverClosed'] = driver != null;
    } catch (error, stack) {
      report['driverClosed'] = false;
      report['driverCloseError'] = '$error';
      failure ??= error;
      failureStack ??= stack;
    } finally {
      report['complete'] =
          report['measurementComplete'] == true &&
          report['cleanupComplete'] == true &&
          report['driverClosed'] == true &&
          failure == null;
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      try {
        await persist();
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
      stdout.writeln('Native-input evidence: ${runDirectory.path}');
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}
