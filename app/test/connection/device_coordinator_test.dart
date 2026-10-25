import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_command_exception.dart';
import 'package:scrcpy_connect/stores/connection/connection_owner.dart';
import 'package:scrcpy_connect/stores/connection/device_coordinator.dart';
import 'package:scrcpy_connect/stores/connection/device_discovery.dart';
import 'package:scrcpy_connect/services/connection/device_reconnection_candidates.dart';
import 'package:scrcpy_connect/stores/connection/identity_manager.dart';
import 'package:scrcpy_connect/stores/connection/device_record_store.dart';
import 'package:scrcpy_connect/stores/connection/reconnection_coordinator.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() async => fixture.dispose());

  test('普通连接也等待准入准备，结束前不交付连接或发布connected事件', () async {
    final id = await fixture.add();
    final preparing = Completer<void>(), prepared = Completer<void>();
    fixture.onPrepare = (connection, _) async {
      expect(connection.device.id, 'handle-1');
      expect(fixture.owner.current(id), isNull);
      preparing.complete();
      await prepared.future;
    };
    final connecting = fixture.connect(id);
    await preparing.future;
    expect(fixture.connected, isEmpty);
    expect(fixture.owner.projectDevices().single['status'], isNot('connected'));
    expect(
      fixture.events
          .where((entry) => entry.$1 == 'devices.changed')
          .expand((entry) => entry.$2['devices']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .any((device) => device['status'] == 'connected'),
      isFalse,
    );
    prepared.complete();
    expect((await connecting)['connected'], isTrue);
    expect(fixture.connected, [fixture.owner.requireConnection(id)]);
  });

  test('配置候选准备仅在旧活动与连接退出后执行，失败如实离线而不复活旧窗口', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    final stopping = Completer<void>(), stopped = Completer<void>();
    var preparations = 0;
    fixture.onStop = (connection) async {
      if (identical(connection, original)) {
        stopping.complete();
        await stopped.future;
      }
    };
    fixture.onPrepare = (connection, _) async {
      preparations++;
      expect(connection.device.id, 'handle-2');
      expect(fixture.owner.current(id), isNull);
      expect(fixture.client.disconnected, ['handle-1']);
      throw const ApplicationCommandException(
        'display_recovery_unconfirmed',
        '恢复结果尚未确认',
      );
    };
    final configuring = fixture.configure(id);
    final rejected = expectLater(
      configuring,
      _failure('display_recovery_unconfirmed'),
    );
    await stopping.future;
    expect(preparations, 0);
    stopped.complete();
    await rejected;
    expect(preparations, 1);
    expect(fixture.owner.current(id), isNull);
    expect(fixture.records.current.find(id)!.status, 'offline');
    expect(fixture.records.current.find(id)!.address, '192.0.2.2');
    expect(fixture.client.disconnected, ['handle-1', 'handle-2']);
    expect(fixture.connected, [original]);
  });

  test('准入准备取消后等待真实恢复收尾，断开不能提前关闭候选', () async {
    final id = await fixture.add();
    final preparing = Completer<void>(), cancelled = Completer<void>();
    final cleanup = Completer<void>();
    var preparedExited = false, disconnected = false;
    fixture.onPrepare = (_, stop) async {
      preparing.complete();
      await stop.whenCancelled;
      cancelled.complete();
      await cleanup.future;
      preparedExited = true;
    };
    fixture.onStop = (_) async => expect(preparedExited, isTrue);
    final connecting = fixture.connect(id);
    final rejected = expectLater(connecting, _failure('cancelled'));
    await preparing.future;
    final stopping = fixture.owner
        .command('devices.disconnect', {'deviceId': id})
        .then((_) => disconnected = true);
    await cancelled.future;
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.disconnected, isEmpty);
    expect(disconnected, isFalse);
    cleanup.complete();
    await rejected;
    await stopping;
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.connected, isEmpty);
  });

  test('准备失败保留同候选清理责任，断开重试不重播准备', () async {
    final id = await fixture.paired();
    fixture.candidates.endpoints = [
      _endpoint('192.0.2.8', 4444),
      _endpoint('192.0.2.9', 5556),
    ];
    var preparations = 0;
    fixture.onPrepare = (_, _) async {
      preparations++;
      throw const AdbException('timeout', '已执行恢复但未确认结果');
    };
    fixture.client.failDisconnect = true;
    await expectLater(
      fixture.connect(id),
      _failure('connection_cleanup_unconfirmed'),
    );
    expect(fixture.client.connects, ['192.0.2.8:4444']);
    expect(fixture.owner.current(id), isNull);
    fixture.client.failDisconnect = false;
    await fixture.owner.command('devices.disconnect', {'deviceId': id});
    expect(fixture.client.disconnected, ['handle-1']);
    expect(preparations, 1);
    expect(fixture.connected, isEmpty);
  });

  test('准备后重新读取精确连接事实，已关闭候选不能交付或切换地址', () async {
    final id = await fixture.paired();
    fixture.candidates.endpoints = [
      _endpoint('192.0.2.8', 4444),
      _endpoint('192.0.2.9', 5556),
    ];
    fixture.onPrepare = (connection, _) async {
      fixture.client.native.closedConnections.add(connection.device.id);
    };
    await expectLater(fixture.connect(id), _failure('disconnected'));
    expect(fixture.client.connects, ['192.0.2.8:4444']);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.connected, isEmpty);
    expect(fixture.records.current.find(id)!.status, 'offline');
  });

  test('健康退休同步撤准入并发布offline，保留自动重连意图及精确清理重试', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final connection = fixture.owner.requireConnection(id);
    expect(fixture.connected, [connection]);
    fixture.client.failDisconnect = true;
    final retirement = fixture.owner.retireUnhealthy(
      id,
      connection,
      reason: 'transport_closed',
    );
    expect(fixture.owner.current(id), isNull);
    await expectLater(retirement, throwsStateError);
    final record = fixture.records.current.find(id)!;
    expect(record.status, 'offline');
    expect(record.autoReconnect, isTrue);
    expect(record.reason, 'transport_closed');
    expect(fixture.events.last.$1, 'devices.changed');
    fixture.client.failDisconnect = false;
    await fixture.owner.retireUnhealthy(
      id,
      connection,
      reason: 'transport_closed',
    );
    expect(fixture.client.disconnected, [connection.device.id]);
  });

  test('迟到健康结论及旧清理重试不撤后继连接，不改后继记录', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final old = fixture.owner.requireConnection(id);
    fixture.client.failDisconnect = true;
    await expectLater(
      fixture.owner.retireUnhealthy(id, old, reason: 'health_response_timeout'),
      throwsStateError,
    );
    fixture.client.failDisconnect = false;
    await fixture.connect(id);
    final replacement = fixture.owner.requireConnection(id);
    expect(replacement, isNot(same(old)));
    await fixture.owner.retireUnhealthy(id, old, reason: 'transport_closed');
    expect(fixture.owner.current(id), same(replacement));
    expect(fixture.records.current.find(id)!.status, 'connected');
    expect(fixture.client.disconnected, [old.device.id]);
  });

  test('健康离线持久化失败保留原投影，重试后才结清', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final connection = fixture.owner.requireConnection(id);
    fixture.rejectCommit = true;
    await expectLater(
      fixture.owner.retireUnhealthy(id, connection, reason: 'transport_closed'),
      throwsA(isA<FileSystemException>()),
    );
    expect(fixture.owner.current(id), isNull);
    fixture.rejectCommit = false;
    await fixture.owner.retireUnhealthy(
      id,
      connection,
      reason: 'transport_closed',
    );
    expect(fixture.records.current.find(id)!.status, 'offline');
    expect(fixture.client.disconnected, [connection.device.id]);
  });

  test('用户明确断开结清旧健康债务，迟到重试不恢复自动重连', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final old = fixture.owner.requireConnection(id);
    fixture.client.failDisconnect = true;
    await expectLater(
      fixture.owner.retireUnhealthy(id, old, reason: 'health_response_timeout'),
      throwsStateError,
    );
    fixture.client.failDisconnect = false;
    await fixture.owner.command('devices.disconnect', {'deviceId': id});
    await fixture.owner.retireUnhealthy(id, old, reason: 'transport_closed');
    final record = fixture.records.current.find(id)!;
    expect(record.status, 'offline');
    expect(record.autoReconnect, isFalse);
    expect(record.reason, isNull);
    expect(fixture.client.disconnected, [old.device.id]);
  });

  test('已配对零端口记录通过发现核验真实 GUID 后才提交当前端点', () async {
    final id = await fixture.paired();
    fixture.candidates.endpoints = [_endpoint('192.0.2.8', 4444)];
    expect((await fixture.connect(id))['connected'], isTrue);
    expect(fixture.candidates.guids, ['guid']);
    expect(fixture.client.connects, ['192.0.2.8:4444']);
    expect(fixture.client.requiredTls, [true]);
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    expect(reopened.current.find(id)!.address, '192.0.2.8');
    expect(reopened.current.find(id)!.port, 4444);
    expect(reopened.current.find(id)!.transport, DeviceTransport.tls);
  });

  test('保存的明确 TLS 地址可无发现跨网直连，手填配置仍直接核验', () async {
    final id = await fixture.paired(port: 5555);
    fixture.candidates.error = const ApplicationCommandException(
      'discovery_unavailable',
      '没有组播',
    );
    await fixture.connect(id);
    expect(fixture.candidates.guids, isEmpty);
    await fixture.owner.command('devices.configure', {
      'deviceId': id,
      'host': '198.51.100.4',
      'port': 7777,
      'transport': 'tls',
    });
    expect(fixture.client.connects, ['192.0.2.1:5555', '198.51.100.4:7777']);
    expect(fixture.client.requiredTls, [true, true]);
    expect(fixture.candidates.guids, isEmpty);
    expect(fixture.client.disconnected, ['handle-1']);
  });

  test('缓存地址不可达后在同次连接中发现漫游地址，不能提前保存首个失败候选', () async {
    final id = await fixture.paired(port: 5555);
    fixture.candidates.endpoints = [_endpoint('192.0.2.8', 4444)];
    fixture.client.onConnect = (address, _) async {
      if (address == '192.0.2.1:5555') {
        throw const AdbException('host_unreachable');
      }
      expect(fixture.records.current.find(id)!.address, '192.0.2.1');
      return _device('roamed');
    };
    await fixture.connect(id);
    expect(fixture.client.connects, ['192.0.2.1:5555', '192.0.2.8:4444']);
    expect(fixture.owner.requireConnection(id).device.id, 'roamed');
    expect(fixture.records.current.find(id)!.address, '192.0.2.8');
  });

  test('首发现候选不可达继续第二候选，桌面始终使用可信服务名与 Required TLS', () async {
    final id = await fixture.paired();
    fixture.client.official = true;
    fixture.candidates.endpoints = [
      _endpoint('192.0.2.8', 4444),
      _endpoint('192.0.2.9', 5556, instance: 'guid (2)'),
    ];
    fixture.client.onConnect = (address, _) async {
      if (address == 'guid._adb-tls-connect._tcp') {
        throw const AdbException('connect_failed');
      }
      return _device('second-service');
    };
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'auto',
      'active': true,
    });
    await fixture.records.update(
      id,
      (record) => record.copyWith(autoReconnect: true),
    );
    await fixture.automatic(id, 'auto');
    expect(fixture.client.connects, [
      'guid._adb-tls-connect._tcp',
      'guid (2)._adb-tls-connect._tcp',
    ]);
    expect(fixture.client.requiredTls, [true, true]);
    expect(fixture.records.current.find(id)!.address, '192.0.2.9');
    expect(fixture.owner.requireConnection(id).device.id, 'second-service');
  });

  test('授权失败和清理未知都不能换地址重播', () async {
    final id = await fixture.paired();
    fixture.candidates.endpoints = [
      _endpoint('192.0.2.8', 4444),
      _endpoint('192.0.2.9', 5556),
    ];
    for (final code in [
      'auth_failed',
      'adb_cleanup_unconfirmed',
      'official_connect_result_unknown',
    ]) {
      fixture.client.connectError = AdbException(code);
      await expectLater(fixture.connect(id), _failure(code));
      expect(fixture.client.connects.last, '192.0.2.8:4444');
    }
    expect(fixture.client.connects, hasLength(3));
    expect(fixture.records.current.find(id)!.port, 0);
  });

  test('实际 GUID 不符不能接纳或尝试另一候选，失败清理保留可重试资源', () async {
    final id = await fixture.paired();
    fixture.candidates.endpoints = [
      _endpoint('192.0.2.8', 4444),
      _endpoint('192.0.2.9', 5556),
    ];
    fixture.client.guid = 'other-guid';
    fixture.client.failDisconnect = true;
    await expectLater(
      fixture.connect(id),
      _failure('connection_cleanup_unconfirmed'),
    );
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.connects, ['192.0.2.8:4444']);
    expect(fixture.records.current.find(id)!.port, 0);
    fixture.client.failDisconnect = false;
    await fixture.owner.command('devices.disconnect', {'deviceId': id});
    expect(fixture.client.disconnected, ['handle-1']);
  });

  test('发现服务撤销后迟到连接只精确清理，不提交端点或授权失败投影', () async {
    final id = await fixture.paired();
    final endpoint = _endpoint('192.0.2.8', 4444);
    fixture.candidates.endpoints = [endpoint];
    final opening = fixture.client.opening = Completer<AdbDevice>();
    final pending = fixture.connect(id);
    final rejected = expectLater(pending, _failure('discovery_changed'));
    await fixture.client.started.future;
    fixture.candidates.withdrawn.add(endpoint);
    opening.complete(_device('withdrawn'));
    await rejected;
    expect(fixture.client.disconnected, ['withdrawn']);
    expect(fixture.records.current.find(id)!.port, 0);
    expect(fixture.owner.current(id), isNull);
  });

  test('发现尚未结束时断开同步取消同一 owner，迟到发现不能启动连接', () async {
    final id = await fixture.paired();
    final found = Completer<List<AdbDiscoveryEndpoint>>();
    fixture.candidates.pending = found;
    final pending = fixture.connect(id);
    final rejected = expectLater(pending, _failure('cancelled'));
    await fixture.candidates.started.future;
    var stopped = false;
    final stopping = fixture.owner
        .command('devices.disconnect', {'deviceId': id})
        .then((_) => stopped = true);
    expect(fixture.candidates.cancellation!.isCancelled, isTrue);
    await Future<void>.value();
    expect(stopped, isFalse);
    found.complete([_endpoint('192.0.2.8', 4444)]);
    await rejected;
    await stopping;
    expect(fixture.client.connects, isEmpty);
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
  });

  test('真实重连所有者在宿主停止后换租约，手动恢复再离线可自动连接', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final timers = <_ReconnectTimer>[];
    final leases = <String>[];
    final cancelledAttempts = <String>[];
    final automatic = Completer<Map<String, Object?>>();
    var sequence = 0;
    final reconnecting = ReconnectionCoordinator(
      policy: fixture.owner.policy,
      ownerPrefix: 'stop-recovery',
      schedule: (_, run) {
        final timer = _ReconnectTimer(run);
        timers.add(timer);
        return timer;
      },
      request: (command, params) async {
        if (command == 'devices.cancel') {
          cancelledAttempts.add(params['attemptId'] as String);
        }
        if (command == 'state.snapshot') {
          return {
            'sequence': sequence,
            'settings': {'backgroundKeepAlive': true},
            'devices': fixture.owner.projectDevices(),
          };
        }
        final result = await fixture.owner.command(command, params);
        if (command == 'devices.reconnect.owner' && params['active'] == true) {
          leases.add(params['ownerId'] as String);
        }
        if (command == 'devices.connect' && params['automatic'] == true) {
          automatic.complete(result);
        }
        return Map<String, dynamic>.from(result);
      },
    );
    fixture.onEmit = (type, data) => reconnecting.handleEvent({
      'type': type,
      'sequence': ++sequence,
      'data': data,
    });
    try {
      await reconnecting.start();
      for (var i = 0; i < 40; i++) {
        await Future<void>.value();
      }
      final oldOwner = leases.single;
      reconnecting.stopAutomaticConnections();
      await fixture.owner.stopConnections();
      for (var i = 0; i < 40; i++) {
        await Future<void>.value();
      }
      expect(leases, hasLength(2));
      expect(leases.last, isNot(oldOwner));
      expect(timers.where((timer) => timer.isActive), isEmpty);
      expect(fixture.client.connects, hasLength(1));

      final finish = reconnecting.beforeRequest('devices.connect', {
        'deviceId': id,
      });
      await fixture.connect(id);
      await finish();
      // 旧租约迟到释放不能撤销新权限；真实断线不等同于用户主动停止。
      await fixture.owner.command('devices.reconnect.owner', {
        'ownerId': oldOwner,
        'active': false,
      });
      await fixture.owner.invalidate([id]);
      await fixture.records.update(
        id,
        (record) => record.copyWith(status: 'offline'),
      );
      reconnecting.handleEvent({
        'type': 'devices.changed',
        'sequence': ++sequence,
        'data': {'devices': fixture.owner.projectDevices()},
      });
      final timer = timers.where((timer) => timer.isActive).single;
      timer.fire();
      expect((await automatic.future)['connected'], isTrue);
      expect(fixture.owner.requireConnection(id).device.id, 'handle-3');
      expect(fixture.client.connects, hasLength(3));
      expect(cancelledAttempts, isEmpty);
      final finishStop = reconnecting.beforeRequest('devices.disconnect', {
        'deviceId': id,
      });
      await fixture.owner.command('devices.disconnect', {'deviceId': id});
      await finishStop();
      expect(fixture.owner.current(id), isNull);
      expect(fixture.client.disconnected, ['handle-1', 'handle-2', 'handle-3']);
      expect(timers.where((timer) => timer.isActive), isEmpty);
    } finally {
      fixture.onEmit = null;
      await reconnecting.dispose();
    }
  });

  test('宿主停止同步撤销所有连接，等待活动后持久停用重连且仍可手动连接', () async {
    final first = await fixture.add(),
        second = await fixture.add(host: '192.0.2.2');
    await fixture.connect(first);
    await fixture.connect(second);
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'auto',
      'active': true,
    });
    final entered = Completer<void>(), release = Completer<void>();
    fixture.onStop = (_) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    var finished = false;
    final stopping = fixture.owner.stopConnections().then(
      (_) => finished = true,
    );
    expect(fixture.owner.current(first), isNull);
    expect(fixture.owner.current(second), isNull);
    await entered.future;
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(fixture.client.disconnected, isEmpty);
    // 通过同一存储队列确认真实持久化，不能用事件循环次数推断磁盘提交完成。
    await fixture.records.reload();
    expect(
      fixture.records.current.devices.every(
        (record) => record.status == 'offline' && !record.autoReconnect,
      ),
      isTrue,
    );
    await expectLater(fixture.connect(first), _failure('cancelled'));
    release.complete();
    await stopping;
    expect(
      fixture.client.disconnected,
      unorderedEquals(['handle-1', 'handle-2']),
    );
    await expectLater(
      fixture.automatic(first, 'auto'),
      _failure('reconnect_owner_required'),
    );
    await fixture.connect(first);
    expect(fixture.owner.current(first), isNotNull);
    expect(fixture.client.closed, isFalse);
  });

  test('宿主停止清理失败仍保存停止意图，重试回收原句柄而不关闭共享客户端', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    fixture.client.failDisconnect = true;
    await expectLater(fixture.owner.stopConnections(), throwsStateError);
    expect(fixture.owner.current(id), isNull);
    final saved = fixture.records.current.find(id)!;
    expect(saved.status, 'offline');
    expect(saved.autoReconnect, isFalse);
    fixture.client.failDisconnect = false;
    await fixture.owner.stopConnections();
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.stopped, ['handle-1']);
    await fixture.connect(id);
    expect(fixture.owner.requireConnection(id).device.id, 'handle-2');
    expect(fixture.client.closed, isFalse);
  });

  test('停止意图保存失败也排空连接，重试仅补写未确认记录', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    fixture.rejectCommit = true;
    await expectLater(
      fixture.owner.stopConnections(),
      throwsA(isA<FileSystemException>()),
    );
    expect(fixture.client.disconnected, ['handle-1']);
    fixture.rejectCommit = false;
    await fixture.owner.stopConnections();
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
  });

  test('模式切换同步撤发布，原记录只变离线且活动结束前不能执行服务', () async {
    final id = await fixture.add(transport: 'tls');
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    final saved = fixture.records.current.find(id)!;
    final stopping = Completer<void>(), stopped = Completer<void>();
    final started = Completer<void>(), serviceReply = Completer<String>();
    fixture.onStop = (connection) async {
      expect(connection, same(original));
      stopping.complete();
      await stopped.future;
    };
    final changing = fixture.owner.retireForChange(
      id,
      original,
      change: (connection, _) {
        expect(connection, same(original));
        expect(fixture.owner.current(id), isNull);
        final record = fixture.records.current.find(id)!;
        expect(record.status, 'offline');
        expect(record.autoReconnect, isFalse);
        started.complete();
        return serviceReply.future;
      },
    );
    expect(fixture.owner.current(id), isNull);
    await stopping.future;
    expect(started.isCompleted, isFalse);
    stopped.complete();
    await started.future;
    expect(fixture.client.disconnected, isEmpty);
    serviceReply.complete('restarting');
    expect(await changing, 'restarting');
    final record = fixture.records.current.find(id)!;
    expect(record.address, saved.address);
    expect(record.port, saved.port);
    expect(record.transport, saved.transport);
    expect(record.guid, saved.guid);
    expect(record.serial, saved.serial);
    expect(fixture.client.disconnected, [original.device.id]);
    expect(fixture.events.last.$1, 'devices.changed');
    fixture.onStop = null;
  });

  test('模式切换持久化失败不能执行服务，仍收回精确旧连接', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    var changed = false;
    fixture.rejectCommit = true;
    await expectLater(
      fixture.owner.retireForChange(
        id,
        original,
        change: (_, _) async => changed = true,
      ),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          'injected commit failure',
        ),
      ),
    );
    fixture.rejectCommit = false;
    expect(changed, isFalse);
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.disconnected, [original.device.id]);
  });

  test('USB 平台租约跟随实际准入连接，成功握手与核验不会提前释放', () async {
    final identity = await fixture.owner.identities.prepareSetup({});
    var released = 0;
    try {
      final receipt = await fixture.owner.admitSetupCandidate(
        identity: identity,
        transport: DeviceTransport.usb,
        open: (_, _) async => _device('usb-owned'),
        releasePlatformResources: () async {
          expect(fixture.client.disconnected, contains('usb-owned'));
          released++;
        },
      );
      final id = receipt['deviceId']! as String;
      expect(released, 0);
      expect(fixture.owner.requireConnection(id).device.id, 'usb-owned');
      await fixture.owner.command('devices.disconnect', {'deviceId': id});
      expect(released, 1);
      await fixture.owner.command('devices.disconnect', {'deviceId': id});
      expect(released, 1);
    } finally {
      await identity.dispose();
    }
  });

  test('USB SDK 未交付句柄时平台责任不转移，仍由设置流程收尾', () async {
    final identity = await fixture.owner.identities.prepareSetup({});
    var released = false;
    try {
      await expectLater(
        fixture.owner.admitSetupCandidate(
          identity: identity,
          transport: DeviceTransport.usb,
          open: (_, _) async => throw const AdbException('io_error'),
          releasePlatformResources: () async => released = true,
        ),
        _failure('io_error'),
      );
      expect(fixture.client.disconnected, isEmpty);
      await fixture.owner.close();
      expect(released, isFalse);
    } finally {
      await identity.dispose();
    }
  });

  test('USB 已交付但准入核验失败，SDK 清理失败保留平台租约直到精确重试', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final identity = await fixture.owner.identities.prepareSetup(
      {},
      deviceId: id,
    );
    fixture.client.serial = 'wrong-phone';
    fixture.client.failDisconnect = true;
    var released = 0;
    try {
      await expectLater(
        fixture.owner.admitSetupCandidate(
          deviceId: id,
          identity: identity,
          client: fixture.client,
          transport: DeviceTransport.usb,
          open: (_, _) async => _device('usb-rejected'),
          releasePlatformResources: () async {
            expect(fixture.client.disconnected, contains('usb-rejected'));
            released++;
          },
        ),
        _failure('connection_cleanup_unconfirmed'),
      );
      expect(released, 0);
      expect(fixture.owner.requireConnection(id).device.id, 'handle-1');
      fixture.client.failDisconnect = false;
      await fixture.owner.command('devices.disconnect', {'deviceId': id});
      expect(released, 1);
      expect(fixture.client.disconnected, ['usb-rejected', 'handle-1']);
      expect(fixture.client.closed, isFalse);
    } finally {
      fixture.client.failDisconnect = false;
      await identity.dispose();
    }
  });

  test('真实配对创建 TLS 离线记录且端口为零，重复 GUID 不重复创建', () async {
    final first = await fixture.owner.identities.prepareSetup({});
    final second = await fixture.owner.identities.prepareSetup({});
    try {
      final results = await Future.wait([
        fixture.owner.recordPairing(
          guid: 'guid',
          address: '192.0.2.20',
          identity: first,
        ),
        fixture.owner.recordPairing(
          guid: 'guid',
          address: '192.0.2.21',
          identity: second,
        ),
      ]);
      expect(results.first['guid'], 'guid');
      expect(results.first['connected'], isFalse);
      expect(results.first['deviceId'], results.last['deviceId']);
      final record = fixture.records.current.devices.single;
      expect(record.transport, DeviceTransport.tls);
      expect(record.port, 0);
      expect(record.address, '192.0.2.20');
      expect(record.status, 'offline');
      expect(fixture.owner.current(record.id), isNull);
      expect(fixture.client.connects, isEmpty);
    } finally {
      await first.dispose();
      await second.dispose();
    }
  });

  test('专属身份绑定到新配对记录，首次发现按指定端点连接并核验真实 GUID', () async {
    final identity = await fixture.owner.identities.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    try {
      final paired = await fixture.owner.recordPairing(
        guid: 'guid',
        address: '192.0.2.20',
        identity: identity,
      );
      final id = paired['deviceId']! as String;
      expect(fixture.records.current.deviceIdentityFingerprints[id], 'b' * 64);
      expect(identity.selection.scope, 'device');
      final result = await fixture.owner.admitSetupCandidate(
        deviceId: id,
        identity: identity,
        client: fixture.client,
        transport: DeviceTransport.tls,
        guid: 'guid',
        address: '198.51.100.7',
        port: 43777,
        checkCandidate: () {},
        open: (client, stop) => client.connect(
          '198.51.100.7:43777',
          requireTls: true,
          cancellation: stop,
        ),
      );
      expect(result['connected'], isTrue);
      expect(fixture.client.connects, ['198.51.100.7:43777']);
      final record = fixture.records.current.find(id)!;
      expect(record.address, '198.51.100.7');
      expect(record.port, 43777);
      expect(record.serial, 'hardware-serial');
      expect(record.guid, 'guid');
    } finally {
      await identity.dispose();
    }
  });

  test('已有配对仅核对 GUID 和当前身份，不改旧端点或偷换专属身份', () async {
    final id = await fixture.add(transport: 'tls');
    await fixture.records.update(id, (record) => record.copyWith(guid: 'guid'));
    final identity = await fixture.owner.identities.prepareSetup(
      {},
      deviceId: id,
    );
    final other = await fixture.owner.identities.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    try {
      await expectLater(
        fixture.owner.recordPairing(
          deviceId: id,
          guid: 'another',
          address: '192.0.2.20',
          identity: identity,
        ),
        _failure('device_identity_mismatch'),
      );
      await expectLater(
        fixture.owner.recordPairing(
          deviceId: id,
          guid: 'guid',
          address: '192.0.2.20',
          identity: other,
        ),
        _failure('identity_changed'),
      );
      final receipt = await fixture.owner.recordPairing(
        deviceId: id,
        guid: 'guid',
        address: '192.0.2.20',
        identity: identity,
      );
      expect(receipt['guid'], 'guid');
      expect(fixture.records.current.find(id)!.address, '192.0.2.1');
      expect(fixture.records.current.find(id)!.port, 5555);
      expect(fixture.records.current.deviceIdentityFingerprints[id], isNull);
    } finally {
      await identity.dispose();
      await other.dispose();
    }
  });

  test('发现答案在配置实际落盘后过期，补偿端点并保留原连接', () async {
    final id = await fixture.add(transport: 'tls');
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    final identity = await fixture.owner.identities.prepareSetup(
      {},
      deviceId: id,
    );
    final gate = fixture.pauseEndpointCommit('198.51.100.7');
    var valid = true;
    try {
      final pending = fixture.owner.admitSetupCandidate(
        deviceId: id,
        identity: identity,
        client: fixture.client,
        transport: DeviceTransport.tls,
        guid: 'guid',
        address: '198.51.100.7',
        port: 43777,
        checkCandidate: () {
          if (!valid) {
            throw const ApplicationCommandException(
              'discovery_changed',
              '答案已撤回',
            );
          }
        },
        open: (client, stop) =>
            fixture.client.connect('198.51.100.7:43777', cancellation: stop),
      );
      final rejected = expectLater(pending, _failure('discovery_changed'));
      await gate.renamed.future;
      expect(fixture.owner.requireConnection(id), same(original));
      valid = false;
      gate.resume.complete();
      await rejected;
      expect(fixture.owner.requireConnection(id), same(original));
      expect(fixture.records.current.find(id)!.address, '192.0.2.1');
      expect(fixture.records.current.find(id)!.guid, isNull);
      expect(fixture.client.disconnected, ['handle-2']);
    } finally {
      await identity.dispose();
    }
  });

  test('新设备密钥发布未知保留离线记录，不打开候选或回退全局身份', () async {
    final identity = await fixture.owner.identities.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    fixture.identityApi.unknownReplacement = true;
    try {
      await expectLater(
        fixture.owner.admitSetupCandidate(
          identity: identity,
          transport: DeviceTransport.usb,
          open: (client, stop) =>
              client.connect('must-not-open', cancellation: stop),
        ),
        _failure('identity_result_unknown'),
      );
      final record = fixture.records.current.devices.single;
      expect(record.status, 'offline');
      expect(fixture.owner.current(record.id), isNull);
      expect(fixture.client.connects, isEmpty);
      expect(
        await File('${fixture.root.path}/identity_transaction.json').exists(),
        isTrue,
      );
    } finally {
      fixture.identityApi.unknownReplacement = false;
      await identity.dispose();
    }
  });

  test('新 USB 专属身份先绑定持久路径，再创建实际客户端与候选', () async {
    final identity = await fixture.owner.identities.prepareSetup({
      'identity': {'scope': 'device', 'privateKeyPem': 'key-b'},
    });
    final temporaryPath = identity.selection.path;
    try {
      final result = await fixture.owner.admitSetupCandidate(
        identity: identity,
        transport: DeviceTransport.usb,
        open: (client, stop) =>
            client.connect('usb-selected', cancellation: stop),
      );
      final id = result['deviceId']! as String;
      expect(fixture.selectedPaths.single, isNot(temporaryPath));
      expect(fixture.selectedPaths.single, identity.selection.path);
      expect(fixture.records.current.deviceIdentityFingerprints[id], 'b' * 64);
      await identity.dispose();
      expect(await File(fixture.selectedPaths.single).readAsString(), 'key-b');
      expect(fixture.owner.requireConnection(id).client, same(fixture.client));
    } finally {
      await identity.dispose();
    }
  });

  test('close 等待 typed USB 实际迟到结果回收，不遗失非 command 操作', () async {
    final identity = await fixture.owner.identities.prepareSetup({});
    final entered = Completer<void>();
    final opened = Completer<AdbDevice>();
    try {
      final pending = fixture.owner.admitSetupCandidate(
        identity: identity,
        transport: DeviceTransport.usb,
        open: (_, _) {
          entered.complete();
          return opened.future;
        },
      );
      final rejected = expectLater(pending, _failure('cancelled'));
      await entered.future;
      var finished = false;
      final closing = fixture.owner.close().then((_) => finished = true);
      expect(finished, isFalse);
      opened.complete(_device('late-usb'));
      await rejected;
      await closing;
      expect(fixture.client.disconnected, ['late-usb']);
      expect(fixture.owner.projectDevices().single['status'], 'offline');
    } finally {
      await identity.dispose();
    }
  });

  test('只有显式 TCP 转换可清 TLS 和 GUID，且要求切换前真实序列号', () async {
    final id = await fixture.add(transport: 'tls');
    await fixture.records.update(id, (record) => record.copyWith(guid: 'guid'));
    await fixture.connect(id);
    final identity = await fixture.owner.identities.prepareSetup(
      {},
      deviceId: id,
    );
    try {
      expect(
        () => fixture.owner.admitTcpipCandidate(
          deviceId: id,
          expectedSerial: 'wrong',
          identity: identity,
          client: fixture.client,
          address: '198.51.100.7',
          port: 5555,
          open: (_, _) async => _device('never'),
        ),
        throwsA(isA<ApplicationCommandException>()),
      );
      await fixture.owner.admitTcpipCandidate(
        deviceId: id,
        expectedSerial: 'hardware-serial',
        identity: identity,
        client: fixture.client,
        address: '198.51.100.7',
        port: 5555,
        open: (client, stop) =>
            fixture.client.connect('198.51.100.7:5555', cancellation: stop),
      );
      final record = fixture.records.current.find(id)!;
      expect(record.transport, DeviceTransport.tcp);
      expect(record.guid, isNull);
      expect(record.address, '198.51.100.7');
      expect(fixture.client.disconnected, ['handle-1']);
    } finally {
      await identity.dispose();
    }
  });

  test('记录列表与真实连接投影分别取证，不把磁盘 connected 或 selector 当连接身份', () async {
    final id = await fixture.add();
    await fixture.records.update(
      id,
      (record) => record.copyWith(status: 'connected'),
    );
    expect(fixture.owner.projectDevices().single['status'], 'offline');
    expect(
      fixture.owner.projectDevices().single.containsKey('connectionId'),
      isFalse,
    );
    final result = await fixture.connect(id);
    final device = result['device']! as Map;
    expect(device['status'], 'connected');
    expect(device['connectionId'], 'physical-1');
    expect(device['serial'], 'hardware-serial');
    expect(device['model'], '测试手机');
    expect(fixture.owner.requireConnection(id).device.serial, '192.0.2.1:5555');
    expect(fixture.events.last.$1, 'devices.changed');
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    expect(reopened.current.find(id)!.serial, 'hardware-serial');
    expect(reopened.current.find(id)!.status, 'connected');
    expect(reopened.current.find(id)!.lastSeen, 1);
  });

  test('记录编辑真实落盘，既有 TLS 不因手动修改回退明文', () async {
    final id = await fixture.add(transport: 'tls');
    await fixture.owner.command('devices.rename', {
      'deviceId': id,
      'name': '  工作手机  ',
    });
    await fixture.owner.command('devices.add', {
      'deviceId': id,
      'host': '192.0.2.2',
      'port': 6666,
      'transport': 'tcp',
    });
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    final record = reopened.current.find(id)!;
    expect(record.name, '工作手机');
    expect(record.address, '192.0.2.2');
    expect(record.port, 6666);
    expect(record.transport.name, 'tls');
  });

  test('设备详情由协调器接入同一实际连接，断开后不沿用旧查询身份', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    expect(fixture.owner.handles('device.network.get'), isTrue);
    final result = await fixture.owner.command('device.network.get', {
      'deviceId': id,
      'connectionId': 'physical-1',
    });
    expect(result['deviceId'], id);
    expect(result['connectionId'], 'physical-1');
    await fixture.owner.command('devices.disconnect', {'deviceId': id});
    await expectLater(
      fixture.owner.command('device.network.get', {'deviceId': id}),
      _failure('disconnected'),
    );
  });

  test('连接先核验真实序列号与已知 GUID 冲突，失败不交付候选', () async {
    final id = await fixture.add();
    await fixture.records.update(
      id,
      (record) => record.copyWith(serial: 'saved-serial'),
    );
    await expectLater(
      fixture.connect(id),
      _failure('device_identity_mismatch'),
    );
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.records.current.find(id)!.serial, 'saved-serial');
  });

  test('SDK 授权失败保留业务错误码和消息，记录真实 unauthorized 且不交付连接', () async {
    final id = await fixture.add();
    fixture.client.connectError = const AdbException(
      'auth_failed',
      '设备拒绝了本次授权',
    );
    await expectLater(
      fixture.connect(id),
      throwsA(
        isA<ApplicationCommandException>()
            .having((error) => error.code, 'code', 'auth_failed')
            .having((error) => error.message, 'message', '设备拒绝了本次授权'),
      ),
    );
    final saved = (await DeviceRecordStore.open(directory: fixture.root))
        .current
        .find(id)!;
    expect(saved.status, 'unauthorized');
    expect(saved.autoReconnect, isFalse);
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.disconnected, isEmpty);
  });

  test('同端点官方客户端不能独立创建候选时，在 connect 前拒绝并保留原连接', () async {
    fixture.client.official = true;
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    await expectLater(
      fixture.configure(id, host: '192.0.2.1', port: 5555),
      _failure('independent_connection_required'),
    );
    expect(fixture.client.connects, hasLength(1));
    expect(fixture.owner.requireConnection(id), same(original));
    expect(fixture.client.disconnected, isEmpty);
    expect(fixture.client.options.single, isNull);
  });

  test('配置候选身份核验失败保留原端点、原连接与原活动', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    var prepared = false;
    fixture.onPrepare = (_, _) async => prepared = true;
    fixture.client.serial = 'other-phone';
    await expectLater(
      fixture.configure(id),
      _failure('device_identity_mismatch'),
    );
    expect(fixture.owner.requireConnection(id), same(original));
    expect(fixture.records.current.find(id)!.address, '192.0.2.1');
    expect(fixture.records.current.find(id)!.status, 'connected');
    expect(fixture.stopped, ['handle-2']);
    expect(fixture.client.disconnected, ['handle-2']);
    expect(prepared, isFalse);
  });

  test('候选磁盘提交失败不能交付或撤销仍可用的原连接', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    fixture.rejectCommit = true;
    await expectLater(
      fixture.configure(id),
      throwsA(isA<FileSystemException>()),
    );
    fixture.rejectCommit = false;
    expect(fixture.owner.requireConnection(id), same(original));
    expect(fixture.client.disconnected, ['handle-2']);
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    expect(reopened.current.find(id)!.address, '192.0.2.1');
  });

  test('候选 rename 已成功但回执未返回时取消，只补偿端点并保留并发名称编辑', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    final commit = fixture.pauseEndpointCommit('192.0.2.2');
    final stop = AdbCancellation();
    final pending = fixture.configure(id, cancellation: stop);
    final rejected = expectLater(pending, _failure('cancelled'));
    await commit.renamed.future;
    final written = jsonDecode(
      await fixture.records.file.readAsString(),
    ) as Map<String, dynamic>;
    expect(
      ((written['devices'] as List<dynamic>).single
          as Map<String, dynamic>)['address'],
      '192.0.2.2',
    );
    final renamed = fixture.records.rename(id, '并发编辑的名称');
    stop.cancel();
    commit.resume.complete();
    await rejected;
    await renamed;
    expect(fixture.owner.requireConnection(id), same(original));
    expect(fixture.client.disconnected, ['handle-2']);
    final record = (await DeviceRecordStore.open(directory: fixture.root))
        .current
        .find(id)!;
    expect(record.address, '192.0.2.1');
    expect(record.port, 5555);
    expect(record.name, '并发编辑的名称');
    expect(record.serial, 'hardware-serial');
  });

  for (final successorSucceeds in [true, false]) {
    test('已提交候选取消后，后继${successorSucceeds ? '成功保留新端点' : '核验失败恢复原端点'}', () async {
      final id = await fixture.add();
      await fixture.connect(id);
      final original = fixture.owner.requireConnection(id);
      final commit = fixture.pauseEndpointCommit('192.0.2.2');
      final stop = AdbCancellation();
      final stale = fixture.configure(id, cancellation: stop);
      final rejected = expectLater(stale, _failure('cancelled'));
      await commit.renamed.future;
      stop.cancel();
      if (!successorSucceeds) fixture.client.serial = 'other-phone';
      final successor = fixture.configure(id, host: '192.0.2.3', port: 7777);
      final verified = successorSucceeds
          ? successor.then<void>((_) {})
          : expectLater(successor, _failure('device_identity_mismatch'));
      commit.resume.complete();
      await rejected;
      await verified;
      final record = (await DeviceRecordStore.open(directory: fixture.root))
          .current
          .find(id)!;
      expect(record.address, successorSucceeds ? '192.0.2.3' : '192.0.2.1');
      expect(record.port, successorSucceeds ? 7777 : 5555);
      expect(
        fixture.owner.requireConnection(id),
        successorSucceeds ? isNot(same(original)) : same(original),
      );
      expect(fixture.client.disconnected, contains('handle-2'));
      expect(
        fixture.client.disconnected,
        successorSucceeds ? contains('handle-1') : isNot(contains('handle-1')),
      );
    });
  }

  test('补偿只比较本次候选端点，不覆盖队列内后来的端点或身份绑定', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final commit = fixture.pauseEndpointCommit('192.0.2.2');
    final stop = AdbCancellation();
    final pending = fixture.configure(id, cancellation: stop);
    final rejected = expectLater(pending, _failure('cancelled'));
    await commit.renamed.future;
    final edited = fixture.records.update(
      id,
      (record) => record.copyWith(address: '192.0.2.4', port: 8888),
    );
    final fingerprint = 'c' * 64;
    final rebound = fixture.records.bindIdentity(id, fingerprint);
    stop.cancel();
    commit.resume.complete();
    await rejected;
    await edited;
    await rebound;
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    expect(reopened.current.find(id)!.address, '192.0.2.4');
    expect(reopened.current.find(id)!.port, 8888);
    expect(reopened.current.deviceIdentityFingerprints[id], fingerprint);
    expect(fixture.client.disconnected, ['handle-2']);
  });

  test('提交已替换但未知异常丢失回执时，补偿重新核对真实磁盘而非旧内存快照', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    final commit = fixture.pauseEndpointCommit('192.0.2.2');
    final replyLost = StateError('commit reply lost');
    commit.replyError = replyLost;
    final rejected = expectLater(
      fixture.configure(id),
      throwsA(same(replyLost)),
    );
    await commit.renamed.future;
    // 旧内存还没有发布候选，真实文件已经是候选端点。
    expect(fixture.records.current.find(id)!.address, '192.0.2.1');
    commit.resume.complete();
    await rejected;
    expect(fixture.owner.requireConnection(id), same(original));
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    expect(reopened.current.find(id)!.address, '192.0.2.1');
    expect(fixture.client.disconnected, ['handle-2']);
  });

  test('端点补偿失败保留责任，后继核验前必须完成重试且不会覆盖后继提交', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final original = fixture.owner.requireConnection(id);
    final commit = fixture.pauseEndpointCommit('192.0.2.2');
    final stop = AdbCancellation();
    final pending = fixture.configure(id, cancellation: stop);
    final rejected = expectLater(
      pending,
      _failure('connection_cleanup_unconfirmed'),
    );
    await commit.renamed.future;
    commit.rejectCompensation = true;
    stop.cancel();
    commit.resume.complete();
    await rejected;
    expect(fixture.owner.requireConnection(id), same(original));
    expect(fixture.client.disconnected, isEmpty);
    expect(fixture.records.current.find(id)!.address, '192.0.2.2');
    await expectLater(
      fixture.configure(id, host: '192.0.2.3', port: 7777),
      throwsA(isA<FileSystemException>()),
    );
    expect(fixture.client.connects, hasLength(2));
    commit.rejectCompensation = false;
    await fixture.configure(id, host: '192.0.2.3', port: 7777);
    final record = (await DeviceRecordStore.open(directory: fixture.root))
        .current
        .find(id)!;
    expect(record.address, '192.0.2.3');
    expect(record.port, 7777);
    expect(fixture.client.disconnected, ['handle-2', 'handle-1']);
  });

  test('同记录配置被后继替换时，迟到候选只能回收，最新候选才交付', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final opening = Completer<AdbDevice>();
    final started = Completer<void>();
    fixture.client.opening = opening;
    fixture.client.nextStarted = started;
    final stale = fixture.configure(id);
    final rejected = expectLater(stale, _failure('cancelled'));
    await started.future;
    final newest = fixture.configure(id, host: '192.0.2.3', port: 7777);
    opening.complete(_device('late'));
    await rejected;
    await newest;
    expect(fixture.owner.requireConnection(id).device.id, 'handle-3');
    expect(fixture.records.current.find(id)!.address, '192.0.2.3');
    expect(fixture.client.disconnected, ['late', 'handle-1']);
  });

  test('同官方客户端不同记录同时请求相同端点，第二次不触发底层 connect', () async {
    fixture.client.official = true;
    final first = await fixture.add();
    final second = await fixture.add();
    final opening = Completer<AdbDevice>();
    fixture.client.opening = opening;
    final pending = fixture.connect(first);
    await fixture.client.started.future;
    await expectLater(
      fixture.connect(second),
      _failure('independent_connection_required'),
    );
    expect(fixture.client.connects, hasLength(1));
    opening.complete(_device('first'));
    await pending;
    expect(fixture.owner.current(first), isNotNull);
    expect(fixture.owner.current(second), isNull);
  });

  test('官方端点在旧活动排空期间仍被精确连接保护，记录编辑不改变旧拨号端点', () async {
    fixture.client.official = true;
    final first = await fixture.add();
    final second = await fixture.add();
    await fixture.connect(first);
    final stopping = Completer<void>();
    final drain = Completer<void>();
    fixture.onStop = (_) async {
      stopping.complete();
      await drain.future;
    };
    final disconnect = fixture.owner.command('devices.disconnect', {
      'deviceId': first,
    });
    await stopping.future;
    expect(fixture.owner.current(first), isNull);
    await fixture.records.update(
      first,
      (record) => record.copyWith(address: '198.51.100.10'),
    );
    await expectLater(
      fixture.connect(second),
      _failure('independent_connection_required'),
    );
    expect(fixture.client.connects, hasLength(1));
    expect(fixture.client.disconnected, isEmpty);
    drain.complete();
    await disconnect;
    fixture.onStop = null;
    await fixture.connect(second);
    expect(fixture.client.connects, hasLength(2));
    expect(fixture.owner.requireConnection(second).device.id, 'handle-2');
  });

  test('官方连接实际断开失败后仍保护端点，重试成功才允许同端点新连接', () async {
    fixture.client.official = true;
    final first = await fixture.add();
    final second = await fixture.add();
    await fixture.connect(first);
    fixture.client.failDisconnect = true;
    await expectLater(
      fixture.owner.command('devices.disconnect', {'deviceId': first}),
      throwsStateError,
    );
    await expectLater(
      fixture.connect(second),
      _failure('independent_connection_required'),
    );
    expect(fixture.client.connects, hasLength(1));
    fixture.client.failDisconnect = false;
    await fixture.owner.command('devices.disconnect', {'deviceId': first});
    await fixture.connect(second);
    expect(fixture.stopped, ['handle-1']);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.client.connects, hasLength(2));
  });

  test('未发布的官方候选清理失败仍保护端点，内部清理确认后才释放', () async {
    fixture.client.official = true;
    final first = await fixture.add();
    final second = await fixture.add();
    await fixture.records.update(
      first,
      (record) => record.copyWith(serial: 'other-phone'),
    );
    fixture.onStop = (_) async => throw StateError('activities not drained');
    await expectLater(
      fixture.connect(first),
      _failure('connection_cleanup_unconfirmed'),
    );
    expect(fixture.owner.current(first), isNull);
    await expectLater(
      fixture.connect(second),
      _failure('independent_connection_required'),
    );
    expect(fixture.client.connects, hasLength(1));
    fixture.onStop = null;
    await fixture.owner.command('devices.disconnect', {'deviceId': first});
    await fixture.connect(second);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.client.connects, hasLength(2));
  });

  test('官方配置成功退休原连接后释放原实际端点，新端点继续由新连接保护', () async {
    fixture.client.official = true;
    final first = await fixture.add();
    final second = await fixture.add();
    await fixture.connect(first);
    await fixture.configure(first);
    await fixture.connect(second);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.client.connects, [
      '192.0.2.1:5555',
      '192.0.2.2:6666',
      '192.0.2.1:5555',
    ]);
    expect(fixture.owner.requireConnection(first).device.id, 'handle-2');
    expect(fixture.owner.requireConnection(second).device.id, 'handle-3');
  });

  test('断开与迟到连接并发时，同步撤准入且不会被迟到回执重建', () async {
    final id = await fixture.add();
    final opening = Completer<AdbDevice>();
    fixture.client.opening = opening;
    final operation = fixture.connect(id);
    final rejected = expectLater(operation, _failure('cancelled'));
    await fixture.client.started.future;
    final disconnect = fixture.owner.command('devices.disconnect', {
      'deviceId': id,
    });
    expect(fixture.owner.current(id), isNull);
    opening.complete(_device('late'));
    await rejected;
    await disconnect;
    expect(fixture.client.disconnected, ['late']);
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
    expect(fixture.records.current.find(id)!.status, 'offline');
  });

  test('连接期间原始密钥文件改变，真实 SDK 指纹阻止迟到连接准入', () async {
    final id = await fixture.add();
    final opening = Completer<AdbDevice>();
    fixture.client.opening = opening;
    final operation = fixture.connect(id);
    final rejected = expectLater(operation, _failure('identity_changed'));
    await fixture.client.started.future;
    await File('${fixture.root.path}/host_identity.pem')
        .writeAsString('key-b', flush: true);
    opening.complete(_device('late'));
    await rejected;
    expect(fixture.client.disconnected, ['late']);
    expect(fixture.owner.current(id), isNull);
  });

  test('身份命令直接使用身份事务并通过同步失效回调撤销原连接', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    final result = await fixture.owner.command('identity.global.import', {
      'privateKeyPem': 'key-b',
    });
    expect(result['fingerprint'], 'b' * 64);
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.records.current.find(id)!.status, 'unauthorized');
    expect(fixture.records.current.find(id)!.autoReconnect, isFalse);
  });

  test('forget 落盘后移除身份材料，可重复清理且不复建设备', () async {
    final id = await fixture.add();
    await fixture.connect(id);
    await fixture.owner.command('devices.forget', {'deviceId': id});
    await fixture.owner.command('devices.forget', {'deviceId': id});
    final reopened = await DeviceRecordStore.open(directory: fixture.root);
    expect(reopened.current.find(id), isNull);
    expect(fixture.client.disconnected, ['handle-1']);
  });

  test('自动连接要求当前租约及持久意图，不能重放用户已停止的设备', () async {
    final id = await fixture.add();
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': true,
    });
    await expectLater(fixture.automatic(id, 'owner-a'), _failure('cancelled'));
    await expectLater(
      fixture.automatic(id, 'other'),
      _failure('reconnect_owner_required'),
    );
    expect(fixture.client.connects, isEmpty);
    await fixture.records.update(
      id,
      (record) => record.copyWith(autoReconnect: true),
    );
    expect((await fixture.automatic(id, 'owner-a'))['connected'], isTrue);
    expect(fixture.owner.current(id), isNotNull);
  });

  test('交付事件中释放重连租约仍回收已接纳候选，不把活连接隐藏为离线', () async {
    final id = await fixture.add();
    await fixture.records.update(
      id,
      (record) => record.copyWith(autoReconnect: true),
    );
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': true,
    });
    fixture.onEmit = (_, data) {
      final devices = data['devices']! as List;
      if ((devices.single as Map)['status'] == 'connected') {
        fixture.onEmit = null;
        unawaited(
          fixture.owner.command('devices.reconnect.owner', {
            'ownerId': 'owner-a',
            'active': false,
          }),
        );
      }
    };
    await expectLater(fixture.automatic(id, 'owner-a'), _failure('cancelled'));
    expect(fixture.owner.current(id), isNull);
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.records.current.find(id)!.status, 'offline');
  });

  test('交付后取消并同步发起后继请求，只回收旧候选且不覆盖新状态', () async {
    final id = await fixture.add();
    final cancellation = AdbCancellation();
    Future<Map<String, Object?>>? successor;
    fixture.onEmit = (_, data) {
      if (((data['devices']! as List).single as Map)['status'] == 'connected') {
        fixture.onEmit = null;
        cancellation.cancel();
        successor = fixture.connect(id);
      }
    };
    await expectLater(
      fixture.owner.command('devices.connect', {
        'deviceId': id,
      }, cancellation: cancellation),
      _failure('cancelled'),
    );
    expect((await successor!)['connected'], isTrue);
    expect(fixture.owner.current(id)!.device.id, 'handle-2');
    expect(fixture.client.disconnected, ['handle-1']);
    expect(fixture.records.current.find(id)!.status, 'connected');
  });

  test('后继租约撤旧在途尝试，旧所有者迟到释放不能撤销后继', () async {
    final id = await fixture.add();
    await fixture.records.update(
      id,
      (record) => record.copyWith(autoReconnect: true),
    );
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': true,
    });
    final opening = Completer<AdbDevice>();
    fixture.client.opening = opening;
    final rejected = expectLater(
      fixture.automatic(id, 'owner-a'),
      _failure('cancelled'),
    );
    await fixture.client.started.future;
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-b',
      'active': true,
    });
    expect(
      await fixture.owner.command('devices.reconnect.owner', {
        'ownerId': 'owner-a',
        'active': false,
      }),
      {'ownerId': 'owner-a', 'active': false},
    );
    opening.complete(_device('retired-auto'));
    await rejected;
    expect((await fixture.automatic(id, 'owner-b'))['connected'], isTrue);
    expect(fixture.client.disconnected, ['retired-auto']);
  });

  test('租约释放只取消所属待定自动尝试，不断开已交付或手动连接', () async {
    final first = await fixture.add();
    final second = await fixture.add(host: '192.0.2.2');
    await fixture.records.update(
      first,
      (record) => record.copyWith(autoReconnect: true),
    );
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': true,
    });
    await fixture.automatic(first, 'owner-a');
    await fixture.connect(second);
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': false,
    });
    expect(fixture.owner.current(first), isNotNull);
    expect(fixture.owner.current(second), isNotNull);
    expect(fixture.client.disconnected, isEmpty);
  });

  test('同名重复取得租约不取消在途尝试，调用者取消仍能穿透租约链接', () async {
    final id = await fixture.add();
    await fixture.records.update(
      id,
      (record) => record.copyWith(autoReconnect: true),
    );
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': true,
    });
    final opening = Completer<AdbDevice>();
    fixture.client.opening = opening;
    final stop = AdbCancellation();
    final rejected = expectLater(
      fixture.owner.command('devices.connect', {
        'deviceId': id,
        'automatic': true,
        'ownerId': 'owner-a',
      }, cancellation: stop),
      _failure('cancelled'),
    );
    await fixture.client.started.future;
    await fixture.owner.command('devices.reconnect.owner', {
      'ownerId': 'owner-a',
      'active': true,
    });
    stop.cancel();
    opening.complete(_device('cancelled-auto'));
    await rejected;
    expect(fixture.client.disconnected, ['cancelled-auto']);
  });

  test('重连租约和自动标记严格校验，不把字符串当布尔值', () async {
    final id = await fixture.add();
    for (final invalid in [
      {'ownerId': '', 'active': true},
      {'ownerId': 'owner', 'active': 'true'},
      {'ownerId': 'owner\x00invalid', 'active': true},
    ]) {
      await expectLater(
        fixture.owner.command('devices.reconnect.owner', invalid),
        _failure('invalid_argument'),
      );
    }
    await expectLater(
      fixture.owner.command('devices.connect', {
        'deviceId': id,
        'automatic': 'false',
      }),
      _failure('invalid_argument'),
    );
    expect(fixture.client.connects, isEmpty);
  });

  test('发现与未持有租约的自动重连明确拒绝，不伪造业务成功', () async {
    final id = await fixture.add();
    await expectLater(
      fixture.owner.command('devices.connect', {
        'deviceId': id,
        'automatic': true,
      }),
      _failure('reconnect_owner_required'),
    );
    await expectLater(
      fixture.owner.command('devices.connect', {
        'deviceId': id,
        'candidateSource': 'discovery',
      }),
      _failure('discovery_unavailable'),
    );
    expect(fixture.owner.handles('adb.pair'), isFalse);
    expect(fixture.owner.handles('devices.discover'), isFalse);
    expect(fixture.client.connects, isEmpty);
  });
}

Matcher _failure(String code) => throwsA(
  isA<ApplicationCommandException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

final class _ReconnectTimer implements Timer {
  _ReconnectTimer(this._run);
  final void Function() _run;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    _run();
  }
}

AdbDevice _device(String id) =>
    AdbDevice(id: id, serial: '192.0.2.1:5555', state: 'device');

AdbDiscoveryEndpoint _endpoint(
  String address,
  int port, {
  String instance = 'guid',
}) => AdbDiscoveryEndpoint(
  kind: AdbDiscoveryKind.tlsConnect,
  serviceName: '$instance._adb-tls-connect._tcp.local',
  instance: instance,
  hostname: 'android.local',
  address: address,
  port: port,
  validUntil: DateTime.utc(2100),
  generation: 1,
);

final class _Candidates implements DeviceReconnectionCandidates {
  List<AdbDiscoveryEndpoint> endpoints = [];
  final guids = <String>[];
  final withdrawn = <AdbDiscoveryEndpoint>{};
  final started = Completer<void>();
  Completer<List<AdbDiscoveryEndpoint>>? pending;
  AdbCancellation? cancellation;
  Object? error;

  @override
  Future<List<AdbDiscoveryEndpoint>> resolve(
    String guid, {
    required AdbCancellation cancellation,
  }) async {
    guids.add(guid);
    this.cancellation = cancellation;
    if (!started.isCompleted) started.complete();
    if (error case final failure?) throw failure;
    return pending?.future ?? endpoints;
  }

  @override
  bool isCurrent(AdbDiscoveryEndpoint endpoint) =>
      !withdrawn.contains(endpoint);
}

final class _Fixture {
  _Fixture(this.root);
  final Directory root;
  late DeviceRecordStore records;
  late DeviceCoordinator owner;
  final client = _Client();
  final candidates = _Candidates();
  final identityApi = _Identities();
  final selectedPaths = <String>[];
  final stopped = <String>[];
  final connected = <DeviceConnection>[];
  final events = <(String, Map<String, Object?>)>[];
  void Function(String, Map<String, Object?>)? onEmit;
  bool rejectCommit = false;
  Future<void> Function(File, File)? onCommit;
  Future<void> Function(DeviceConnection)? onStop;
  Future<void> Function(DeviceConnection, AdbCancellation)? onPrepare;
  int _nextId = 0;
  bool _ready = false;

  static Future<_Fixture> open() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('device-coordinator-'),
    );
    fixture.records = await DeviceRecordStore.open(
      directory: fixture.root,
      idFactory: () =>
          '00000000-0000-4000-8000-${(++fixture._nextId).toString().padLeft(12, '0')}',
      commitFile: (temporary, destination) async {
        if (fixture.rejectCommit) {
          throw const FileSystemException('injected commit failure');
        }
        if (fixture.onCommit case final commit?) {
          await commit(temporary, destination);
        } else {
          await temporary.rename(destination.path);
        }
      },
    );
    final identities = await IdentityManager.open(
      directory: fixture.root,
      records: fixture.records,
      identities: fixture.identityApi,
      invalidate: (ids, {required global}) =>
          fixture._ready ? fixture.owner.invalidate(ids) : Future<void>.value(),
    );
    fixture.owner = DeviceCoordinator(
      records: fixture.records,
      identities: identities,
      reconnectionCandidates: fixture.candidates,
      clientForIdentity: (selection) {
        fixture.selectedPaths.add(selection.path);
        return fixture.client;
      },
      prepareConnection: (connection, cancellation) async {
        await fixture.onPrepare?.call(connection, cancellation);
      },
      onConnected: (_, connection) => fixture.connected.add(connection),
      stopActivities: (_, connection) async {
        fixture.stopped.add(connection.device.id);
        await fixture.onStop?.call(connection);
      },
      emit: (name, data) {
        fixture.events.add((name, data));
        fixture.onEmit?.call(name, data);
      },
      now: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );
    fixture._ready = true;
    return fixture;
  }

  Future<String> add({
    String host = '192.0.2.1',
    String transport = 'tcp',
  }) async =>
      (await owner.command('devices.add', {
            'host': host,
            'port': 5555,
            'transport': transport,
          }))['deviceId']!
          as String;
  Future<Map<String, Object?>> connect(String id) =>
      owner.command('devices.connect', {'deviceId': id});
  Future<String> paired({int port = 0}) async {
    final id = await add(transport: 'tls');
    await records.update(
      id,
      (record) => record.copyWith(guid: 'guid', port: port),
    );
    return id;
  }

  Future<Map<String, Object?>> automatic(String id, String ownerId) =>
      owner.command('devices.connect', {
        'deviceId': id,
        'automatic': true,
        'ownerId': ownerId,
      });
  Future<Map<String, Object?>> configure(
    String id, {
    String host = '192.0.2.2',
    int port = 6666,
    AdbCancellation? cancellation,
  }) => owner.command('devices.configure', {
    'deviceId': id,
    'host': host,
    'port': port,
  }, cancellation: cancellation);
  _EndpointCommitGate pauseEndpointCommit(String address) {
    final gate = _EndpointCommitGate(address);
    onCommit = gate.commit;
    return gate;
  }

  Future<void> dispose() async {
    client.failDisconnect = false;
    rejectCommit = false;
    onCommit = null;
    await owner.close();
    await root.delete(recursive: true);
  }
}

/// 真正完成文件替换后才阻塞回执，覆盖磁盘与异步调用完成之间的窗口。
final class _EndpointCommitGate {
  _EndpointCommitGate(this.address);
  final String address;
  final renamed = Completer<void>();
  final resume = Completer<void>();
  bool rejectCompensation = false;
  Object? replyError;
  bool _paused = false;

  Future<void> commit(File temporary, File destination) async {
    final snapshot =
        jsonDecode(await temporary.readAsString()) as Map<String, dynamic>;
    final devices = snapshot['devices'] as List<dynamic>;
    final matches = devices.any(
      (record) => (record as Map<String, dynamic>)['address'] == address,
    );
    if (!_paused && matches) {
      _paused = true;
      await temporary.rename(destination.path);
      renamed.complete();
      await resume.future;
      if (replyError case final error?) throw error;
    } else {
      if (_paused && !matches && rejectCompensation) {
        throw const FileSystemException('injected compensation failure');
      }
      await temporary.rename(destination.path);
    }
  }
}

final class _Client implements AdbClient {
  bool official = false, failDisconnect = false, closed = false;
  String serial = 'hardware-serial';
  String guid = 'guid';
  final connects = <String>[];
  final requiredTls = <bool>[];
  final options = <AdbConnectOptions?>[];
  final disconnected = <String>[];
  final started = Completer<void>();
  Completer<void>? nextStarted;
  Completer<AdbDevice>? opening;
  Object? connectError;
  Future<AdbDevice> Function(String, AdbCancellation?)? onConnect;
  late final _Native native = _Native();
  @override
  late final services = AdbServices(
    () => native,
    (device) async => device,
    () {},
  );
  @override
  AdbCapabilities get capabilities => AdbCapabilities(
    officialServer: official,
    suppressAuthorizationPrompt: !official,
    forceTlsWithoutMdns: !official,
    androidUsbFd: false,
  );
  @override
  Future<AdbDevice> connect(
    String address, {
    bool requireTls = false,
    bool authorize = true,
    Duration timeout = const Duration(seconds: 15),
    AdbConnectOptions? directOptions,
    AdbCancellation? cancellation,
  }) async {
    connects.add(address);
    requiredTls.add(requireTls);
    options.add(directOptions);
    if (!started.isCompleted) started.complete();
    nextStarted?.complete();
    nextStarted = null;
    if (connectError case final error?) throw error;
    if (onConnect case final open?) return open(address, cancellation);
    if (opening case final pending?) {
      opening = null;
      return pending.future;
    }
    return _device('handle-${connects.length}');
  }

  @override
  Stream<AdbShellEvent> shell(
    AdbDevice device,
    String command, {
    Duration timeout = const Duration(minutes: 5),
    AdbCancellation? cancellation,
  }) async* {
    yield AdbShellEvent(
      AdbShellChannel.stdout,
      Uint8List.fromList(
        utf8.encode('$serial\x00boot\x00测试手机\x0016\x0036\x00$guid\x00'),
      ),
    );
    yield AdbShellEvent(AdbShellChannel.exit, Uint8List(0), exitCode: 0);
  }

  @override
  Future<void> disconnect(AdbDevice device) async {
    if (failDisconnect) throw StateError('cleanup not confirmed');
    disconnected.add(device.id);
  }

  @override
  Future<void> close() async => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Native implements NativeAdbApi {
  final closedConnections = <String>{};
  @override
  Future<AdbConnectionFacts> connectionFacts(String id) async =>
      AdbConnectionFacts(
        officialServer: false,
        closed: closedConnections.contains(id),
        features: const [],
        connectionId: 'physical-${id.split('-').last}',
        burstMode: false,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 身份文件和元数据使用真实磁盘，只替换本测试不关心的 RSA 计算。
final class _Identities implements AdbIdentities {
  bool unknownReplacement = false;
  AdbIdentityInfo _info(String pem) => AdbIdentityInfo(
    fingerprint: (pem == 'key-a' ? 'a' : 'b') * 64,
    fingerprintAlgorithm: 'sha256',
    fingerprintInput: 'adb-public-key-interop-v1',
    bits: 2048,
    exponent: 65537,
  );
  @override
  Future<void> prepareIdentity(String path) async {
    final file = File(path);
    if (!await file.exists()) await file.writeAsString('key-a', flush: true);
  }

  @override
  Future<AdbIdentityInfo?> inspectIdentity(String path) async {
    final file = File(path);
    return await file.exists() ? _info(await file.readAsString()) : null;
  }

  @override
  Future<AdbIdentityInfo> validateIdentity(String pem) async => _info(pem);
  @override
  Future<AdbIdentityCommitReceipt> replaceIdentity(
    String path,
    String pem, {
    String? expectedFingerprint,
  }) async {
    if ((await inspectIdentity(path))?.fingerprint != expectedFingerprint) {
      return const AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unchanged,
        error: 'conflict',
      );
    }
    final file = File('$path.tmp');
    await file.writeAsString(pem, flush: true);
    await file.rename(path);
    if (unknownReplacement) {
      return const AdbIdentityCommitReceipt(
        state: AdbIdentityCommitState.unknown,
      );
    }
    return AdbIdentityCommitReceipt(
      state: AdbIdentityCommitState.committed,
      identity: _info(pem),
    );
  }
}
