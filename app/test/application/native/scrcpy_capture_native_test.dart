import 'dart:convert';
import 'dart:io';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/utils/ordered_disposal.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/services/connection/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/stores/media/app_launch_store.dart';
import 'package:scrcpy_connect/services/media/scrcpy_capture_adapter.dart';
import 'package:scrcpy_connect/stores/media/session_coordinator.dart';
import 'package:scrcpy_connect/services/platform/bundled_servers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final target = Platform.environment['INTEROP_SCRCPY_AVD'];
  test(
    '公开SDK连接上的应用窗口与独立捕获精确隔离，替换捕获不复用旧代次',
    () async {
      final directory = await Directory.systemTemp.createTemp('typed-scrcpy-');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      var repository = Directory.current.absolute;
      while (!File(p.join(repository.path, 'Cargo.toml')).existsSync()) {
        if (repository.parent.path == repository.path) {
          throw StateError('找不到仓库根目录');
        }
        repository = repository.parent;
      }
      final identity =
          Platform.environment['INTEROP_ADB_KEY'] ??
          p.join(Platform.environment['HOME']!, '.android', 'adbkey');
      final privateKey = await File(identity)
          .copy(p.join(directory.path, 'identity.pem'));
      final servers = await BundledServers().prepare(directory);
      final host = await createNativeScrcpyHost(
        serverBytes: servers.scrcpyBytes,
        identityPath: privateKey.path,
        dataDirectory: directory,
        binaryDirectory: Directory(
          p.join(
            repository.path,
            '.dart_tool',
            'adb',
            Platform.operatingSystem,
          ),
        ),
      );
      ScrcpyServerQueries? queries;
      SessionCoordinator? sessions;
      ScrcpySession? attached;
      ScrcpySession? independent;
      AdbDevice? device;
      try {
        device = await host.adb.connect(target!);
        final connection = DeviceConnection(client: host.adb, device: device);
        queries = ScrcpyServerQueries(
          serverBytes: servers.scrcpyBytes,
          timeout: const Duration(seconds: 15),
        );
        final launches = await AppLaunchStore.open(directory: directory);
        sessions = SessionCoordinator(
          scrcpy: host.scrcpy,
          requireConnection: (_) => connection,
          launches: launches,
          serverQueries: queries,
          emit: (_, _, _) {},
        );
        final api = host.scrcpy.api;
        const quality = {
          'videoCodec': 'h264',
          'maxSize': 720,
          'maxFps': 30,
          'videoBitRate': 2000000,
          'videoEncoder': null,
          'qualityPreset': 'smooth',
        };
        final started = await sessions.command('session.start', {
          'deviceId': 'test-device',
          ...quality,
        });
        final sessionId = started['sessionId'] as String;
        final oldRef = started['captureRef'] as String;
        attached = await host.scrcpy.attach(oldRef, generation: 3);
        final source = attached.info!.source!;
        expect(source.sourceId, started['videoSourceId']);
        expect(source.generation, 3);
        expect(source.attachAddress, greaterThan(0));
        expect(source.detachAddress, greaterThan(0));
        final endpoint = await ScrcpyCaptureAdapter(api).openSource(started, 4);
        expect(endpoint['generation'], 4);
        expect(endpoint['sourceId'], source.sourceId);
        expect(
          (await attached.sendControl(
            const ScrcpyKey(action: ScrcpyKeyAction.down, keycode: 59),
          )).completion,
          ScrcpyControlCompletion.written,
        );
        await attached.sendControl(
          const ScrcpyKey(action: ScrcpyKeyAction.up, keycode: 59),
        );
        expect(
          (await attached.sendControl(const ScrcpyClipboard('类型化捕获回归')))
              .completion,
          ScrcpyControlCompletion.clipboardAcknowledged,
        );
        await attached.close();
        attached = null;
        expect(
          (await api.inspect(oldRef)).id,
          oldRef,
          reason: '释放附着观察不停止应用窗口所有者的捕获。',
        );

        final replacement = await sessions.command('session.reconfigure', {
          'deviceId': 'test-device',
          'sessionId': sessionId,
          ...quality,
          'maxSize': 1280,
        });
        final newRef = replacement['captureRef'] as String;
        expect(newRef, isNot(oldRef));
        expect(replacement['sessionId'], sessionId);
        expect(
          replacement['captureGeneration'],
          greaterThan(started['captureGeneration'] as int),
        );
        await expectLater(
          api.inspect(oldRef),
          throwsA(
            isA<ScrcpyException>().having(
              (error) => error.code,
              'code',
              'stale_capture',
            ),
          ),
        );
        await expectLater(
          api.sendControl(
            oldRef,
            const ScrcpyKey(action: ScrcpyKeyAction.down, keycode: 59),
          ),
          throwsA(
            isA<ScrcpyException>().having(
              (error) => error.code,
              'code',
              'stale_capture',
            ),
          ),
        );
        final replacementInfo = await api.inspect(newRef, generation: 5);
        expect(replacementInfo.source!.sourceId, replacement['videoSourceId']);
        expect(replacementInfo.source!.generation, 5);
        await expectLater(
          sessions.command('session.clipboard', {
            'sessionId': sessionId,
            'captureGeneration': replacement['captureGeneration'],
            'text': '等待新画面确认',
          }),
          throwsA(
            isA<RequestFailure>().having(
              (error) => error.code,
              'code',
              'stale_capture',
            ),
          ),
          reason: '协议夹具没有真实呈现新画面，不伪造renderer ready绕过应用门禁。',
        );

        final facts = await host.adb.services.connectionFacts(device);
        expect(facts.connectionId, isNotEmpty);
        independent = await host.scrcpy.createSession(
          device,
          options: const ScrcpyOptions(
            maxSize: 720,
            maxFps: 30,
            videoBitRate: 2000000,
            powerOn: false,
            clipboardAutosync: false,
          ),
        );
        final independentInfo = await independent.start();
        expect(independentInfo.id, isNot(newRef));
        expect(
          independentInfo.source!.sourceId,
          isNot(replacement['videoSourceId']),
        );
        expect(independentInfo.source!.attachAddress, greaterThan(0));
        expect(
          (await independent.sendControl(const ScrcpyClipboard('独立 SDK 捕获回归')))
              .completion,
          ScrcpyControlCompletion.clipboardAcknowledged,
        );
        final independentId = independent.id;
        await independent.close();
        independent = null;
        await expectLater(
          api.inspect(independentId),
          throwsA(isA<ScrcpyException>()),
        );
        expect(
          (await api.inspect(newRef)).source!.sourceId,
          replacement['videoSourceId'],
        );
        final after = await host.adb.services.connectionFacts(device);
        expect(after.closed, isFalse);
        expect(after.connectionId, facts.connectionId);
        final output = <int>[];
        await for (final event in host.adb.shell(
          device,
          'printf typed-sdk-owner-alive',
          timeout: const Duration(seconds: 5),
        )) {
          if (event.channel == AdbShellChannel.stdout) {
            output.addAll(event.bytes);
          }
          if (event.channel == AdbShellChannel.exit) expect(event.exitCode, 0);
        }
        expect(
          utf8.decode(output),
          'typed-sdk-owner-alive',
          reason: '独立捕获关闭后，同一个真实连接仍可执行服务。',
        );
        await sessions.command('session.stop', {'sessionId': sessionId});
        await expectLater(api.inspect(newRef), throwsA(isA<ScrcpyException>()));
        expect(
          (await host.adb.services.connectionFacts(device)).closed,
          isFalse,
        );
      } finally {
        await OrderedDisposal([
          () async => independent?.close(),
          () async => attached?.close(),
          () async => sessions?.close(),
          () async => queries?.close(),
          () async {
            if (device != null) await host.adb.disconnect(device);
          },
          host.close,
        ]).run();
      }
    },
    skip: target == null ? '需要隔离且已授权的 INTEROP_SCRCPY_AVD 目标。' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
