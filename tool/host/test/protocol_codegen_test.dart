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

  test('缺口恢复核验标记只附在要求已核验状态的命令，不阻碍停止和快照', () {
    final commands = {
      for (final command
          in (original['commands'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
        command['name']: command,
    };
    for (final name in [
      'apps.launch',
      'audio.start',
      'session.start',
      'session.reconfigure',
      'notifications.open',
    ]) {
      final command = commands[name]!;
      expect(command['requiresVerifiedState'], isTrue, reason: name);
    }
    for (final name in ['session.stop', 'transfers.cancel', 'state.snapshot']) {
      final command = commands[name]!;
      expect(command['requiresVerifiedState'], isNot(isTrue), reason: name);
    }
  });

  test('快照只有一个公开结果契约，保留应用组合的传输任务与业务状态', () {
    final snapshot = (original['commands'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((command) => command['name'] == 'state.snapshot');
    final result = generator.fields(snapshot, 'result');
    expect(result, containsPair('sequence', 'integer'));
    expect(result, containsPair('settings', 'object'));
    for (final name in [
      'devices',
      'sessions',
      'sources',
      'transfers',
      'activities',
      'shares',
      'companions',
      'observations',
    ]) {
      expect(result, containsPair(name, 'array'));
    }
    expect(snapshot.containsKey('nativeResult'), isFalse);
  });

  for (final value in ['core', 'bridge', 'application', null]) {
    test('旧 owner 字段即使值为 $value 也拒绝，不能恢复双所有者路由', () {
      final schema = _clone(original);
      _first(schema)['owner'] = value;
      expect(() => _load(schema), throwsFormatException);
    });
  }
  for (final value in [
    <String, dynamic>{'sequence': 'integer'},
    <String, dynamic>{},
    null,
  ]) {
    test('拒绝旧 nativeResult 字段：$value', () {
      final schema = _clone(original);
      _first(schema)['nativeResult'] = value;
      expect(() => _load(schema), throwsFormatException);
    });
  }

  final mutations = <String, void Function(Map<String, dynamic>)>{
    '命令重名': (schema) {
      final commands = schema['commands'] as List<dynamic>;
      commands.insert(0, commands.first);
    },
    '命令未排序': (schema) {
      final commands = schema['commands'] as List<dynamic>;
      commands.add(commands.removeAt(0));
    },
    '命令名称无效': (schema) => _first(schema)['name'] = 'bad command',
    '命令名称类型错误': (schema) => _first(schema)['name'] = 42,
    '缺少命令名称': (schema) {
      _first(schema).remove('name');
    },
    '命令不是对象': (schema) => (schema['commands'] as List<dynamic>)[0] = 'invalid',
    '命令集合为空': (schema) => schema['commands'] = <dynamic>[],
    '命令集合不是数组': (schema) => schema['commands'] = <String, dynamic>{},
    '未知命令元数据': (schema) => _first(schema)['native'] = true,
    '必填字段类型未知': (schema) => _first(schema)['required'] = {'id': 'anything'},
    '可选字段类型未知': (schema) => _first(schema)['optional'] = {'id': 'anything'},
    '结果字段类型未知': (schema) => _first(schema)['result'] = {'id': 'anything'},
    '字段名称无效': (schema) => _first(schema)['required'] = {"bad'field": 'string'},
    '字段组不是对象': (schema) => _first(schema)['optional'] = <dynamic>[],
    '显式空字段组': (schema) => _first(schema)['result'] = null,
    '必填可选字段重叠': (schema) {
      _first(schema)['required'] = {'id': 'string'};
      _first(schema)['optional'] = {'id': 'integer'};
    },
    '核验标记不是布尔值': (schema) => _first(schema)['requiresVerifiedState'] = 'true',
    '核验标记为空': (schema) => _first(schema)['requiresVerifiedState'] = null,
    '版本不是整数': (schema) => schema['version'] = true,
    '版本不是正数': (schema) => schema['version'] = 0,
    '未知顶层字段': (schema) => schema['owner'] = 'application',
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
