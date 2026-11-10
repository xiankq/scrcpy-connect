import 'package:scrcpy_connect/models/application_request.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/services/app_runtime.dart';
import 'package:scrcpy_connect/services/application_host.dart';

import 'package:scrcpy_connect/bootstrap/app_bootstrap.dart';
import 'package:scrcpy_connect/bootstrap/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实 Dart 应用在资源组装或待分享目录准备失败后可以重试', () async {
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
    final sessions = <AppRuntime>[];
    Future<AppDependencies> open() async {
      final pending = AppRuntime.initialize(
        dataDirectory: root.path,
        adbBinaryDirectory: binaryDirectory,
      );
      if (sessions.isEmpty) {
        await expectLater(
          AppRuntime.initialize(dataDirectory: '${root.path}/different'),
          throwsA(
            isA<RequestFailure>().having(
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
      final launches = File('${root.path}/app-opens.json');
      await launches.writeAsString('corrupt-launches', flush: true);
      await expectLater(
        AppRuntime.initialize(
          dataDirectory: root.path,
          adbBinaryDirectory: binaryDirectory,
        ),
        throwsA(
          isA<RequestFailure>().having(
            (error) => error.code,
            'code',
            'app_open_storage_invalid',
          ),
        ),
      );
      expect(await launches.readAsString(), 'corrupt-launches');
      await launches.delete();

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
          isA<RequestFailure>().having(
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
