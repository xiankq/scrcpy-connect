import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../protocol_codegen.dart' as generator;
import '../src/core_tooling.dart';

void main() {
  late Directory root;
  late Map<String, dynamic> original;
  setUpAll(() {
    root = repositoryRoot(
      File(
        p.join(Directory.current.path, 'tool/test/protocol_codegen_test.dart'),
      ).uri,
    );
    original = generator.loadSchema(
      File(p.join(root.path, 'protocol/commands.json')),
    );
  });

  test('invalid contracts are rejected before generation', () {
    for (final mutation in [
      'duplicate',
      'owner',
      'field',
      'version',
      'overlap',
      'order',
    ]) {
      final schema = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      final commands = (schema['commands'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      switch (mutation) {
        case 'duplicate':
          commands.insert(0, commands.first);
        case 'owner':
          commands.first['owner'] = 'platform';
        case 'field':
          commands.first['required'] = {'id': 'anything'};
        case 'version':
          schema['version'] = true;
        case 'overlap':
          commands.first['required'] = {'id': 'string'};
          commands.first['optional'] = {'id': 'integer'};
        case 'order':
          final first = commands.removeAt(0);
          commands.add(first);
      }
      schema['commands'] = commands;
      final temp = Directory.systemTemp.createTempSync('contract-test-');
      try {
        final path = File(p.join(temp.path, 'commands.json'))
          ..writeAsStringSync(jsonEncode(schema));
        expect(
          () => generator.loadSchema(path),
          throwsFormatException,
          reason: mutation,
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    }
  });

  test('core and bridge ownership generate distinct dispatchers', () {
    final rust = generator.rustSource(original),
        dart = generator.dartSource(original);
    expect(rust, contains('"session.start" => Self::SessionStart'));
    expect(rust, isNot(contains('"documents.importFiles" =>')));
    expect(
      dart,
      contains('documentsImportFiles("documents.importFiles", core: false)'),
    );
  });
}
