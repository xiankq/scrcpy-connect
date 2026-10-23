import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) => writeResponseData(
    data,
    testOutputFilename: 'result',
    destinationDirectory: p.join(
      Directory.systemTemp.path,
      'connect-e2e',
      'media-texture-replay',
    ),
  ),
);
