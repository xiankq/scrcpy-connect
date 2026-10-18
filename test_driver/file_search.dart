import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final path =
      Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
      '/tmp/connect-e2e/file-search';
  if (!path.startsWith('/tmp/') || path.split('/').contains('..')) {
    throw StateError('Search evidence must remain under /tmp/.');
  }
  final output = await Directory(path).create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      final report = {...?data}..remove('screenshots');
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(report), flush: true);
      if (report.containsKey('productAcceptanceComplete') ||
          [
            'fileSearchComplete',
            'actualNestedNames',
            'actualTypeFilter',
            'actualDetailRevalidated',
            'fixtureCreated',
            'fixtureRemoved',
          ].any((key) => report[key] != true)) {
        throw StateError(
          'Scoped actual file-search acceptance did not complete.',
        );
      }
    },
    onScreenshot: (name, bytes, [args]) async {
      final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${output.path}/$safe.png').writeAsBytes(bytes, flush: true);
      return true;
    },
  );
}
