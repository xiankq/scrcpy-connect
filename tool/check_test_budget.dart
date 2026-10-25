import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'src/process.dart';
import 'src/repository_tooling.dart';

// 同时限制源码维护量与 runner 实际展开的用例数，不推断覆盖率。
Future<void> main(List<String> arguments) async {
  final root = repositoryRoot();
  if (arguments.length == 3 && arguments.first == '--runtime') {
    final scope = arguments[1];
    final budgets = jsonDecode(
      File(p.join(root.path, 'tool/test_budget.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    final budget = budgets[scope] as Map<String, dynamic>?;
    final limit = budget?['cases'] as int?;
    final completed = <int>{};
    var succeeded = false;
    await for (final line in File(
      arguments[2],
    ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      final event = jsonDecode(line) as Map<String, dynamic>;
      if (event['type'] == 'testDone' && event['hidden'] != true) {
        completed.add(event['testID'] as int);
      }
      if (event['type'] == 'done') succeeded = event['success'] == true;
    }
    if (!succeeded || completed.isEmpty) {
      throw StateError('$scope: 测试报告未完整通过或没有用例');
    }
    if (limit == null || completed.length > limit) {
      stderr.writeln(
        '$scope: cases=${completed.length}, budget=${limit ?? "missing"}；先去重，独立高风险缺口才人工调整预算。',
      );
      exitCode = 1;
    } else {
      stdout.writeln('PASS: $scope ${completed.length}/$limit 个用例（含跳过）');
    }
    return;
  }
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--report')) {
    throw ArgumentError(
      'Usage: check_test_budget.dart [--report | --runtime <scope> <json-report>]',
    );
  }
  final result = await runProcess('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  final totals = <String, Map<String, int>>{};
  const extensions = {
    '.dart',
    '.rs',
    '.kt',
    '.java',
    '.cpp',
    '.cc',
    '.c',
    '.h',
    '.mm',
    '.mjs',
    '.py',
    '.sh',
  };
  final registrations = RegExp(
    r'\b(?:test|testWidgets)\s*(?:<[^\n>]*>)?\s*\(|'
    r'#\[(?:\w+::)?test\b|^\s*def test_',
    multiLine: true,
  );
  for (final path in (result.stdout as String).split('\u0000').toSet()) {
    if (!extensions.contains(p.extension(path))) continue;
    final segments = p.posix.split(path);
    if (segments.length < 2) continue;
    final owner = switch (segments) {
      ['app', 'test', ...] => 'app/host',
      ['app', 'integration_test', ...] => 'app/device',
      ['app', 'android', ...] => 'app/native',
      ['packages' || 'rust', final package, ...] =>
        '${segments.first}/$package',
      ['tool' || 'servers', ...] => segments.first,
      _ => null,
    };
    if (owner == null) continue;
    final file = File(p.join(root.path, path));
    if (!file.existsSync()) continue;
    // Flutter drive 的通用宿主入口叫 integration_test.dart，但不是测试源码。
    if (path == 'tool/driver/integration_test.dart') continue;
    final testFile =
        segments.any(
          {
            'test',
            'tests',
            'integration_test',
            'e2e_test',
            'androidTest',
          }.contains,
        ) ||
        RegExp(r'(_tests?\.rs|_test\.dart|\.test\.mjs)$').hasMatch(path) ||
        p.basename(path).startsWith('test_');
    // Rust 在生产文件内声明测试模块；计入注册数，生产代码不计入测试行数。
    if (!testFile && !(segments.first == 'rust' && path.endsWith('.rs'))) {
      continue;
    }
    final source = file.readAsStringSync();
    final count = registrations.allMatches(source).length;
    if (!testFile && count == 0) continue;
    final total = totals.putIfAbsent(
      owner,
      () => {'lines': 0, 'registrations': 0},
    );
    if (testFile) {
      total['lines'] =
          total['lines']! + const LineSplitter().convert(source).length;
    }
    total['registrations'] = total['registrations']! + count;
  }
  if (arguments.isNotEmpty) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(totals));
    return;
  }
  final budgets = jsonDecode(
    File(p.join(root.path, 'tool/test_budget.json')).readAsStringSync(),
  ) as Map<String, dynamic>;
  var failed = false;
  for (final entry in totals.entries) {
    final budget = budgets[entry.key] as Map<String, dynamic>?;
    for (final metric in entry.value.entries) {
      final limit = budget?[metric.key] as int?;
      if (limit == null || metric.value > limit) {
        failed = true;
        stderr.writeln(
          '${entry.key}: ${metric.key}=${metric.value}, budget=${limit ?? "missing"}',
        );
      }
    }
  }
  if (failed) {
    stderr.writeln(
      '测试净增长：先复用或替换同一风险的覆盖；独立高风险缺口须说明理由后人工调整预算。见 docs/implementation/repository-tooling.md#测试取舍。',
    );
    exitCode = 1;
  } else {
    stdout.writeln('PASS: 测试源码与注册声明均在维护预算内');
  }
}
