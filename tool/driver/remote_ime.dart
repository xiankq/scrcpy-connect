import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  if (adb == null ||
      target == null ||
      controller == null ||
      target == controller) {
    throw StateError(
      'Set CONNECT_E2E_ADB, CONNECT_E2E_DEVICE and a distinct CONNECT_E2E_TARGET.',
    );
  }
  final directory = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
        '/tmp/connect-e2e/remote-ime',
  );
  if (!directory.absolute.path.startsWith('/tmp/')) {
    throw StateError('Keep remote IME evidence under /tmp.');
  }
  await directory.create(recursive: true);
  final runId = DateTime.now().microsecondsSinceEpoch;
  final remoteDump = '/data/local/tmp/connect-remote-ime-$runId.xml';
  final checks = <Map<String, Object?>>[];
  final captures = <Map<String, Object?>>[];
  Future<void> capture(String device, String label) async {
    final started = DateTime.now().toUtc();
    final captured = await Process.run(adb, [
      '-s',
      device,
      'exec-out',
      'screencap',
      '-p',
    ], stdoutEncoding: null).timeout(const Duration(seconds: 15));
    final bytes = captured.stdout as List<int>;
    if (captured.exitCode != 0 ||
        bytes.length < 8 ||
        bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
      throw StateError('Could not capture the actual $label display.');
    }
    await File('${directory.path}/$label.png').writeAsBytes(bytes);
    captures.add({
      'label': label,
      'startedAt': started.toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> shell(List<String> command) async {
    final result = await Process.run(adb, [
      '-s',
      target,
      'shell',
      ...command,
    ]).timeout(const Duration(seconds: 15));
    if (result.exitCode != 0) {
      throw StateError(
        'Independent Android inspection failed for ${command.first}: ${result.stderr}',
      );
    }
    return result.stdout as String;
  }

  String attribute(String node, String key) {
    final value = RegExp('$key="([^"]*)"').firstMatch(node)?.group(1);
    if (value == null) throw StateError('EditText lacks $key.');
    return value
        .replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (match) {
          final number = match[1]!;
          return String.fromCharCode(
            number.startsWith('x')
                ? int.parse(number.substring(1), radix: 16)
                : int.parse(number),
          );
        })
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  Future<String> editText(String stage) async {
    try {
      String? xml;
      for (var attempt = 1; attempt <= 3; attempt++) {
        final dump = await shell(['uiautomator', 'dump', remoteDump]);
        final read = await Process.run(adb, [
          '-s',
          target,
          'shell',
          'cat',
          remoteDump,
        ]).timeout(const Duration(seconds: 15));
        await File('${directory.path}/$stage-dump-$attempt.txt').writeAsString(
          'uiautomator:\n$dump\nread exit=${read.exitCode}\n${read.stderr}',
        );
        if (read.exitCode == 0 && '${read.stdout}'.contains('<hierarchy')) {
          xml = read.stdout as String;
          break;
        }
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      if (xml == null) {
        throw StateError(
          'Android uiautomator did not produce an actual hierarchy at $stage after three attempts; see captured dump receipts.',
        );
      }
      await File('${directory.path}/$stage.xml').writeAsString(xml);
      final fields = RegExp(r'<node\b[^>]*>')
          .allMatches(xml)
          .map((match) => match.group(0)!)
          .where(
            (node) => attribute(node, 'class') == 'android.widget.EditText',
          )
          .toList();
      if (fields.length != 1) {
        throw StateError(
          'Settings search must expose exactly one real EditText; found ${fields.length}. APP_SEARCH_SETTINGS/search indexing must be prepared on this target.',
        );
      }
      // Newer AOSP may expose Settings search from its system search package.
      final package = attribute(fields.single, 'package');
      if (package != 'com.android.settings' &&
          package != 'com.google.android.settings.intelligence' &&
          package != 'com.android.settings.intelligence') {
        throw StateError('Unexpected search EditText package: $package');
      }
      return fields.single;
    } finally {
      await shell(['rm', '-f', remoteDump]);
    }
  }

  Future<Map<String, Object?>> inspect(String stage) async {
    if (stage == 'prepare-settings') {
      final output = await shell([
        'am',
        'start',
        '-W',
        '-a',
        'android.settings.APP_SEARCH_SETTINGS',
      ]);
      if (output.contains('Error') || output.contains('Exception')) {
        throw StateError(
          'Target cannot launch system Settings search with APP_SEARCH_SETTINGS. Prepare the actual system search activity before rerunning.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    // Retry to allow the actual Unicode clipboard-paste and search UI to settle.
    final expected = stage.startsWith('committed-') ? '你好🙂' : '';
    String query(String node) {
      final raw = attribute(node, 'text');
      final hint = RegExp(r'hint="([^"]*)"').firstMatch(node)?.group(1);
      // This API36 Settings EditText exposes its placeholder as both text and
      // hint when empty. Committed checkpoints still require the exact raw text.
      return expected.isEmpty && hint != null && raw == hint ? '' : raw;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var node = await editText(stage);
    while (query(node) != expected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      node = await editText(stage);
    }
    final actual = query(node);
    if (actual != expected) {
      throw StateError(
        'Actual Android EditText at $stage is ${jsonEncode(actual)}, expected ${jsonEncode(expected)}. Settings search must begin with an empty real query; no app data is reset by this fixture.',
      );
    }
    if (stage != 'prepare-settings' && attribute(node, 'focused') != 'true') {
      throw StateError(
        'The real scrcpy touch did not leave Settings EditText focused at $stage.',
      );
    }
    if (stage == 'committed-once') {
      // Establish target pixels first. Accessibility text alone does not prove
      // that Android has painted, nor that the remote decoder has caught up.
      await capture(target, 'target-committed');
      await Future<void>.delayed(const Duration(milliseconds: 750));
      await capture(controller, 'controller-committed');
    } else if (stage == 'committed-still-once') {
      await capture(target, 'target-settled');
      await capture(controller, 'controller-settled');
    }
    final evidence = <String, Object?>{
      'stage': stage,
      'text': actual,
      'rawAccessibilityText': attribute(node, 'text'),
      'focused': attribute(node, 'focused'),
      'package': attribute(node, 'package'),
      'source': 'independent host adb uiautomator dump',
    };
    checks.add(evidence);
    if (stage != 'prepare-settings') return evidence;
    final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        .firstMatch(attribute(node, 'bounds'));
    final sizeOutput = await shell(['wm', 'size']);
    final sizes = RegExp(r'(\d+)x(\d+)').allMatches(sizeOutput).toList();
    if (bounds == null || sizes.isEmpty) {
      throw StateError('Missing actual target bounds or display dimensions.');
    }
    final size = sizes.last;
    return {
      ...evidence,
      'x': (int.parse(bounds.group(1)!) + int.parse(bounds.group(3)!)) / 2,
      'y': (int.parse(bounds.group(2)!) + int.parse(bounds.group(4)!)) / 2,
      'width': int.parse(size.group(1)!),
      'height': int.parse(size.group(2)!),
    };
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
              'ext.connect.remoteIme',
              isolateId: driver.appIsolate.id,
            );
            final checkpoint = response.json?['checkpoint'];
            if (checkpoint is Map && checkpoint['name'] != previous) {
              previous = checkpoint['name'] as String;
              String? error;
              Map<String, Object?>? result;
              try {
                result = await inspect(previous);
              } catch (failure) {
                error = failure.toString();
                inspectionError = failure;
              }
              await driver.serviceClient.callServiceExtension(
                'ext.connect.remoteIme',
                isolateId: driver.appIsolate.id,
                args: {
                  'ack': previous,
                  'error': ?error,
                  if (result != null) 'result': jsonEncode(result),
                },
              );
            }
          } catch (error) {
            if (!error.toString().contains('ext.connect.remoteIme') &&
                !error.toString().contains('Method not found')) {
              rethrow;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!finished) {
          throw StateError(
            'Timed out independently inspecting Android IME input.',
          );
        }
      }().catchError((Object error) {
        inspectionError = error;
      });
  await integrationDriver(
    driver: driver,
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      finished = true;
      await inspection;
      final metadata = {...?data}..remove('screenshots');
      metadata['independentEditTextChecks'] = checks;
      metadata['displayCaptures'] = captures;
      metadata['inspectionError'] = inspectionError?.toString();
      await File('${directory.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      if (inspectionError != null ||
          metadata['remoteImeComplete'] != true ||
          metadata['targetQueryRestored'] != true ||
          checks.map((check) => check['stage']).join(',') !=
              'prepare-settings,focused-empty,composing-no-leak,committed-once,committed-still-once,cleanup-empty') {
        throw StateError(
          'Real Android IME acceptance did not complete: ${inspectionError ?? 'missing checkpoints'}',
        );
      }
    },
  );
}
