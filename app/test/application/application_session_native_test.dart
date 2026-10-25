import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:scrcpy_connect/stores/application_session.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('真实公开 SDK 组装只由 Dart 保存业务、发布水位并恢复，读取不连接设备', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart-application-',
    );
    var root = Directory.current;
    while (!File(p.join(root.path, 'Cargo.toml')).existsSync()) {
      if (root.parent.path == root.path) throw StateError('找不到工作区。');
      root = root.parent;
    }
    final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
    final binaryDirectory = binary == null
        ? Directory(
            p.join(root.path, '.dart_tool', 'adb', Platform.operatingSystem),
          )
        : File(binary).parent;
    const policy = ConnectionPolicy(
      healthEnabled: false,
      reconnectEnabled: false,
    );
    ApplicationSession? session;
    final received = <Map<String, dynamic>>[];
    try {
      session = await ApplicationSession.initialize(
        dataDirectory: directory.path,
        connectionPolicy: policy,
        adbBinaryDirectory: binaryDirectory,
      );
      final subscription = session.events.listen(received.add);
      addTearDown(subscription.cancel);
      final initial = await session.request('state.snapshot');
      expect(initial['devices'], isEmpty);
      expect(initial['sessions'], isEmpty);
      PackageInfo.setMockInitialValues(
        appName: '安装包测试名称',
        packageName: 'test.installed.application',
        version: '8.6.4',
        buildNumber: '712',
        buildSignature: '',
      );
      final info = await session.request('system.info');
      expect(info['version'], '8.6.4');
      expect(info['buildNumber'], '712');
      expect(info['packageName'], 'test.installed.application');
      expect(info['appName'], '安装包测试名称');
      final added = await session.request('devices.add', {
        'address': '127.0.0.1',
        'port': 9,
        'name': '离线测试设备',
      });
      final id = added['deviceId'] as String;
      await session.request('settings.update', {'appearance': 'dark'});
      final metadata =
          (await session.request('settings.export'))['metadata'] as Map;
      final exported = (metadata['devices'] as List).single as Map;
      expect(exported, isNot(contains('id')));
      expect(exported, isNot(contains('privateKeyPem')));
      await expectLater(
        session.request('settings.import', {
          'metadata': <String, dynamic>{
            ...Map<String, dynamic>.from(metadata),
            'devices': [
              <String, dynamic>{
                ...Map<String, dynamic>.from(exported),
                'port': -1,
              },
            ],
          },
        }),
        throwsA(
          isA<ApplicationCommandException>().having(
            (error) => error.code,
            'code',
            startsWith('invalid_'),
          ),
        ),
      );
      expect(
        (await session.request('state.snapshot'))['devices'],
        hasLength(1),
      );
      await session.request('settings.import', {'metadata': metadata});
      final snapshot = await session.request('state.reconcile');
      expect((snapshot['devices'] as List), hasLength(2));
      final imported = (snapshot['devices'] as List)
          .cast<Map<Object?, Object?>>()
          .singleWhere((device) => device['id'] != id);
      expect(imported['status'], 'unauthorized');
      expect(imported['autoReconnect'], isFalse);
      expect((snapshot['sessions'] as List), isEmpty);
      expect((snapshot['sources'] as List), isEmpty);
      expect((snapshot['settings'] as Map)['appearance'], 'dark');
      final activities = await session.request('activities.list');
      expect(
        (activities['activities'] as List).cast<Map<Object?, Object?>>().where(
          (activity) => (activity['id'] as String).startsWith('connection:'),
        ),
        isEmpty,
      );
      await Future<void>.delayed(Duration.zero);
      final changed = received
          .where((event) => event['sequence'] is int)
          .toList();
      expect(changed, isNotEmpty);
      final sequences = changed
          .map((event) => event['sequence'] as int)
          .toList();
      expect(sequences, orderedEquals([...sequences]..sort()));
      expect(sequences.last, lessThanOrEqualTo(snapshot['sequence'] as int));
      expect(
        received.where((event) => event['type'] == 'state.resynced'),
        isNotEmpty,
      );
      await subscription.cancel();
      await session.dispose();
      session = await ApplicationSession.initialize(
        dataDirectory: directory.path,
        connectionPolicy: policy,
        adbBinaryDirectory: binaryDirectory,
      );
      final reopened = await session.request('state.snapshot');
      expect((reopened['devices'] as List), hasLength(2));
      expect((reopened['settings'] as Map)['appearance'], 'dark');
      expect((reopened['sessions'] as List), isEmpty);
    } finally {
      await session?.shutdown();
      await directory.delete(recursive: true);
    }
  }, skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows));
}
