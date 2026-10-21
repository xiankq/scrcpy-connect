// ignore_for_file: file_names
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../../tooling.dart';
import 'android-probe.dart' as transport;

/// An installed source app and a UID2000 product companion observe the same
/// actual Android notifications. No product notification permission is changed.
class SnapshotProbe extends transport.Probe {
  SnapshotProbe(super.adbExecutable, super.serial)
    : super(calls: false, skipReceiver: true, fixtureFile: File('/unused'));

  static const package = 'dev.scrcpyconnect.notificationfixture';
  late final runId = randomHex(16);
  bool installed = false;

  Future<void> action(String action) async {
    await adb([
      'shell',
      'am',
      'start',
      '-n',
      '$package/.NotificationFixtureActivity',
      '-a',
      '$package.$action',
      '--es',
      'runId',
      runId,
    ]);
  }

  List<transport.Json> ownRecords(transport.Json snapshot) =>
      (snapshot['notifications'] as List)
          .cast<transport.Json>()
          .where(
            (item) =>
                item['packageName'] == package &&
                (item['key'] as String).contains(
                  '|notification-fixture-$runId|',
                ),
          )
          .toList();

  final binderEvents = <String, transport.Json>{};

  /// Consume only unsolicited transport events. A notifications.list request
  /// actively refreshes the companion and would hide a missing Binder callback.
  Future<List<transport.Json>> waitOwnEvent(
    String phase,
    bool Function(List<transport.Json>) ready,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      require(remaining > Duration.zero, 'No Binder invalidation for $phase');
      final event = await response().timeout(
        remaining,
        onTimeout: () => throw StateError('No Binder invalidation for $phase'),
      );
      events.add(event);
      if (event['event'] != 'notifications.changed') continue;
      final snapshot = event['data'] as transport.Json;
      if (snapshot['observationEpoch'] != 1 ||
          snapshot['observationEnabled'] != true ||
          snapshot['live'] != true) {
        continue;
      }
      final items = ownRecords(snapshot);
      if (!ready(items)) continue;
      binderEvents[phase] = event;
      return items;
    }
  }

  @override
  Future<void> execute() async {
    final existing = await adb(['shell', 'pm', 'path', package], check: false);
    require(
      (existing.stdout as String).trim().isEmpty,
      'Refusing an existing fixture installation',
    );
    await adb([
      'install',
      '/tmp/connect-notification-fixture/notification-fixture.apk',
    ]);
    installed = true;
    await adb([
      'shell',
      'pm',
      'grant',
      package,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    final id = randomHex(16),
        name = 'interop-companion-$id',
        secret = randomHex(32);
    final jar = '/data/local/tmp/interop-snapshot-$id.jar';
    pushed.add(jar);
    await adb([
      'push',
      p.join(repositoryRoot().path, 'servers/companion/companion.jar'),
      jar,
    ]);
    process = await startJar(
      'CLASSPATH=$jar app_process / com.interop.companion.Main $name $secret',
    );
    require(
      (await process!.line()).startsWith('INTEROP_COMPANION_READY '),
      'Missing ready marker',
    );
    final forward = await adb(['forward', 'tcp:0', 'localabstract:$name']);
    port = int.parse((forward.stdout as String).trim());
    socket = await Socket.connect('127.0.0.1', port!);
    responses = StreamIterator(
      socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    socket!.writeln(jsonEncode({'token': secret}));
    await socket!.flush();
    while ((await response())['event'] != 'ready') {}
    await success('observation.set', {'enabled': true, 'epoch': 1});
    await action('CREATE_SNAPSHOT');
    final initial = await waitOwnEvent('create', (items) => items.length == 3);
    // Independent Android service dump proves these are actually posted,
    // rather than only values supplied to the companion assertion.
    final dump =
        (await adb(['shell', 'dumpsys', 'notification', '--noredact'])).stdout
            as String;
    for (final text in [
      'Expanded title',
      'Real expanded body',
      'Alice: first message',
      'Bob: latest message',
    ]) {
      require(dump.contains(text), 'Target notification service missing $text');
    }
    final evidence = Directory('/tmp/connect-notification-snapshot')
      ..createSync(recursive: true);
    File(p.join(evidence.path, 'initial.json'))
        .writeAsStringSync(jsonEncode(initial));
    File(p.join(evidence.path, 'android-notifications.txt'))
        .writeAsStringSync(dump);
    final big = initial.singleWhere(
      (n) => (n['key'] as String).contains('|0|'),
    );
    final inbox = initial.singleWhere(
      (n) => (n['key'] as String).contains('|1|'),
    );
    require(big['title'] == 'Expanded title', 'Expanded title mismatch: $big');
    require(
      big['body'] == 'Real expanded body',
      'Expanded body mismatch: $big',
    );
    require(
      inbox['body'] == 'Alice: first message\nBob: latest message',
      'Inbox body mismatch: $inbox',
    );
    final messages = initial.singleWhere(
      (n) => (n['key'] as String).contains('|2|'),
    );
    require(
      messages['body'] == 'Latest' &&
          (messages['title'] as String).contains('Team chat'),
      'Messaging preview mismatch: $messages',
    );
    final originalId = big['id'];
    await action('UPDATE_SNAPSHOT');
    final updated = await waitOwnEvent(
      'update',
      (items) =>
          items.length == 3 &&
          items.any(
            (n) =>
                n['title'] == 'Updated expanded title' &&
                n['body'] == 'Updated real expanded body' &&
                n['id'] != originalId,
          ),
    );
    final replacement = updated.singleWhere(
      (n) => (n['key'] as String).contains('|0|'),
    );
    require(
      replacement['title'] == 'Updated expanded title' &&
          replacement['id'] != originalId,
      'Revision/title not updated',
    );
    await rejected('notifications.open', 'notification_expired', {
      'notificationId': originalId,
    });
    await action('CLEANUP');
    await waitOwnEvent('withdraw', (items) => items.isEmpty);
    File(p.join(evidence.path, 'binder-events.json'))
        .writeAsStringSync(jsonEncode(binderEvents));
    // Reattach observation after cleanup must not resurrect the removed set.
    await success('observation.set', {'enabled': false, 'epoch': 2});
    await success('observation.set', {'enabled': true, 'epoch': 3});
    final reattached = await success('notifications.list');
    require(reattached['live'] == true, reattached);
    require(
      ownRecords(reattached).isEmpty,
      'Removed notifications resurrected',
    );
    stdout.writeln(
      'PASS: target actual BigText/Inbox snapshots, update, removal, Binder callbacks and observation reattach',
    );
  }

  @override
  Future<void> cleanup() async {
    Object? failure;
    if (installed) {
      try {
        await action('CLEANUP');
        final dump =
            (await adb(['shell', 'dumpsys', 'notification', '--noredact']))
                    .stdout
                as String;
        // Active entries have a NotificationRecord; deleted channels may retain the tag.
        require(
          !RegExp(
            'NotificationRecord[^\\n]*${RegExp.escape('notification-fixture-$runId')}',
          ).hasMatch(dump),
          'Owned notification remains active',
        );
      } catch (error) {
        failure = error;
      }
      try {
        await adb(['uninstall', package]);
        final remaining = await adb([
          'shell',
          'pm',
          'path',
          package,
        ], check: false);
        require(
          (remaining.stdout as String).trim().isEmpty,
          'Owned fixture remained installed',
        );
      } catch (error) {
        failure ??= error;
      }
    }
    try {
      await super.cleanup();
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }
}

Future<void> main(List<String> args) => cli(() async {
  final options =
      (ArgParser()
            ..addOption('adb')
            ..addOption('serial'))
          .parse(args);
  require(
    options['adb'] != null &&
        (options['serial'] as String? ?? '').startsWith('emulator-'),
    'Explicit --adb and emulator --serial required',
  );
  final probe = SnapshotProbe(
    options['adb'] as String,
    options['serial'] as String,
  );
  Object? failure;
  try {
    await probe.execute();
  } catch (error) {
    failure = error;
  }
  try {
    await probe.cleanup();
  } catch (error) {
    failure ??= error;
  }
  if (failure != null) throw failure;
});
