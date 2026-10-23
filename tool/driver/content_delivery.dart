import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../src/process.dart';

const _receiverPackage = 'dev.scrcpyconnect.deliveryfixture';
const _receiverApk =
    '/tmp/connect-content-delivery-fixture/content-delivery-fixture.apk';

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

class _UiNode {
  _UiNode(this.attributes, this.ancestors);
  final Map<String, String> attributes;
  final List<Map<String, String>> ancestors;
  String operator [](String key) => attributes[key] ?? '';
  bool get documentsUi => this['package'].endsWith('.documentsui');
}

String _xmlDecode(String value) => value
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

List<_UiNode> _parseNodes(String xml) {
  final nodes = <_UiNode>[];
  final ancestors = <Map<String, String>>[];
  for (final match in RegExp(r'<node\b[^>]*>|</node>').allMatches(xml)) {
    final tag = match.group(0)!;
    if (tag == '</node>') {
      if (ancestors.isNotEmpty) ancestors.removeLast();
      continue;
    }
    final attributes = {
      for (final attr in RegExp(r'([\w-]+)="([^"]*)"').allMatches(tag))
        attr.group(1)!: _xmlDecode(attr.group(2)!),
    };
    nodes.add(_UiNode(attributes, List.of(ancestors)));
    if (!tag.endsWith('/>')) ancestors.add(attributes);
  }
  return nodes;
}

class _AndroidDelivery {
  _AndroidDelivery(
    this.adb,
    this.controller,
    this.target,
    this.output,
    this.kind,
  ) : runId = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  final String adb;
  final String controller;
  final String target;
  final Directory output;
  final String kind;
  final String runId;
  final receipt = <String, dynamic>{};
  bool receiverOwned = false;
  bool sourceOwned = false;
  bool exportOwned = false;
  bool cleanupConfirmed = false;
  String? expectedSha256;

  String get extension => switch (kind) {
    'image' => 'jpg',
    'video' => 'mp4',
    _ => 'txt',
  };
  String get mime => switch (kind) {
    'image' => 'image/jpeg',
    'video' => 'video/mp4',
    _ => 'text/plain',
  };
  String get filename => 'connect-delivery-$runId.$extension';
  String get sourcePath =>
      '/sdcard/${switch (kind) {
        'image' => 'Pictures',
        'video' => 'Movies',
        _ => 'Download',
      }}/$filename';
  String get exportPath => '/sdcard/Download/$filename';
  late final List<int> expected;

  Future<ProcessResult> _run(
    String serial,
    List<String> args, {
    bool binary = false,
  }) async {
    return runProcess(
      adb,
      ['-s', serial, ...args],
      timeout: const Duration(seconds: 30),
      stdoutEncoding: binary ? null : utf8,
      stderrEncoding: utf8,
    );
  }

  Future<ProcessResult> _shellResult(String serial, List<String> tokens) =>
      _run(serial, ['shell', tokens.map(_quote).join(' ')]);

  Future<String> _shell(String serial, List<String> tokens) async {
    final result = await _shellResult(serial, tokens);
    if (result.exitCode != 0) {
      throw StateError(
        'Android ${tokens.first} failed on $serial (${result.exitCode}).',
      );
    }
    return result.stdout as String;
  }

  Future<bool> _exists(String serial, String path) async {
    final result = await _shellResult(serial, ['test', '-e', path]);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw StateError('Cannot inspect the exact fixture path on $serial.');
    }
    return result.exitCode == 0;
  }

  Future<void> _wait(Future<bool> Function() check, String failure) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      if (await check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError(failure);
  }

  Future<void> installReceiver() async {
    if (!await File(_receiverApk).exists()) {
      throw StateError(
        'Build the external delivery receiver at $_receiverApk.',
      );
    }
    final installed = await _shellResult(controller, [
      'pm',
      'path',
      _receiverPackage,
    ]);
    if (installed.exitCode != 0 && installed.exitCode != 1) {
      throw StateError('Cannot inspect the independent receiver installation.');
    }
    if ((installed.stdout as String).trim().isNotEmpty) {
      throw StateError(
        'The delivery receiver is already installed; refusing to replace its data.',
      );
    }
    receiverOwned = true;
    final result = await _run(controller, ['install', '-t', _receiverApk]);
    if (result.exitCode != 0 ||
        !(result.stdout as String).contains('Success')) {
      throw StateError('Installing the independent delivery receiver failed.');
    }
  }

  Future<void> createSource() async {
    if (await _exists(target, sourcePath) ||
        await _exists(controller, exportPath)) {
      throw StateError(
        'This run’s exact source/export filename already exists.',
      );
    }
    final knownFile = File('${output.path}/$filename');
    if (kind == 'text') {
      await knownFile.writeAsBytes(
        utf8.encode('Connect delivery $runId\n字节核验\n'),
        flush: true,
      );
    } else {
      final ffmpeg = Platform.environment['CONNECT_E2E_FFMPEG'];
      if (ffmpeg == null ||
          !File(ffmpeg).isAbsolute ||
          !await File(ffmpeg).exists()) {
        throw StateError(
          'Media delivery requires an explicit host FFmpeg tool.',
        );
      }
      final result = await runProcess(
        ffmpeg,
        [
          '-v',
          'error',
          '-nostdin',
          '-n',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=320x180:rate=15',
          if (kind == 'image') ...[
            '-frames:v',
            '1',
            '-c:v',
            'mjpeg',
            '-q:v',
            '3',
          ] else ...[
            '-t',
            '6',
            '-an',
            '-c:v',
            'libx264',
            '-preset',
            'ultrafast',
            '-pix_fmt',
            'yuv420p',
            '-movflags',
            '+faststart',
          ],
          knownFile.path,
        ],
        timeout: const Duration(seconds: 30),
        stdoutEncoding: null,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        throw StateError('Host media fixture failed: ${result.stderr}');
      }
    }
    expected = await knownFile.readAsBytes();
    if (expected.isEmpty || expected.length >= 2 * 1024 * 1024) {
      throw StateError(
        'Delivery fixture exceeds the independent receiver bound.',
      );
    }
    final hash = await runProcess('sha256sum', [
      knownFile.path,
    ], timeout: const Duration(seconds: 10));
    final value = RegExp(r'^([a-f0-9]{64})\s').firstMatch('${hash.stdout}');
    if (hash.exitCode != 0 || value == null) {
      throw StateError('Independent host SHA256 calculation failed.');
    }
    expectedSha256 = value.group(1);
    // Claim only these exact fresh paths, so even a failed push or picker can
    // be cleaned without touching any other fixture, download or app cache.
    sourceOwned = true;
    exportOwned = true;
    final push = await _run(target, ['push', knownFile.path, sourcePath]);
    if (push.exitCode != 0) {
      throw StateError('Pushing the source fixture failed.');
    }
    await _verifyBytes(target);
    receipt.addAll({
      'runId': runId,
      'filename': filename,
      'contentKind': kind,
      'expectedMime': mime,
      'expectedBytes': expected.length,
      'expectedSha256': expectedSha256,
      'sourceBytesVerified': true,
    });
  }

  Future<void> _verifyBytes(String serial) async {
    final result = await _run(serial, [
      'exec-out',
      'cat',
      serial == target ? sourcePath : exportPath,
    ], binary: true);
    final actual = result.stdout as List<int>;
    final wanted = expected;
    if (result.exitCode != 0 ||
        actual.length != wanted.length ||
        List.generate(
          wanted.length,
          (index) => index,
        ).any((index) => actual[index] != wanted[index])) {
      throw StateError('Exact original fixture bytes differ on $serial.');
    }
  }

  Future<void> _capture(String name) async {
    final result = await _run(controller, [
      'exec-out',
      'screencap',
      '-p',
    ], binary: true);
    if (result.exitCode != 0 || (result.stdout as List<int>).isEmpty) {
      throw StateError('Android delivery screenshot capture failed.');
    }
    await File('${output.path}/$name.png')
        .writeAsBytes(result.stdout as List<int>, flush: true);
  }

  Future<List<_UiNode>> _ui() async {
    final path = '/data/local/tmp/connect-delivery-$runId.xml';
    try {
      await _shell(controller, ['uiautomator', 'dump', '--compressed', path]);
      final xml = await _shell(controller, ['cat', path]);
      await File('${output.path}/last-ui.xml').writeAsString(xml, flush: true);
      return _parseNodes(xml);
    } finally {
      await _shell(controller, ['rm', '-f', path]);
    }
  }

  Future<bool> _tap(
    List<_UiNode> nodes,
    bool Function(_UiNode) predicate,
  ) async {
    final matching = nodes.where(predicate).toList();
    if (matching.isEmpty) return false;
    if (matching.length != 1) {
      throw StateError('The exact Android delivery tap target is ambiguous.');
    }
    final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        .firstMatch(matching.single['bounds']);
    if (bounds == null) throw StateError('Android tap target lacks bounds.');
    final left = int.parse(bounds.group(1)!);
    final top = int.parse(bounds.group(2)!);
    final right = int.parse(bounds.group(3)!);
    final bottom = int.parse(bounds.group(4)!);
    if (right <= left || bottom <= top) {
      throw StateError('Android tap target has empty bounds.');
    }
    await _shell(controller, [
      'input',
      'tap',
      '${(left + right) ~/ 2}',
      '${(top + bottom) ~/ 2}',
    ]);
    return true;
  }

  Future<void> _waitCreateDocument() async {
    await _wait(() async {
      if (!(await _ui()).any((node) => node.documentsUi)) return false;
      final activities = await _shell(controller, [
        'dumpsys',
        'activity',
        'activities',
      ]);
      return activities.contains('android.intent.action.CREATE_DOCUMENT');
    }, 'The real Android ACTION_CREATE_DOCUMENT page did not open.');
  }

  Future<void> cancelPicker() async {
    await _capture('content-delivery-before-picker');
    await _waitCreateDocument();
    await _capture('content-delivery-cancel-picker');
    await _shell(controller, ['input', 'keyevent', 'KEYCODE_BACK']);
    await _wait(() async {
      if (!(await _ui()).any((node) => node.documentsUi)) return true;
      // The first BACK may only dismiss the filename keyboard.
      await _shell(controller, ['input', 'keyevent', 'KEYCODE_BACK']);
      return false;
    }, 'BACK did not dismiss the actual Android document picker.');
    receipt['actualPickerCancelled'] = true;
  }

  Future<void> savePicker() async {
    await _waitCreateDocument();
    var nodes = await _ui();
    final opened = await _tap(
      nodes,
      (node) =>
          node.documentsUi &&
          node['class'] == 'android.widget.ImageButton' &&
          (node['content-desc'] == 'Show roots' ||
              node['content-desc'] == 'Open navigation drawer' ||
              node.ancestors.any(
                (parent) =>
                    (parent['resource-id'] ?? '').endsWith(':id/roots_toolbar'),
              )),
    );
    if (opened) nodes = await _ui();
    final downloads = await _tap(
      nodes,
      (node) =>
          node.documentsUi &&
          node['text'] == 'Downloads' &&
          node['resource-id'].endsWith(':id/title'),
    );
    if (!downloads) {
      throw StateError('The actual DocumentsUI Downloads root is unavailable.');
    }
    await _wait(() async {
      final current = await _ui();
      return current.any(
            (node) =>
                node.documentsUi &&
                node['class'] == 'android.widget.EditText' &&
                node['text'] == filename,
          ) &&
          current.any(
            (node) => node.documentsUi && node['text'] == 'Downloads',
          );
    }, 'The Android Downloads save page has the wrong filename or location.');
    await _capture('content-delivery-save-picker');
    await _wait(
      () async => _tap(
        await _ui(),
        (node) =>
            node.documentsUi &&
            node['text'].toLowerCase() == 'save' &&
            node['enabled'] == 'true' &&
            (node['resource-id'].endsWith(':id/button1') ||
                node['resource-id'].endsWith(':id/save')),
      ),
      'The actual Android Save action was not tappable.',
    );
    await _wait(() async {
      if (!await _exists(controller, exportPath)) return false;
      try {
        await _verifyBytes(controller);
        return true;
      } on StateError {
        // CREATE_DOCUMENT can publish an empty entry before the Rust copy.
        return false;
      }
    }, 'The actual DocumentsUI save did not finish the exact Downloads bytes.');
    await _capture('content-delivery-saved');
    receipt.addAll({'actualSavePage': true, 'savedBytesVerified': true});
  }

  Future<void> sharePicker() async {
    var expanded = false;
    await _wait(() async {
      final nodes = await _ui();
      final visible = nodes.any(
        (node) =>
            (node['package'] == 'android' ||
                node['package'].contains('intentresolver')) &&
            node['text'] == 'Connect delivery verifier',
      );
      if (visible) await _capture('content-delivery-share-picker');
      if (!visible && !expanded) {
        final headlines = nodes
            .where(
              (node) =>
                  node['package'].contains('intentresolver') &&
                  node['resource-id'].endsWith(':id/headline'),
            )
            .toList();
        final panels = nodes
            .where(
              (node) =>
                  node['package'].contains('intentresolver') &&
                  node['resource-id'] == 'android:id/contentPanel',
            )
            .toList();
        if (headlines.length == 1 && panels.length == 1) {
          final pattern = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$');
          final headline = pattern.firstMatch(headlines.single['bounds']);
          final panel = pattern.firstMatch(panels.single['bounds']);
          if (headline != null && panel != null) {
            final x =
                (int.parse(headline.group(1)!) +
                    int.parse(headline.group(3)!)) ~/
                2;
            final y =
                (int.parse(headline.group(2)!) +
                    int.parse(headline.group(4)!)) ~/
                2;
            final top = int.parse(panel.group(2)!);
            final end = top + (int.parse(panel.group(4)!) - top) ~/ 8;
            await _shell(controller, [
              'input',
              'swipe',
              '$x',
              '$y',
              '$x',
              '$end',
              '450',
            ]);
            expanded = true;
          }
        }
      }
      return visible;
    }, 'The actual Android Sharesheet did not offer the independent receiver.');
    if (!await _tap(
      await _ui(),
      (node) =>
          (node['package'] == 'android' ||
              node['package'].contains('intentresolver')) &&
          node['text'] == 'Connect delivery verifier',
    )) {
      throw StateError(
        'The independent Android Sharesheet target disappeared.',
      );
    }
    Map<String, dynamic>? receiver;
    await _wait(
      () async {
        final result = await _shellResult(controller, [
          'run-as',
          _receiverPackage,
          'cat',
          'files/receipt.json',
        ]);
        if (result.exitCode != 0) return false;
        final value = jsonDecode(result.stdout as String);
        if (value is! Map<String, dynamic>) {
          throw StateError(
            'The independent Android receiver receipt is invalid.',
          );
        }
        receiver = value;
        return value['status'] != 'processing';
      },
      'The independent Android receiver did not write its real-grant receipt.',
    );
    final value = receiver!;
    if (value['success'] != true ||
        value['displayName'] != filename ||
        value['intentMime'] != mime ||
        value['resolvedMime'] != mime ||
        value['uriScheme'] != 'content' ||
        value['readGrant'] != true ||
        value['bytes'] != expected.length ||
        value['sha256'] != expectedSha256) {
      throw StateError(
        'The receiver did not prove exact bytes and a real URI grant.',
      );
    }
    await File('${output.path}/receiver-receipt.json')
        .writeAsString(jsonEncode(value), flush: true);
    receipt.addAll({'actualSharePage': true, 'receiver': value});
    await _capture('content-delivery-shared');
    await _shell(controller, ['input', 'keyevent', 'KEYCODE_BACK']);
  }

  Future<void> cleanup() async {
    final failures = <String>[];
    for (final entry in [
      (serial: controller, owned: exportOwned, path: exportPath),
      (serial: target, owned: sourceOwned, path: sourcePath),
    ]) {
      if (!entry.owned) continue;
      try {
        await _shell(entry.serial, ['rm', '-f', entry.path]);
        if (await _exists(entry.serial, entry.path)) {
          throw StateError('The exact fixture file remains.');
        }
      } catch (error) {
        failures.add('${entry.serial}: $error');
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
        'Exact delivery file cleanup failed: ${failures.join('; ')}',
      );
    }
    cleanupConfirmed = sourceOwned && exportOwned;
    receipt['exactFilesAbsent'] = cleanupConfirmed;
  }

  Future<void> uninstallReceiver() async {
    if (!receiverOwned) return;
    final installed = await _shellResult(controller, [
      'pm',
      'path',
      _receiverPackage,
    ]);
    if (installed.exitCode == 1 &&
        (installed.stdout as String).trim().isEmpty) {
      receiverOwned = false;
      receipt['ownedReceiverUninstalled'] = true;
      return;
    }
    final result = await _run(controller, ['uninstall', _receiverPackage]);
    if (result.exitCode != 0 ||
        !(result.stdout as String).contains('Success')) {
      throw StateError(
        'Uninstalling this run’s owned delivery receiver failed.',
      );
    }
    receiverOwned = false;
    receipt['ownedReceiverUninstalled'] = true;
  }

  void validate(Map<String, dynamic> report) {
    if (report.containsKey('productAcceptanceComplete') ||
        report['fixtureRunId'] != runId ||
        report['contentKind'] != kind ||
        (kind != 'text' &&
            (report['galleryThumbnailLoaded'] != true ||
                report['actualMediaPreview'] != true)) ||
        (kind == 'video' && report['videoPlaybackControls'] != true) ||
        report['exportedBytes'] != expected.length ||
        [
          'contentDeliveryComplete',
          'pickerCancellationPreservedCache',
          'actualSavePage',
          'actualSharePage',
          'fixtureCleanupAcknowledged',
          'savedProductPageCaptured',
          'systemSaveReceiptRestored',
          'shareProductPageCaptured',
          'sharedProductPageCaptured',
        ].any((key) => report[key] != true) ||
        !cleanupConfirmed ||
        [
          'sourceBytesVerified',
          'actualPickerCancelled',
          'actualSavePage',
          'savedBytesVerified',
          'actualSharePage',
          'exactFilesAbsent',
          'ownedReceiverUninstalled',
        ].any((key) => receipt[key] != true)) {
      throw StateError(
        'Scoped real Android content delivery acceptance is incomplete.',
      );
    }
  }
}

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  final kind = Platform.environment['CONNECT_E2E_CONTENT_KIND'] ?? 'text';
  if (!['text', 'image', 'video'].contains(kind)) {
    throw StateError('Choose an explicit text/image/video content fixture.');
  }
  if (adb == null ||
      adb.isEmpty ||
      controller == null ||
      target == null ||
      !controller.startsWith('emulator-') ||
      !target.startsWith('emulator-') ||
      controller == target) {
    throw StateError(
      'Select explicit distinct AVDs with CONNECT_E2E_ADB, CONNECT_E2E_DEVICE and CONNECT_E2E_TARGET.',
    );
  }
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/content-delivery';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Content delivery artifacts must remain under /tmp/.');
  }
  final fixture = _AndroidDelivery(
    adb,
    controller,
    target,
    await Directory(path).create(recursive: true),
    kind,
  );
  final errors = <String>[];
  var finished = false;
  Future<void>? coordination;
  Future<void> finishHost() async {
    finished = true;
    await coordination;
    // integrationDriver may exit after its callback, so both normal and failure
    // cleanup must run here as well as from main's finally block.
    try {
      await fixture.cleanup();
    } catch (error) {
      errors.add('Final file cleanup failed: $error');
    }
    try {
      await fixture.uninstallReceiver();
    } catch (error) {
      errors.add('Owned receiver cleanup failed: $error');
    }
  }

  try {
    await fixture.installReceiver();
    final driver = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await driver.serviceClient
                .callServiceExtension(
                  'ext.connect.contentDelivery',
                  isolateId: driver.appIsolate.id,
                  args: args,
                )
                .timeout(const Duration(seconds: 15)))
            .json ??
        {};
    coordination =
        () async {
          final acknowledged = <String>{};
          final failed = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 8));
          var lastStage = '';
          var stageSince = DateTime.now();
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
            if (stage == 'complete') return;
            if (stage is String && stage != lastStage) {
              lastStage = stage;
              stageSince = DateTime.now();
            }
            if (DateTime.now().difference(stageSince) >
                const Duration(seconds: 90)) {
              throw StateError(
                'Content delivery stage $stage exceeded its deadline.',
              );
            }
            if (stage is String &&
                !acknowledged.contains(stage) &&
                !failed.contains(stage)) {
              try {
                if (stage != 'waiting-fixture' &&
                    state['runId'] != fixture.runId) {
                  throw StateError(
                    'Content delivery extension runId does not match.',
                  );
                }
                String? action;
                switch (stage) {
                  case 'waiting-fixture':
                    await fixture.createSource();
                    action = 'fixture';
                  case 'cancel-picker':
                    await fixture.cancelPicker();
                    action = 'picker-cancelled';
                  case 'save-picker':
                    await fixture.savePicker();
                    action = 'saved';
                  case 'share-picker':
                    await fixture.sharePicker();
                    action = 'shared';
                  case 'saved-product-page':
                    await fixture._capture('content-delivery-saved-product');
                    action = 'saved-product-captured';
                  case 'restored-save-product-page':
                    await fixture._capture(
                      'content-delivery-restored-save-product',
                    );
                    action = 'restored-save-captured';
                  case 'media-preview-page':
                    await fixture._capture('content-delivery-media-preview');
                    action = 'media-preview-captured';
                  case 'share-product-page':
                    await fixture._capture('content-delivery-share-product');
                    action = 'share-product-captured';
                  case 'shared-product-page':
                    await File(
                      '${fixture.output.path}/shared-product-windows.txt',
                    ).writeAsString(
                      await fixture._shell(fixture.controller, [
                        'dumpsys',
                        'window',
                        'windows',
                      ]),
                      flush: true,
                    );
                    await fixture._capture('content-delivery-shared-product');
                    action = 'shared-product-captured';
                  case 'awaiting-cleanup':
                    await fixture.cleanup();
                    action = 'cleanup';
                }
                if (action != null) {
                  await extension({
                    'action': action,
                    'runId': fixture.runId,
                    if (action == 'fixture') ...{
                      'contentKind': kind,
                      'fixtureBytes': base64Encode(fixture.expected),
                    },
                  });
                  acknowledged.add(stage);
                  if (action == 'cleanup') return;
                }
              } catch (error) {
                errors.add('Android delivery stage $stage failed: $error');
                failed.add(stage);
                try {
                  await fixture._capture('content-delivery-failed-$stage');
                } catch (captureError) {
                  errors.add('Failure capture unavailable: $captureError');
                }
                // Fail the exact run, then keep draining stages so the app's finally
                // block can obtain its independent file-cleanup acknowledgement.
                await extension({
                  'runId': fixture.runId,
                  'error': 'Independent Android delivery evidence failed',
                });
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          if (!finished) {
            throw StateError('Content delivery host handshake timed out.');
          }
        }().catchError((Object error) {
          errors.add('Host content delivery coordination failed: $error');
        });
    await integrationDriver(
      driver: driver,
      writeResponseOnFailure: true,
      responseDataCallback: (data) async {
        await finishHost();
        final report = {...?data}..remove('screenshots');
        report.addAll({
          'androidOsReceipt': fixture.receipt,
          'fixtureCleanupConfirmed': fixture.cleanupConfirmed,
          'controllerAvd': controller,
          'targetAvd': target,
          'hostErrors': errors,
          'evidenceScope': 'real-Android-SAF-save-and-outgoing-share-URI-grant',
        });
        await File('${fixture.output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        if (errors.isNotEmpty) {
          throw StateError(
            'Independent Android delivery checks failed; see /tmp report.',
          );
        }
        fixture.validate(report);
      },
    );
  } finally {
    await finishHost();
  }
}
