import 'dart:convert';
import 'dart:io';

import 'support/capture.dart';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';
import 'support/cleanup.dart';

Future<void> main() async {
  final serial = Platform.environment['CONNECT_E2E_DEVICE'];
  if (serial == null) {
    throw StateError('Set CONNECT_E2E_DEVICE to the controller.');
  }
  final adb = Platform.environment['CONNECT_E2E_ADB'] ?? 'adb';
  final driver = await FlutterDriver.connect();
  var hostFinished = false;
  Object? fixtureError;
  StackTrace? fixtureStack;
  final controller = driveShares(driver, adb, serial, () => hostFinished)
      .catchError((Object error, StackTrace stack) async {
        fixtureError = error;
        fixtureStack = stack;
        hostFinished = true;
        try {
          await driverRpc(driver.close());
        } catch (closeError) {
          stderr.writeln('Sharing driver shutdown failed: $closeError');
        }
      });
  Future<void> finishHost() async {
    hostFinished = true;
    await controller;
    if (fixtureError != null) {
      Error.throwWithStackTrace(fixtureError!, fixtureStack!);
    }
  }

  await withDriverCleanup(
    () async {
      await integrationDriver(
        driver: driver,
        writeResponseOnFailure: true,
        responseDataCallback: (data) async {
          await finishHost();
          final metadata = {...?data}..remove('screenshots');
          final output = Directory('/tmp/connect-e2e/incoming-share');
          await output.create(recursive: true);
          await File('${output.path}/result.json')
              .writeAsString(jsonEncode(metadata));
          if (metadata['shareAcceptanceComplete'] != true) {
            throw StateError(
              'The app did not complete external share acceptance.',
            );
          }
        },
        onScreenshot: (name, bytes, [args]) => saveScreenshot(
          Directory('/tmp/connect-e2e/incoming-share'),
          name,
          bytes,
        ),
      );
    },
    () => {
      'sharing fixture': finishHost,
      'driver connection': () => driverRpc(driver.close()),
    },
  );
}

Future<void> driveShares(
  FlutterDriver driver,
  String adb,
  String serial,
  bool Function() shouldStop,
) async {
  final sent = <String>{};
  var launcherReturned = false;
  var backgrounded = false;
  Future<ProcessResult> runAdb(List<String> args) async {
    final result = await runProcess(adb, [
      '-s',
      serial,
      ...args,
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('External sharing host failed: ${result.stderr}');
    }
    return result;
  }

  final deadline = DateTime.now().add(const Duration(minutes: 8));
  await withDriverCleanup(
    () async {
      while (!shouldStop() && DateTime.now().isBefore(deadline)) {
        try {
          final state =
              (await driver.serviceClient
                      .callServiceExtension(
                        'ext.connect.incomingShare',
                        isolateId: driver.appIsolate.id,
                      )
                      .timeout(const Duration(seconds: 5)))
                  .json ??
              {};
          if (state['stage'] == 'complete') return;
          if (state['stage'] == 'launcher-return' && !launcherReturned) {
            launcherReturned = true;
            backgrounded = true;
            await runAdb(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
            await runAdb([
              'shell',
              'am',
              'start',
              '-W',
              '-a',
              'android.intent.action.MAIN',
              '-c',
              'android.intent.category.LAUNCHER',
              '-n',
              'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
            ]);
            backgrounded = false;
            final activities = await runAdb([
              'shell',
              'dumpsys',
              'activity',
              'activities',
            ]);
            final hosts = RegExp(
              r'^\s*\* Hist\s+#\d+: ActivityRecord\{[^\n]* dev\.scrcpyconnect\.scrcpy_connect/\.MainActivity ',
              multiLine: true,
            ).allMatches('${activities.stdout}').length;
            if (hosts != 1) {
              throw StateError(
                'One Flutter engine has $hosts Android UI hosts after launcher return.',
              );
            }
            await driver.serviceClient
                .callServiceExtension(
                  'ext.connect.incomingShare',
                  isolateId: driver.appIsolate.id,
                  args: {'action': 'launcherReturned'},
                )
                .timeout(const Duration(seconds: 5));
            stdout.writeln(
              'Actual HOME and launcher return: one Android UI host.',
            );
          }
          final mode = state['mode'];
          if (state['stage'] == 'send' && mode is String && sent.add(mode)) {
            final result = await runProcess(adb, [
              '-s',
              serial,
              'shell',
              'am',
              'start',
              // 即使任务上方仍有先前打开的接收页，也把发送方本身置顶并交付此模式。
              //
              '-f',
              '0x24000000',
              '-n',
              'dev.scrcpyconnect.sharefixture/.ShareFixtureActivity',
              '--es',
              'mode',
              mode,
            ], timeout: const Duration(seconds: 20));
            if (result.exitCode != 0) {
              throw StateError('External fixture failed: ${result.stderr}');
            }
            stdout.writeln('External share launch $mode: ${result.stdout}');
          }
        } catch (error) {
          if (shouldStop()) return;
          if (!error.toString().contains('ext.connect.incomingShare') &&
              !error.toString().contains('Method not found')) {
            rethrow;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!shouldStop()) {
        throw StateError('External share integration deadline exceeded.');
      }
    },
    () => {
      'controller foreground': () async {
        if (!backgrounded) return;
        await runAdb([
          'shell',
          'am',
          'start',
          '-W',
          '-n',
          'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
        ]);
      },
    },
  );
}
