import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../src/process.dart';

const fixturePackage = 'dev.scrcpyconnect.inputfixture';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-e2e',
  );
  await directory.create(recursive: true);
  final driver = await FlutterDriver.connect();
  var appFinished = false;
  Object? fixtureError;
  final fixture =
      driveInputRelease(
        driver,
        directory,
        shouldStop: () => appFinished,
      ).catchError((Object error) {
        fixtureError = error;
      });
  await integrationDriver(
    driver: driver,
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      appFinished = true;
      // integrationDriver exits after this callback. Drain actual Android
      // fixture cleanup here, before it can terminate a pending finally block.
      await fixture;
      final metadata = {...?data}..remove('screenshots');
      metadata['fixtureCleanupComplete'] = fixtureError == null;
      metadata['fixtureError'] = fixtureError?.toString();
      await File('${directory.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      if (fixtureError != null ||
          metadata['nativeInputReleaseComplete'] != true) {
        throw StateError(
          'Native input acceptance incomplete: ${fixtureError ?? 'missing app receipt'}',
        );
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${directory.path}/$safeName.png')
          .writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}

Future<void> driveInputRelease(
  FlutterDriver driver,
  Directory captures, {
  bool Function()? shouldStop,
}) async {
  final serial =
      Platform.environment['CONNECT_E2E_DEVICE'] ??
      Platform.environment['ANDROID_SERIAL'];
  final target = Platform.environment['CONNECT_E2E_TARGET'] ?? 'emulator-5556';
  final apk = Platform.environment['CONNECT_E2E_INPUT_APK'];
  if (serial != 'emulator-5554' || target != 'emulator-5556') {
    throw StateError(
      'This opt-in fixture is authorized only for controller emulator-5554 and target emulator-5556.',
    );
  }
  if (apk == null || !await File(apk).exists()) {
    throw StateError(
      'Build the test receiver and set CONNECT_E2E_INPUT_APK to its actual APK.',
    );
  }
  final controllerSerial = serial;
  final sdk =
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'] ??
      '${Platform.environment['HOME']}/Android/Sdk';
  final adb =
      Platform.environment['CONNECT_E2E_ADB'] ?? '$sdk/platform-tools/adb';
  final buildTools = await Directory('$sdk/build-tools')
      .list()
      .where((e) => e is Directory)
      .toList();
  buildTools.sort((a, b) => a.path.compareTo(b.path));
  if (buildTools.isEmpty) {
    throw StateError(
      'Installed Android build-tools are required to verify the test APK identity.',
    );
  }
  final badging = await runProcess('${buildTools.last.path}/aapt2', [
    'dump',
    'badging',
    apk,
  ], timeout: const Duration(seconds: 15));
  final packageName = RegExp(
    r"^package: name='([^']+)'",
    multiLine: true,
  ).firstMatch('${badging.stdout}')?.group(1);
  if (badging.exitCode != 0 || packageName != fixturePackage) {
    throw StateError(
      'Refusing to install an APK outside the dedicated input fixture package.',
    );
  }
  Future<ProcessResult> adbRun(
    String device,
    List<String> args, {
    bool binary = false,
  }) async {
    final result = await runProcess(
      adb,
      ['-s', device, ...args],
      stdoutEncoding: binary ? null : utf8,
      timeout: const Duration(seconds: 20),
    );
    if (result.exitCode != 0) {
      throw StateError('Official adb ${args.first} failed: ${result.stderr}');
    }
    return result;
  }

  Future<Map<String, dynamic>> state([String? action]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.inputRelease',
                isolateId: driver.appIsolate.id,
                args: {'action': ?action},
              )
              .timeout(const Duration(seconds: 5)))
          .json ??
      {};
  var installed = false;
  var backgrounded = false;
  String? remoteXml;
  Future<void> foreground() async {
    await adbRun(controllerSerial!, [
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
    ]);
    backgrounded = false;
  }

  Future<Map<String, String>> readFixture(
    String runId,
    String sessionId,
    String evidence,
  ) async {
    final path = '/sdcard/Download/interop-$runId.xml';
    remoteXml = path;
    await adbRun(target, [
      'shell',
      'uiautomator',
      'dump',
      '--compressed',
      path,
    ]);
    final xml = '${(await adbRun(target, ['shell', 'cat', path])).stdout}';
    await File('${captures.path}/input-$evidence-target.xml')
        .writeAsString(xml, flush: true);
    final node = RegExp(
      '<node\\b[^>]*\\bresource-id="$fixturePackage:id/state"[^>]*>',
    ).firstMatch(xml)?.group(0);
    final text = node == null
        ? null
        : RegExp(r'\btext="([^"]*)"').firstMatch(node)?.group(1);
    if (text == null) {
      throw StateError(
        'The actual target native fixture state is absent from UiAutomator XML.',
      );
    }
    final fields = {
      for (final match in RegExp(r'(\w+)=([A-Za-z0-9_:-]+)').allMatches(text))
        match.group(1)!: match.group(2)!,
    };
    if (fields['RUN'] != runId ||
        fields['SESSION'] != sessionId ||
        fields['KEY'] != '20') {
      throw StateError(
        'Target native state does not belong to this run and actual product session.',
      );
    }
    return fields;
  }

  void verify(Map<String, String> actual, {required bool released}) {
    final expected = released
        ? {'INITIAL_DOWN': '1', 'UP': '1', 'PRESSED': 'false', 'LAST': 'UP'}
        : {'INITIAL_DOWN': '1', 'UP': '0', 'PRESSED': 'true', 'LAST': 'DOWN'};
    for (final entry in {
      ...expected,
      'ORPHAN_UP': '0',
      'DUPLICATE_DOWN': '0',
    }.entries) {
      if (actual[entry.key] != entry.value) {
        throw StateError(
          'Actual native fixture ${entry.key}=${actual[entry.key]}, expected ${entry.value}.',
        );
      }
    }
    final downAt = int.tryParse(actual['DOWN_AT'] ?? '') ?? 0;
    final upAt = int.tryParse(actual['UP_AT'] ?? '') ?? 0;
    if (downAt <= 0 || (released && upAt < downAt)) {
      throw StateError(
        'Native dispatch timestamps do not prove the key release ordering.',
      );
    }
  }

  final deadline = DateTime.now().add(const Duration(minutes: 6));
  var lastStage = '';
  try {
    while (shouldStop?.call() != true && DateTime.now().isBefore(deadline)) {
      Map<String, dynamic> current;
      try {
        current = await state();
      } catch (error) {
        if (!error.toString().contains('ext.connect.inputRelease') &&
            !error.toString().contains('Method not found')) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final runId = '${current['runId']}';
      final sessionId = '${current['sessionId']}';
      if (!RegExp(r'^input-[0-9]+$').hasMatch(runId)) {
        throw StateError('Invalid input fixture run identity.');
      }
      final stage = '${current['stage']}';
      if (stage != lastStage) {
        lastStage = stage;
        stdout.writeln('Actual native input fixture stage: $stage');
        switch (stage) {
          case 'prepare':
            await adbRun(target, [
              'shell',
              'input',
              'keyevent',
              'KEYCODE_WAKEUP',
            ]);
            // Remove only this test receiver, including an older test signing key.
            final packages =
                '${(await adbRun(target, ['shell', 'pm', 'list', 'packages', fixturePackage])).stdout}';
            if (packages
                .split('\n')
                .any((line) => line.trim() == 'package:$fixturePackage')) {
              await adbRun(target, [
                'shell',
                'pm',
                'uninstall',
                fixturePackage,
              ]);
            }
            await adbRun(target, ['install', apk]);
            installed = true;
            await adbRun(target, [
              'shell',
              'am',
              'start',
              '-W',
              '-n',
              '$fixturePackage/.InputReceiverActivity',
              '--es',
              'run_id',
              runId,
              '--es',
              'session_id',
              'unbound',
            ]);
            await readFixture(runId, 'unbound', 'prepared');
            await state('prepared');
          case 'arm':
            if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(sessionId) ||
                sessionId == 'null') {
              throw StateError(
                'The actual rendered product session must be known before arming.',
              );
            }
            await adbRun(target, [
              'shell',
              'am',
              'start',
              '-W',
              '-n',
              '$fixturePackage/.InputReceiverActivity',
              '--es',
              'run_id',
              runId,
              '--es',
              'session_id',
              sessionId,
            ]);
            final baseline = await readFixture(runId, sessionId, 'armed');
            if (baseline['INITIAL_DOWN'] != '0' ||
                baseline['UP'] != '0' ||
                baseline['PRESSED'] != 'false') {
              throw StateError('Fresh native fixture counters must be zero.');
            }
            await state('armed');
          case 'hold':
            var held = await readFixture(runId, sessionId, 'before-home');
            final holdDeadline = DateTime.now().add(
              const Duration(seconds: 20),
            );
            while (held['INITIAL_DOWN'] == '0' &&
                DateTime.now().isBefore(holdDeadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              held = await readFixture(runId, sessionId, 'before-home');
            }
            verify(held, released: false);
            await adbRun(controllerSerial!, [
              'shell',
              'input',
              'keyevent',
              'KEYCODE_HOME',
            ]);
            backgrounded = true;
            var released = await readFixture(runId, sessionId, 'after-home');
            final releaseDeadline = DateTime.now().add(
              const Duration(seconds: 20),
            );
            while (released['UP'] == '0' &&
                DateTime.now().isBefore(releaseDeadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              released = await readFixture(runId, sessionId, 'after-home');
            }
            verify(released, released: true);
            final background = await state();
            if (!['hidden', 'paused'].contains(background['lifecycle'])) {
              throw StateError(
                'Controller did not actually become hidden/paused after HOME.',
              );
            }
            await Future<void>.delayed(const Duration(seconds: 2));
            verify(
              await readFixture(runId, sessionId, 'background-stable'),
              released: true,
            );
            final png = await adbRun(target, [
              'exec-out',
              'screencap',
              '-p',
            ], binary: true);
            await File('${captures.path}/input-native-target-released.png')
                .writeAsBytes(png.stdout as List<int>, flush: true);
            stdout.writeln(jsonEncode({'actualTargetDispatch': released}));
            await foreground();
            await state('returned');
          case 'verify-exit':
            final finalState = await readFixture(
              runId,
              sessionId,
              'after-exit',
            );
            verify(finalState, released: true);
            final closeDeadline = DateTime.now().add(
              const Duration(seconds: 10),
            );
            var processRemains = true;
            do {
              final listing =
                  '${(await adbRun(target, ['shell', 'ps', '-A', '-o', 'ARGS'])).stdout}';
              processRemains = listing.contains(
                'interop-scrcpy-$sessionId.jar',
              );
              if (!processRemains) break;
              await Future<void>.delayed(const Duration(milliseconds: 150));
            } while (DateTime.now().isBefore(closeDeadline));
            if (processRemains) {
              throw StateError(
                'The explicitly closed window still owns a target scrcpy process.',
              );
            }
            await state('verified');
            stdout.writeln(
              'Native target DOWN/UP, actual HOME and retained target task all verified.',
            );
            return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Real native input release test exceeded its bounded deadline.',
    );
  } finally {
    if (backgrounded) await foreground();
    if (remoteXml != null) {
      await adbRun(target, ['shell', 'rm', '-f', remoteXml!]);
    }
    if (installed &&
        Platform.environment['CONNECT_E2E_KEEP_INPUT_FIXTURE'] != '1') {
      await adbRun(target, ['uninstall', fixturePackage]);
    }
  }
}
