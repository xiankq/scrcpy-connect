import 'dart:io';

import '../scripts/src/architecture.dart';

void main() {
  final root = Directory.systemTemp.createTempSync('architecture-events-');
  try {
    File('${root.path}/pubspec.yaml').writeAsStringSync('workspace: [app]\n');
    final lib = Directory('${root.path}/app/lib/core/messages');
    lib.createSync(recursive: true);
    File('${root.path}/app/pubspec.yaml')
        .writeAsStringSync('name: scrcpy_connect\n');
    final payload = File('${lib.path}/payload.dart');
    final bridge = File('${lib.path}/bridge.dart');
    final consumer = File('${lib.path}/consumer.dart');
    const definitions =
        'typedef NativePayload = Map<String, Object?>;\n'
        'typedef Payload = NativePayload;\n'
        'typedef Box<T> = Stream<T>;\n';

    for (final type in [
      'Stream<wire.Payload>',
      'StreamController<wire.Payload>',
      'StreamSubscription<wire.Payload>',
      'wire.Events',
      'wire.Box<wire.Payload>',
      'Stream<List<wire.Payload>>',
      'Stream<Fact>',
    ]) {
      final streamAlias = type == 'wire.Events';
      payload.writeAsStringSync(
        '$definitions${streamAlias ? 'typedef Events = Stream<Payload>;\n' : ''}',
      );
      bridge.writeAsStringSync(
        "export 'payload.dart' show Payload, Box${streamAlias ? ', Events' : ''};\n",
      );
      consumer.writeAsStringSync(
        "import 'dart:async';\nimport 'bridge.dart' as wire;\n"
        'class Fact { const Fact(this.id); final String id; }\n'
        'abstract class Consumer { $type get events; }\n',
      );
      final problems = checkArchitecture(root);
      final rejected = problems.any(
        (problem) =>
            problem.startsWith('app/lib/core/messages/consumer.dart: 应用事件流'),
      );
      if (rejected != (type != 'Stream<Fact>')) {
        throw StateError('$type: $problems');
      }
      if (type == 'Stream<Fact>' && problems.isNotEmpty) {
        throw StateError('Typed facts must pass the complete check: $problems');
      }
    }

    payload.writeAsStringSync(definitions);
    bridge.writeAsStringSync("export 'payload.dart' show Payload, Box;\n");
    for (final declaration in [
      'class Payload {}',
      'typedef Payload = String;',
    ]) {
      consumer.writeAsStringSync(
        "import 'bridge.dart';\n$declaration\n"
        'abstract class Consumer { Stream<Payload> get events; }\n',
      );
      final problems = checkArchitecture(root);
      if (problems.isNotEmpty) {
        throw StateError('Local type must shadow imported aliases: $problems');
      }
    }
    stdout.writeln('PASS: 事件容器、跨文件别名、导出与前缀、泛型及局部类型遮蔽');
  } finally {
    root.deleteSync(recursive: true);
  }
}
