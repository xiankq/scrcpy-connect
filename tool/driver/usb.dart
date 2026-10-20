import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

class _Node {
  _Node(this.attributes);
  final Map<String, String> attributes;
  String operator [](String key) => attributes[key] ?? '';
}

/// The caller owns USBIP/adbd preparation and teardown. This driver only reads
/// the controller and taps its real USB permission dialog; it never grants a
/// permission using pm, appops, a mock channel or the fixture's transport.
class _UsbPermissionUi {
  _UsbPermissionUi(this.adb, this.controller);
  final String adb;
  final String controller;
  final runId = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  final receipt = <String, dynamic>{};
  String get xmlPath => '/data/local/tmp/connect-usb-$runId.xml';

  Future<String> _run(List<String> args) async {
    final process = await Process.start(adb, ['-s', controller, ...args]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    try {
      final exit = await process.exitCode.timeout(const Duration(seconds: 15));
      await errors;
      final text = await output;
      if (exit != 0) throw StateError('USB UI command failed ($exit).');
      return text;
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await errors;
      await output;
      rethrow;
    }
  }

  Future<String> shell(List<String> args) =>
      _run(['shell', args.map(_quote).join(' ')]);

  Future<void> prepare() async {
    final api = (await shell(['getprop', 'ro.build.version.sdk'])).trim();
    final selinux = (await shell(['getenforce'])).trim();
    if (api != '36' || selinux != 'Enforcing') {
      throw StateError(
        'USB permission regression requires an API36 enforcing AVD.',
      );
    }
    receipt.addAll({
      'controllerSerial': controller,
      'controllerApiLevel': 36,
      'selinuxEnforcing': true,
      'fixtureManagedExternally': true,
      'transport': 'virtual-USBIP-to-real-adbd',
      'permissionMechanism': 'Android-UsbManager-system-dialog',
    });
  }

  Future<List<_Node>> nodes() async {
    await shell(['uiautomator', 'dump', xmlPath]);
    final xml = await shell(['cat', xmlPath]);
    String decode(String value) => value
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    return [
      for (final match in RegExp(r'<node\s+[^>]*>').allMatches(xml))
        _Node({
          for (final attribute in RegExp(
            r'([\w-]+)="([^"]*)"',
          ).allMatches(match[0]!))
            attribute[1]!: decode(attribute[2]!),
        }),
    ];
  }

  Future<void> choose({required bool allow}) async {
    final label = allow ? 'OK' : 'Cancel';
    final resourceId = allow ? 'android:id/button1' : 'android:id/button2';
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(deadline)) {
      final current = await nodes();
      // Require the expected USB device in the genuine SystemUI prompt before
      // selecting a unique, enabled system button. Never tap by coordinates
      // guessed from a screenshot or accept unrelated runtime/ADB dialogs.
      final titles = current
          .where(
            (node) =>
                node['package'] == 'com.android.systemui' &&
                node['text'].startsWith('Allow ') &&
                node['text'].contains(' to access Virtual Android?'),
          )
          .toList();
      final buttons = current
          .where(
            (node) =>
                node['package'] == 'com.android.systemui' &&
                node['resource-id'] == resourceId &&
                node['text'] == label &&
                node['enabled'] == 'true' &&
                node['clickable'] == 'true',
          )
          .toList();
      if (titles.length == 1 && buttons.length == 1) {
        final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
            .firstMatch(buttons.single['bounds']);
        if (bounds == null) {
          throw StateError('System USB button bounds are missing.');
        }
        final left = int.parse(bounds[1]!);
        final top = int.parse(bounds[2]!);
        final right = int.parse(bounds[3]!);
        final bottom = int.parse(bounds[4]!);
        if (right <= left || bottom <= top) {
          throw StateError('System USB button bounds are empty.');
        }
        await shell([
          'input',
          'tap',
          '${(left + right) ~/ 2}',
          '${(top + bottom) ~/ 2}',
        ]);
        receipt[allow ? 'systemOkTapped' : 'systemCancelTapped'] = true;
        return;
      }
      if (titles.length > 1 || buttons.length > 1) {
        throw StateError('USB system permission action is ambiguous.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Expected a fresh USB permission prompt with $label.');
  }

  Future<void> cleanup() async {
    await shell(['rm', '-f', xmlPath]);
    receipt['ownedUiDumpRemoved'] = true;
  }
}

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  if (adb == null ||
      adb.isEmpty ||
      controller == null ||
      !RegExp(r'^emulator-\d+$').hasMatch(controller)) {
    throw StateError(
      'Set CONNECT_E2E_ADB and an explicit CONNECT_E2E_DEVICE emulator serial.',
    );
  }
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-e2e/usb';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('USB evidence must remain under /tmp/.');
  }
  final output = await Directory(path).create(recursive: true);
  final ui = _UsbPermissionUi(adb, controller);
  final errors = <String>[];
  var finished = false;
  Future<void>? coordination;
  try {
    final driver = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await driver.serviceClient
                .callServiceExtension(
                  'ext.connect.usb',
                  isolateId: driver.appIsolate.id,
                  args: args,
                )
                .timeout(const Duration(seconds: 15)))
            .json ??
        {};
    coordination =
        () async {
          final handled = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 5));
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
            final stage = state['stage'];
            if (stage == 'done') return;
            if (stage is String && handled.add(stage)) {
              try {
                switch (stage) {
                  case 'waiting-fixture':
                    await ui.prepare();
                    await extension({'action': 'fixture', 'runId': ui.runId});
                  case 'need-deny':
                    await ui.choose(allow: false);
                    await extension({'action': 'denied', 'runId': ui.runId});
                  case 'need-grant':
                    await ui.choose(allow: true);
                    await extension({'action': 'granted', 'runId': ui.runId});
                }
              } catch (error) {
                errors.add(
                  'USB host coordination failed at $stage (${error.runtimeType}).',
                );
                await extension({'error': 'true'});
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!finished) throw StateError('USB host handshake timed out.');
        }().catchError((Object error) {
          errors.add('USB host coordination stopped (${error.runtimeType}).');
        });
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        finished = true;
        await coordination;
        await ui.cleanup();
        final report = {...?data}..remove('screenshots');
        report.addAll({'hostErrors': errors, 'androidUsbReceipt': ui.receipt});
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        const required = [
          'usbConnectionComplete',
          'systemDenialReturned',
          'denialRetryAvailable',
          'systemGrantReturned',
          'usbWorkspaceOpened',
          'postLeaseShellVerified',
          'postLeaseFilesVerified',
          'ownedRecordRemoved',
          'baselineRecordsRetained',
        ];
        if (errors.isNotEmpty ||
            required.any((key) => report[key] != true) ||
            [
              'selinuxEnforcing',
              'systemCancelTapped',
              'systemOkTapped',
              'ownedUiDumpRemoved',
            ].any((key) => ui.receipt[key] != true) ||
            report['physicalCableVerified'] != false ||
            report.containsKey('productAcceptanceComplete')) {
          throw StateError(
            'Scoped Android USB permission regression did not complete.',
          );
        }
      },
    );
  } finally {
    finished = true;
    await coordination;
    if (ui.receipt['ownedUiDumpRemoved'] != true) await ui.cleanup();
  }
}
