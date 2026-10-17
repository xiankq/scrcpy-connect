import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/audio-activities';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError(
      'Audio activity evidence must stay in an explicit /tmp directory.',
    );
  }
  final output = await Directory(path).create(recursive: true);
  final screenshots = <String>{};
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^audio-activity-[a-z-]+$').hasMatch(name)) return false;
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
      screenshots.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      final report = {...?data}..remove('screenshots');
      report['savedScreenshots'] = screenshots.toList();
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(report), flush: true);
      if ([
            'audioActivitiesComplete',
            'actualPlaybackReady',
            'coreSourceAbsent',
            'localOutputAbsent',
            'connectionPreserved',
            'observationPreserved',
            'baselineMediaPreserved',
            'ownedCleanupComplete',
          ].any((key) => report[key] != true) ||
          !screenshots.containsAll({
            'audio-activity-playing',
            'audio-activity-confirm',
            'audio-activity-stopped-connection-preserved',
          })) {
        throw StateError('Actual audio activity acceptance did not complete.');
      }
    },
  );
}
