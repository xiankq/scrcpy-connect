import 'dart:convert';
import 'dart:io';

import 'support/capture.dart';

import 'package:integration_test/integration_test_driver_extended.dart';

/// 目标测试负责断言；宿主仅保存截图和报告，不重复业务验收规则。
Future<void> main() async {
  final path = Platform.environment['CONNECT_E2E_CAPTURE_DIR'];
  final output = path == null
      ? await Directory.systemTemp.createTemp('connect-e2e-')
      : await Directory(path).create(recursive: true);
  stdout.writeln('Captures: ${output.path}');
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) => saveScreenshot(output, name, bytes),
    responseDataCallback: (data) async {
      final report = {...?data}..remove('screenshots');
      await File('${output.path}/result.json')
          .writeAsString(jsonEncode(report), flush: true);
      if (report.isEmpty) {
        throw StateError('The target test produced no report.');
      }
    },
  );
}
