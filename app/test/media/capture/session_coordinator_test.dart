import '../../support/scrcpy_event_fixture.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy/scrcpy.dart';
import 'package:scrcpy_connect/application/transport/application_command_exception.dart';
import 'package:scrcpy_connect/connection/connection_owner.dart';
import 'package:scrcpy_connect/connection/scrcpy_server_queries.dart';
import 'package:scrcpy_connect/media/capture/app_launch_store.dart';
import 'package:scrcpy_connect/media/capture/session_coordinator.dart';
import 'package:scrcpy_connect/media/capture/session_shell.dart';

void main() {
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.open();
  });
  tearDown(() async {
    await f.dispose();
  });

  test('手机捕获分阶段启动，逻辑身份与精确源分开，时间保持 Unix 秒', () async {
    final state = await f.start();
    expect(state['sessionId'], isNot(state['captureRef']));
    expect(state['captureRef'], 'capture-1');
    expect(state['videoSourceId'], 'source-capture-1');
    expect(state['createdAt'], 1700000000);
    expect(state['status'], 'awaiting_renderer');
    expect(f.native.stages, ['control:capture-1', 'media:capture-1:1']);
    expect(f.native.controls, isEmpty);
    expect(f.owner.hasAudioOwner('device'), isTrue);
    expect(f.native.options.single.logLevel, ScrcpyLogLevel.warn);
    expect(f.native.options.single.audio, isFalse);
    expect(f.native.options.single.powerOn, isFalse);
  });

  test('事件消费者失败不留下未启动窗口，也不阻断精确捕获回收', () async {
    f.failEvents = true;
    final state = await f.start();
    expect(state['captureRef'], 'capture-1');
    await f.owner.command('session.stop', {'sessionId': state['sessionId']});
    expect(f.native.stopped, ['capture-1']);
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.owner.hasAudioOwner('device'), isFalse);
  });

  test('音源资格通知启动失败仍可停止该窗口，不占用无执行的启动 Future', () async {
    f.failAudioEligibility = true;
    await expectLater(
      f.start(),
      throwsA(_error('session_cleanup_unconfirmed')),
    );
    expect(f.native.created, isEmpty);
    expect((await f.owner.snapshots()).single['status'], 'failed');
    f.failAudioEligibility = false;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('音源资格撤销抛错仍先释放捕获，保留停止责任供后继重试', () async {
    await f.start();
    f.failAudioEligibility = true;
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(isA<StateError>()),
    );
    expect(f.native.stopped, ['capture-1']);
    expect((await f.owner.snapshots()).single['status'], 'stopping');
    expect(f.owner.hasAudioOwner('device'), isFalse);
    f.failAudioEligibility = false;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.native.stopped, ['capture-1']);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('旧版 Android 只读查询缺少退出码仍可打开手机窗口', () async {
    f.adb.apiLevel = 21;
    f.adb.queryExitCode = null;
    final state = await f.start();
    expect(state['apiLevel'], 21);
    expect(state['captureRef'], 'capture-1');
    final metrics = await SessionShell(
      f.connection,
      const Duration(seconds: 5),
    ).metrics(AdbCancellation());
    expect(metrics, (width: 1080, height: 1920, density: 420));
  });

  test('只读查询不能忽略已知非零退出码，状态修改不能把未知退出码当成功', () async {
    final shell = SessionShell(f.connection, const Duration(seconds: 5));
    f.adb.queryExitCode = 7;
    await expectLater(f.start(), throwsA(_error('shell_failed')));
    expect(f.native.created, isEmpty);
    f.adb.queryExitCode = null;
    await expectLater(
      shell.run('getprop ro.build.version.sdk'),
      throwsA(_error('result_unknown')),
    );
  });

  test('独立应用先持久登记后仅提交一次，再由真实首帧确认', () async {
    f.native.onControl = (ref, message) async {
      if (message is ScrcpyStartApp) {
        final saved = jsonDecode(
          await f.launches.file.readAsString(),
        ) as Map<String, dynamic>;
        final records = saved['records'] as Map<String, dynamic>;
        expect(
          (records.values.single as Map<String, dynamic>)['status'],
          'pending',
        );
        expect(f.native.stages, isNot(contains('media:$ref:1')));
      }
    };
    final opening = f.owner.command('apps.launch', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'packageName': 'org.example.app',
    });
    final repeated = f.owner.command('apps.launch', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'packageName': 'org.example.app',
    });
    final result = await opening;
    await repeated;
    expect(f.native.created, ['capture-1']);
    expect(f.native.controls.whereType<ScrcpyStartApp>(), hasLength(1));
    expect(result['launchOutcome'], 'observed');
    expect(result['displayId'], 11);
    expect(await f.launches.unresolved(), isEmpty);
    expect(f.native.options.single.logLevel, ScrcpyLogLevel.info);
    expect(f.native.options.single.vdDestroyContent, isFalse);
    expect(f.native.options.single.flexDisplay, isTrue);
  });

  test('创建句柄晚到时停止等待真实交付并回收，不启动远端', () async {
    f.native.creation = Completer<String>();
    final starting = f.start();
    final failed = expectLater(starting, throwsA(_error('cancelled')));
    await _until(() => f.native.options.isNotEmpty);
    var stopped = false;
    final stop = f.owner
        .command('session.stop', {'sessionId': _id(1)})
        .then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    f.native.creation!.complete('capture-late');
    await failed;
    await stop;
    expect(f.native.stopped, ['capture-late']);
    expect(f.native.stages, isEmpty);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('首帧在停止后才返回不能复活，停止等待该 Future 退出', () async {
    f.native.media = Completer<ScrcpySessionInfo>();
    final starting = f.start();
    final failed = expectLater(
      starting,
      throwsA(isA<ApplicationCommandException>()),
    );
    await _until(
      () => f.native.stages.any((value) => value.startsWith('media:')),
    );
    var stopped = false;
    final stop = f.owner
        .command('session.stop', {'sessionId': _id(1)})
        .then((_) => stopped = true);
    await _until(() => f.native.stopped.isNotEmpty);
    expect(stopped, isFalse);
    f.native.media!.complete(_info('capture-1', 1));
    await failed;
    await stop;
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.owner.hasAudioOwner('device'), isFalse);
  });

  test('关闭失败保留精确捕获和容量，重试只关闭原身份', () async {
    await f.start();
    f.native.stopFailures = 1;
    await expectLater(f.owner.close(), throwsA(isA<ScrcpyException>()));
    expect((await f.owner.snapshots()).single['captureRef'], 'capture-1');
    await f.owner.close();
    expect(f.native.stopped, ['capture-1', 'capture-1']);
    expect(await f.owner.snapshots(), isEmpty);
    await expectLater(f.start(id: 2), throwsA(_error('disposed')));
  });

  test('16个启动中窗口占准入，停止未确认不能让出名额', () async {
    for (var index = 1; index <= 16; index++) {
      await f.start(id: index);
    }
    f.native.stopping = Completer<void>();
    final stopping = f.owner.command('session.stop', {'sessionId': _id(1)});
    await _until(() => f.native.stopped.isNotEmpty);
    await expectLater(f.start(id: 17), throwsA(_error('session_capacity')));
    f.native.stopping!.complete();
    await stopping;
    f.native.stopping = null;
    await f.start(id: 17);
    expect(f.native.created, hasLength(17));
  });

  test('输入与帧必须匹配捕获和渲染代次，错误尺寸不进入 SDK', () async {
    await f.start();
    await expectLater(
      f.owner.command('session.key', {
        'sessionId': _id(1),
        'captureGeneration': 2,
        'keyCode': 3,
      }),
      throwsA(_error('stale_capture')),
    );
    await expectLater(
      f.owner.command('session.touch', {
        'sessionId': _id(1),
        'captureGeneration': 1,
        'action': 'down',
        'pointerId': 0,
        'x': 1,
        'y': 1,
        'screenWidth': 600,
        'screenHeight': 800,
      }),
      throwsA(_error('stale_capture')),
    );
    await f.owner.command('session.ready', {
      'sessionId': _id(1),
      'captureGeneration': 1,
      'generation': 7,
      'textureId': 42,
    });
    await expectLater(
      f.owner.command('session.frame', {
        'sessionId': _id(1),
        'captureGeneration': 1,
        'generation': 6,
        'textureId': 42,
      }),
      throwsA(_error('stale_renderer')),
    );
    await f.owner.command('session.frame', {
      'sessionId': _id(1),
      'captureGeneration': 1,
      'generation': 7,
      'textureId': 42,
      'decodedWidth': 640,
      'decodedHeight': 480,
    });
    expect((await f.owner.snapshots()).single['decodedWidth'], 640);
    expect(f.native.controls, isEmpty);
  });

  test('手机窗口打开请求未知后不重放，显式关闭记录不声称强停应用', () async {
    await f.start();
    f.native.onControl = (_, message) async {
      if (message is ScrcpyStartApp) {
        throw const ScrcpyException('transport_failed');
      }
    };
    await expectLater(
      f.owner.command('session.launch', {
        'sessionId': _id(1),
        'packageName': 'org.example.app',
      }),
      throwsA(_error('transport_failed')),
    );
    expect(await f.launches.unresolved(), hasLength(1));
    f.native.onControl = null;
    await expectLater(
      f.owner.command('session.launch', {
        'sessionId': _id(1),
        'packageName': 'org.example.app',
      }),
      throwsA(_error('app_launch_unknown')),
    );
    final record = (await f.launches.unresolved()).single;
    final receipt = await f.owner.command('session.stop', {
      'sessionId': record.operationId,
    });
    expect(receipt['applicationStopped'], isFalse);
    expect(f.native.controls.whereType<ScrcpyStartApp>(), hasLength(1));
  });

  test('候选编码器不支持时保持原捕获，不提交 START_APP', () async {
    final original = await f.start();
    await expectLater(
      f.owner.command('session.reconfigure', {
        'sessionId': _id(1),
        'videoCodec': 'av1',
      }),
      throwsA(_error('encoder_unavailable')),
    );
    expect(f.native.created, ['capture-1']);
    expect(f.native.stopped, isEmpty);
    expect(
      (await f.owner.snapshots()).single['captureRef'],
      original['captureRef'],
    );
  });

  test('独立窗口画质切换移动真实任务，逻辑身份不变且不再次打开应用', () async {
    await f.start(package: 'org.example.app');
    final result = await f.owner.command('session.reconfigure', {
      'sessionId': _id(1),
      'maxSize': 1920,
    });
    expect(result['sessionId'], _id(1));
    expect(result['captureRef'], 'capture-2');
    expect(result['captureGeneration'], 2);
    expect(result['taskId'], 42);
    expect(f.adb.commands, contains('cmd activity display move-stack 42 12'));
    expect(f.native.controls.whereType<ScrcpyStartApp>(), hasLength(1));
    expect(f.native.stopped, ['capture-1']);
    await expectLater(
      f.owner.command('session.key', {
        'sessionId': _id(1),
        'captureGeneration': 1,
        'keyCode': 3,
      }),
      throwsA(_error('stale_capture')),
    );
    await f.owner.command('session.ready', {
      'sessionId': _id(1),
      'captureGeneration': 2,
      'generation': 2,
      'textureId': 55,
    });
    expect((await f.owner.snapshots()).single['qualityRebuilding'], isFalse);
  });

  test('候选首帧失败还原原任务与旧画质，保持原捕获并不重放打开', () async {
    await f.start(package: 'org.example.app');
    f.native.failMediaFor = 'capture-2';
    await expectLater(
      f.owner.command('session.reconfigure', {
        'sessionId': _id(1),
        'maxSize': 1920,
      }),
      throwsA(_error('encoder_failed')),
    );
    final state = (await f.owner.snapshots()).single;
    expect(state['captureRef'], 'capture-1');
    expect((state['quality'] as Map<String, dynamic>)['maxSize'], 1280);
    expect(
      f.adb.commands,
      containsAllInOrder([
        'cmd activity display move-stack 42 12',
        'cmd activity display move-stack 42 11',
      ]),
    );
    expect(f.native.stopped, isNot(contains('capture-1')));
    expect(f.native.stopped, contains('capture-2'));
    expect(f.native.controls.whereType<ScrcpyStartApp>(), hasLength(1));
  });

  test('旧 SDK 捕获开始 close 后失败也不能回滚为可用窗口，停止可重试且不重放打开', () async {
    await f.start(package: 'org.example.app');
    await f.owner.command('session.ready', {
      'sessionId': _id(1),
      'captureGeneration': 1,
      'generation': 1,
      'textureId': 55,
    });
    f.native.failStopFor.add('capture-1');
    await expectLater(
      f.owner.command('session.reconfigure', {
        'sessionId': _id(1),
        'maxSize': 1920,
      }),
      throwsA(_error('capture_cleanup_unconfirmed')),
    );
    final state = (await f.owner.snapshots()).single;
    expect(state['status'], 'failed');
    expect(f.owner.hasAudioOwner('device'), isFalse);
    final sent = f.native.controls.length;
    await expectLater(
      f.owner.command('session.key', {
        'sessionId': _id(1),
        'captureGeneration': 1,
        'keyCode': 3,
      }),
      throwsA(_error('session_stopped')),
    );
    expect(f.native.controls, hasLength(sent));
    expect(f.native.controls.whereType<ScrcpyStartApp>(), hasLength(1));
    expect(f.native.stopped, ['capture-1', 'capture-2']);
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('capture_cleanup_unconfirmed')),
    );
    expect((await f.owner.snapshots()).single['status'], 'stopping');
    f.native.failStopFor.clear();
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.native.stopped.where((id) => id == 'capture-2'), hasLength(1));
    expect(f.native.controls.whereType<ScrcpyStartApp>(), hasLength(1));
  });

  test('未确认释放的画质候选占真实容量并阻止再重建，实际清理后才恢复名额', () async {
    await f.start();
    f.native.failMediaFor = 'capture-2';
    f.native.failStopFor.add('capture-2');
    await expectLater(
      f.owner.command('session.reconfigure', {
        'sessionId': _id(1),
        'maxSize': 1920,
      }),
      throwsA(_error('quality_cleanup_unconfirmed')),
    );
    expect((await f.owner.snapshots()).single['captureRef'], 'capture-1');
    for (var id = 2; id <= 15; id++) {
      await f.start(id: id);
    }
    expect(f.native.created, hasLength(16));
    for (var attempt = 0; attempt < 3; attempt++) {
      await expectLater(
        f.owner.command('session.reconfigure', {
          'sessionId': _id(1),
          'maxSize': 1920,
        }),
        throwsA(_error('quality_cleanup_unconfirmed')),
      );
    }
    expect(f.native.created, hasLength(16));
    await expectLater(f.start(id: 16), throwsA(_error('session_capacity')));
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('capture_cleanup_unconfirmed')),
    );
    // 原捕获已关，但候选与尚未完成的逻辑窗口继续保留一个名额。
    await f.start(id: 16);
    await expectLater(f.start(id: 17), throwsA(_error('session_capacity')));
    f.native.failStopFor.clear();
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    await f.start(id: 17);
    await expectLater(f.start(id: 18), throwsA(_error('session_capacity')));
    expect(f.native.controls.whereType<ScrcpyStartApp>(), isEmpty);
  });

  test('创建中的画质预约计入容量，交付句柄后不重复计数', () async {
    for (var id = 1; id <= 14; id++) {
      await f.start(id: id);
    }
    final created = Completer<String>();
    f.native.creation = created;
    final rebuilding = f.owner.command('session.reconfigure', {
      'sessionId': _id(1),
      'maxSize': 1920,
    });
    await _until(() => f.native.options.length == 15);
    f.native.creation = null;
    await f.start(id: 15);
    await expectLater(f.start(id: 16), throwsA(_error('session_capacity')));
    final firstFrame = Completer<ScrcpySessionInfo>();
    f.native.media = firstFrame;
    created.complete('capture-100');
    await _until(() => f.native.stages.contains('media:capture-100:2'));
    f.native.media = null;
    await expectLater(f.start(id: 16), throwsA(_error('session_capacity')));
    firstFrame.complete(_info('capture-100', 2));
    await rebuilding;
    await f.start(id: 16);
    await expectLater(f.start(id: 17), throwsA(_error('session_capacity')));
  });

  test('按精确旧连接停止不会取消同设备的新连接窗口', () async {
    final old = f.connection;
    await f.start();
    f.connection = DeviceConnection(
      client: f.adb,
      device: const AdbDevice(
        id: 'replacement',
        serial: 'address',
        state: 'device',
      ),
    );
    await f.start(id: 2);
    await f.owner.stopForConnection('device', old);
    final remaining = await f.owner.snapshots();
    expect(remaining.single['sessionId'], _id(2));
    expect(f.native.stopped, ['capture-1']);
  });

  for (final sameDevice in [false, true]) {
    test(
      sameDevice
          ? '旧连接退休等待自己的迟到查询上传，不等待同设备后继连接的查询'
          : '设备退休等待自己的迟到查询上传，不等待另一设备的能力查询',
      () async {
        final old = f.connection;
        final other = _Adb();
        final replacement = DeviceConnection(
          client: other,
          device: const AdbDevice(
            id: 'other-connection',
            serial: 'other-address',
            state: 'device',
          ),
        );
        f.adb._uploads.creation = Completer<void>();
        other._uploads.creation = Completer<void>();
        final oldQuery = expectLater(
          f.owner.command('session.quality.options', {'deviceId': 'device'}),
          throwsA(_error('cancelled')),
        );
        await _until(() => f.adb._uploads.opened.isNotEmpty);
        final otherDevice = sameDevice ? 'device' : 'other-device';
        if (sameDevice) {
          f.connection = replacement;
        } else {
          f.additionalConnections[otherDevice] = replacement;
        }
        var otherSettled = false, stopped = false;
        final otherQuery = f.owner
            .command('session.quality', {'deviceId': otherDevice})
            .then((value) {
              otherSettled = true;
              return value;
            });
        await _until(() => other._uploads.opened.isNotEmpty);
        final stopping = f.owner
            .stopForConnection('device', old)
            .then((_) => stopped = true);
        try {
          await Future<void>.delayed(Duration.zero);
          expect(stopped, isFalse, reason: '取消不能冒充尚未交付的 SYNC 会话已关闭');
          expect(f.adb._uploads.cancelled, isEmpty);
          f.adb._uploads.creation!.complete();
          // 只有另一连接仍被夹具阻塞；退休必须独立完成，不能等待全局查询集合。
          await stopping.timeout(const Duration(seconds: 1));
          await oldQuery;
          expect(stopped, isTrue);
          expect(f.adb._uploads.cancelled, f.adb._uploads.opened);
          expect(otherSettled, isFalse);
          expect(other._uploads.cancelled, isEmpty);
          other._uploads.creation!.complete();
          final result = await otherQuery;
          expect(result['deviceId'], otherDevice);
          expect(result['appliesNextSession'], isTrue);
          expect(
            other.commands.any((value) => value.contains('list_encoders=true')),
            isTrue,
          );
        } finally {
          if (!f.adb._uploads.creation!.isCompleted) {
            f.adb._uploads.creation!.complete();
          }
          if (!other._uploads.creation!.isCompleted) {
            other._uploads.creation!.complete();
          }
          await oldQuery;
          await otherQuery;
          await stopping;
          await other.services.close();
        }
      },
    );
  }

  test('物理尺寸经独立租约确认，只在捕获关闭后恢复', () async {
    await f.start();
    final result = await f.owner.command('session.display', {
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    expect(result['displaySize'], {'width': 960, 'height': 1920});
    expect(f.native.stopped, isEmpty);
    f.adb._uploads.onDisplayStop = () =>
        expect(f.native.stopped, ['capture-1']);
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.adb._uploads.displayStops, 1);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('自动比例创建模式与已确认尺寸跨画质捕获交接保留', () async {
    final initial = await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
      'displayAuto': true,
    });
    expect(initial['displayAuto'], isTrue);
    expect(initial['displaySize'], {'width': 960, 'height': 1920});
    final replacement = await f.owner.command('session.reconfigure', {
      'sessionId': _id(1),
      'maxSize': 720,
    });
    expect(replacement['displayAuto'], isTrue);
    expect(replacement['displaySize'], initial['displaySize']);
    expect(f.adb._uploads.displayStarts, 1);
    expect(f.adb._uploads.displayStops, 0);
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.adb._uploads.displayStops, 1);
  });

  test('捕获关闭失败不提前恢复手机覆盖，重试沿同租约排空', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.native.stopFailures = 1;
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('capture_cleanup_unconfirmed')),
    );
    expect(f.adb._uploads.displayStops, 0);
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.adb._uploads.displayStarts, 1);
    expect(f.adb._uploads.displayStops, 1);
  });

  test('已RUN的精确连接closed且捕获真正关闭后，只排空本机不发恢复或ACK', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.connectionClosed = true;
    f.adb._uploads.omitDisplayDone = true;
    f.native.stopping = Completer<void>();
    var stopped = false;
    final stopping = f.owner
        .command('session.stop', {'sessionId': _id(1)})
        .then((_) => stopped = true);
    await _until(() => f.native.stopped.isNotEmpty);
    expect(stopped, isFalse);
    expect(f.adb._uploads.factQueries, isEmpty);
    expect(f.adb._uploads.cancelled, isEmpty);
    f.native.stopping!.complete();
    await stopping;
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.adb._uploads.factQueries, everyElement('connection'));
    expect(f.adb._uploads.displayStops, 0);
    expect(f.adb._uploads.displayRecoveries, 0);
    expect(f.adb._uploads.displayAcknowledgements, 0);
    expect(f.adb._uploads._execs, hasLength(1));
    expect(f.adb._uploads.cancelled, contains('exec-1'));
  });

  test('closed连接原流关闭失败仍保留同slot，重试只关同一流不重断捕获', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.connectionClosed = true;
    f.adb._uploads.displayCloseFailures = 100;
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('display_close_failed')),
    );
    expect(await f.owner.snapshots(), hasLength(1));
    expect(f.native.stopped, ['capture-1']);
    expect(f.adb._uploads.displayRecoveries, 0);
    expect(f.adb._uploads.displayAcknowledgements, 0);
    f.adb._uploads.displayCloseFailures = 0;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.native.stopped, ['capture-1']);
    expect(f.adb._uploads._execs, hasLength(1));
    expect(f.adb._uploads.cancelled.toSet(), {'exec-1'});
  });

  test('连接事实未知不能按页面stopping或错误放行本机detach', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.factsFail = true;
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('connection_facts_unknown')),
    );
    expect(await f.owner.snapshots(), hasLength(1));
    expect(f.adb._uploads.cancelled, isEmpty);
    expect(f.adb._uploads.displayStops, 0);
    f.adb._uploads.factsFail = false;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.adb._uploads.displayStops, 1);
    expect(f.adb._uploads.displayAcknowledgements, 1);
  });

  test('显示STOP期间才真实断链，重新核验closed后只结清原本机责任', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.omitDisplayDone = true;
    f.adb._uploads.onDisplayStop = () => f.adb._uploads.connectionClosed = true;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.adb._uploads.displayStops, 1);
    expect(f.adb._uploads.displayRecoveries, 0);
    expect(f.adb._uploads.displayAcknowledgements, 0);
    expect(f.adb._uploads._execs, hasLength(1));
  });

  test('closed连接显示句柄迟到也必须等交付后精确关闭，不发START或恢复', () async {
    f.adb._uploads.execCreation = Completer<void>();
    final starting = f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    final rejected = expectLater(starting, throwsA(_error('cancelled')));
    await _until(() => f.adb._uploads._execs.isNotEmpty);
    f.adb._uploads.connectionClosed = true;
    var stopped = false;
    final stopping = f.owner
        .command('session.stop', {'sessionId': _id(1)})
        .then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    expect(f.adb._uploads.cancelled, isEmpty);
    f.adb._uploads.execCreation!.complete();
    await rejected;
    await stopping;
    expect(await f.owner.snapshots(), isEmpty);
    expect(f.adb._uploads.displayStarts, 0);
    expect(f.adb._uploads.displayStops, 0);
    expect(f.adb._uploads.displayRecoveries, 0);
    expect(f.adb._uploads.displayAcknowledgements, 0);
    expect(f.adb._uploads._execs, hasLength(1));
    expect(f.adb._uploads.cancelled.toSet(), {'exec-1'});
  });

  test('显示恢复关闭失败仍持有同窗口，重试不重新修改尺寸', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.displayCloseFailures = 2;
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('display_close_failed')),
    );
    expect(await f.owner.snapshots(), hasLength(1));
    f.adb._uploads.displayCloseFailures = 0;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.adb._uploads.displayStarts, 1);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('显示执行句柄迟到，停止等待交付并回收且不发 START 或创建捕获', () async {
    f.adb._uploads.execCreation = Completer<void>();
    final starting = f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    final rejected = expectLater(starting, throwsA(_error('cancelled')));
    await _until(() => f.adb._uploads._execs.isNotEmpty);
    var finished = false;
    final stopping = f.owner
        .command('session.stop', {'sessionId': _id(1)})
        .then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    f.adb._uploads.execCreation!.complete();
    await rejected;
    await stopping;
    expect(f.adb._uploads.displayStarts, 0);
    expect(f.native.created, isEmpty);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('恢复回执丢失通过原owner核验，失败保留窗口重试且不重建捕获', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.omitDisplayDone = true;
    f.adb._uploads.failDisplayRecovery = true;
    await expectLater(
      f.owner.command('session.stop', {'sessionId': _id(1)}),
      throwsA(_error('display_cleanup_unconfirmed')),
    );
    expect(f.adb._uploads.displayRecoveries, 1);
    expect(await f.owner.snapshots(), hasLength(1));
    f.adb._uploads.failDisplayRecovery = false;
    await f.owner.command('session.stop', {'sessionId': _id(1)});
    expect(f.adb._uploads.displayRecoveries, 2);
    expect(f.adb._uploads.displayStarts, 1);
    expect(f.native.created, ['capture-1']);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('显示监督意外断流撤销原窗口，不能继续投影为可用捕获', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads._execs.values.first.finish();
    await _until(() => f.native.stopped.isNotEmpty);
    await f.owner.close();
    expect(f.adb._uploads.displayRecoveries, 1);
    expect(f.native.stopped, ['capture-1']);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('同一数据包中 READY 后的 DONE 立即撤销，不能作为成功窗口交付', () async {
    f.adb._uploads.endAfterDisplayReady = true;
    await expectLater(
      f.owner.command('session.start', {
        'deviceId': 'device',
        'sessionId': _id(1),
        'displayWidth': 960,
        'displayHeight': 1920,
      }),
      throwsA(_error('cancelled')),
    );
    await f.owner.close();
    expect(f.native.created, isEmpty);
    expect(await f.owner.snapshots(), isEmpty);
  });

  test('画质切换先封存尺寸准入并等在途调整，保留最终尺寸事实', () async {
    await f.owner.command('session.start', {
      'deviceId': 'device',
      'sessionId': _id(1),
      'displayWidth': 960,
      'displayHeight': 1920,
    });
    f.adb._uploads.holdResize = Completer<void>();
    final resizing = f.owner.command('session.display', {
      'sessionId': _id(1),
      'displayWidth': 640,
      'displayHeight': 960,
    });
    await _until(() => f.adb._uploads.resizeEntered);
    var replaced = false;
    final reconfiguring = f.owner
        .command('session.reconfigure', {'sessionId': _id(1)})
        .then((value) {
          replaced = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(replaced, isFalse);
    expect(f.native.created, ['capture-1']);
    f.adb._uploads.holdResize!.complete();
    await resizing;
    final result = await reconfiguring;
    expect(result['displaySize'], {'width': 640, 'height': 960});
    expect(f.adb._uploads.displayStarts, 1);
    expect(f.adb._uploads.displayStops, 0);
  });

  test('窗口所有者关闭不关闭注入的共享清单查询所有者', () async {
    await f.owner.close();
    final encoders = await f.queries.encoders(f.connection, AdbCancellation());
    expect(encoders, isNotEmpty);
  });

  test('查询缺监督终态不能当枚举成功，停止可独立核验原进程并恢复清理', () async {
    f.adb.omitProbeExit = true;
    await expectLater(
      f.owner.command('session.quality.options', {'deviceId': 'device'}),
      throwsA(_error('result_unknown')),
    );
    await f.queries.close();
    expect(
      f.adb.commands.any((command) => command.startsWith('rm -f -- ')),
      isTrue,
    );
  });
}

Matcher _error(String code) => isA<ApplicationCommandException>().having(
  (error) => error.code,
  'code',
  code,
);
String _id(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('未到达受控异步边界');
}

final class _Fixture {
  _Fixture(this.directory, this.launches) {
    connection = DeviceConnection(
      client: adb,
      device: const AdbDevice(
        id: 'connection',
        serial: 'address',
        state: 'device',
      ),
    );
    queries = ScrcpyServerQueries(
      serverBytes: Uint8List.fromList([1, 2, 3]),
      timeout: const SessionPolicy().shellTimeout,
      newId: () => _id(++next),
    );
    owner = SessionCoordinator(
      scrcpy: ScrcpyClient(native),
      requireConnection: (device) =>
          additionalConnections[device] ?? connection,
      launches: launches,
      serverQueries: queries,
      emit: (type, device, data) {
        if (failEvents) throw StateError('event consumer failed');
        events.add(type);
      },
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      newId: () => _id(++next),
      onAudioEligibilityChanged: (_) {
        if (failAudioEligibility) throw StateError('音源资格通知受控失败');
      },
    );
  }
  final Directory directory;
  final AppLaunchStore launches;
  final adb = _Adb();
  final native = _Native();
  final events = <String>[];
  final additionalConnections = <String, DeviceConnection>{};
  late DeviceConnection connection;
  late SessionCoordinator owner;
  late ScrcpyServerQueries queries;
  int next = 100;
  bool allowCleanupFailure = false;
  bool failEvents = false;
  bool failAudioEligibility = false;
  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp('session-owner-');
    return _Fixture(directory, await AppLaunchStore.open(directory: directory));
  }

  Future<Map<String, dynamic>> start({int id = 1, String? package}) =>
      owner.command('session.start', {
        'deviceId': 'device',
        'sessionId': _id(id),
        'packageName': ?package,
      });
  Future<void> dispose() async {
    if (allowCleanupFailure) {
      try {
        await owner.close();
        await queries.close();
      } catch (_) {
        /* 本例明确保留未知执行责任，不能虚报已排空。 */
      }
    } else {
      await owner.close();
      await queries.close();
    }
    await directory.delete(recursive: true);
  }
}

final class _Adb implements AdbClient {
  final commands = <String>[];
  final _uploads = _UploadApi();
  _Adb() {
    _uploads.onCommand = commands.add;
    _uploads.omitQueryEnd = () => omitProbeExit;
  }
  @override
  late final services = AdbServices(
    () => _uploads,
    (device) async => device,
    () {},
  );
  bool omitProbeExit = false;
  int apiLevel = 35;
  int? queryExitCode = 0;
  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    commands.add(command);
    cancellation?.check();
    final output = command == 'getprop ro.build.version.sdk'
        ? '$apiLevel\n'
        : command == 'wm size; wm density'
        ? 'Physical size: 1080x1920\nPhysical density: 420\n'
        : command == 'cmd activity stack list'
        ? 'RootTask id=42 bounds=[0,0][1080,1920] displayId=11\n  taskId=42: org.example.app/.Main\n'
        : command.contains('list_encoders=true')
        ? 'List of video encoders:\n --video-codec=h264 --video-encoder=c2.fake.h264 (hw)\n'
        : '';
    if (output.isNotEmpty) {
      yield AdbShellEvent(
        AdbShellChannel.stdout,
        Uint8List.fromList(utf8.encode(output)),
      );
    }
    if (!command.contains('list_encoders=true') || !omitProbeExit) {
      final readOnly =
          command == 'getprop ro.build.version.sdk' ||
          command == 'wm size; wm density' ||
          command == 'cmd activity stack list';
      yield AdbShellEvent(
        AdbShellChannel.exit,
        Uint8List(0),
        exitCode: readOnly ? queryExitCode : 0,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UploadApi implements NativeAdbApi {
  final _pending = <String, Completer<NativeAdbEvent?>>{};
  final _bytes = <String, int>{};
  final opened = <String>[], cancelled = <String>[];
  Completer<void>? creation;
  final _execs = <String, _Exec>{};
  void Function(String)? onCommand;
  bool Function()? omitQueryEnd;
  void Function()? onDisplayStop;
  int displayStarts = 0, displayStops = 0, displayCloseFailures = 0;
  int displayRecoveries = 0, displayAcknowledgements = 0;
  bool connectionClosed = false, factsFail = false;
  final factQueries = <String>[];
  bool omitDisplayDone = false, failDisplayRecovery = false;
  bool endAfterDisplayReady = false, resizeEntered = false;
  Completer<void>? holdResize;
  Completer<void>? execCreation;

  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async {
    factQueries.add(id);
    if (factsFail) throw const AdbException('connection_facts_unknown');
    return AdbConnectionFacts(
      officialServer: false,
      closed: connectionClosed,
      connectionId: 'physical-$id',
      features: const [],
    );
  }

  @override
  Future<String> service(
    String connectionId,
    AdbServiceRequest request,
    int timeoutMs,
  ) async {
    expect(request.kind, AdbServiceKind.exec);
    if (connectionClosed) throw const AdbException('connection_closed');
    final command = request.service;
    onCommand?.call(command);
    final id = 'exec-${_execs.length + 1}';
    final execution = _Exec(command);
    _execs[id] = execution;
    final ready = RegExp(r'__INTEROP_QUERY_READY_([0-9a-f]{32})__:')
        .firstMatch(command);
    final check = RegExp(r'__INTEROP_QUERY_CHECK_([0-9a-f]{32})__:')
        .firstMatch(command);
    if (ready != null) {
      execution.queryNonce = ready[1];
    } else if (check != null) {
      execution.add(
        'released:absent\n\n__INTEROP_QUERY_CHECK_${check[1]}__:0\n',
      );
      execution.finish();
    }
    await execCreation?.future;
    return id;
  }

  @override
  Future<String> sync(String id, AdbSyncRequest request, int timeoutMs) async {
    expect(request.kind, AdbSyncKind.push);
    final operation = 'push-${opened.length + 1}';
    opened.add(operation);
    await creation?.future;
    _pending[operation] = Completer<NativeAdbEvent?>();
    _bytes[operation] = 0;
    return operation;
  }

  @override
  Future<void> write(String id, AdbServiceInput input) async {
    if (_execs[id] case final execution?) {
      final text = utf8.decode(input.bytes);
      final queryNonce = execution.queryNonce;
      if (queryNonce != null && text == 'START $queryNonce\n') {
        execution.add('__INTEROP_QUERY_READY_${queryNonce}__:71:81\n');
      } else if (queryNonce != null && text == 'STOP $queryNonce\n') {
        execution.add('\n__INTEROP_QUERY_END_${queryNonce}__:143\n');
        execution.finish();
      } else if (queryNonce != null && text == 'RUN $queryNonce\n') {
        execution.add(
          'List of video encoders:\n --video-codec=h264 --video-encoder=c2.fake.h264 (hw)\n',
        );
        if (omitQueryEnd?.call() != true) {
          execution.add('\n__INTEROP_QUERY_END_${queryNonce}__:0\n');
        }
        execution.finish();
      } else if (text.startsWith('START:') &&
          text.endsWith('\n') &&
          !text.contains(' ')) {
        execution.owner = text.trim().substring('START:'.length);
        execution.add('__DISPLAY_OWNER__${execution.owner}:71:81\n');
      } else if (text == 'RUN:${execution.owner}\n') {
        final program = execution.program.toString();
        execution.width = int.parse(
          RegExp(r'desired_width=(\d+)').firstMatch(program)![1]!,
        );
        execution.height = int.parse(
          RegExp(r'desired_height=(\d+)').firstMatch(program)![1]!,
        );
        displayStarts++;
        execution.add(
          '__DISPLAY_READY__${execution.owner}:${execution.width}:${execution.height}\n${endAfterDisplayReady ? '__DISPLAY_DONE__${execution.owner}:restored\n' : ''}',
        );
      } else if (text.startsWith('RESIZE:')) {
        resizeEntered = true;
        await holdResize?.future;
        execution.add(
          '__DISPLAY_SIZE__${text.trim().substring('RESIZE:'.length)}\n',
        );
      } else if (text == 'STOP:${execution.owner}\n') {
        onDisplayStop?.call();
        displayStops++;
        if (!omitDisplayDone) {
          execution.add('__DISPLAY_DONE__${execution.owner}:restored\n');
        }
        execution.finish();
      } else {
        execution.program.write(text);
        if (text.endsWith('__INTEROP_DISPLAY_PROGRAM_END__\n')) {
          final program = execution.program.toString();
          final owner = RegExp("expected_owner='([0-9a-f]{32})'")
              .firstMatch(program)?[1];
          if (owner != null && program.contains('emit_ack()')) {
            displayAcknowledgements++;
            execution.add('__DISPLAY_ACK__$owner\n');
            execution.finish();
          } else if (owner != null &&
              !RegExp(r'desired_width=\d+').hasMatch(program)) {
            displayRecoveries++;
            if (!failDisplayRecovery) {
              execution.add('__DISPLAY_DONE__$owner:restored\n');
            }
            execution.finish();
          }
        }
      }
      return;
    }
    if (input.kind == AdbInputKind.bytes) {
      _bytes[id] = _bytes[id]! + input.bytes.length;
    } else if (input.kind == AdbInputKind.finish) {
      _pending[id]!.complete(
        NativeAdbEvent(
          kind: 'done',
          bytes: Uint8List(0),
          done: true,
          transferred: _bytes[id]!,
        ),
      );
    }
  }

  @override
  Future<NativeAdbEvent?> next(String id) =>
      _execs[id]?.next() ?? _pending[id]!.future;

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    if (_execs[id] case final execution?) {
      if (execution.owner != null && displayCloseFailures-- > 0) {
        throw const AdbException('display_close_failed');
      }
      execution.finish();
      return;
    }
    if (!_pending[id]!.isCompleted) _pending[id]!.complete(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Exec {
  _Exec(this.command);
  final String command;
  final program = StringBuffer();
  final events = Queue<NativeAdbEvent?>();
  Completer<NativeAdbEvent?>? pending;
  String? queryNonce, owner;
  int? width, height;
  void add(String text) => _event(
    NativeAdbEvent(
      kind: 'data',
      bytes: Uint8List.fromList(utf8.encode(text)),
      done: false,
    ),
  );
  void finish() =>
      _event(NativeAdbEvent(kind: 'done', bytes: Uint8List(0), done: true));
  void _event(NativeAdbEvent event) {
    final waiting = pending;
    if (waiting != null) {
      pending = null;
      waiting.complete(event);
    } else {
      events.add(event);
    }
  }

  Future<NativeAdbEvent?> next() {
    if (events.isNotEmpty) return Future.value(events.removeFirst());
    return (pending ??= Completer<NativeAdbEvent?>()).future;
  }
}

final class _Native implements NativeScrcpyApi, NativeScrcpyStagedApi {
  final created = <String>[], stopped = <String>[], stages = <String>[];
  final options = <ScrcpyOptions>[];
  final controls = <ScrcpyControlMessage>[];
  Completer<String>? creation;
  Completer<ScrcpySessionInfo>? media;
  Completer<void>? stopping;
  int stopFailures = 0;
  final failStopFor = <String>{};
  String? failMediaFor;
  Future<void> Function(String, ScrcpyControlMessage)? onControl;
  @override
  Future<String> createSession({
    required String connectionId,
    required ScrcpyOptions options,
  }) async {
    this.options.add(options);
    final id = creation == null
        ? 'capture-${created.length + 1}'
        : await creation!.future;
    created.add(id);
    return id;
  }

  @override
  Future<ScrcpySessionInfo> startControl(String sessionId) async {
    stages.add('control:$sessionId');
    return _info(sessionId, 1, media: false);
  }

  @override
  Future<ScrcpySessionInfo> awaitMedia(
    String captureRef, {
    int generation = 1,
  }) async {
    stages.add('media:$captureRef:$generation');
    if (captureRef == failMediaFor) {
      throw const ScrcpyException('encoder_failed');
    }
    return media == null ? _info(captureRef, generation) : media!.future;
  }

  @override
  Future<ScrcpyProcessInfo> processInfo(
    String captureRef,
  ) async => ScrcpyProcessInfo(
    pid: 7,
    started: 8,
    logTail: utf8.encode(
      'New display: 1080x1920 (id=${10 + int.parse(captureRef.split('-').last)})\n',
    ),
    truncated: false,
  );
  @override
  Future<ScrcpyControlReceipt> sendControl(
    String sessionId,
    ScrcpyControlMessage message,
  ) async {
    controls.add(message);
    await onControl?.call(sessionId, message);
    return ScrcpyControlReceipt(
      message is ScrcpyClipboard
          ? ScrcpyControlCompletion.clipboardAcknowledged
          : ScrcpyControlCompletion.written,
    );
  }

  @override
  Future<void> stopSession(String sessionId) async {
    stopped.add(sessionId);
    if (stopFailures-- > 0 || failStopFor.contains(sessionId)) {
      throw const ScrcpyException('capture_cleanup_unconfirmed');
    }
    await stopping?.future;
  }

  @override
  ScrcpyEventObserver openEvents(String captureRef) => idleFixtureObserver();
  @override
  Future<ScrcpySessionInfo> inspect(
    String captureRef, {
    int generation = 1,
  }) async => _info(captureRef, generation);
  @override
  Future<ScrcpySessionInfo> startSession(String sessionId) =>
      throw UnimplementedError('应用必须使用分阶段启动');
}

ScrcpySessionInfo _info(String id, int generation, {bool media = true}) =>
    ScrcpySessionInfo(
      id: id,
      deviceName: 'fixture',
      videoCodec: ScrcpyVideoCodec.h264,
      width: 640,
      height: 480,
      mediaReady: media,
      source: media
          ? ScrcpyNativeSource(
              sourceId: 'source-$id',
              generation: generation,
              codec: 'h264',
              width: 640,
              height: 480,
              attachAddress: 1,
              detachAddress: 2,
            )
          : null,
    );
