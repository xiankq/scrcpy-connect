// 离线分析器及 Android 夹具共用的宿主支持。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../src/process.dart';

export '../src/repository_tooling.dart' show repositoryRoot;

typedef Json = Map<String, dynamic>;
typedef Query = Future<List<Json>> Function(String sql);

ArgParser options(List<String> required, {List<String> flags = const []}) {
  final parser = ArgParser()..addFlag('help', abbr: 'h', negatable: false);
  for (final name in required) {
    parser.addOption(name, mandatory: true);
  }
  for (final name in flags) {
    parser.addFlag(name, negatable: false);
  }
  return parser;
}

Future<void> cli(FutureOr<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

ArgResults parse(ArgParser parser, List<String> arguments) {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(parser.usage);
    exit(0);
  }
  return parser.parse(arguments);
}

Future<ProcessResult> checked(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 120),
  bool binary = false,
}) async {
  final result = await runProcess(
    executable,
    arguments,
    timeout: timeout,
    stdoutEncoding: binary ? null : utf8,
    stderrEncoding: null,
  );
  final errors = result.stderr as List<int>;
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      utf8.decode(errors, allowMalformed: true),
      result.exitCode,
    );
  }
  return ProcessResult(
    result.pid,
    result.exitCode,
    result.stdout,
    binary ? errors : utf8.decode(errors),
  );
}

// Perfetto 输出 RFC 风格 CSV，包括带引号名称与双写引号。
List<Json> csvRows(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '"') {
      if (quoted && i + 1 < source.length && source[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == ',' || c == '\n' || c == '\r')) {
      row.add(field.toString());
      field = StringBuffer();
      if (c != ',') {
        if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
        if (row.any((s) => s.isNotEmpty)) rows.add(row);
        row = [];
      }
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('Unterminated CSV quote');
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  if (rows.isEmpty) return [];
  return [
    for (final values in rows.skip(1))
      {
        for (var i = 0; i < rows.first.length; i++)
          rows.first[i]: i < values.length ? values[i] : '',
      },
  ];
}

Query traceQuery(String processor, String trace, {int seconds = 30}) =>
    (sql) async => csvRows(
      (await checked(processor, [
            'query',
            trace,
            sql,
          ], timeout: Duration(seconds: seconds))).stdout
          as String,
    );

num median(Iterable<num> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) throw StateError('No observations');
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

num minimum(Iterable<num> values) {
  final iterator = values.iterator;
  if (!iterator.moveNext()) throw StateError("No observations");
  num result = iterator.current;
  while (iterator.moveNext()) {
    if (iterator.current < result) result = iterator.current;
  }
  return result;
}

num maximum(Iterable<num> values) {
  final iterator = values.iterator;
  if (!iterator.moveNext()) throw StateError("No observations");
  num result = iterator.current;
  while (iterator.moveNext()) {
    if (iterator.current > result) result = iterator.current;
  }
  return result;
}

int integer(dynamic value) => value is int ? value : int.parse('$value');
Json readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Json;
List<dynamic> readJsonList(String path) =>
    jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
const pretty = JsonEncoder.withIndent('  ');
void writeJson(String path, dynamic value, {bool exclusive = false}) {
  final file = File(path);
  if (exclusive) file.createSync(exclusive: true);
  file.writeAsStringSync('${pretty.convert(value)}\n');
}

void refuseEvidence(String directory, List<String> names) {
  for (final name in names) {
    if (File(p.join(directory, name)).existsSync()) {
      throw FileSystemException('Refusing to replace existing evidence: $name');
    }
  }
}

bool sameList(List<dynamic> a, List<dynamic> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
