import 'dart:convert';
import 'dart:io';

import 'glass_metrics.dart';

/// 运行：dart run tool/benchmark/glass_analyze.dart /tmp/connect-glass-widgets/result.json
/// 证据缺失或 profile 帧预算未达标时以非零状态退出。
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/benchmark/glass_analyze.dart /tmp/.../result.json',
    );
    exitCode = 64;
    return;
  }
  final report = jsonDecode(
    File(arguments.single).readAsStringSync(),
  ) as Map<String, dynamic>;
  final summary = summarizeGlassPerformance(report);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
  final completeScope = report['scope'] == 'glass-performance'
      ? report['performanceCaptureComplete'] == true &&
            report['nativeSurfaceDuringTiming'] == true
      : report['dynamicCaptureComplete'] == true;
  if (report['hostValidationComplete'] != true ||
      !completeScope ||
      summary['performanceAcceptanceComplete'] != true) {
    exitCode = 1;
  }
}
