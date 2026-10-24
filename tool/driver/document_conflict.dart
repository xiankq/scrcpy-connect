import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../src/process.dart';

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
String _decodeXml(String value) => value
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

class _Node {
  _Node(this.attributes, this.ancestors);
  final Map<String, String> attributes;
  final List<Map<String, String>> ancestors;
  String operator [](String key) => attributes[key] ?? '';
  bool get documentsUi => const [
    'com.google.android.documentsui',
    'com.android.documentsui',
  ].contains(this['package']);
  bool get documentItem =>
      documentsUi &&
      this['resource-id'].endsWith(':id/title') &&
      ancestors.any(
        (parent) => parent['resource-id'] == '${this['package']}:id/dir_list',
      ) &&
      ancestors.any(
        (parent) => parent['resource-id'] == '${this['package']}:id/item_root',
      );
  bool get breadcrumb =>
      documentsUi &&
      this['resource-id'] == '${this['package']}:id/breadcrumb_text';
}

/// 基于官方 adb 的真实 DocumentsUI 夹具，独立读取公共文件结果，不替换应用平台通道或桥接。
///
class _Fixture {
  _Fixture(this.adb, this.controller, this.target, this.output);
  final String adb, controller, target;
  final Directory output;
  final runId = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final receipt = <String, dynamic>{};
  final originalStamps = <String, String>{};
  bool sourceOwned = false, destinationOwned = false, cleanupConfirmed = false;
  int? forward;
  String? storageLabel;
  String get rootName => 'connect-doc-conflict-$runId';
  String get root => '/sdcard/Download/$rootName';
  String get xmlPath => '/data/local/tmp/connect-doc-conflict-$runId.xml';
  List<int> get one => utf8.encode('document conflict one $runId\n汉字\n');
  List<int> get two => [0, 1, 2, 127, 128, 255];
  List<int> sentinel(String mode) => utf8.encode('original $mode $runId\n');

  Future<ProcessResult> run(
    String serial,
    List<String> args, {
    bool binary = false,
    bool check = true,
  }) async {
    final result = await runProcess(
      adb,
      ['-s', serial, ...args],
      timeout: const Duration(seconds: 25),
      stdoutEncoding: binary ? null : utf8,
      stderrEncoding: utf8,
    );
    if (check && result.exitCode != 0) {
      throw StateError(
        'Android fixture ${args.first} failed (${result.exitCode}).',
      );
    }
    return result;
  }

  Future<String> shell(String serial, List<String> args) async =>
      '${(await run(serial, ['shell', args.map(_quote).join(' ')])).stdout}';
  Future<bool> exists(String serial, String path) async {
    final result = await run(serial, [
      'shell',
      'test -e ${_quote(path)}',
    ], check: false);
    if (result.exitCode != 0 && result.exitCode != 1) {
      throw StateError('Android filesystem existence check failed.');
    }
    return result.exitCode == 0;
  }

  Future<void> push(String serial, String path, List<int> bytes) async {
    final temporary = await Directory.systemTemp.createTemp(
      'document-conflict-',
    );
    try {
      final file = File('${temporary.path}/payload');
      await file.writeAsBytes(bytes, flush: true);
      await run(serial, ['push', file.path, path]);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<void> verifyBytes(
    String serial,
    String path,
    List<int> expected,
  ) async {
    final actual =
        (await run(serial, [
              'exec-out',
              'cat ${_quote(path)}',
            ], binary: true)).stdout
            as List<int>;
    if (base64Encode(actual) != base64Encode(expected)) {
      throw StateError('Independent bytes differ at an owned fixture path.');
    }
  }

  Future<List<String>> entries(String serial, String path) async {
    final listed = await shell(serial, [
      'find',
      path,
      '-mindepth',
      '1',
      '-print',
    ]);
    return listed
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => line.substring(path.length + 1))
        .toList()
      ..sort();
  }

  Future<void> expectEntries(
    String serial,
    String path,
    List<String> expected,
  ) async {
    final actual = await entries(serial, path);
    final sorted = List<String>.of(expected)..sort();
    if (jsonEncode(actual) != jsonEncode(sorted)) {
      throw StateError(
        'The independent fixture tree contains missing or unexpected entries: $actual',
      );
    }
  }

  Future<void> waitAsync(
    Future<bool> Function() condition,
    String reason,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(reason);
  }

  Future<void> capture(String label) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(label)) {
      throw StateError('Unsafe capture name.');
    }
    final bytes =
        (await run(controller, [
              'exec-out',
              'screencap',
              '-p',
            ], binary: true)).stdout
            as List<int>;
    if (bytes.isEmpty) throw StateError('Actual Android screenshot is empty.');
    await File('${output.path}/$label.png').writeAsBytes(bytes, flush: true);
  }

  Future<List<_Node>> nodes() async {
    try {
      await shell(controller, ['uiautomator', 'dump', '--compressed', xmlPath]);
      final xml = await shell(controller, ['cat', xmlPath]);
      await File('${output.path}/last-system-ui.xml')
          .writeAsString(xml, flush: true);
      final result = <_Node>[];
      final ancestors = <Map<String, String>>[];
      for (final match in RegExp(r'<node\b[^>]*>|</node>').allMatches(xml)) {
        final tag = match[0]!;
        if (tag == '</node>') {
          if (ancestors.isNotEmpty) ancestors.removeLast();
          continue;
        }
        final attributes = {
          for (final attribute in RegExp(r'([\w-]+)="([^"]*)"').allMatches(tag))
            attribute[1]!: _decodeXml(attribute[2]!),
        };
        result.add(_Node(attributes, List.of(ancestors)));
        if (!tag.endsWith('/>')) ancestors.add(attributes);
      }
      return result;
    } finally {
      await shell(controller, ['rm', '-f', xmlPath]);
    }
  }

  Future<bool> tap(List<_Node> current, bool Function(_Node) matches) async {
    final candidates = current.where(matches).toList();
    if (candidates.isEmpty) return false;
    if (candidates.length != 1) {
      throw StateError('The real system picker target is ambiguous.');
    }
    final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        .firstMatch(candidates.single['bounds']);
    if (bounds == null) {
      throw StateError('The real system picker target has no bounds.');
    }
    final left = int.parse(bounds[1]!), top = int.parse(bounds[2]!);
    final right = int.parse(bounds[3]!), bottom = int.parse(bounds[4]!);
    if (right <= left || bottom <= top) {
      throw StateError('The real system picker target is empty.');
    }
    await shell(controller, [
      'input',
      'tap',
      '${(left + right) ~/ 2}',
      '${(top + bottom) ~/ 2}',
    ]);
    return true;
  }

  Future<Map<String, String>> prepare() async {
    // 文件系统验收不以开启调试、改变 adbd 授权或替换已有主控身份作为捷径。
    //
    if ((await shell(target, ['getprop', 'ro.adb.secure'])).trim() != '0') {
      throw StateError(
        'Use the existing isolated non-auth target AVD for this filesystem fixture.',
      );
    }
    storageLabel = (await shell(controller, [
      'getprop',
      'ro.product.model',
    ])).trim();
    if (storageLabel!.isEmpty) {
      throw StateError('The actual controller storage label is unknown.');
    }
    final port = int.tryParse(
      Platform.environment['CONNECT_E2E_TARGET_ADB_PORT'] ??
          (await shell(target, ['getprop', 'service.adb.tcp.port'])).trim(),
    );
    if (port == null || port <= 0 || port > 65535) {
      throw StateError(
        'The target must already expose a TCP adbd port; set CONNECT_E2E_TARGET_ADB_PORT if needed.',
      );
    }
    if (await exists(target, root) || await exists(controller, root)) {
      throw StateError(
        'A fixture path already exists; no pre-existing files may be replaced.',
      );
    }
    sourceOwned = true;
    await shell(target, [
      'mkdir',
      '-p',
      '$root/bundle/empty',
      '$root/bundle/nested',
    ]);
    await push(target, '$root/bundle/one.txt', one);
    await push(target, '$root/bundle/nested/two.bin', two);
    destinationOwned = true;
    await shell(controller, [
      'mkdir',
      '-p',
      '$root/output/keepBoth/bundle',
      '$root/output/skip',
      '$root/output/cancel/bundle',
      '$root/output/leave',
      '$root/output/fresh/bundle',
    ]);
    for (final mode in ['keepBoth', 'cancel', 'fresh']) {
      await push(
        controller,
        '$root/output/$mode/bundle/sentinel.txt',
        sentinel(mode),
      );
    }
    for (final mode in ['skip', 'leave']) {
      await push(controller, '$root/output/$mode/bundle', sentinel(mode));
    }
    await verifySource();
    for (final mode in ['keepBoth', 'skip', 'cancel', 'leave', 'fresh']) {
      await verifyUnchanged(mode);
    }
    forward = int.parse(
      '${(await run(target, ['forward', 'tcp:0', 'tcp:$port'])).stdout}'.trim(),
    );
    receipt['fixtureSourceVerified'] = true;
    return {'action': 'fixture', 'runId': runId, 'connectPort': '$forward'};
  }

  Future<void> verifySource() async {
    await verifyBytes(target, '$root/bundle/one.txt', one);
    await verifyBytes(target, '$root/bundle/nested/two.bin', two);
    await shell(target, ['test', '-d', '$root/bundle/empty']);
    await expectEntries(target, '$root/bundle', [
      'empty',
      'nested',
      'nested/two.bin',
      'one.txt',
    ]);
  }

  Future<void> verifyUnchanged(String mode) async {
    final parent = '$root/output/$mode';
    final directory = ['keepBoth', 'cancel', 'fresh'].contains(mode);
    await verifyBytes(
      controller,
      directory ? '$parent/bundle/sentinel.txt' : '$parent/bundle',
      sentinel(mode),
    );
    await verifyOriginalStamp(mode);
    await expectEntries(
      controller,
      parent,
      directory ? ['bundle', 'bundle/sentinel.txt'] : ['bundle'],
    );
  }

  Future<void> verifyOriginalStamp(String mode) async {
    final parent = '$root/output/$mode';
    final directory = ['keepBoth', 'cancel', 'fresh'].contains(mode);
    final stamp = await shell(controller, [
      'stat',
      '-c',
      '%d:%i:%s:%Y:%Z',
      '$parent/bundle',
      if (directory) '$parent/bundle/sentinel.txt',
    ]);
    final baseline = originalStamps[mode];
    if (baseline == null) {
      originalStamps[mode] = stamp;
    } else if (stamp != baseline) {
      throw StateError(
        'An original fixture identity or modification timestamp changed.',
      );
    }
  }

  Future<void> verifyKept(String name) async {
    if (!RegExp(r'^bundle \([a-f0-9]{32}\)$').hasMatch(name)) {
      throw StateError(
        'The actual provider keep-both name is missing or unsafe.',
      );
    }
    final parent = '$root/output/keepBoth';
    await verifyBytes(
      controller,
      '$parent/bundle/sentinel.txt',
      sentinel('keepBoth'),
    );
    await verifyOriginalStamp('keepBoth');
    await verifyBytes(controller, '$parent/$name/one.txt', one);
    await verifyBytes(controller, '$parent/$name/nested/two.bin', two);
    await shell(controller, ['test', '-d', '$parent/$name/empty']);
    await expectEntries(controller, parent, [
      'bundle',
      'bundle/sentinel.txt',
      name,
      '$name/one.txt',
      '$name/empty',
      '$name/nested',
      '$name/nested/two.bin',
    ]);
    receipt.addAll({
      'keepBothOldDirectoryPreserved': true,
      'copiedTextBytesVerified': true,
      'copiedBinaryBytesVerified': true,
      'copiedEmptyDirectoryVerified': true,
    });
  }

  Future<void> selectTree(String mode) async {
    if (!['keepBoth', 'skip', 'cancel', 'leave', 'fresh'].contains(mode)) {
      throw StateError('Unknown tree fixture.');
    }
    await waitAsync(() async {
      final current = await nodes();
      if (!current.any((node) => node.documentsUi)) return false;
      final activities = await shell(controller, [
        'dumpsys',
        'activity',
        'activities',
      ]);
      return activities.contains('android.intent.action.OPEN_DOCUMENT_TREE');
    }, 'The actual Android tree picker did not open.');
    await openDownloads(mode);
    for (final component in [rootName, 'output', mode]) {
      await waitAsync(
        () async => tap(
          await nodes(),
          (node) => node.documentItem && node['text'] == component,
        ),
        'The exact isolated folder $component is absent from DocumentsUI.',
      );
      await waitAsync(
        () async => (await nodes()).any(
          (node) => node.breadcrumb && node['text'] == component,
        ),
        'DocumentsUI did not enter the exact isolated folder $component.',
      );
    }
    await capture('$mode-system-tree');
    await waitAsync(
      () async => tap(
        await nodes(),
        (node) =>
            node.documentsUi &&
            node['text'].toLowerCase() == 'use this folder' &&
            node['enabled'] == 'true',
      ),
      'The actual Use this folder action is unavailable.',
    );
    await waitAsync(() async {
      final current = await nodes();
      if (!current.any((node) => node.documentsUi) &&
          current.any(
            (node) => node['package'] == 'dev.scrcpyconnect.scrcpy_connect',
          )) {
        return true;
      }
      await tap(
        current,
        (node) =>
            (node.documentsUi || node['package'] == 'android') &&
            node['text'].toLowerCase() == 'allow' &&
            node['enabled'] == 'true',
      );
      return false;
    }, 'The real tree grant did not return to the production app.');
    receipt['${mode}ActualTreeSelected'] = true;
  }

  Future<void> openDownloads(String mode) async {
    var drawerRequested = false;
    var drawerDownloadsSelected = false;
    var breadcrumbSwipes = 0;
    await waitAsync(
      () async {
        final current = await nodes();
        final crumbs = current.where((node) => node.breadcrumb).toList();
        // 主存储树选择器可能没有导航抽屉；先识别真实模型面包屑和根标题，再点击唯一 Download 目录，排除其他位置的同名文件。
        //
        //
        final primaryRoot =
            crumbs.length == 1 &&
            crumbs.single['text'] == storageLabel &&
            current.any(
              (node) =>
                  node.documentsUi &&
                  node['resource-id'] == '${node['package']}:id/header_title' &&
                  node['text'] == 'Files on $storageLabel',
            );
        if (crumbs.length == 2 &&
            crumbs.first['text'] == storageLabel &&
            crumbs.last['text'] == 'Download') {
          receipt['${mode}DownloadNavigation'] = 'primary-storage-Download';
          return true;
        }
        if (drawerDownloadsSelected &&
            crumbs.length == 1 &&
            crumbs.single['text'] == 'Downloads') {
          receipt['${mode}DownloadNavigation'] = 'system-drawer-Downloads';
          return true;
        }
        if (primaryRoot) {
          await tap(
            current,
            (node) => node.documentItem && node['text'] == 'Download',
          );
          return false;
        }
        // 后续树选择器可能重开上次子目录，只沿属于主存储的真实面包屑导航。
        //
        if (crumbs.any((node) => node['text'] == storageLabel) &&
            crumbs.length > 1) {
          await tap(
            current,
            (node) => node.breadcrumb && node['text'] == storageLabel,
          );
          return false;
        }
        if (!drawerRequested) {
          drawerRequested = await tap(
            current,
            (node) =>
                node.documentsUi &&
                node['class'] == 'android.widget.ImageButton' &&
                [
                  'Show roots',
                  'Open navigation drawer',
                ].contains(node['content-desc']),
          );
          if (drawerRequested) return false;
        }
        // 等待抽屉层级完成展开；标题必须属于根列表，而非目录内容行。
        //
        if (!drawerDownloadsSelected) {
          drawerDownloadsSelected = await tap(
            current,
            (node) =>
                node.documentsUi &&
                node['text'] == 'Downloads' &&
                node['resource-id'].endsWith(':id/title') &&
                node.ancestors.any(
                  (parent) =>
                      parent['resource-id'] ==
                      '${node['package']}:id/roots_list',
                ),
          );
        }
        if (!drawerRequested &&
            !drawerDownloadsSelected &&
            breadcrumbSwipes < 4) {
          final strips = current
              .where(
                (node) =>
                    node.documentsUi &&
                    node['resource-id'] ==
                        '${node['package']}:id/horizontal_breadcrumb' &&
                    node['scrollable'] == 'true',
              )
              .toList();
          if (strips.length > 1) {
            throw StateError('The system breadcrumb strip is ambiguous.');
          }
          if (strips.length == 1) {
            final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
                .firstMatch(strips.single['bounds']);
            if (bounds == null) {
              throw StateError('The system breadcrumb strip has no bounds.');
            }
            final left = int.parse(bounds[1]!), top = int.parse(bounds[2]!);
            final right = int.parse(bounds[3]!), bottom = int.parse(bounds[4]!);
            if (right - left < 200 || bottom <= top) {
              throw StateError('The system breadcrumb strip is too small.');
            }
            // 重开深层路径时，仅滚动已识别的系统条以显示首层面包屑；点击仍要求精确模型身份和随后确认的主根标题。
            //
            //
            await shell(controller, [
              'input',
              'swipe',
              '${left + 80}',
              '${(top + bottom) ~/ 2}',
              '${right - 80}',
              '${(top + bottom) ~/ 2}',
              '250',
            ]);
            breadcrumbSwipes++;
          }
        }
        return false;
      },
      'The exact DocumentsUI primary Download directory or drawer Downloads root is absent.',
    );
  }

  Future<void> cleanup() async {
    if (sourceOwned) {
      await shell(target, ['rm', '-rf', '--', root]);
      if (await exists(target, root)) {
        throw StateError('Owned target fixture did not clear.');
      }
      sourceOwned = false;
    }
    if (destinationOwned) {
      await shell(controller, ['rm', '-rf', '--', root]);
      if (await exists(controller, root)) {
        throw StateError('Owned controller fixture did not clear.');
      }
      destinationOwned = false;
    }
    final ownedForward = forward;
    if (ownedForward != null) {
      await run(target, ['forward', '--remove', 'tcp:$ownedForward']);
      forward = null;
    }
    await shell(controller, ['rm', '-f', xmlPath]);
    cleanupConfirmed = true;
    receipt['ownedFilesystemAndForwardRemoved'] = true;
  }
}

Future<void> main() async {
  final adb = Platform.environment['CONNECT_E2E_ADB'];
  final controller = Platform.environment['CONNECT_E2E_DEVICE'];
  final target = Platform.environment['CONNECT_E2E_TARGET'];
  if (adb == null ||
      controller != 'emulator-5554' ||
      target != 'emulator-5556') {
    throw StateError(
      'This opt-in fixture requires explicit CONNECT_E2E_ADB, controller emulator-5554 and target emulator-5556.',
    );
  }
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/document-conflict';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Evidence must remain under /tmp/.');
  }
  final fixture = _Fixture(
    adb,
    controller!,
    target!,
    await Directory(path).create(recursive: true),
  );
  final errors = <String>[];
  var finished = false;
  Future<void>? coordination;
  try {
    final driver = await FlutterDriver.connect();
    Future<Map<String, dynamic>> extension([Map<String, String>? args]) async =>
        (await driver.serviceClient
                .callServiceExtension(
                  'ext.connect.documentConflict',
                  isolateId: driver.appIsolate.id,
                  args: args,
                )
                .timeout(const Duration(seconds: 12)))
            .json ??
        {};
    Future<void> acknowledge(String action) =>
        extension({'action': action, 'runId': fixture.runId});
    coordination =
        () async {
          final handled = <String>{};
          final deadline = DateTime.now().add(const Duration(minutes: 10));
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
              await Future<void>.delayed(const Duration(milliseconds: 150));
              continue;
            }
            final stage = state['stage'];
            if (stage == 'complete') return;
            if (stage is String && handled.add(stage)) {
              stdout.writeln('Actual shared document-conflict stage: $stage');
              try {
                if (stage == 'waiting-fixture') {
                  await extension(await fixture.prepare());
                } else {
                  if (state['runId'] != fixture.runId) {
                    throw StateError(
                      'The app and filesystem fixture owners differ.',
                    );
                  }
                  if (stage.endsWith('-picker')) {
                    final mode = stage.substring(
                      0,
                      stage.length - '-picker'.length,
                    );
                    await fixture.selectTree(mode);
                    await acknowledge('$mode-tree-selected');
                  } else if (stage.endsWith('-panel')) {
                    final mode = stage.substring(
                      0,
                      stage.length - '-panel'.length,
                    );
                    if ((state['operationId'] as String? ?? '').isEmpty ||
                        (state['conflictId'] as String? ?? '').isEmpty) {
                      throw StateError(
                        'The product conflict owner is missing.',
                      );
                    }
                    await fixture.capture('$mode-shared-product-panel');
                    await acknowledge('$mode-panel-captured');
                  } else if (stage == 'keepBoth-saved') {
                    await fixture.verifyKept('${state['savedName']}');
                    await fixture.capture('keepBoth-saved-product');
                    await acknowledge('keepBoth-verified');
                  } else if (stage.endsWith('-finished')) {
                    final mode = stage.substring(
                      0,
                      stage.length - '-finished'.length,
                    );
                    await fixture.verifyUnchanged(mode);
                    await fixture.verifySource();
                    fixture.receipt['${mode}NoWriteVerified'] = true;
                    await fixture.capture('$mode-product-result');
                    await acknowledge('$mode-verified');
                  } else if (stage == 'cleanup') {
                    await fixture.cleanup();
                    await acknowledge('cleanup-confirmed');
                  }
                }
              } catch (error, stack) {
                errors.add(
                  'Android fixture failed at $stage (${error.runtimeType}).',
                );
                fixture.receipt.putIfAbsent('failureStage', () => stage);
                fixture.receipt.putIfAbsent('failureReason', () => '$error');
                fixture.receipt.putIfAbsent(
                  'failureLocations',
                  () => stack
                      .toString()
                      .split('\n')
                      .where((line) => line.contains('document_conflict.dart'))
                      .take(3)
                      .toList(),
                );
                await extension({'runId': fixture.runId, 'error': 'true'});
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          if (!finished) {
            throw StateError(
              'Actual document-conflict handshake exceeded its deadline.',
            );
          }
        }().catchError((Object error) {
          errors.add('Host coordination failed (${error.runtimeType}).');
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
          'androidFilesystemReceipt': fixture.receipt,
          'fixtureCleanupConfirmed': fixture.cleanupConfirmed,
          'evidenceScope':
              'actual-shared-Flutter-conflict-and-Android-tree-provider',
          'subsequentConflictPolicyScope': 'checkbox-selected-here; deterministic multi-conflict coverage is in coordinator tests',
          'retainedHistoryScope': 'production transfer and save history retained; only owned fixture files and cache removed',
        });
        await File('${fixture.output.path}/result.json')
            .writeAsString(jsonEncode(report), flush: true);
        final required = [
          'documentConflictComplete',
          'realDirectoryPull',
          'actualProductionExportRoute',
          'applyRemainingSelected',
          'keepBothOriginalPreserved',
          'skipExistingFilePreserved',
          'emptyPartialReceiptRendered',
          'cancelNoWrite',
          'leaveCancelled',
          'staleDecisionRejected',
          'freshOperationUnaffected',
          'hostFilesystemVerified',
          'fixtureCleanupAcknowledged',
          'scopedCacheRemoved',
        ];
        final hostRequired = [
          'fixtureSourceVerified',
          'keepBothActualTreeSelected',
          'skipActualTreeSelected',
          'cancelActualTreeSelected',
          'leaveActualTreeSelected',
          'freshActualTreeSelected',
          'keepBothOldDirectoryPreserved',
          'copiedTextBytesVerified',
          'copiedBinaryBytesVerified',
          'copiedEmptyDirectoryVerified',
          'skipNoWriteVerified',
          'cancelNoWriteVerified',
          'leaveNoWriteVerified',
          'freshNoWriteVerified',
          'ownedFilesystemAndForwardRemoved',
        ];
        if (errors.isNotEmpty ||
            !fixture.cleanupConfirmed ||
            required.any((key) => report[key] != true) ||
            hostRequired.any((key) => fixture.receipt[key] != true) ||
            report.containsKey('productAcceptanceComplete')) {
          throw StateError(
            'Scoped actual document-conflict acceptance did not complete.',
          );
        }
      },
    );
  } finally {
    finished = true;
    await coordination;
    if (!fixture.cleanupConfirmed) await fixture.cleanup();
  }
}
