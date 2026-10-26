import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

class _Node {
  _Node(this.text, this.bounds);
  final String text;
  final List<int> bounds;
}

/// 仅宿主使用的 Android 设置协调，不调用 adb pair 或导入身份；主控应用用自身 Rust 密钥执行 PAKE/TLS。
///
class _PairingFixture {
  _PairingFixture(this.adb, this.target, this.controller, this.output);
  final String adb;
  final String target;
  final String controller;
  final Directory output;
  final runId = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  final forwards = <int>[];
  final receipt = <String, dynamic>{};
  Set<String>? baseline;
  Set<String>? baselineKeys;
  var canManageTrust = false;
  String get xmlPath => '/data/local/tmp/connect-pair-$runId.xml';

  Future<String> _run(List<String> args) async {
    final result = await runProcess(
      adb,
      ['-s', target, ...args],
      timeout: const Duration(seconds: 25),
      stdoutEncoding: utf8,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) {
      throw StateError('Android fixture command failed (${result.exitCode}).');
    }
    return result.stdout as String;
  }

  Future<String> shell(List<String> args) =>
      _run(['shell', args.map(_quote).join(' ')]);

  Future<List<_Node>> nodes() async {
    await shell(['uiautomator', 'dump', xmlPath]);
    final xml = await shell(['cat', xmlPath]);
    String decode(String value) => value
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    final result = <_Node>[];
    for (final match in RegExp(r'<node\s+[^>]*>').allMatches(xml)) {
      final text = RegExp(r'text="([^"]*)"').firstMatch(match[0]!);
      final bounds = RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
          .firstMatch(match[0]!);
      if (text != null && bounds != null) {
        result.add(
          _Node(decode(text[1]!), [
            for (var i = 1; i <= 4; i++) int.parse(bounds[i]!),
          ]),
        );
      }
    }
    return result;
  }

  Future<void> tap(String label, List<_Node> current) async {
    final matches = current.where((node) => node.text == label).toList();
    if (matches.length != 1 || matches.single.bounds.length != 4) {
      throw StateError('Expected one Android Settings action: $label.');
    }
    final bounds = matches.single.bounds;
    await shell([
      'input',
      'tap',
      '${(bounds[0] + bounds[2]) ~/ 2}',
      '${(bounds[1] + bounds[3]) ~/ 2}',
    ]);
  }

  Future<List<_Node>> wirelessPage() async {
    var current = await nodes();
    if (current.any((node) => node.text == 'Pair with device')) {
      await shell(['input', 'keyevent', 'BACK']);
      current = await nodes();
    }
    if (current.any((node) => node.text == 'interop-controller') &&
        current.any((node) => node.text == 'Forget')) {
      await shell(['input', 'keyevent', 'BACK']);
      current = await nodes();
    }
    if (current.any((node) => node.text == 'Use wireless debugging')) {
      return current;
    }
    await shell([
      'am',
      'start',
      '-W',
      '-a',
      'android.settings.APPLICATION_DEVELOPMENT_SETTINGS',
    ]);
    for (var i = 0; i < 4; i++) {
      await shell(['input', 'swipe', '500', '800', '500', '2100', '200']);
    }
    for (var i = 0; i < 20; i++) {
      current = await nodes();
      // am start 返回后设置对话框可能仍在关闭，每次读取都要识别目标，包括迟到画面。
      //
      if (current.any((node) => node.text == 'Use wireless debugging')) {
        return current;
      }
      if (current.any((node) => node.text == 'Wireless debugging')) {
        await tap('Wireless debugging', current);
        current = await nodes();
        if (current.any((node) => node.text == 'Use wireless debugging')) {
          return current;
        }
      }
      await shell(['input', 'swipe', '500', '2100', '500', '800', '300']);
    }
    throw StateError('The target must expose enabled wireless debugging.');
  }

  Set<String> pairedNames(List<_Node> current) {
    final index = current.indexWhere((node) => node.text == 'Paired devices');
    if (index < 0) return {};
    return current
        .skip(index + 1)
        .map((node) => node.text)
        .where((text) => text.isNotEmpty)
        .toSet();
  }

  Set<String> authorizedKeys(String dump) {
    final start = dump.indexOf('user_keys=');
    final end = dump.indexOf('system_keys=', start < 0 ? 0 : start);
    if (start < 0 || end < start) {
      throw StateError(
        'The Android fixture authorization snapshot is missing.',
      );
    }
    // 公钥仅留在宿主内存，不把此快照写入报告。
    return dump
        .substring(start + 'user_keys='.length, end)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
  }

  Future<int> forward(int targetPort) async {
    final port = int.parse(
      (await _run(['forward', 'tcp:0', 'tcp:$targetPort'])).trim(),
    );
    forwards.add(port);
    return port;
  }

  Future<Map<String, String>> code() async {
    final current = await wirelessPage();
    await tap('Pair device with pairing code', current);
    for (var i = 0; i < 10; i++) {
      final dialog = await nodes();
      final codes = dialog
          .map((node) => node.text)
          .where((text) => RegExp(r'^\d{6}$').hasMatch(text))
          .toList();
      final endpoints = dialog
          .map((node) => node.text)
          .where((text) => RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(text))
          .toList();
      if (codes.length == 1 && endpoints.length == 1) {
        final port = await forward(int.parse(endpoints.single.split(':').last));
        return {'pairPort': '$port', 'code': codes.single};
      }
    }
    throw StateError(
      'The current system pairing dialog did not provide a code.',
    );
  }

  Future<Map<String, String>> prepare() async {
    if ((await shell(['getprop', 'ro.build.version.sdk'])).trim() != '36') {
      throw StateError('The system unpair fixture is pinned to Android API36.');
    }
    if ((await shell(['getprop', 'ro.adb.secure'])).trim() != '1') {
      throw StateError('This fixture must enforce Android host authorization.');
    }
    if ((await shell(['settings', 'get', 'global', 'adb_wifi_enabled']))
            .trim() !=
        '1') {
      throw StateError('Enable target wireless debugging before this run.');
    }
    final current = await wirelessPage();
    baseline = pairedNames(current);
    if (baseline!.contains('interop-controller')) {
      throw StateError('A pre-existing product trust entry must be preserved.');
    }
    final dump = await shell(['dumpsys', 'adb']);
    if (dump.contains('interop-controller')) {
      throw StateError(
        'A pre-existing product authorization must be preserved.',
      );
    }
    baselineKeys = authorizedKeys(dump);
    canManageTrust = true;
    final endpoints = current
        .map((node) => node.text)
        .where((text) => RegExp(r'^\d+\.\d+\.\d+\.\d+:\d+$').hasMatch(text))
        .toList();
    if (endpoints.length != 1) {
      throw StateError('Expected one actual wireless connection endpoint.');
    }
    final port = await forward(int.parse(endpoints.single.split(':').last));
    receipt['authorizationEnforcedProperty'] = true;
    receipt['noPreexistingProductTrustEntry'] = true;
    return {
      'action': 'fixture',
      'runId': runId,
      'address': '10.0.2.2',
      'connectPort': '$port',
      ...await code(),
    };
  }

  Future<void> revoke({required bool mustExist}) async {
    if (!canManageTrust) {
      throw StateError('This run does not own a product trust entry.');
    }
    var current = await wirelessPage();
    final matches = current.where((node) => node.text == 'interop-controller');
    if (matches.isEmpty && !mustExist) return;
    if (matches.length != 1) {
      throw StateError('The exact newly paired product identity is missing.');
    }
    await tap('interop-controller', current);
    current = await nodes();
    final fingerprints = current
        .map((node) => node.text)
        .expand(
          (text) => RegExp(r'(?:[A-F0-9]{2}:){15}[A-F0-9]{2}').allMatches(text),
        )
        .map((match) => match[0]!)
        .toList();
    if (fingerprints.length != 1) {
      throw StateError('The owned product fingerprint is not unique.');
    }
    // API36 设置在 handler 持久化取消配对时可能重开 AtomicFile 并删除待提交 .new；停止设置读取后仍调用同一系统取消配对方法，不改写密钥文件。
    //
    //
    await shell(['am', 'force-stop', 'com.android.settings']);
    final result = await shell([
      'service',
      'call',
      'adb',
      '7',
      's16',
      fingerprints.single,
    ]);
    if (!RegExp(r"^Result: Parcel\(\s*00000000\s*'\.\.\.\.'\s*\)$")
        .hasMatch(result.trim())) {
      throw StateError(
        'The pinned Android unpair service did not acknowledge.',
      );
    }
    receipt['revocationMechanism'] = 'API36-IAdbManager.unpairDevice';
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final dump = await shell(['dumpsys', 'adb']);
      if (!dump.contains('interop-controller') &&
          authorizedKeys(dump).containsAll(baselineKeys ?? {})) {
        final remaining = pairedNames(await wirelessPage());
        if (!remaining.contains('interop-controller') &&
            remaining.containsAll(baseline ?? {})) {
          receipt['exactProductTrustRevoked'] = true;
          return;
        }
        throw StateError('The system authorization and Settings disagree.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Exact trust revocation was not confirmed by Android.');
  }

  Future<void> cleanup() async {
    try {
      if (canManageTrust) {
        await revoke(mustExist: false);
        final remaining = pairedNames(await wirelessPage());
        final dump = await shell(['dumpsys', 'adb']);
        if (remaining.contains('interop-controller') ||
            !remaining.containsAll(baseline!) ||
            dump.contains('interop-controller') ||
            !authorizedKeys(dump).containsAll(baselineKeys!)) {
          throw StateError('The original trust entries were not preserved.');
        }
        receipt['originalTrustEntriesRetained'] = true;
        receipt['ownedTrustAbsent'] = true;
      }
    } finally {
      try {
        var failed = false;
        for (final port in List<int>.of(forwards)) {
          try {
            await _run(['forward', '--remove', 'tcp:$port']);
            forwards.remove(port);
          } catch (_) {
            failed = true;
          }
        }
        receipt['ownedForwardsRemoved'] = !failed && forwards.isEmpty;
        if (failed) throw StateError('An owned forward did not clear.');
      } finally {
        await shell(['rm', '-f', xmlPath]);
      }
    }
  }

  Future<void> capture(String label) async {
    final result = await runProcess(
      adb,
      ['-s', controller, 'exec-out', 'screencap', '-p'],
      timeout: const Duration(seconds: 25),
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) throw StateError('Controller screenshot failed.');
    await File('${output.path}/$label.png')
        .writeAsBytes(result.stdout as List<int>, flush: true);
  }
}

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  if (adb == null ||
      controller == null ||
      target == null ||
      !controller.startsWith('emulator-') ||
      !target.startsWith('emulator-') ||
      controller == target) {
    throw StateError('Select explicit, distinct controller and target AVDs.');
  }
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/first-pairing';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Pairing evidence must remain under /tmp/.');
  }
  final output = await Directory(path).create(recursive: true);
  final fixture = _PairingFixture(adb, target, controller, output);
  final errors = <String>[];
  var finished = false;
  Future<void>? coordination;
  var cleanupConfirmed = false;
  try {
    final driver = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await driver.serviceClient
                .callServiceExtension(
                  'ext.connect.firstPairing',
                  isolateId: driver.appIsolate.id,
                  args: args,
                )
                .timeout(const Duration(seconds: 15)))
            .json ??
        {};
    coordination =
        () async {
          final handled = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 9));
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
                    await extension(await fixture.prepare());
                  case 'need-fresh-code':
                    await extension({
                      'action': 'freshCode',
                      'runId': fixture.runId,
                      ...await fixture.code(),
                    });
                  case 'need-connected-capture':
                    await fixture.capture('paired-connected-workspace');
                    await extension({
                      'action': 'connectedCaptured',
                      'runId': fixture.runId,
                    });
                  case 'need-revoke':
                    await fixture.revoke(mustExist: true);
                    await extension({
                      'action': 'revoked',
                      'runId': fixture.runId,
                    });
                  case 'revoked-rejected':
                    await fixture.capture(stage);
                    await extension({
                      'action': 'rejectionCaptured',
                      'runId': fixture.runId,
                    });
                  case 'cleanup':
                    await fixture.cleanup();
                    cleanupConfirmed = true;
                    await extension({
                      'action': 'cleanup',
                      'runId': fixture.runId,
                    });
                }
              } catch (error, stack) {
                // 命令可能携带当前配对码，不将异常或 VM service 参数序列化到日志与结果。
                //
                errors.add('Android fixture failed at stage $stage.');
                fixture.receipt.putIfAbsent('failureStage', () => stage);
                fixture.receipt.putIfAbsent(
                  'failureType',
                  () => '${error.runtimeType}',
                );
                fixture.receipt.putIfAbsent(
                  'failureLocations',
                  () => stack
                      .toString()
                      .split('\n')
                      .where((line) => line.contains('first_pairing.dart'))
                      .take(3)
                      .toList(),
                );
                await extension({'runId': fixture.runId, 'error': 'true'});
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!finished) {
            throw StateError('First-pairing host handshake timed out.');
          }
        }().catchError((Object _) {
          errors.add('First-pairing host coordination failed.');
        });
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        finished = true;
        await coordination;
        final report = {...?data}..remove('screenshots');
        report.addAll({
          'hostErrors': errors,
          'androidOsReceipt': fixture.receipt,
          'fixtureCleanupConfirmed': cleanupConfirmed,
          'evidenceScope': 'actual-Android-code-pairing-TLS-revocation',
        });
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        final required = [
          'firstPairingComplete',
          'initialUnpairedRejected',
          'wrongCodeRejected',
          'realPairingCompleted',
          'requiredTlsConnected',
          'revokedIdentityRejected',
          'ownedRecordRemoved',
          'fixtureCleanupAcknowledged',
        ];
        if (errors.isNotEmpty ||
            !cleanupConfirmed ||
            report.containsKey('productAcceptanceComplete') ||
            required.any((key) => report[key] != true) ||
            [
              'authorizationEnforcedProperty',
              'noPreexistingProductTrustEntry',
              'exactProductTrustRevoked',
              'originalTrustEntriesRetained',
              'ownedTrustAbsent',
              'ownedForwardsRemoved',
            ].any((key) => fixture.receipt[key] != true)) {
          throw StateError('Scoped first-pairing acceptance did not complete.');
        }
      },
    );
  } finally {
    finished = true;
    await coordination;
    if (!cleanupConfirmed) await fixture.cleanup();
  }
}
