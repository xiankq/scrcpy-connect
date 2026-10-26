import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scrcpy_connect/stores/application_session.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/models/connection_policy.dart';
import 'package:scrcpy_connect/stores/media/app_launch_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实 Session 核验等待与失败后均拦截新副作用，读取和精确清理仍可分派', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'application-recovery-barrier-',
    );
    final directory = Directory(await temporary.resolveSymbolicLinks());
    ApplicationSession? session;
    _BlockedSnapshotFile? blockedFile;
    Future<AppLaunchStore>? replacement;
    Future<void>? reconcileFailure;
    StreamSubscription<Map<String, dynamic>>? subscription;
    final received = <Map<String, dynamic>>[];
    try {
      session = await ApplicationSession.initialize(
        dataDirectory: directory.path,
        adbBinaryDirectory: _officialBinaryDirectory(),
        connectionPolicy: const ConnectionPolicy(
          healthEnabled: false,
          reconnectEnabled: false,
        ),
      );
      subscription = session.events.listen(received.add);
      final added = await session.request('devices.add', {
        'address': '127.0.0.1',
        'port': 9,
        'name': '恢复屏障测试设备',
      });
      final device = added['deviceId'] as String;

      // 结构校验先于媒体探测、文件执行和重连意图；不能以类型转换或平台错误代替。
      for (final (command, params) in <(String, Map<String, dynamic>)>[
        ('session.start', {'deviceId': device, 'packageName': 7}),
        ('files.mkdir', {'deviceId': 7, 'path': '/sdcard/invalid'}),
        ('settings.import', {'metadata': <Object?>[]}),
      ]) {
        await expectLater(
          session.request(command, params),
          throwsA(_commandFailure('invalid_argument')),
        );
      }
      await expectLater(
        session.request('devices.disconect', {'deviceId': device}),
        throwsA(_commandFailure('unknown_command')),
      );
      expect((await session.request('transfers.list'))['transfers'], isEmpty);

      // 已核验时同一文件命令确实进入连接执行边界，而非未知命令或静态分类。
      await expectLater(
        session.request('files.mkdir', {
          'deviceId': device,
          'path': '/sdcard/recovery-barrier',
        }),
        throwsA(_commandFailure('disconnected')),
      );

      // 真实账本串行队列固定快照读取；后继接管后，旧 Session 的读取明确失败。
      // 只替换磁盘读取能力，不替换 Session、StateRecovery 或命令分派器。
      final file = File(p.join(directory.path, 'app-opens.json'));
      await file.writeAsString('{"version":1,"records":{}}', flush: true);
      blockedFile = _BlockedSnapshotFile(file);
      replacement = IOOverrides.runWithIOOverrides(
        () => AppLaunchStore.open(directory: directory),
        _SnapshotReadOverrides(blockedFile),
      );
      await blockedFile.entered.future;
      final resync = session.events.firstWhere(
        (event) => event['type'] == 'state.resync',
      );
      final reconcile = session.request('state.reconcile');
      reconcileFailure = expectLater(
        reconcile,
        throwsA(_commandFailure('app_open_owner_replaced')),
      );
      await resync;
      var settled = false;
      unawaited(reconcileFailure.then((_) => settled = true));

      await _expectNewActionsBlocked(session, device);
      await _expectReadsAndCleanupAvailable(session, device);
      expect(settled, isFalse, reason: '快照读取门闩未放行时必须仍在核验。');
      expect(
        received.where((event) => event['type'] == 'state.resynced'),
        isEmpty,
      );

      final failed = session.events.firstWhere(
        (event) => event['type'] == 'state.resync.failed',
      );
      blockedFile.release.complete();
      await replacement;
      await reconcileFailure;
      await failed;

      // 核验 Future 已失败也不能解除屏障；新传输没有落到账本，旧读取仍可见。
      await _expectNewActionsBlocked(session, device);
      await _expectReadsAndCleanupAvailable(session, device);
      expect((await session.request('transfers.list'))['transfers'], isEmpty);
      expect(
        received.where((event) => event['type'] == 'state.resynced'),
        isEmpty,
      );
    } finally {
      if (blockedFile != null && !blockedFile.release.isCompleted) {
        blockedFile.release.complete();
      }
      try {
        await replacement;
        await reconcileFailure;
      } finally {
        try {
          await subscription?.cancel();
          await session?.shutdown();
        } finally {
          await directory.delete(recursive: true);
        }
      }
    }
  }, skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows));
}

Future<void> _expectNewActionsBlocked(
  ApplicationSession session,
  String device,
) async {
  final common = <String, dynamic>{'deviceId': device};
  final actions = <(String, Map<String, dynamic>)>[
    ('calls.open', {...common, 'callId': 'old-call'}),
    (
      'files.delete',
      {
        ...common,
        'paths': ['/sdcard/old-file'],
        'expectedStamps': <String, Object?>{},
      },
    ),
    ('files.mkdir', {...common, 'path': '/sdcard/new-directory'}),
    (
      'files.rename',
      {
        ...common,
        'path': '/sdcard/old-file',
        'name': 'new-file',
        'expectedStamp': <String, Object?>{},
      },
    ),
    (
      'files.push',
      {...common, 'path': '/private/source', 'destination': '/sdcard/target'},
    ),
    (
      'files.pull',
      {...common, 'path': '/sdcard/source', 'destination': '/private/target'},
    ),
    ('transfers.resolve', {'transferId': 'old-transfer', 'policy': 'replace'}),
    ('transfers.resume', {'transferId': 'old-transfer', 'restart': true}),
    (
      'session.scroll',
      {
        ...common,
        'sessionId': 'old-session',
        'captureGeneration': 1,
        'x': 0,
        'y': 0,
        'screenWidth': 100,
        'screenHeight': 100,
        'hscroll': 0,
        'vscroll': 1,
      },
    ),
    ('session.refresh', {...common, 'sessionId': 'old-session'}),
    ('session.quality', {...common, 'qualityPreset': 'standard'}),
    (
      'devices.configure',
      {...common, 'address': '127.0.0.1', 'port': 9, 'transport': 'tcp'},
    ),
    ('devices.connect', common),
    ('devices.pair', {...common, 'address': '127.0.0.1', 'port': 9}),
    ('devices.pair.qr', common),
    ('devices.usb', common),
    ('devices.wake', common),
    ('devices.wireless', {...common, 'address': '127.0.0.1', 'port': 5555}),
  ];
  for (final (command, params) in actions) {
    await expectLater(
      session.request(command, params),
      throwsA(_commandFailure('state_unverified')),
      reason: '$command 不得在快照核验完成前进入执行边界。',
    );
  }
}

Future<void> _expectReadsAndCleanupAvailable(
  ApplicationSession session,
  String device,
) async {
  expect((await session.request('devices.list'))['devices'], hasLength(1));
  expect(await session.request('settings.get'), isNotEmpty);
  expect((await session.request('transfers.list'))['transfers'], isEmpty);
  await expectLater(
    session.request('transfers.cancel', {'transferId': 'missing-transfer'}),
    throwsA(_commandFailure('not_found')),
  );
  for (final (command, action) in [
    ('session.key', 'up'),
    ('session.touch', 'up'),
    ('session.touch', 'cancel'),
  ]) {
    await expectLater(
      session.request(command, {
        'deviceId': device,
        'sessionId': 'missing-session',
        'captureGeneration': 1,
        'action': action,
      }),
      throwsA(_commandFailure('session_not_found')),
      reason: '$command $action 应进入精确对象清理，不能被恢复屏障拒绝。',
    );
  }
  await expectLater(
    session.request('session.pause', {'sessionId': 'missing-session'}),
    throwsA(_commandFailure('session_required')),
  );
  final stopped = await session.request('devices.disconnect', {
    'deviceId': device,
  });
  expect(stopped['disconnected'], isTrue);
  final record =
      ((await session.request('devices.list'))['devices'] as List).single
          as Map<Object?, Object?>;
  expect(record['status'], 'offline');
  expect(record['autoReconnect'], isFalse);
}

Matcher _commandFailure(String code) => isA<ApplicationCommandException>()
    .having((error) => error.code, 'code', code);

Directory _officialBinaryDirectory() {
  final binary = Platform.environment['INTEROP_OFFICIAL_ADB_BINARY'];
  if (binary != null) return File(binary).parent;
  var root = Directory.current;
  while (!File(p.join(root.path, 'Cargo.toml')).existsSync()) {
    if (root.parent.path == root.path) throw StateError('找不到工作区。');
    root = root.parent;
  }
  return Directory(
    p.join(root.path, '.dart_tool', 'adb', Platform.operatingSystem),
  );
}

final class _SnapshotReadOverrides extends IOOverrides {
  _SnapshotReadOverrides(this.file);
  final _BlockedSnapshotFile file;

  @override
  File createFile(String path) =>
      path == file.path ? file : super.createFile(path);
}

final class _BlockedSnapshotFile extends Fake implements File {
  _BlockedSnapshotFile(this.delegate);
  final File delegate;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  String get path => delegate.path;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    entered.complete();
    await release.future;
    return delegate.open(mode: mode);
  }
}
