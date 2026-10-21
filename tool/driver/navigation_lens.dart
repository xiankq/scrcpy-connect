import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = await Directory(
    Platform.environment['NAVIGATION_LENS_OUTPUT'] ??
        '/tmp/connect-navigation-lens',
  ).create(recursive: true);
  final captures = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z-]+$').hasMatch(name)) throw StateError(name);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes, flush: true);
      captures.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final report = {...?data}..remove('screenshots');
      await File('${directory.path}/result.json')
          .writeAsString(jsonEncode(report));
      if (report['navigationLensComplete'] != true || captures.length != 8) {
        throw StateError('Navigation lens acceptance did not complete.');
      }
    },
    writeResponseOnFailure: true,
  );
}
