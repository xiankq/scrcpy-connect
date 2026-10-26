// root 仅限一次性 AVD 的准备阶段，应用仍使用 UsbManager。
import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../support.dart';
import 'usbip_server.dart';

String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addOption('device', mandatory: true)
    ..addOption('sdk', defaultsTo: Platform.environment['ANDROID_HOME'])
    ..addOption('ndk', defaultsTo: '30.0.16248370')
    ..addOption('target-port')
    ..addOption('port', defaultsTo: '0');
  final args = parser.parse(arguments);
  final device = args['device'] as String;
  final sdk = args['sdk'] as String?;
  if (!RegExp(r'^emulator-\d+$').hasMatch(device) || sdk == null) {
    throw ArgumentError('Select a disposable -read-only AVD and --sdk.');
  }
  final adb = p.join(sdk, 'platform-tools', 'adb');
  Future<String> command(List<String> command) async =>
      (await checked(adb, ['-s', device, ...command])).stdout as String;
  Future<String> shell(String script) => command(['shell', script]);
  if ((await shell('getprop ro.kernel.qemu')).trim() != '1' ||
      (await shell('getprop ro.build.version.sdk')).trim() != '36') {
    throw StateError('This setup is limited to an API36 AVD.');
  }
  await command(['root']);
  await command(['wait-for-device']);
  if (!(await shell('id')).contains('uid=0(') ||
      (await shell('getenforce')).trim() != 'Enforcing') {
    throw StateError('A rootable, initially enforcing AVD is required.');
  }
  // 不接管其他测试已拥有的控制器端口。
  final status = await shell('cat /sys/devices/platform/vhci_hcd.0/status');
  if (!RegExp(r'^hs\s+0000\s+004\s', multiLine: true).hasMatch(status)) {
    throw StateError(
      'vhci port 0 is unavailable; detach its owning fixture first.',
    );
  }
  final temporary = await Directory.systemTemp.createTemp('connect-usb-');
  final guest = '/data/local/tmp/${p.basename(temporary.path)}';
  UsbIpAdbServer? server;
  var mounted = false;
  var attached = false;
  StreamSubscription<ProcessSignal>? interrupt;
  StreamSubscription<ProcessSignal>? terminate;
  final done = Completer<void>();
  void stop(ProcessSignal _) {
    if (!done.isCompleted) done.complete();
  }

  interrupt = ProcessSignal.sigint.watch().listen(stop);
  terminate = ProcessSignal.sigterm.watch().listen(stop);
  try {
    final compiler = p.join(
      sdk,
      'ndk',
      args['ndk'] as String,
      'toolchains',
      'llvm',
      'prebuilt',
      'linux-x86_64',
      'bin',
      'x86_64-linux-android28-clang',
    );
    final binary = p.join(temporary.path, 'attach');
    await checked(compiler, [
      '-Wall',
      '-Wextra',
      '-Werror',
      '-O2',
      p.join(repositoryRoot().path, 'test/fixtures/usb_fixture/attach.c'),
      '-o',
      binary,
    ]);
    await shell('mkdir ${quote(guest)}');
    await command(['push', binary, '$guest/attach']);
    if (!(await shell('pm list features'))
        .contains('feature:android.hardware.usb.host')) {
      await shell(
        'mkdir ${quote('$guest/permissions')} && '
        'cp -a /vendor/etc/permissions/. ${quote('$guest/permissions/')} && '
        'echo ${quote('<permissions><feature name="android.hardware.usb.host" /></permissions>')} '
        '> ${quote('$guest/permissions/connect-usb-host.xml')} && '
        'chmod 755 ${quote('$guest/permissions')} && '
        'chmod 644 ${quote('$guest/permissions/connect-usb-host.xml')} && '
        'chcon -h -R u:object_r:vendor_configs_file:s0 ${quote('$guest/permissions')} && '
        'mount -o bind ${quote('$guest/permissions')} /vendor/etc/permissions',
      );
      mounted = true;
      await shell('stop; start');
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        try {
          if ((await shell('pm list features'))
              .contains('feature:android.hardware.usb.host')) {
            break;
          }
        } on ProcessException {
          // framework 重启期间 package service 不可用。
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    final serviceDeadline = DateTime.now().add(const Duration(seconds: 60));
    var hostReady = false;
    while (DateTime.now().isBefore(serviceDeadline)) {
      if ((await shell('dumpsys usb')).contains('host_manager=')) {
        hostReady = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!hostReady) {
      throw StateError('Android USB Host service did not start.');
    }
    // framework 重启也会重建模拟器默认 Wi-Fi 网络。
    final networkDeadline = DateTime.now().add(const Duration(seconds: 60));
    var networkReady = false;
    while (DateTime.now().isBefore(networkDeadline)) {
      try {
        await shell('ip route get 10.0.2.2');
        networkReady = true;
        break;
      } on ProcessException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (!networkReady) {
      throw StateError('The AVD host network did not recover.');
    }
    final targetArgument = args['target-port'] as String?;
    final targetPort = targetArgument == null
        ? null
        : int.parse(targetArgument);
    if (targetPort != null && (targetPort < 1 || targetPort > 65535)) {
      throw ArgumentError('target-port must be between 1 and 65535.');
    }
    server = await UsbIpAdbServer.start(
      port: int.parse(args['port'] as String),
      targetHost: targetPort == null ? null : '127.0.0.1',
      targetPort: targetPort,
      log: stdout.writeln,
    );
    await shell(
      '${quote('$guest/attach')} 10.0.2.2 ${server.port} ${server.busId} 0',
    );
    attached = true;
    if ((await shell('getenforce')).trim() != 'Enforcing') {
      throw StateError('USB must run with SELinux enforcing.');
    }
    stdout.writeln(
      'USB fixture ready: $device; mode=${server.simulated ? 'simulated' : 'real-adbd'}; SELinux=Enforcing. Ctrl-C to detach and clean up.',
    );
    await done.future;
  } finally {
    Object? cleanupFailure;
    Future<void> clean(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        cleanupFailure ??= error;
      }
    }

    await clean(() async {
      if (attached) {
        await shell('echo 0 > /sys/devices/platform/vhci_hcd.0/detach');
      }
    });
    await clean(() async {
      await server?.close();
    });
    await clean(() async {
      if ((await shell('getenforce')).trim() != 'Enforcing') {
        await shell('setenforce 1');
      }
    });
    await clean(() async {
      if (mounted) {
        await shell('umount /vendor/etc/permissions');
        mounted = false;
        await shell('stop; start');
      }
    });
    await clean(() async {
      if (!mounted) {
        await shell('rm -rf ${quote(guest)}');
      }
    });
    await clean(() async {
      await temporary.delete(recursive: true);
    });
    await interrupt.cancel();
    await terminate.cancel();
    if (cleanupFailure != null) {
      throw StateError('USB fixture cleanup failed: $cleanupFailure');
    }
  }
});
