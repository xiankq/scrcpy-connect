import 'dart:convert';
import 'dart:io';

import 'support/capture.dart';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';

Future<void> main() async {
  final outputPath = Platform.environment['CONNECT_E2E_CAPTURE_DIR']!;
  final adb = Platform.environment['CONNECT_E2E_ADB']!;
  final target = Platform.environment['CONNECT_E2E_TARGET']!;
  final controller = Platform.environment['CONNECT_E2E_DEVICE']!;
  const package = 'dev.scrcpyconnect.scrcpy_connect';
  if (!outputPath.startsWith('/tmp/') ||
      outputPath.split('/').contains('..') ||
      controller == target ||
      !RegExp(r'^emulator-\d+$').hasMatch(target)) {
    throw StateError(
      'An isolated emulator pair and temporary evidence directory are required.',
    );
  }
  final output = await Directory(outputPath).create(recursive: true);
  final driver = await FlutterDriver.connect();
  Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.mediaCache',
                isolateId: driver.appIsolate.id,
                args: args,
              )
              .timeout(const Duration(seconds: 15)))
          .json ??
      {};
  var finished = false;
  final verified = <String>{};
  final errors = <String>[];
  String? remote;
  bool safeLocal(String path) =>
      ['/data/user/0/$package/', '/data/data/$package/'].any(path.startsWith) &&
      !path.split('/').contains('..') &&
      RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(path) &&
      (path.contains('/media/') || path.contains('/cache/outgoing/'));
  Future<void> bytesEqual(List<String> args, List<int> expected) async {
    final result = await runProcess(adb, args, stdoutEncoding: null);
    final actual = result.stdout as List<int>;
    if (result.exitCode != 0 ||
        actual.length != expected.length ||
        !List.generate(
          expected.length,
          (i) => i,
        ).every((i) => actual[i] == expected[i])) {
      throw StateError('Independent original byte verification failed.');
    }
  }

  final coordination =
      () async {
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (!finished && DateTime.now().isBefore(deadline)) {
          Map<String, dynamic> state;
          try {
            state = await extension();
          } catch (error) {
            if (finished) return;
            if (!error.toString().contains('Method not found') &&
                !error.toString().contains('-32601')) {
              rethrow;
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
            continue;
          }
          final phase = state['stage'];
          if (['protected', 'evicted'].contains(phase) &&
              !verified.contains(phase)) {
            try {
              final path = state['remote'] as String;
              if (!RegExp(r'^/sdcard/Download/connect-cache-\d+\.png$')
                  .hasMatch(path)) {
                throw StateError('Invalid owned target path.');
              }
              remote = path;
              final expected = base64Decode(state['expectedBytes'] as String);
              if (expected.isEmpty || expected.length > 1024 * 1024) {
                throw StateError('Invalid fixture bytes.');
              }
              final present = Map<String, dynamic>.from(
                state['present'] as Map,
              );
              final absent = List<String>.from(state['absent'] as List);
              await File('${output.path}/checkpoint-$phase.json')
                  .writeAsString(jsonEncode(state), flush: true);
              if (phase == 'protected' &&
                  (present.length != 2 ||
                      !present.keys.toSet().containsAll({
                        'preview',
                        'original',
                      }) ||
                      absent.length != 1)) {
                throw StateError('Unexpected protected content.');
              }
              if (phase == 'evicted' &&
                  (present.isNotEmpty || absent.length != 3)) {
                throw StateError('Unexpected eviction checkpoint.');
              }
              if (!([
                ...present.values.cast<String>(),
                ...absent,
              ].every(safeLocal))) {
                throw StateError('Invalid managed cache path.');
              }
              await bytesEqual([
                '-s',
                target,
                'exec-out',
                'cat',
                path,
              ], expected);
              for (final path in present.values.cast<String>()) {
                await bytesEqual([
                  '-s',
                  controller,
                  'exec-out',
                  'run-as',
                  package,
                  'cat',
                  path,
                ], expected);
              }
              for (final path in absent) {
                final result = await runProcess(adb, [
                  '-s',
                  controller,
                  'shell',
                  'run-as',
                  package,
                  'test',
                  '!',
                  '-e',
                  path,
                ]);
                if (result.exitCode != 0) {
                  throw StateError('A released cache file still exists.');
                }
              }
              verified.add(phase as String);
              await extension({
                'token': state['token'] as String,
                'action': 'verified',
              });
            } catch (error) {
              await extension({
                'token': state['token'] as String,
                'error': 'host-verification-failed',
              });
              rethrow;
            }
          }
          if (state['stage'] == 'done') return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }().catchError((Object error, StackTrace stack) {
        errors.add('$error');
      });
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      finished = true;
      await coordination;
      var removed = false;
      if (remote != null) {
        removed =
            (await runProcess(adb, [
              '-s',
              target,
              'shell',
              'test',
              '!',
              '-e',
              remote!,
            ])).exitCode ==
            0;
      }
      final report = {...?data}..remove('screenshots');
      report.addAll({
        'hostErrors': errors,
        'independentProtectedBytes': verified.contains('protected'),
        'independentReleasedEviction': verified.contains('evicted'),
        'independentRemoteRemoved': removed,
      });
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(report), flush: true);
      if (errors.isNotEmpty ||
          verified.length != 2 ||
          !removed ||
          [
            'mediaCacheComplete',
            'actualProtectedClear',
            'actualReleasedEviction',
            'fixtureRemoved',
          ].any((key) => report[key] != true)) {
        throw StateError('Actual cache acceptance did not complete.');
      }
    },
    onScreenshot: (name, bytes, [args]) => saveScreenshot(output, name, bytes),
  );
}
