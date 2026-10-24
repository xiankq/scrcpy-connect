import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

/// 普通 main/bootstrap 回归的宿主 driver，使用独立回执目录，避免覆盖媒体回放或产品证据。
///
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
