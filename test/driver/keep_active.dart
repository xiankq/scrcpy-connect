import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

import '../../scripts/src/process.dart';
import 'support/cleanup.dart';

/// 为 keep_active_test.dart 提供独立 Android 进程与电源证据，不注入产品 ready 回执、会话或设置。
///
Future<void> main() async {
  final env = Platform.environment;
  final adb = env['CONNECT_E2E_ADB'];
  final controller = env['CONNECT_E2E_DEVICE'];
  final target = env['CONNECT_E2E_TARGET'];
  if (adb == null ||
      controller == null ||
      target == null ||
      controller == target) {
    throw StateError(
      'Explicit adb and distinct controller/target serials are required.',
    );
  }
  final path =
      env['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/scrcpy-connect-visual-reaudit/keep-active';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Evidence must stay under /tmp.');
  }
  final directory = await Directory(path).create(recursive: true);
  Future<String> shell(String command) async {
    final result = await runProcess(adb, [
      '-s',
      target,
      'shell',
      command,
    ], timeout: const Duration(seconds: 20));
    if (result.exitCode != 0) throw StateError('$command: ${result.stderr}');
    return result.stdout as String;
  }

  Future<void> until(Future<bool> Function() predicate, String reason) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (await predicate()) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(reason);
  }

  int activity(String power) {
    final match = RegExp(
      r'^\s*lastUserActivityTime=(\d+)',
      multiLine: true,
    ).firstMatch(power);
    if (match == null) {
      throw StateError('Missing real PowerManager userActivity timestamp.');
    }
    return int.parse(match[1]!);
  }

  bool awake(String power) => power.contains('mWakefulness=Awake');
  Future<Map<String, String>> snapshot() async => {
    'processes': await shell('ps -A -w -o PID,PPID,CMDLINE'),
    'power': await shell('dumpsys power'),
    'timeouts': await shell(
      'settings get system screen_off_timeout; settings get global stay_on_while_plugged_in',
    ),
    'tasks': await shell('dumpsys activity activities'),
    'display': await shell('dumpsys display'),
    'wm': await shell('wm size'),
    'keepActiveJars': await shell(
      'find /data/local/tmp -maxdepth 1 -name "interop-keep-active-*.jar"',
    ),
  };
  List<RegExpMatch> helpers(String processes) => RegExp(
    r'^\s*(\d+)\s+(\d+)\s+(interop\.scrcpy:[0-9a-f]+:/data/local/tmp/interop-keep-active-[a-zA-Z0-9-]+\.jar)(?:\s|$)',
    multiLine: true,
  ).allMatches(processes).toList();
  final checks = <Map<String, dynamic>>[];
  Map<String, String>? baseline;
  String? sharedIdentity;
  final ownedSettingsTasks = <int>{};
  var sleepingFixture = false;
  Future<void> capture(String name) async {
    final result = await runProcess(
      adb,
      ['-s', controller, 'exec-out', 'screencap', '-p'],
      stdoutEncoding: null,
      timeout: const Duration(seconds: 20),
    );
    final bytes = result.stdout as List<int>;
    if (result.exitCode != 0 ||
        bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
      throw StateError('Actual controller screenshot failed.');
    }
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
  }

  Future<void> inspect(Map<String, dynamic> checkpoint) async {
    final name = checkpoint['name'] as String;
    final stem = checkpoint['id'].toString().replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    if (name == 'baseline') {
      baseline = await snapshot();
      await File('${directory.path}/build.txt').writeAsString(
        await shell(
          'getprop ro.build.version.sdk; getprop ro.product.cpu.abi; getprop ro.build.fingerprint',
        ),
      );
      if (helpers(baseline!['processes']!).isNotEmpty) {
        throw StateError('Refuse to disturb an existing keep-active owner.');
      }
      if (baseline!['tasks']!.contains('com.android.settings')) {
        throw StateError(
          'Use an isolated target without a pre-existing Settings task.',
        );
      }
      if (!awake(baseline!['power']!)) {
        await shell('input keyevent 224');
        await until(
          () async => awake(await shell('dumpsys power')),
          'Target did not wake for fixture setup.',
        );
      }
    }
    if (baseline == null) throw StateError('Missing independent baseline.');
    for (final task
        in checkpoint['ownedApplicationTasks'] as List? ?? const []) {
      if (task is int) ownedSettingsTasks.add(task);
    }
    for (final session
        in (checkpoint['sessions'] as List).cast<Map<String, dynamic>>()) {
      if (session['packageName'] == 'com.android.settings' &&
          session['taskId'] is int) {
        ownedSettingsTasks.add(session['taskId'] as int);
      }
    }
    if (name == 'cleanup') {
      // 产品关闭保留应用任务；仅移除经独立核实由夹具新建的根任务，保留系统服务。
      //
      for (final task in ownedSettingsTasks) {
        final tasks = await shell('dumpsys activity activities');
        final header = RegExp(
          '^\\s*\\* Task\\{[^\\n]*#$task\\s[^\\n]*',
          multiLine: true,
        ).firstMatch(tasks)?.group(0);
        if (header == null) continue;
        if (!header.contains('com.android.settings.root') ||
            header.contains('rootTaskId=')) {
          throw StateError(
            'Refuse to remove a changed fixture root task $task.',
          );
        }
        await File('${directory.path}/$stem-task-$task-before.txt')
            .writeAsString(tasks);
        await shell('cmd activity stack remove $task');
        await until(
          () async =>
              !RegExp('#$task(?:\\s|\\})')
                  .hasMatch(await shell('dumpsys activity activities')),
          'Owned Settings task $task did not finish.',
        );
      }
    }
    if (name == 'sleep-target') {
      await shell('input keyevent 223');
      await until(
        () async => !awake(await shell('dumpsys power')),
        'Target did not sleep.',
      );
      sleepingFixture = true;
    }
    if (name == 'wake-target' || name == 'cleanup') {
      await shell('input keyevent 224');
      await until(
        () async => awake(await shell('dumpsys power')),
        'Target did not wake after fixture.',
      );
      sleepingFixture = false;
    }
    final expected = checkpoint['expectedLeases'] as int?;
    if (expected != null) {
      await until(
        () async =>
            helpers(await shell('ps -A -w -o PID,PPID,CMDLINE')).length ==
            expected,
        '$name: actual target keep-active process count did not become $expected.',
      );
    }
    final current = await snapshot();
    for (final entry in current.entries) {
      await File('${directory.path}/$stem-${entry.key}.txt')
          .writeAsString(entry.value);
    }
    if (current['timeouts'] != baseline!['timeouts']) {
      throw StateError('Product modified permanent timeout/stay-on settings.');
    }
    if (current['wm'] != baseline!['wm']) {
      throw StateError('Keep-active changed physical display geometry.');
    }
    final processes = helpers(current['processes']!);
    String? identity, command;
    if (processes.length == 1) {
      final process = processes.single;
      final pid = process[1]!, parent = process[2]!;
      final stat = await shell('cat /proc/$pid/stat');
      final fields = stat
          .substring(stat.lastIndexOf(')') + 2)
          .trim()
          .split(RegExp(r'\s+'));
      identity = '$pid:${fields[19]}:${process[3]}';
      // 即使 ART 已将 argv[0] 替换为唯一进程身份，精确目标监督器仍保留启动命令。
      //
      command = await shell(
        "tr '\\000' '\\n' < /proc/$pid/cmdline; tr '\\000' '\\n' < /proc/$parent/cmdline",
      );
      await File('${directory.path}/$stem-owned-command.txt')
          .writeAsString(command);
      for (final parameter in [
        'video=false',
        'audio=false',
        'control=true',
        'keep_active=true',
        'power_on=false',
        'power_off_on_close=false',
        'stay_awake=false',
        'clipboard_autosync=false',
      ]) {
        if (!command.contains(parameter)) {
          throw StateError(
            'Independent owned target command lacks $parameter.',
          );
        }
      }
      if (RegExp(
        r'(?:video=true|audio=true|power_on=true|power_off_on_close=true|screen_off=)',
      ).hasMatch(command)) {
        throw StateError(
          'Owned helper enables a forbidden media or power side effect.',
        );
      }
      if ([
            'two-windows-one-lease',
            'application-closed-phone-paused',
          ].contains(name) &&
          identity != sharedIdentity) {
        throw StateError('Opening/closing B replaced the shared target lease.');
      }
      if (name == 'enabled-existing-paused') sharedIdentity = identity;
      final sessions = (checkpoint['sessions'] as List)
          .cast<Map<String, dynamic>>();
      if (sessions.any(
        (session) => session['keepActivePid'] != int.parse(pid),
      )) {
        throw StateError(
          'Session ownership differs from independently observed target PID.',
        );
      }
    }
    int? beforeActivity, afterActivity;
    if (checkpoint['advance'] == true || name == 'enabled-asleep-no-wake') {
      beforeActivity = activity(current['power']!);
      await Future<void>.delayed(const Duration(milliseconds: 4700));
      final later = await shell('dumpsys power');
      await File('${directory.path}/$stem-power-later.txt')
          .writeAsString(later);
      afterActivity = activity(later);
      if (checkpoint['advance'] == true && afterActivity <= beforeActivity) {
        throw StateError(
          'Real PowerManager userActivity did not advance with paused A still open.',
        );
      }
      if (sleepingFixture && awake(later)) {
        throw StateError('Enabling keep-active woke the sleeping target.');
      }
    }
    if (sleepingFixture && awake(current['power']!)) {
      throw StateError('Sleeping target unexpectedly woke.');
    }
    // 独立任务列表须包含产品实际返回的应用任务，保持唤醒不能自行创建替代任务。
    //
    for (final session
        in (checkpoint['sessions'] as List).cast<Map<String, dynamic>>()) {
      final task = session['taskId'];
      if (task is int &&
          !RegExp('#$task(?:\\s|\\})').hasMatch(current['tasks']!)) {
        throw StateError(
          'Production task $task is absent from actual target ActivityManager.',
        );
      }
    }
    if (name == 'cleanup' || name == 'last-window-closed') {
      if (current['keepActiveJars'] != baseline!['keepActiveJars']) {
        throw StateError('An owned keep-active JAR remains after last close.');
      }
    }
    if ([
      'paused-off',
      'two-windows-one-lease',
      'reenabled-existing-paused',
      'last-window-closed',
    ].contains(name)) {
      await capture(name);
    }
    final record = <String, dynamic>{
      ...checkpoint,
      'target': target,
      'controller': controller,
      'observedLeases': processes.length,
      'ownedProcessIdentity': identity,
      'awake': awake(current['power']!),
      'userActivityBefore': beforeActivity,
      'userActivityAfter': afterActivity,
      'timeoutsUnchanged': true,
      'physicalGeometryUnchanged': true,
      'source': 'independent target ps, /proc, dumpsys power/activity/display, settings',
      if (name == 'cleanup')
        'removedOwnedSettingsTasks': ownedSettingsTasks.toList(),
    };
    checks.add(record);
    await File('${directory.path}/$stem.json')
        .writeAsString(jsonEncode(record));
  }

  final driver = await FlutterDriver.connect();
  var finished = false;
  Object? inspectionError;
  final inspection =
      () async {
        String? previous;
        final deadline = DateTime.now().add(const Duration(minutes: 10));
        while (!finished && DateTime.now().isBefore(deadline)) {
          try {
            final response = await driverRpc(
              driver.serviceClient.callServiceExtension(
                'ext.connect.keepActive',
                isolateId: driver.appIsolate.id,
              ),
            );
            if (finished) return;
            final checkpoint = response.json?['checkpoint'];
            if (checkpoint is Map && checkpoint['id'] != previous) {
              final data = Map<String, dynamic>.from(checkpoint);
              previous = data['id'] as String;
              String? error;
              try {
                await inspect(data);
              } catch (failure) {
                error = failure.toString();
                inspectionError ??= failure;
              }
              if (finished) return;
              await driverRpc(
                driver.serviceClient.callServiceExtension(
                  'ext.connect.keepActive',
                  isolateId: driver.appIsolate.id,
                  args: {'ack': previous, 'error': ?error},
                ),
              );
            }
          } catch (error) {
            if (finished) return;
            if (!error.toString().contains('ext.connect.keepActive') &&
                !error.toString().contains('Method not found')) {
              rethrow;
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!finished) {
          throw StateError('Timed out inspecting actual keep-active state.');
        }
      }().catchError((Object error) {
        inspectionError ??= error;
      });
  await withDriverCleanup(
    () async {
      await integrationDriver(
        driver: driver,
        writeResponseOnFailure: true,
        responseDataCallback: (data) async {
          finished = true;
          await inspection;
          // SDK 回调返回后直接退出进程，因此正常和失败回执都先恢复本次休眠。
          if (sleepingFixture) {
            await shell('input keyevent 224');
            sleepingFixture = false;
          }
          final result = {...?data}..remove('screenshots');
          result['independentTargetChecks'] = checks;
          result['inspectionError'] = inspectionError?.toString();
          await File('${directory.path}/result.json')
              .writeAsString(jsonEncode(result));
          if (inspectionError != null ||
              result['keepActiveComplete'] != true ||
              (result['cleanupErrors'] as List?)?.isEmpty != true) {
            throw StateError(
              'Actual dynamic keep-active acceptance incomplete: $inspectionError',
            );
          }
        },
      );
    },
    () => {
      'keep-active inspection': () async {
        finished = true;
        await inspection;
      },
      'driver connection': () => driverRpc(driver.close()),
      'target power state': () async {
        if (sleepingFixture) {
          await shell('input keyevent 224');
          sleepingFixture = false;
        }
      },
    },
  );
}
