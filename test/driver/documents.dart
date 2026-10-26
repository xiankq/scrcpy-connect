import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import '../../scripts/src/process.dart';

/// 使用真实系统选择器，操作者选择此处打印的路径；driver 通过官方 adb 独立读取最终公共文件。
///
Future<void> driveDocuments(
  FlutterDriver driver,
  Directory captures, {
  bool Function()? shouldStop,
}) async {
  final serial =
      Platform.environment['CONNECT_E2E_DEVICE'] ??
      Platform.environment['ANDROID_SERIAL'];
  if (serial == null || serial.isEmpty) {
    throw StateError(
      'CONNECT_E2E_DEVICE must identify the actual controller Android.',
    );
  }
  final sdk =
      Platform.environment['ANDROID_SDK_ROOT'] ??
      Platform.environment['ANDROID_HOME'];
  final adb =
      Platform.environment['CONNECT_E2E_ADB'] ??
      (sdk == null ? 'adb' : '$sdk/platform-tools/adb');
  Future<ProcessResult> run(List<String> args, {bool binary = false}) async {
    final result = await runProcess(
      adb,
      ['-s', serial, ...args],
      stdoutEncoding: binary ? null : systemEncoding,
      timeout: const Duration(seconds: 20),
    );
    if (result.exitCode != 0) {
      throw StateError('Official adb ${args.first} failed: ${result.stderr}');
    }
    return result;
  }

  Future<void> acknowledge(String action) => driver.serviceClient
      .callServiceExtension(
        'ext.connect.documents',
        isolateId: driver.appIsolate.id,
        args: {'action': action},
      )
      .timeout(const Duration(seconds: 5));
  Future<void> capture(String name) async {
    final result = await run(['exec-out', 'screencap', '-p'], binary: true);
    await File('${captures.path}/$name.png')
        .writeAsBytes(result.stdout as List<int>, flush: true);
  }

  final ownedRoots = <String>{};
  try {
    var lastStage = '';
    final deadline = DateTime.now().add(const Duration(minutes: 14));
    while (DateTime.now().isBefore(deadline)) {
      if (shouldStop?.call() == true) return;
      Map<String, dynamic> state;
      try {
        state =
            (await driver.serviceClient
                    .callServiceExtension(
                      'ext.connect.documents',
                      isolateId: driver.appIsolate.id,
                    )
                    .timeout(const Duration(seconds: 5)))
                .json ??
            {};
      } catch (error) {
        if (shouldStop?.call() == true) return;
        if (!error.toString().contains('ext.connect.documents') &&
            !error.toString().contains('Method not found')) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final stage = state['stage'];
      final runId = '${state['runId']}';
      if (!RegExp(r'^interop-documents-[0-9]+$').hasMatch(runId)) {
        throw StateError('Invalid integration-test directory identity.');
      }
      final root = '/sdcard/Download/$runId';
      if (stage != lastStage) {
        lastStage = '$stage';
        switch (stage) {
          case 'prepare':
            await run(['shell', 'test', '!', '-e', root]);
            // 先登记本次唯一且原先不存在的目录，创建回执丢失也能精确收尾。
            ownedRoots.add(root);
            await run([
              'shell',
              'mkdir',
              '-p',
              '$root/source/sub',
              '$root/source/empty',
            ]);
            final temporary = await Directory.systemTemp.createTemp(
              'interop-documents-host-',
            );
            try {
              final source = File('${temporary.path}/one.txt');
              await source.writeAsString(
                'native SAF directory $runId\n',
                flush: true,
              );
              await run(['push', source.path, '$root/source/sub/one.txt']);
            } finally {
              await temporary.delete(recursive: true);
            }
            await acknowledge('prepared');
          case 'export-file':
            stdout.writeln(
              'SAF ACTION REQUIRED [$serial]: In the actual system Save dialog choose Downloads/$runId, keep the default export filename, and tap Save.',
            );
            await Future<void>.delayed(const Duration(seconds: 1));
            await capture('saf-export-file-system');
          case 'file-saved':
            final name = '${state['exportedFileName']}';
            if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)) {
              throw StateError('Unexpected provider filename.');
            }
            final content = await run(['exec-out', 'cat', '$root/$name']);
            if (content.stdout != 'native SAF export $runId\n') {
              throw StateError('Actual exported system-file bytes differ.');
            }
            await acknowledge('fileVerified');
          case 'import-directory':
            stdout.writeln(
              'SAF ACTION REQUIRED [$serial]: In the actual tree picker choose Downloads/$runId/source, tap Use this folder, and confirm Allow.',
            );
            await Future<void>.delayed(const Duration(seconds: 1));
            await capture('saf-import-directory-system');
          case 'export-directory':
            stdout.writeln(
              'SAF ACTION REQUIRED [$serial]: In the actual destination tree picker choose Downloads/$runId (the parent of source), tap Use this folder, and confirm Allow.',
            );
            await Future<void>.delayed(const Duration(seconds: 1));
            await capture('saf-export-directory-system');
          case 'directory-saved':
            final name = '${state['exportedDirectoryName']}';
            if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)) {
              throw StateError('Unexpected provider directory name.');
            }
            final content = await run([
              'exec-out',
              'cat',
              '$root/$name/sub/one.txt',
            ]);
            if (content.stdout != 'native SAF directory $runId\n') {
              throw StateError('Actual exported directory bytes differ.');
            }
            await run(['shell', 'test', '-d', '$root/$name/empty']);
            await acknowledge('directoryVerified');
            stdout.writeln(
              'Actual SAF file export and directory import/export verified at $root.',
            );
            return;
          case 'complete':
            stdout.writeln(
              'Actual SAF file export and directory import/export verified at $root.',
            );
            return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Actual DocumentsUI integration exceeded its bounded deadline.',
    );
  } finally {
    for (final owned in ownedRoots) {
      await run(['shell', 'rm', '-rf', '--', owned]);
      await run(['shell', 'test', '!', '-e', owned]);
    }
  }
}
