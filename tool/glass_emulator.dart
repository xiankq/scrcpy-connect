/// Linux/X11 workaround for Emulator 37.2.12's software GLES translator crash.
/// See docs/implementation/glass-components-2026-10-20.md for native evidence.
library;

import 'dart:io';

import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'avd',
      help: 'Existing AVD to start; never creates or wipes one.',
    )
    ..addOption('port', defaultsTo: '5554')
    ..addOption('sdk', help: 'Defaults to ANDROID_HOME or ANDROID_SDK_ROOT.')
    ..addOption('display', help: 'Accessible X11 display; defaults to DISPLAY.')
    ..addOption('xauthority', help: 'Defaults to XAUTHORITY.')
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln('dart tool/glass_emulator.dart --avd NAME [options]');
      stdout.writeln(parser.usage);
      return;
    }
    final env = Map<String, String>.of(Platform.environment);
    final sdk =
        options.option('sdk') ?? env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
    final display = options.option('display') ?? env['DISPLAY'];
    final avd = options.option('avd');
    final port = int.tryParse(options.option('port')!);
    if (!Platform.isLinux ||
        sdk == null ||
        avd == null ||
        avd.isEmpty ||
        options.rest.isNotEmpty ||
        display == null ||
        display.isEmpty ||
        port == null ||
        port < 5554 ||
        port > 5682 ||
        port.isOdd) {
      throw FormatException(
        'Requires Linux, --avd, Android SDK, an accessible X11 --display, '
        'and an even --port from 5554 to 5682. See --help.',
      );
    }
    for (final key in [
      'MESA_LOADER_DRIVER_OVERRIDE',
      'GALLIUM_DRIVER',
      'LIBGL_ALWAYS_SOFTWARE',
      'ANDROID_EGL_ON_EGL',
      'ANDROID_EGL_LIB',
      'ANDROID_GLESv1_LIB',
      'ANDROID_GLESv2_LIB',
    ]) {
      env.remove(key);
    }
    env['DISPLAY'] = display;
    final authority = options.option('xauthority');
    if (authority != null) env['XAUTHORITY'] = authority;
    stdout.writeln(
      'Starting $avd with host GL and Vulkan disabled. '
      'Host GL may itself use Mesa software rendering; inspect renderer logs.',
    );
    final process = await Process.start(
      '$sdk/emulator/emulator',
      [
        '-avd',
        avd,
        '-port',
        '$port',
        '-gpu',
        'host',
        '-feature',
        '-Vulkan',
        '-no-window',
        '-no-audio',
        '-no-snapshot-load',
        '-no-snapshot-save',
        '-cores',
        '2',
      ],
      environment: env,
      includeParentEnvironment: false,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  }
}
