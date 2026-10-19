import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

// Host for the experimental native_input_probe. Screenshots are evidence only;
// collecting one does not establish pixel correctness or display latency.
Future<void> main() async {
  final environment = Platform.environment;
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
  final seconds = int.parse(
    environment['CONNECT_MDK_INPUT_TIMEOUT_SECONDS'] ?? '90',
  );
  if (order.isEmpty ||
      order.any((mode) => mode != 'http' && mode != 'append') ||
      seconds < 1 ||
      seconds > 600) {
    throw StateError('Invalid order or timeout.');
  }
  final timeout = Duration(seconds: seconds);
  final runDirectory = await output.createTemp('run-');
  final report = <String, dynamic>{
    'complete': false,
    'order': order,
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
    report['initialState'] = await request({
      'command': 'state',
    }, 'state-before');
    final rounds = <String, int>{'http': 0, 'append': 0};
    for (var index = 0; index < order.length; index++) {
      final mode = order[index];
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
        'command': 'run',
        'mode': mode,
        'round': round,
      }, name);
      await persist();
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
