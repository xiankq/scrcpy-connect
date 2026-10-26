import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'companion/build.dart' as companion;
import 'helpers/build.dart' as helpers;
import 'package.dart';
import 'tooling.dart';
import 'vendor/build.dart' as vendor;

/// The single command line entry point for controlled device artifacts.
Future<void> main(List<String> arguments) => cli(() async {
  final parser = ArgParser()
    ..addFlag(
      'check',
      negatable: false,
      help: 'Verify pinned inputs and outputs offline (default)',
    )
    ..addFlag(
      'rebuild',
      negatable: false,
      help: 'Rebuild and compare without replacing controlled outputs',
    )
    ..addFlag(
      'update',
      negatable: false,
      help: 'Rebuild selected outputs and their manifests',
    )
    ..addOption('sdk', help: 'Android SDK override for the vendor build')
    ..addOption('gradle', help: 'Pinned Gradle executable for the vendor build')
    ..addOption('source', help: 'Local pinned scrcpy source archive')
    ..addFlag(
      'offline',
      negatable: false,
      help: 'Use cached vendor Gradle dependencies',
    )
    ..addMultiOption('gradle-arg', splitCommas: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  final options = parser.parse(arguments);
  if (options['help'] as bool) {
    stdout.writeln(
      'Usage: dart servers/build.dart [options] [vendor companion helpers assets]\n${parser.usage}',
    );
    return;
  }
  require(
    [
          'check',
          'rebuild',
          'update',
        ].where((name) => options[name] as bool).length <=
        1,
    'Choose one of --check, --rebuild or --update',
  );
  const order = ['vendor', 'companion', 'helpers', 'assets'];
  final selected = options.rest.isEmpty ? order : options.rest;
  require(
    selected.every(order.contains),
    'Unknown target; choose vendor, companion, helpers or assets',
  );
  final check = !(options['rebuild'] as bool || options['update'] as bool);
  final compare = options['rebuild'] as bool;
  final root = repositoryRoot();
  // Always package last, even when targets are passed in another order.
  for (final target in order.where(selected.contains)) {
    switch (target) {
      case 'vendor':
        if (check) {
          vendor.check();
        } else {
          await vendor.build(
            sdkPath: options['sdk'] as String?,
            gradlePath: options['gradle'] as String?,
            sourcePath: options['source'] as String?,
            offline: options['offline'] as bool,
            compare: compare,
            gradleArguments: options['gradle-arg'] as List<String>,
          );
        }
      case 'companion':
        if (check) {
          await companion.verifyManifest(
            Directory(p.join(root.path, 'servers', 'companion')),
          );
          stdout.writeln(
            'PASS: companion sources, build tools and artifact hash',
          );
        } else {
          await companion.update(root, compare: compare);
        }
      case 'helpers':
        if (check) {
          helpers.check(root);
        } else {
          await helpers.update(root, compare: compare);
        }
      case 'assets':
        packageServers(root, check: check || compare);
    }
  }
});
