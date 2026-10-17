import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory(
    Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ?? '/tmp/connect-e2e/fvp',
  );
  await output.create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      await File('${output.path}/$safe.png').writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) async {
      final metadata = {...?data}..remove('screenshots');
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(metadata));
      if (metadata['mediaAcceptanceComplete'] != true) {
        throw StateError(
          'The app did not complete media acceptance; see result.json and device test output.',
        );
      }
    },
  );
}
