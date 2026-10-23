import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../src/process.dart';

Future<void> main() async {
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/gallery-index';
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  if (!path.startsWith('/tmp/') ||
      path.split('/').contains('..') ||
      adb == null ||
      target == null ||
      controller == null ||
      controller == target ||
      !RegExp(r'^emulator-\d+$').hasMatch(target)) {
    throw StateError(
      'Gallery acceptance requires explicit isolated target and /tmp evidence.',
    );
  }
  final output = await Directory(path).create(recursive: true);
  var actualSourceBytesVerified = false;
  var actualAllSizesVerified = false;
  final driver = await FlutterDriver.connect();
  Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
      (await driver.serviceClient
              .callServiceExtension(
                'ext.connect.galleryIndex',
                isolateId: driver.appIsolate.id,
                args: args,
              )
              .timeout(const Duration(seconds: 15)))
          .json ??
      {};
  var finished = false;
  final errors = <String>[];
  final coordination =
      () async {
        final deadline = DateTime.now().add(const Duration(minutes: 6));
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
          try {
            if (state['stage'] == 'verify-fixture') {
              final paths =
                  (state['fixturePaths'] as List<Object?>? ?? const [])
                      .whereType<String>()
                      .toList();
              final encoded = state['fixtureBytes'];
              final safePaths =
                  paths.length == 105 &&
                  paths.every(
                    (p) => RegExp(
                      r'^/sdcard/(?:Download/|Android/media/)?connect-gallery-\d+(?:/(?:custom|app-media|download-\d{3}))?\.png$',
                    ).hasMatch(p),
                  );
              if (!safePaths || encoded is! String) {
                throw StateError(
                  'Independent gallery original verification failed.',
                );
              }
              final expected = base64Decode(encoded);
              if (expected.isEmpty || expected.length > 1024 * 1024) {
                throw StateError(
                  'Independent gallery original verification failed.',
                );
              }
              final sizes = await runProcess(adb, [
                '-s',
                target,
                'shell',
                'stat -c %s -- ${paths.map((p) => '"$p"').join(' ')}',
              ]);
              final values = (sizes.stdout as String).trim().split(
                RegExp(r'\s+'),
              );
              actualAllSizesVerified =
                  sizes.exitCode == 0 &&
                  values.length == 105 &&
                  values.every(
                    (value) => int.tryParse(value) == expected.length,
                  );
              final source = await runProcess(adb, [
                '-s',
                target,
                'exec-out',
                'cat',
                paths.first,
              ], stdoutEncoding: null);
              final actual = source.stdout as List<int>;
              actualSourceBytesVerified =
                  source.exitCode == 0 &&
                  actual.length == expected.length &&
                  List.generate(
                    expected.length,
                    (i) => i,
                  ).every((i) => actual[i] == expected[i]);
              if (!actualAllSizesVerified || !actualSourceBytesVerified) {
                throw StateError(
                  'Independent gallery original verification failed.',
                );
              }
              await extension({
                'action': 'verified',
                'token': state['token'] as String,
              });
              return;
            }
          } catch (error) {
            await extension({
              'token': state['token'] as String,
              'error': 'verification-failed',
            });
            rethrow;
          }
          if (state['stage'] == 'done' || state['stage'] == 'cleanup') return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!finished) {
          throw StateError('Gallery host verification deadline exceeded.');
        }
      }().catchError((Object error, StackTrace stack) {
        errors.add('$error');
      });
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      finished = true;
      await coordination;
      final report = {...?data}..remove('screenshots');
      report['hostErrors'] = errors;
      final roots = (report['fixtureRoots'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList();
      final loose = report['looseFixture'];
      final owned = [...roots, if (loose is String) loose];
      final safe =
          owned.length == 4 &&
          owned.every(
            (p) => RegExp(
              r'^/sdcard/(?:Download/|Android/media/)?connect-gallery-\d+(?:\.png)?$',
            ).hasMatch(p),
          );
      var absent = false;
      if (safe) {
        final result = await runProcess(adb, [
          '-s',
          target,
          'shell',
          owned.map((p) => 'test ! -e "$p"').join(' && '),
        ]);
        absent = result.exitCode == 0;
      }
      report['independentOwnedPathsAbsent'] = absent;
      report['independentSourceBytesVerified'] = actualSourceBytesVerified;
      report['independentAllSizesVerified'] = actualAllSizesVerified;
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(report), flush: true);
      if (!safe ||
          !absent ||
          errors.isNotEmpty ||
          !actualSourceBytesVerified ||
          !actualAllSizesVerified ||
          [
            'galleryIndexComplete',
            'actualDynamicRoots',
            'actualStablePages',
            'actualGalleryLoadMore',
            'actualVisibleThumbnailsDecoded',
            'actualScrolledThumbnailsDecoded',
            'actualScopeVisible',
            'actualRefreshSnapshotIsolation',
            'fixtureRemoved',
            'hostFixtureAcknowledged',
          ].any((key) => report[key] != true)) {
        throw StateError('Scoped actual gallery acceptance did not complete.');
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${output.path}/$safe.png').writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}
