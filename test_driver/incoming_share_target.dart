import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

// This executable is a host-only experiment. ADB never enters product code.
Future<void> main() async {
  String requiredEnvironment(String name) {
    final value = Platform.environment[name];
    if (value == null || value.isEmpty) {
      throw StateError('Set $name explicitly.');
    }
    return value;
  }

  final adb = requiredEnvironment('CONNECT_E2E_ADB');
  final controller = requiredEnvironment('CONNECT_E2E_DEVICE');
  final targetA = requiredEnvironment('CONNECT_E2E_TARGET');
  final targetB = requiredEnvironment('CONNECT_E2E_SECOND_TARGET');
  if ({controller, targetA, targetB}.length != 3) {
    throw StateError('Use one controller and two distinct target ADB serials.');
  }
  final driver = await FlutterDriver.connect();
  var hostFinished = false;
  Object? hostFailure;
  final host =
      driveShareTarget(
        driver,
        adb,
        controller,
        targetA,
        targetB,
        () => hostFinished,
      ).then<Map<String, Object?>>(
        (value) => value,
        onError: (Object error, StackTrace stack) {
          hostFailure = error;
          return <String, Object?>{};
        },
      );
  await integrationDriver(
    driver: driver,
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      hostFinished = true;
      final evidence = await host;
      final metadata = {...?data, 'independentHost': evidence}
        ..remove('screenshots');
      final output = Directory('/tmp/connect-e2e/incoming-share-target');
      await output.create(recursive: true);
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      if (hostFailure != null) {
        throw StateError('Independent host failed: $hostFailure');
      }
      if (metadata['incomingShareTargetComplete'] != true ||
          evidence['verified'] != true ||
          evidence['cleaned'] != true) {
        throw StateError(
          'The actual incoming-share target acceptance did not complete.',
        );
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      final output = Directory('/tmp/connect-e2e/incoming-share-target');
      await output.create(recursive: true);
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${output.path}/$safeName.png')
          .writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}

Future<Map<String, Object?>> driveShareTarget(
  FlutterDriver driver,
  String adb,
  String controller,
  String targetA,
  String targetB,
  bool Function() shouldStop,
) async {
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aSb8AAAAASUVORK5CYII=';
  const sha256 =
      'ce01132c640469ef7fb497e7496b12f5046d633b588f397e5c45a6c3efc85037';
  final expected = base64Decode(png);
  final evidence = <String, Object?>{};
  final created = <String, String>{};
  String? runId;
  String? failure;
  final handled = <String>{};
  String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  Future<ProcessResult> command(String serial, List<String> args) async {
    final result = await Process.run(
      adb,
      ['-s', serial, ...args],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 25));
    if (result.exitCode != 0) {
      throw StateError(
        'Independent ADB operation failed for $serial: ${result.stderr}',
      );
    }
    return result;
  }

  Future<String> shell(String serial, String script) async => utf8
      .decode((await command(serial, ['shell', script])).stdout as List<int>)
      .trim();

  Future<Map<String, dynamic>> state([
    Map<String, String> args = const {},
  ]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.incomingShareTarget',
                isolateId: driver.appIsolate.id,
                args: args,
              )
              .timeout(const Duration(seconds: 5)))
          .json ??
      {};

  Future<void> cleanup() async {
    for (final serial in created.keys.toList()) {
      final path = created[serial]!;
      await shell(serial, 'rm -rf ${quote(path)}');
      await shell(serial, 'test ! -e ${quote(path)}');
      created.remove(serial);
    }
  }

  final deadline = DateTime.now().add(const Duration(minutes: 6));
  try {
    while (!shouldStop() && DateTime.now().isBefore(deadline)) {
      Map<String, dynamic> current;
      try {
        current = await state();
      } catch (error) {
        if (!error.toString().contains('ext.connect.incomingShareTarget') &&
            !error.toString().contains('Method not found')) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final stage = '${current['stage']}';
      if (stage == 'complete') break;
      if (stage == 'starting' || handled.contains(stage)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      handled.add(stage);
      try {
        final identity = '${current['runId']}';
        if (!RegExp(r'^share-target-[0-9]+$').hasMatch(identity) ||
            (runId != null && runId != identity)) {
          throw StateError(
            'The isolated fixture identity changed or was invalid.',
          );
        }
        runId = identity;
        final directory = '/sdcard/Download/connect-$identity';
        final destination = '$directory/共享 图片.png';
        if (current['directory'] != directory ||
            current['destination'] != destination) {
          throw StateError(
            'Refusing a path outside this unique fixture directory.',
          );
        }
        if (failure != null && stage != 'cleanup') continue;
        stdout.writeln('Actual incoming-share target fixture stage: $stage');
        switch (stage) {
          case 'prepare':
            final actualA = await shell(targetA, 'getprop ro.serialno');
            final actualB = await shell(targetB, 'getprop ro.serialno');
            final avdA = await shell(targetA, 'getprop ro.boot.qemu.avd_name');
            final avdB = await shell(targetB, 'getprop ro.boot.qemu.avd_name');
            final avdController = await shell(
              controller,
              'getprop ro.boot.qemu.avd_name',
            );
            if (actualA.isEmpty ||
                actualB.isEmpty ||
                avdA.isEmpty ||
                avdB.isEmpty ||
                avdController.isEmpty ||
                {avdA, avdB, avdController}.length != 3 ||
                current['serialA'] != actualA ||
                current['serialB'] != actualB) {
              throw StateError(
                'Use three independently booted AVDs with target serial metadata matching the app.',
              );
            }
            for (final target in {targetA: 'a', targetB: 'b'}.entries) {
              final serial = target.key;
              // mkdir, without -p, fails on a pre-existing path; never overwrite it.
              await shell(serial, 'mkdir ${quote(directory)}');
              created[serial] = directory;
              await shell(
                serial,
                'printf %s ${quote('$identity-${target.value}')} > ${quote('$directory/target-${target.value}.marker')}',
              );
              await shell(serial, 'test ! -e ${quote(destination)}');
            }
            evidence['distinctTargetsPrepared'] = true;
            evidence['targetAAvd'] = avdA;
            evidence['targetBAvd'] = avdB;
            evidence['directory'] = directory;
            await state({'action': 'prepared'});
          case 'send-image':
            if (evidence['distinctTargetsPrepared'] != true) {
              throw StateError('Targets were not prepared.');
            }
            await command(controller, [
              'shell',
              'am',
              'start',
              '-W',
              '-f',
              '0x24000000',
              '-n',
              'dev.scrcpyconnect.sharefixture/.ShareFixtureActivity',
              '--es',
              'mode',
              'image',
            ]);
            evidence['externalImageSent'] = true;
          case 'verify':
            if (evidence['externalImageSent'] != true) {
              throw StateError('No external image was sent.');
            }
            final actual =
                (await command(targetA, [
                      'exec-out',
                      'cat ${quote(destination)}',
                    ])).stdout
                    as List<int>;
            if (actual.length != expected.length ||
                List.generate(
                  expected.length,
                  (i) => actual[i] == expected[i],
                ).contains(false)) {
              throw StateError(
                'Independent ADB read found different target A bytes.',
              );
            }
            final checksum = await shell(
              targetA,
              'sha256sum ${quote(destination)}',
            );
            if (checksum.split(RegExp(r'\s+')).first != sha256) {
              throw StateError('Independent target A hash differs.');
            }
            await shell(targetB, 'test ! -e ${quote(destination)}');
            evidence.addAll({
              'verified': true,
              'targetABytes': actual.length,
              'targetASha256': sha256,
              'targetBPathAbsent': true,
            });
            await state({'action': 'verified'});
          case 'cleanup':
            await cleanup();
            evidence['cleaned'] = true;
            await state({'action': 'cleaned'});
            if (failure != null) throw StateError(failure);
            return evidence;
        }
      } catch (error) {
        failure ??= 'Independent host failed during $stage: $error';
        await state({
          'action': 'failed',
          'message': 'Independent host failed during $stage.',
        });
        if (stage == 'cleanup') rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!shouldStop() && !handled.contains('cleanup')) {
      throw StateError('Independent share fixture deadline exceeded.');
    }
    if (failure != null) throw StateError(failure);
    return evidence;
  } finally {
    await cleanup();
  }
}
