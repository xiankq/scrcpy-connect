import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
        '/tmp/connect-e2e/session-workspace',
  );
  await directory.create(recursive: true);
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  if (target == null || adb == null) {
    throw StateError(
      'Set CONNECT_E2E_TARGET and CONNECT_E2E_ADB for independent target process verification.',
    );
  }
  final processChecks = <Map<String, Object?>>[];
  Future<void> verifyProcesses(Map<String, dynamic> args) async {
    final ids = (args['sessionIds'] as List).cast<String>();
    final active = args['activeSessionId'] as String?;
    final closed = (args['closedSessionIds'] as List).cast<String>();
    Future<String> shell(List<String> command) async {
      final result = await Process.run(adb, [
        '-s',
        target,
        'shell',
        ...command,
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        throw StateError(
          'Independent target inspection failed: ${result.stderr}',
        );
      }
      return result.stdout as String;
    }

    final listing = await shell(['ps', '-A', '-o', 'PID,STAT,ARGS']);
    final found = <String, String>{};
    for (final line in const LineSplitter().convert(listing)) {
      if (!line.contains('interop-scrcpy-')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3 || int.tryParse(parts[0]) == null) continue;
      final commandLine = await shell(['cat', '/proc/${parts[0]}/cmdline']);

      for (final id in [...ids, ...closed]) {
        if (commandLine
            .split('\u0000')
            .any(
              (entry) => RegExp(
                '^interop[.]scrcpy:[0-9a-f]{8}:/data/local/tmp/interop-scrcpy-${RegExp.escape(id)}[.]jar\u0024',
              ).hasMatch(entry),
            )) {
          found[id] = parts[1];
        }
      }
    }
    for (final id in ids) {
      if (!found.containsKey(id)) {
        throw StateError('No actual owned scrcpy process for session $id');
      }
      final stopped = found[id]!.contains('T');
      // Capture suspension must leave the controller and Binder threads alive.
      if (stopped) {
        throw StateError(
          'Capture pause froze the whole target service: ${found[id]} for $id',
        );
      }
    }
    for (final id in closed) {
      if (found.containsKey(id)) {
        throw StateError('Closed window still has a target process: $id');
      }
    }
    if (args['name'] == 'session-main-live' ||
        args['name'] == 'session-primary-app-live') {
      final activities = await shell(['dumpsys', 'activity', 'activities']);
      final primary =
          activities
              .split('Display #0')
              .skip(1)
              .firstOrNull
              ?.split('Display #')
              .first ??
          '';
      final settingsResumed = const LineSplitter()
          .convert(primary)
          .any(
            (line) =>
                line.contains('topResumedActivity=') &&
                line.contains('com.android.settings/'),
          );
      if (settingsResumed != (args['name'] == 'session-primary-app-live')) {
        throw StateError(
          'Phone-screen continuation must actually change display 0 from HOME to Settings.',
        );
      }
    }
    processChecks.add({
      'checkpoint': args['name'],
      'activeSessionId': active,
      'states': found,
      'closedSessionIds': closed,
    });
  }

  final driver = await FlutterDriver.connect();
  var finished = false;
  Object? inspectionError;
  final inspection =
      () async {
        String? previous;
        final deadline = DateTime.now().add(const Duration(minutes: 5));
        while (!finished && DateTime.now().isBefore(deadline)) {
          try {
            final response = await driver.serviceClient.callServiceExtension(
              'ext.connect.sessions',
              isolateId: driver.appIsolate.id,
            );
            final checkpoint = response.json?['checkpoint'];
            if (checkpoint is Map && checkpoint['name'] != previous) {
              final state = Map<String, dynamic>.from(checkpoint);
              previous = state['name'] as String;
              String? error;
              try {
                await verifyProcesses(state);
              } catch (failure) {
                error = failure.toString();
                inspectionError = failure;
              }
              await driver.serviceClient.callServiceExtension(
                'ext.connect.sessions',
                isolateId: driver.appIsolate.id,
                args: {'ack': previous, 'error': ?error},
              );
              if (error != null) return;
            }
          } catch (error) {
            if (!error.toString().contains('ext.connect.sessions') &&
                !error.toString().contains('Method not found')) {
              rethrow;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!finished) {
          throw StateError('Timed out inspecting actual session processes.');
        }
      }().catchError((Object error) {
        inspectionError = error;
      });
  await integrationDriver(
    driver: driver,
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      await File(
        '${directory.path}/${name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.png',
      ).writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      finished = true;
      await inspection;
      final metadata = {...?data}..remove('screenshots');
      metadata['independentProcessChecks'] = processChecks;
      await File('${directory.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      if (inspectionError != null ||
          metadata['sessionWorkspaceComplete'] != true ||
          metadata['phoneScreenAppResumed'] != true ||
          metadata['phoneScreenRenderedApp'] != true ||
          metadata['releasedWindowsVerified'] != 4 ||
          (metadata['closedWindowIds'] as List?)?.toSet().length != 4 ||
          processChecks.map((check) => check['checkpoint']).join(',') !=
              'session-main-live,session-closed-1,session-primary-app-live,session-closed-2,session-settings-live,session-closed-3,session-dialer-live,session-closed-4') {
        throw StateError(
          'The real multi-session workflow or independent process checks did not complete.',
        );
      }
    },
  );
}
