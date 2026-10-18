import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

const _fixturePackage = 'dev.scrcpyconnect.notificationfixture';
const _fixtureActivity = '$_fixturePackage/.NotificationFixtureActivity';
const _fixtureApk =
    '/tmp/connect-notification-fixture/notification-fixture.apk';

/// A receiver receipt confirms only this temporary Android fixture received
/// RemoteInput. It makes no assertion about a chat app or message service.
void validateNotificationReplyReceipt(
  Map<String, dynamic>? receipt, {
  required String runId,
  required String expectedText,
}) {
  if (receipt == null ||
      receipt['runId'] != runId ||
      receipt['messageId'] != '$runId:0' ||
      receipt['notificationId'] != 0 ||
      receipt['text'] != expectedText ||
      receipt['count'] is! int ||
      receipt['count'] != 1) {
    throw StateError(
      'The independent Android receiver did not receive exactly one matching reply: $receipt',
    );
  }
}

void validateNotificationReplyReport(
  Map<String, dynamic> report, {
  required String runId,
  required String expectedText,
  required Map<String, dynamic>? receiverReceipt,
  required bool cleanupConfirmed,
}) {
  if (report.containsKey('productAcceptanceComplete') ||
      report['notificationReplyComplete'] != true ||
      report['fixtureRunId'] != runId ||
      report['fixtureTag'] != 'notification-fixture-$runId' ||
      report['replyText'] != expectedText ||
      report['notificationId'] is! String ||
      (report['notificationId'] as String).isEmpty ||
      report['systemAcceptanceVisible'] != true ||
      report['deliveryUnconfirmedVisible'] != true ||
      report['reopenedReplyGuarded'] != true ||
      report['notificationDismissed'] != true ||
      report['dismissedReplyCopyMatches'] != true ||
      report['fixtureCleanupAcknowledged'] != true ||
      report['clipboardBaselinePresent'] != true ||
      report['clipboardRestored'] != true) {
    throw StateError(
      'The app did not complete scoped notification reply acceptance.',
    );
  }
  validateNotificationReplyReceipt(
    receiverReceipt,
    runId: runId,
    expectedText: expectedText,
  );
  if (!cleanupConfirmed) {
    throw StateError('Owned notification fixture cleanup was not confirmed.');
  }
}

class _Fixture {
  _Fixture(this.adb, this.target)
    : runId = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  final String adb;
  final String target;
  final String runId;
  String get tag => 'notification-fixture-$runId';
  String get text => 'Connect actual RemoteInput $runId\n中文与 emoji 👋';
  String get _runFile => 'files/runs/$runId.json';
  String get _receiptFile => 'files/receipts/$runId.json';
  String get _cleanupFile => 'files/cleanup/$runId.json';
  bool _installed = false;
  bool _ready = false;
  bool cleanupConfirmed = false;
  Future<void>? _cleanup;
  Map<String, dynamic>? receiverReceipt;
  Map<String, dynamic>? cleanupReceipt;

  Future<ProcessResult> _run(List<String> args) => Process.run(adb, [
    '-s',
    target,
    ...args,
  ]).timeout(const Duration(seconds: 30));

  Future<String> _checked(List<String> args) async {
    final result = await _run(args);
    if (result.exitCode != 0) {
      throw StateError(
        'Notification fixture adb ${args.first} failed: ${result.stdout} ${result.stderr}',
      );
    }
    return result.stdout as String;
  }

  Future<bool> _packagePresent() async {
    final packages = await _checked([
      'shell',
      'pm',
      'list',
      'packages',
      '-u',
      _fixturePackage,
    ]);
    return const LineSplitter()
        .convert(packages)
        .any((line) => line.trim() == 'package:$_fixturePackage');
  }

  Future<void> _activity(String action) async {
    final output = await _checked([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      _fixtureActivity,
      '-a',
      '$_fixturePackage.$action',
      '--es',
      'runId',
      runId,
    ]);
    if (output.contains('Error:') || output.contains('Exception')) {
      throw StateError('Notification fixture $action failed: $output');
    }
  }

  Future<bool> _fileExists(String path) async {
    final result = await _run([
      'shell',
      'run-as',
      _fixturePackage,
      'test',
      '-e',
      path,
    ]);
    if (result.exitCode == 0) {
      return true;
    }
    if (result.exitCode == 1 && (result.stderr as String).trim().isEmpty) {
      return false;
    }
    throw StateError(
      'Cannot inspect the owned fixture file $path: ${result.stdout} ${result.stderr}',
    );
  }

  Future<Map<String, dynamic>?> _readJson(String path) async {
    if (!await _fileExists(path)) {
      return null;
    }
    final output = await _checked([
      'shell',
      'run-as',
      _fixturePackage,
      'cat',
      path,
    ]);
    return jsonDecode(output) as Map<String, dynamic>;
  }

  Future<void> start() async {
    if (await _packagePresent()) {
      throw StateError(
        '$_fixturePackage already exists; refusing to overwrite or take ownership of it.',
      );
    }
    if (!await File(_fixtureApk).exists()) {
      throw StateError('Build the test-only fixture APK first: $_fixtureApk');
    }
    // No -r: a concurrent/existing installation must fail, never be replaced.
    final installed = await _checked(['install', '-t', _fixtureApk]);
    if (!installed.contains('Success')) {
      throw StateError(
        'Fixture installation did not confirm Success: $installed',
      );
    }
    _installed = true;
    _installed = true;
    await _checked([
      'shell',
      'pm',
      'grant',
      _fixturePackage,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    await _activity('CREATE');
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await _readJson(_runFile);
      if (state != null) {
        if (state['status'] == 'error') {
          throw StateError('Android fixture failed to create its run: $state');
        }
        if (state['status'] == 'ready') {
          if (state['runId'] != runId ||
              state['tag'] != tag ||
              state['channel'] != tag ||
              jsonEncode(state['notificationIds']) != '[0,1,2,3]') {
            throw StateError(
              'Android fixture returned the wrong owned identities: $state',
            );
          }
          _ready = true;
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'Android notification fixture never published its ready state.',
    );
  }

  Future<bool> readReceiver() async {
    receiverReceipt = await _readJson(_receiptFile);
    if (receiverReceipt == null) {
      return false;
    }
    validateNotificationReplyReceipt(
      receiverReceipt,
      runId: runId,
      expectedText: text,
    );
    return true;
  }

  Future<List<int>> _activeNotificationIds() async {
    final listing = await _checked(['shell', 'cmd', 'notification', 'list']);
    final ids = <int>[];
    for (final line in const LineSplitter().convert(listing)) {
      final parts = line.trim().split('|');
      if (!parts.contains(tag)) {
        continue;
      }
      if (parts.length < 5 ||
          parts[1] != _fixturePackage ||
          parts[3] != tag ||
          int.tryParse(parts[2]) == null) {
        throw StateError(
          'Cannot identify the exact fixture notification key: $line',
        );
      }
      ids.add(int.parse(parts[2]));
    }
    return ids..sort();
  }

  Future<void> verifyDismissal() async {
    final ids = await _activeNotificationIds();
    if (jsonEncode(ids) != '[1,2,3]') {
      throw StateError(
        'The UI must clear only this run’s notification 0; actual Android IDs: $ids',
      );
    }
  }

  Future<void> cleanup() => _cleanup ??= _cleanOwnedInstallation();

  Future<void> _cleanOwnedInstallation() async {
    if (!_installed) {
      return;
    }
    final failures = <Object>[];
    // Retain diagnostic evidence even if Android cleanup itself later fails.
    try {
      receiverReceipt = await _readJson(_receiptFile);
    } catch (error) {
      failures.add(error);
    }
    try {
      await _activity('CLEANUP');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var clean = false;
      while (DateTime.now().isBefore(deadline)) {
        cleanupReceipt = await _readJson(_cleanupFile);
        clean =
            cleanupReceipt?['runId'] == runId &&
            cleanupReceipt?['status'] == 'cleaned' &&
            !await _fileExists(_runFile) &&
            !await _fileExists(_receiptFile) &&
            (await _activeNotificationIds()).isEmpty;
        if (clean) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!clean) {
        throw StateError(
          'The exact fixture notifications and private run/receipt did not clear.',
        );
      }
      // Android serializes this final snapshot after invalidating the run and
      // cancelling its PendingIntents. A late count 2 cannot be deleted unseen.
      final finalReceipt = cleanupReceipt!['finalReceipt'];
      receiverReceipt = finalReceipt == null
          ? null
          : Map<String, dynamic>.from(finalReceipt as Map<String, dynamic>);
    } catch (error) {
      failures.add(error);
    } finally {
      // This flag is set only after our non-replacing install succeeded.
      // Even a failed CREATE/CLEANUP must release this owned test APK.
      try {
        final output = await _checked(['uninstall', _fixturePackage]);
        if (!output.contains('Success') || await _packagePresent()) {
          throw StateError(
            'Owned fixture APK removal was not confirmed: $output',
          );
        }
        _installed = false;
      } catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
        'Notification fixture cleanup failed: ${failures.join('; ')}',
      );
    }
    cleanupConfirmed = _ready;
  }
}

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  if (adb == null ||
      adb.isEmpty ||
      target == null ||
      !target.startsWith('emulator-')) {
    throw StateError(
      'Set CONNECT_E2E_ADB and CONNECT_E2E_TARGET to the explicit Android emulator fixture target.',
    );
  }
  final outputPath =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/notification-reply';
  if (!outputPath.startsWith('/tmp/') || outputPath.split('/').contains('..')) {
    throw StateError(
      'Notification reply artifacts must be written under /tmp/.',
    );
  }
  final output = await Directory(outputPath).create(recursive: true);
  final fixture = _Fixture(adb, target);
  final errors = <Object>[];
  var finished = false;
  Future<void>? coordination;
  Future<void> finishHost() async {
    finished = true;
    await coordination;
    try {
      await fixture.cleanup();
    } catch (error) {
      errors.add(error);
    }
  }

  try {
    await fixture.start();
    final connected = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await connected.serviceClient
                .callServiceExtension(
                  'ext.connect.notificationReply',
                  isolateId: connected.appIsolate.id,
                  args: args,
                )
                .timeout(const Duration(seconds: 10)))
            .json ??
        <String, dynamic>{};
    coordination =
        () async {
          final acknowledged = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 7));
          while (!finished && DateTime.now().isBefore(deadline)) {
            Map<String, dynamic> state;
            try {
              state = await extension();
            } catch (error) {
              if (finished) {
                return;
              }
              if (!error.toString().contains('Method not found') &&
                  !error.toString().contains('-32601')) {
                rethrow;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
              continue;
            }
            final stage = state['stage'];
            if (stage == 'complete') {
              return;
            }
            if (stage is String && !acknowledged.contains(stage)) {
              switch (stage) {
                case 'waiting-fixture':
                  await extension({
                    'action': 'fixture',
                    'runId': fixture.runId,
                    'tag': fixture.tag,
                    'text': fixture.text,
                  });
                  acknowledged.add(stage);
                case 'awaiting-receiver':
                  if (await fixture.readReceiver()) {
                    await extension({
                      'action': 'receiver',
                      'runId': fixture.runId,
                      'count': '1',
                    });
                    acknowledged.add(stage);
                  }
                case 'awaiting-dismissal-check':
                  await fixture.verifyDismissal();
                  await extension({
                    'action': 'dismissal',
                    'runId': fixture.runId,
                  });
                  acknowledged.add(stage);
                case 'awaiting-cleanup':
                  if (!await fixture.readReceiver()) {
                    throw StateError(
                      'The final independent receiver receipt is missing.',
                    );
                  }
                  await fixture.cleanup();
                  validateNotificationReplyReceipt(
                    fixture.receiverReceipt,
                    runId: fixture.runId,
                    expectedText: fixture.text,
                  );
                  if (!fixture.cleanupConfirmed) {
                    throw StateError(
                      'Android fixture cleanup was not confirmed.',
                    );
                  }
                  await extension({
                    'action': 'cleanup',
                    'runId': fixture.runId,
                  });
                  return;
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (!finished) {
            throw StateError(
              'The notification reply host handshake timed out.',
            );
          }
        }().catchError((Object error) async {
          errors.add(error);
          if (!finished) {
            try {
              await extension({'error': error.toString()});
            } catch (notificationError) {
              errors.add(notificationError);
            }
          }
        });

    await integrationDriver(
      driver: connected,
      writeResponseOnFailure: true,
      onScreenshot: (name, bytes, [args]) async {
        final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        await File('${output.path}/$safeName.png')
            .writeAsBytes(bytes, flush: true);
        return true;
      },
      responseDataCallback: (data) async {
        // extended integrationDriver calls exit after this callback. Both the
        // success and failure paths must finish cleanup before returning.
        await finishHost();
        final report = {...?data}..remove('screenshots');
        report.addAll({
          'independentReceiverReceipt': fixture.receiverReceipt,
          'independentCleanupReceipt': fixture.cleanupReceipt,
          'receiverEvidenceScope':
              'temporary-Android-fixture-RemoteInput-receiver',
          'fixtureCleanupConfirmed': fixture.cleanupConfirmed,
          'fixtureTarget': target,
          'hostErrors': errors.map((error) => error.toString()).toList(),
        });
        await File('${output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        if (errors.isNotEmpty) {
          throw StateError(
            'Independent notification reply checks failed: ${errors.join('; ')}',
          );
        }
        validateNotificationReplyReport(
          report,
          runId: fixture.runId,
          expectedText: fixture.text,
          receiverReceipt: fixture.receiverReceipt,
          cleanupConfirmed: fixture.cleanupConfirmed,
        );
      },
    );
  } catch (error) {
    errors.add(error);
    rethrow;
  } finally {
    // Covers setup, driver connection, transport and screenshot failures that
    // occur before responseDataCallback can be entered.
    await finishHost();
    if (errors.isNotEmpty) {
      throw StateError('Notification reply host failed: ${errors.join('; ')}');
    }
  }
}
