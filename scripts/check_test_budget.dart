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
      File(p.join(root.path, 'test/budget.json')).readAsStringSync(),
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
      ['test', ...] => 'scripts',
      ['scripts' || 'servers', ...] => segments.first,
      _ => null,
    };
    if (owner == null) continue;
    final file = File(p.join(root.path, path));
    if (!file.existsSync()) continue;
    // Flutter drive 的通用宿主入口叫 integration_test.dart，但不是测试源码。
    if (path == 'test/driver/integration_test.dart') continue;
    // 根 test 是仓库测试的集合；套件目录及用例文件名继续决定统计范围。
    final testSegments = segments.first == 'test' ? segments.skip(1) : segments;
    final testFile =
        testSegments.any(
          {'test', 'tests', 'integration_test', 'androidTest'}.contains,
        ) ||
        RegExp(r'(_tests?\.rs|_test\.dart|\.test\.mjs)$').hasMatch(path) ||
        p.basename(path).startsWith('test_');
    // Rust 内嵌测试单独计行，不把生产实现计入测试维护量。
    if (!testFile && !(segments.first == 'rust' && path.endsWith('.rs'))) {
      continue;
    }
    final source = file.readAsStringSync();
    final count = registrations.allMatches(source).length;
    final lines = testFile
        ? const LineSplitter().convert(source).length
        : rustTestLines(source);
    if (!testFile && count == 0 && lines == 0) continue;
    final total = totals.putIfAbsent(
      owner,
      () => {'lines': 0, 'registrations': 0},
    );
    total['lines'] = total['lines']! + lines;
    total['registrations'] = total['registrations']! + count;
  }
  if (arguments.isNotEmpty) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(totals));
    return;
  }
  final budgets = jsonDecode(
    File(p.join(root.path, 'test/budget.json')).readAsStringSync(),
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

/// Count test-only Rust items, including fixtures without test registrations.
/// Delimiters are matched after removing literals and nested comments.
int rustTestLines(String source) {
  final code = _rustCode(source);
  final tokens = RegExp(r'[A-Za-z_][A-Za-z_0-9]*|[^\s]')
      .allMatches(code)
      .toList();
  final pairs = <int, int>{};
  final stack = <int>[];
  String token(int index) => tokens[index][0]!;
  for (var i = 0; i < tokens.length; i++) {
    final value = token(i);
    if ('([{'.contains(value)) {
      stack.add(i);
    } else if (')]}'.contains(value) && stack.isNotEmpty) {
      final opening = stack.removeLast();
      if ('([{'.indexOf(token(opening)) == ')]}'.indexOf(value)) {
        pairs[opening] = i;
      }
    }
  }
  final lines = <int>{};
  int line(int offset) => '\n'.allMatches(source.substring(0, offset)).length;
  for (var i = 0; i + 2 < tokens.length; i++) {
    if (token(i) != '#') continue;
    final inner = token(i + 1) == '!';
    final bracket = i + (inner ? 2 : 1);
    if (token(bracket) != '[' || !pairs.containsKey(bracket)) continue;
    final close = pairs[bracket]!;
    final attribute = [for (var j = bracket + 1; j < close; j++) token(j)];
    final testOnly =
        attribute.lastOrNull == 'test' ||
        (attribute.length > 3 &&
            attribute.first == 'cfg' &&
            _withoutTest(attribute.sublist(2, attribute.length - 1)) == false);
    if (!testOnly) continue;
    if (inner) {
      final enclosing = pairs.keys
          .where(
            (opening) =>
                token(opening) == '{' && opening < i && pairs[opening]! > close,
          )
          .fold<int?>(
            null,
            (latest, opening) =>
                latest == null || opening > latest ? opening : latest,
          );
      if (enclosing == null) return const LineSplitter().convert(source).length;
      for (
        var number = line(tokens[enclosing].start);
        number <= line(tokens[pairs[enclosing]!].end);
        number++
      ) {
        lines.add(number);
      }
      continue;
    }
    var end = close;
    for (var j = close + 1; j < tokens.length; j++) {
      final value = token(j);
      if (value == ';' || value == ',') {
        end = j;
        break;
      }
      if (value == '{') {
        end = pairs[j] ?? j;
        if (end + 1 < tokens.length && token(end + 1) == ';') end++;
        break;
      }
      // Other attributes, visibility, arguments and array types have no body.
      if (value == '(' || value == '[') j = pairs[j] ?? j;
    }
    final startLine = line(tokens[i].start);
    final endLine = line(tokens[end].end);
    for (var number = startLine; number <= endLine; number++) {
      lines.add(number);
    }
  }
  return lines.length;
}

// Evaluate cfg with test=false; unknown platform/feature predicates stay null.
// Only a definitely false result makes an item exclusive to the test build.
bool? _withoutTest(List<String> tokens) {
  if (tokens.length == 1 && tokens.single == 'test') return false;
  if (tokens.length < 3 || tokens[1] != '(' || tokens.last != ')') {
    return null;
  }
  final children = <bool?>[];
  var depth = 0, start = 2;
  for (var i = 2; i < tokens.length - 1; i++) {
    if (tokens[i] == '(') depth++;
    if (tokens[i] == ')') depth--;
    if (tokens[i] == ',' && depth == 0) {
      children.add(_withoutTest(tokens.sublist(start, i)));
      start = i + 1;
    }
  }
  if (start < tokens.length - 1) {
    children.add(_withoutTest(tokens.sublist(start, tokens.length - 1)));
  }
  return switch (tokens.first) {
    'all' =>
      children.contains(false)
          ? false
          : children.every((value) => value == true)
          ? true
          : null,
    'any' =>
      children.contains(true)
          ? true
          : children.every((value) => value == false)
          ? false
          : null,
    'not' when children.length == 1 =>
      children.single == null ? null : !children.single!,
    _ => null,
  };
}

String _rustCode(String source) {
  final units = source.codeUnits.toList();
  final raw = RegExp(r'(?:b|c)?r(#+)?"');
  final character = RegExp(
    r"'(?:\\(?:u\{[0-9a-fA-F_]+\}|x[0-9a-fA-F]{2}|.)|[^'\\\r\n])'",
    unicode: true,
  );
  var i = 0;
  void erase(int end) {
    while (i < end) {
      if (units[i] != 10 && units[i] != 13) units[i] = 32;
      i++;
    }
  }

  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      erase(end < 0 ? source.length : end);
    } else if (source.startsWith('/*', i)) {
      var end = i + 2, depth = 1;
      while (end < source.length && depth > 0) {
        if (source.startsWith('/*', end)) {
          depth++;
          end += 2;
        } else if (source.startsWith('*/', end)) {
          depth--;
          end += 2;
        } else {
          end++;
        }
      }
      erase(end);
    } else if (raw.matchAsPrefix(source, i) case final match?) {
      final delimiter = '"${match[1] ?? ''}';
      final end = source.indexOf(delimiter, match.end);
      erase(end < 0 ? source.length : end + delimiter.length);
    } else if (source[i] == '"') {
      var end = i + 1;
      while (end < source.length) {
        if (source[end] == '\\') {
          end += 2;
        } else if (source[end++] == '"') {
          break;
        }
      }
      erase(end.clamp(0, source.length));
    } else if (character.matchAsPrefix(source, i) case final match?) {
      erase(match.end);
    } else {
      i++;
    }
  }
  return String.fromCharCodes(units);
}
