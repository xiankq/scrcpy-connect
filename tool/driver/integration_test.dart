import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import 'documents.dart';
import 'clipboard.dart';
import 'audio.dart';
import '../src/process.dart';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-e2e',
  );
  await directory.create(recursive: true);
  final driver = await FlutterDriver.connect();
  var hostFinished = false;
  Future<void>? audioOperation;
  if (Platform.environment['CONNECT_E2E_AUDIO_LIFECYCLE'] == '1') {
    audioOperation = driveAudioLifecycle(
      driver,
      shouldStop: () => hostFinished,
    );
    audioOperation.catchError((Object error, StackTrace stack) {
      stderr.writeln('Actual audio lifecycle test failed: $error');
      exit(1);
    });
  }
  if (Platform.environment['CONNECT_E2E_CLIPBOARD'] == '1') {
    driveClipboard(driver).catchError((Object error, StackTrace stack) {
      stderr.writeln('Actual clipboard test failed: $error');
      exit(1);
    });
  }
  if (Platform.environment['CONNECT_E2E_DOCUMENTS'] == '1') {
    driveDocuments(driver, directory).catchError((
      Object error,
      StackTrace stack,
    ) {
      stderr.writeln('Actual DocumentsUI test failed: $error');
      exit(1);
    });
  }
  if (Platform.environment['CONNECT_E2E_BACKGROUND'] == '1') {
    triggerBackground(driver).catchError((Object error, StackTrace stack) {
      stderr.writeln('Actual background switch failed: $error');
      exit(1);
    });
  }
  await integrationDriver(
    driver: driver,
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      // 扩展 integrationDriver 在回调后退出进程；先排空宿主夹具清理，避免中止尚未完成的 finally。
      //
      hostFinished = true;
      await audioOperation;
      final metadata = {...?data}..remove('screenshots');
      await File('${directory.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      validateAcceptanceReport(metadata, environment: Platform.environment);
    },
    onScreenshot: (name, bytes, [args]) async {
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${directory.path}/$safeName.png')
          .writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}

/// 缺少预期验收回执时判定失败；保持与已连接 driver 独立，便于主机契约测试直接验证。
///
void validateAcceptanceReport(
  Map<String, dynamic> metadata, {
  required Map<String, String> environment,
}) {
  final acceptance = environment['CONNECT_E2E_ACCEPTANCE'] ?? 'product';
  if (acceptance != 'product' && acceptance != 'media') {
    throw StateError('Unknown acceptance scope: $acceptance');
  }
  if (acceptance == 'media' && metadata['mediaAcceptanceComplete'] != true) {
    throw StateError('The app did not complete scoped media acceptance.');
  }
  // 默认目标是完整产品流程，专用宿主夹具模式仍使用下方各自的完成检查。
  //
  final fixtureMode = [
    'CONNECT_E2E_BACKGROUND',
    'CONNECT_E2E_AUDIO_LIFECYCLE',
    'CONNECT_E2E_CLIPBOARD',
    'CONNECT_E2E_DOCUMENTS',
  ].any((key) => environment[key] == '1');
  if (((!fixtureMode && acceptance == 'product') ||
          metadata.containsKey('productAcceptanceComplete')) &&
      metadata['productAcceptanceComplete'] != true) {
    throw StateError('The app did not complete real product acceptance.');
  }
  if (environment['CONNECT_E2E_BACKGROUND'] == '1' &&
      metadata['mediaAcceptanceComplete'] != true) {
    throw StateError('The app did not complete background media acceptance.');
  }
  if (environment['CONNECT_E2E_AUDIO_LIFECYCLE'] == '1' &&
      metadata['audioAcceptanceComplete'] != true) {
    throw StateError('The app did not complete shared audio acceptance.');
  }
  if (environment['CONNECT_E2E_EXIT_HANDLE'] == '1' &&
      metadata['inwardExitHandleExpanded'] != true) {
    throw StateError('The app did not complete inward exit handle acceptance.');
  }
}

Future<void> triggerBackground(FlutterDriver driver) async {
  final serial =
      Platform.environment['CONNECT_E2E_DEVICE'] ??
      Platform.environment['ANDROID_SERIAL'];
  if (serial == null || serial.isEmpty) {
    throw StateError(
      'Set CONNECT_E2E_DEVICE to the actual controller Android serial.',
    );
  }
  final sdk =
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  final adb =
      Platform.environment['CONNECT_E2E_ADB'] ??
      (sdk == null ? 'adb' : '$sdk/platform-tools/adb');
  Future<void> runAdb(List<String> args) async {
    final result = await runProcess(adb, [
      '-s',
      serial,
      ...args,
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) {
      throw StateError('adb ${args.first} failed: ${result.stderr}');
    }
  }

  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final response = await driver.serviceClient.callServiceExtension(
        'ext.connect.background',
        isolateId: driver.appIsolate.id,
      );
      final state = response.json ?? const <String, dynamic>{};
      if (state['stage'] == 'ready') {
        await runAdb(['shell', 'input', 'keyevent', 'KEYCODE_HOME']);
        await Future<void>.delayed(const Duration(seconds: 2));
        await runAdb([
          'shell',
          'am',
          'start',
          '-W',
          '-n',
          'dev.scrcpyconnect.scrcpy_connect/.MainActivity',
        ]);
        await driver.serviceClient.callServiceExtension(
          'ext.connect.background',
          isolateId: driver.appIsolate.id,
          args: {'action': 'returned'},
        );
        stdout.writeln(
          jsonEncode({
            'background': 'actual HOME and Activity restart completed',
            'device': serial,
          }),
        );
        return;
      }
    } catch (error) {
      // 测试在 driver 附着后才注册扩展。
      if (!error.toString().contains('ext.connect.background') &&
          !error.toString().contains('Method not found')) {
        rethrow;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'The test never became ready for an actual background switch.',
  );
}
