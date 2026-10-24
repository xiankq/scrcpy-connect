import 'package:scrcpy_connect/application/transport/application_request.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/application/application_session.dart';
import 'package:scrcpy_connect/application/lifecycle/application_host.dart';

import 'package:scrcpy_connect/application/app_bootstrap.dart';
import 'package:scrcpy_connect/application/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实 Dart 应用在待分享目录准备失败后可以重试', () async {
    final root = await Directory.systemTemp.createTemp('connect-bootstrap-');
    final cache = await Directory.systemTemp.createTemp(
      'connect-bootstrap-cache-',
    );
    var repository = Directory.current;
    while (!File('${repository.path}/Cargo.toml').existsSync()) {
      final parent = repository.parent;
      if (parent.path == repository.path) {
        throw StateError('Repository not found');
      }
      repository = parent;
    }
    final binaryDirectory = Directory(
      '${repository.path}/.dart_tool/adb/${Platform.isMacOS ? 'macos' : Platform.operatingSystem}',
    );
    AppDependencies? owner;
    final sessions = <ApplicationSession>[];
    Future<AppDependencies> open() async {
      final pending = ApplicationSession.initialize(
        dataDirectory: root.path,
        adbBinaryDirectory: binaryDirectory,
      );
      if (sessions.isEmpty) {
        await expectLater(
          ApplicationSession.initialize(
            dataDirectory: '${root.path}/different',
          ),
          throwsA(
            isA<ApplicationCommandException>().having(
              (error) => error.code,
              'code',
              'runtime_directory_mismatch',
            ),
          ),
        );
      }
      final session = await pending;
      sessions.add(session);
      return AppDependencies(
        request: session.request,
        events: session.events,
        close: session.dispose,
        initialize: false,
      );
    }

    try {
      final failure = FileSystemException('temporary storage unavailable');
      await expectLater(
        bootstrapApplication(
          createDependencies: open,
          prepareOutgoingDirectory: () async => throw failure,
        ),
        throwsA(same(failure)),
      );
      await expectLater(
        sessions.single.request('settings.get'),
        throwsA(
          isA<ApplicationCommandException>().having(
            (error) => error.code,
            'code',
            'disposed',
          ),
        ),
      );

      final outgoing = await Directory('${cache.path}/outgoing').create();
      owner = await bootstrapApplication(
        createDependencies: open,
        prepareOutgoingDirectory: () async => outgoing,
      );
      expect(sessions, hasLength(2));
      expect(await owner.request('settings.get'), isA<Json>());
      final status = await owner.request('media.cache.status');
      expect(status, isNotEmpty);
    } finally {
      await owner?.close?.call();
      // 所有应用所有者释放都幂等，包括启动失败的实例。
      for (final session in sessions) {
        await session.dispose();
      }
      if (sessions.isNotEmpty) {
        await sessions.last.shutdown();
      } else {
        await ApplicationHost.closeRetiredHosts();
      }
      await root.delete(recursive: true);
      await cache.delete(recursive: true);
    }
  });
}
