import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

/// Host driver for the ordinary main/bootstrap regression, with a distinct
/// receipt directory so it cannot replace media replay or product evidence.
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final result = data?['applicationBootstrap'];
    if (result is! Map<String, dynamic> ||
        result['mainEntry'] != true ||
        result['startupError'] != false ||
        result['cacheStatusReadable'] != true) {
      throw StateError('Normal application bootstrap did not complete.');
    }
    await writeResponseData(
      data,
      testOutputFilename: 'result',
      destinationDirectory:
          Platform.environment['CONNECT_E2E_CAPTURE_DIR'] ??
          p.join(Directory.systemTemp.path, 'application-bootstrap'),
    );
  },
);
