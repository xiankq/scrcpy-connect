import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

Future<void> driveClipboard(FlutterDriver driver) async {
  final client = Platform.environment['CONNECT_E2E_CLIPBOARD_CLIENT'];
  final serial =
      Platform.environment['CONNECT_E2E_DEVICE'] ??
      Platform.environment['ANDROID_SERIAL'];
  if (client == null || client.isEmpty || serial == null || serial.isEmpty) {
    throw StateError(
      'Set actual CONNECT_E2E_CLIPBOARD_CLIENT and controller CONNECT_E2E_DEVICE.',
    );
  }
  final endpointA =
      Platform.environment['CONNECT_E2E_CLIPBOARD_ENDPOINT'] ??
      '127.0.0.1:15556';
  final endpointB =
      Platform.environment['CONNECT_E2E_CLIPBOARD_SECOND_ENDPOINT'] ??
      '127.0.0.1:15560';
  final sdk =
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  final adb =
      Platform.environment['CONNECT_E2E_ADB'] ??
      (sdk == null ? 'adb' : '$sdk/platform-tools/adb');
  Future<void> adbCommand(String device, List<String> args) async {
    final result = await Process.run(adb, [
      '-s',
      device,
      ...args,
    ]).timeout(const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('Official adb ${args.first} failed: ${result.stderr}');
    }
  }

  Future<Map<String, dynamic>> invoke(
    String endpoint,
    String command, [
    String? text,
  ]) async {
    final result = await Process.run(
      client,
      [endpoint, command, ?text],
      environment: {'INTEROP_CLIPBOARD_FIXTURE': '1'},
    ).timeout(const Duration(seconds: 35));
    if (result.exitCode != 0) {
      throw StateError(
        'Independent actual clipboard client failed: ${result.stderr}',
      );
    }
    final data = Map<String, dynamic>.from(
      jsonDecode(result.stdout as String) as Map,
    );
    if (command == 'set' && data['applied'] != true) {
      throw StateError('Independent target clipboard write was not confirmed.');
    }
    return data;
  }

  Future<Map<String, dynamic>> state([String? action]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.clipboard',
                isolateId: driver.appIsolate.id,
                args: {'action': ?action},
              )
              .timeout(const Duration(seconds: 5)))
          .json ??
      {};
  final originals = <String, String>{};
  Future<void> restore() async {
    for (final original in originals.entries) {
      await invoke(original.key, 'set', original.value);
    }
    originals.clear();
  }

  var lastStage = '';
  var backgrounded = false;
  final deadline = DateTime.now().add(const Duration(minutes: 8));
  try {
    while (DateTime.now().isBefore(deadline)) {
      Map<String, dynamic> current;
      try {
        current = await state();
      } catch (error) {
        if (!error.toString().contains('ext.connect.clipboard') &&
            !error.toString().contains('Method not found')) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final runId = '${current['runId']}';
      if (!RegExp(r'^clipboard-[0-9]+$').hasMatch(runId)) {
        throw StateError('Invalid clipboard fixture identity.');
      }
      final stage = '${current['stage']}';
      if (stage != lastStage) {
        lastStage = stage;
        stdout.writeln('Actual clipboard fixture stage: $stage');
        switch (stage) {
          case 'prepare':
            await adbCommand(
              Platform.environment['CONNECT_E2E_TARGET'] ?? 'emulator-5556',
              ['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'],
            );
            await adbCommand(
              Platform.environment['CONNECT_E2E_SECOND_TARGET'] ??
                  'emulator-5558',
              ['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP'],
            );
            originals[endpointA] =
                '${(await invoke(endpointA, 'get'))['text'] ?? ''}';
            originals[endpointB] =
                '${(await invoke(endpointB, 'get'))['text'] ?? ''}';
            await invoke(endpointA, 'set', '$runId-baseline-a');
            await invoke(endpointB, 'set', '$runId-baseline-b');
            await state('prepared');
          case 'external-a':
            await invoke(endpointA, 'set', '$runId-external-a');
            await state('externalA');
          case 'unselected-a':
            await invoke(endpointA, 'set', '$runId-unselected-a');
            await state('unselectedA');
          case 'background':
            await adbCommand(serial, [
              'shell',
              'input',
              'keyevent',
              'KEYCODE_HOME',
            ]);
            backgrounded = true;
            final pausedDeadline = DateTime.now().add(
              const Duration(seconds: 10),
            );
            var paused = await state();
            while (paused['state'] != 'waitingForeground' &&
                DateTime.now().isBefore(pausedDeadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              paused = await state();
            }
            if (paused['state'] != 'waitingForeground') {
              throw StateError(
                'Actual HOME never suspended automatic clipboard access.',
              );
            }
            await invoke(endpointA, 'set', '$runId-background-a');
            await Future<void>.delayed(const Duration(seconds: 2));
            final after = await state();
            for (final counter in ['reads', 'writes', 'sends']) {
              if (after[counter] != paused[counter]) {
                throw StateError(
                  'Actual automatic clipboard $counter changed while backgrounded.',
                );
              }
            }
            await adbCommand(serial, [
              'shell',
              'am',
              'start',
              '-W',
              '-n',
              'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
            ]);
            backgrounded = false;
            await state('backgroundReturned');
          case 'disabled-a':
            await invoke(endpointA, 'set', '$runId-disabled-a');
            await Future<void>.delayed(const Duration(seconds: 2));
            await restore();
            await state('disabledA');
            stdout.writeln(
              'Independent real clipboard clients and actual HOME suspension completed.',
            );
            return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Actual clipboard integration exceeded its bounded deadline.',
    );
  } finally {
    if (backgrounded) {
      await adbCommand(serial, [
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
      ]);
    }
    await restore();
  }
}
