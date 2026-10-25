import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../../protocol_codegen.dart' as generator;
import '../../src/repository_tooling.dart';

void main() {
  late Map<String, dynamic> original;
  setUpAll(() {
    final root = repositoryRoot();
    original = generator.loadSchema(
      File(p.join(root.path, 'protocol/commands.json')),
    );
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    '命令重名': (schema) {
      final commands = schema['commands'] as List<dynamic>;
      commands.insert(0, commands.first);
    },
    '命令名称无效': (schema) => _first(schema)['name'] = 'bad command',
    '未知命令元数据': (schema) => _first(schema)['native'] = true,
    '必填字段类型未知': (schema) => _first(schema)['required'] = {'id': 'anything'},
    '字段名称无效': (schema) => _first(schema)['required'] = {"bad'field": 'string'},
    '必填可选字段重叠': (schema) {
      _first(schema)['required'] = {'id': 'string'};
      _first(schema)['optional'] = {'id': 'integer'};
    },
    '核验标记不是布尔值': (schema) => _first(schema)['requiresVerifiedState'] = 'true',
  };
  for (final entry in mutations.entries) {
    test('生成前拒绝非法契约：${entry.key}', () {
      final schema = _clone(original);
      entry.value(schema);
      expect(() => _load(schema), throwsFormatException);
    });
  }
}

Map<String, dynamic> _clone(Map<String, dynamic> schema) =>
    jsonDecode(jsonEncode(schema)) as Map<String, dynamic>;
Map<String, dynamic> _first(Map<String, dynamic> schema) =>
    (schema['commands'] as List<dynamic>).first as Map<String, dynamic>;

/// 走实际 JSON 解析入口，避免绕过校验直接给生成器构造半合法对象。
Map<String, dynamic> _load(Map<String, dynamic> schema) {
  final directory = Directory.systemTemp.createTempSync('command-contract-');
  try {
    final file = File(p.join(directory.path, 'commands.json'))
      ..writeAsStringSync(jsonEncode(schema));
    return generator.loadSchema(file);
  } finally {
    directory.deleteSync(recursive: true);
  }
}
