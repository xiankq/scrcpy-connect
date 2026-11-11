import 'package:scrcpy_connect/models/device_connection.dart';

import 'dart:async';

import 'package:adb/adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrcpy_connect/models/application_request.dart';
import 'package:scrcpy_connect/services/device_connection_pool.dart';

final class _Client implements AdbClient {
  final disconnected = <String>[];
  Future<void> Function(AdbDevice)? disconnecting;
  @override
  Future<void> disconnect(AdbDevice device) async {
    await disconnecting?.call(device);
    disconnected.add(device.id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DeviceConnection _connection(
  _Client client,
  String id, {
  Future<void> Function()? releasePlatformResources,
}) => DeviceConnection(
  client: client,
  device: AdbDevice(id: id, serial: '实际序列号', state: 'device'),
  releasePlatformResources: releasePlatformResources,
);

Matcher _failure(String code) =>
    throwsA(isA<RequestFailure>().having((error) => error.code, 'code', code));

void main() {
  test('模式切换同步撤准入，活动排空后才借用原传输并按顺序释放平台租约', () async {
    final client = _Client();
    final order = <String>[];
    final stopping = Completer<void>(), stopped = Completer<void>();
    final owner = DeviceConnectionPool(
      stopActivities: (_, connection) async {
        expect(connection.device.id, 'original');
        stopping.complete();
        await stopped.future;
        order.add('activities');
      },
    );
    client.disconnecting = (_) async => order.add('disconnect');
    final original = _connection(
      client,
      'original',
      releasePlatformResources: () async => order.add('platform'),
    );
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    final changing = owner.retireForChange(
      'record',
      original,
      change: (connection, _) async {
        expect(connection, same(original));
        expect(client.disconnected, isEmpty);
        order.add('change');
        return 'restarted';
      },
    );
    expect(owner.current('record'), isNull);
    await stopping.future;
    expect(order, isEmpty);
    stopped.complete();
    expect(await changing, 'restarted');
    expect(order, ['activities', 'change', 'disconnect', 'platform']);
    await owner.close();
  });

  for (final cancellationKind in [
    'external',
    'disconnect',
    'close',
    'replace',
  ]) {
    test('切换期间 $cancellationKind 取消等待真实服务退出，后继不能提前使用传输', () async {
      final client = _Client();
      final owner = DeviceConnectionPool(stopActivities: (_, _) async {});
      final original = _connection(client, 'original');
      await owner.replace(
        'record',
        open: (_) async => original,
        verify: (_, _) async {},
      );
      final started = Completer<void>(), observed = Completer<void>();
      final serviceExited = Completer<void>();
      final stop = AdbCancellation();
      var calls = 0, openedSuccessor = false;
      final changing = owner.retireForChange(
        'record',
        original,
        cancellation: stop,
        change: (_, token) async {
          calls++;
          started.complete();
          await token.whenCancelled;
          observed.complete();
          await serviceExited.future;
          // 完整服务回执是已发生的事实，即使同时取消也不能改写为未执行。
          return 'confirmed';
        },
      );
      await started.future;
      final Future<void> following;
      switch (cancellationKind) {
        case 'external':
          stop.cancel();
          following = Future.value();
        case 'disconnect':
          following = owner.disconnect('record');
        case 'close':
          following = owner.close();
        case 'replace':
          following = owner
              .replace(
                'record',
                open: (_) async {
                  openedSuccessor = true;
                  return _connection(client, 'successor');
                },
                verify: (_, _) async {},
              )
              .then((_) {});
        default:
          throw StateError('未定义的测试操作');
      }
      await observed.future;
      expect(client.disconnected, isEmpty);
      expect(openedSuccessor, isFalse);
      serviceExited.complete();
      expect(await changing, 'confirmed');
      await following;
      expect(calls, 1);
      expect(client.disconnected, ['original']);
      if (cancellationKind == 'replace') {
        expect(owner.current('record')?.device.id, 'successor');
      }
      await owner.close();
    });
  }

  test('切换只执行一次，SDK 与平台清理失败分别保留阶段供断开重试', () async {
    final client = _Client();
    var disconnectFails = true, platformFails = true, calls = 0;
    var platformCalls = 0;
    client.disconnecting = (_) async {
      if (disconnectFails) throw StateError('driver still active');
    };
    final owner = DeviceConnectionPool(stopActivities: (_, _) async {});
    final original = _connection(
      client,
      'original',
      releasePlatformResources: () async {
        platformCalls++;
        if (platformFails) throw StateError('platform close unconfirmed');
      },
    );
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    await expectLater(
      owner.retireForChange(
        'record',
        original,
        change: (_, _) async => ++calls,
      ),
      throwsStateError,
    );
    expect(calls, 1);
    expect(platformCalls, 0);
    disconnectFails = false;
    await expectLater(owner.disconnect('record'), throwsStateError);
    expect(client.disconnected, ['original']);
    platformFails = false;
    await owner.disconnect('record');
    expect(client.disconnected, ['original']);
    expect(platformCalls, 2);
    expect(calls, 1);
    await owner.close();
  });

  test('切换尚未执行便被替换时只清理原连接，不向后继执行服务', () async {
    final client = _Client();
    final owner = DeviceConnectionPool(stopActivities: (_, _) async {});
    final original = _connection(client, 'original');
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    var changed = false;
    final changing = owner.retireForChange(
      'record',
      original,
      change: (_, _) async => changed = true,
    );
    final cancelled = expectLater(changing, _failure('cancelled'));
    final successor = await owner.replace(
      'record',
      open: (_) async => _connection(client, 'successor'),
      verify: (_, _) async {},
    );
    await cancelled;
    expect(changed, isFalse);
    expect(client.disconnected, ['original']);
    expect(owner.current('record'), same(successor));
    expect(
      () => owner.retireForChange(
        'record',
        original,
        change: (_, _) async => changed = true,
      ),
      _failure('stale_connection'),
    );
    await owner.close();
  });

  test('活动停止失败不执行切换，断开重试只排空活动与原连接', () async {
    final client = _Client();
    var activityFails = true, changes = 0;
    final owner = DeviceConnectionPool(
      stopActivities: (_, _) async {
        if (activityFails) throw StateError('activity still active');
      },
    );
    final original = _connection(client, 'original');
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    await expectLater(
      owner.retireForChange(
        'record',
        original,
        change: (_, _) async => changes++,
      ),
      throwsStateError,
    );
    expect(client.disconnected, isEmpty);
    activityFails = false;
    await owner.disconnect('record');
    expect(changes, 0);
    expect(client.disconnected, ['original']);
    await owner.close();
  });

  test('SDK 断开失败保留平台租约，成功后才按活动、传输、平台次序释放', () async {
    final client = _Client();
    final order = <String>[];
    var failDisconnect = true;
    client.disconnecting = (_) async {
      order.add('disconnect');
      if (failDisconnect) throw StateError('driver still active');
    };
    final owner = DeviceConnectionPool(
      stopActivities: (_, _) async => order.add('activities'),
      onDisconnected: (_, _) => order.add('released'),
    );
    await owner.replace(
      'record',
      open: (_) async => _connection(
        client,
        'usb',
        releasePlatformResources: () async => order.add('platform'),
      ),
      verify: (_, _) async {},
    );
    await expectLater(owner.disconnect('record'), throwsStateError);
    expect(owner.current('record'), isNull);
    expect(order, ['activities', 'disconnect']);
    failDisconnect = false;
    await owner.disconnect('record');
    expect(order, [
      'activities',
      'disconnect',
      'disconnect',
      'platform',
      'released',
    ]);
    await owner.close();
    expect(client.disconnected, ['usb']);
  });

  test('平台关闭失败保留精确退休阶段，后继准入前重试且不重断已结束传输', () async {
    final client = _Client();
    final order = <String>[];
    client.disconnecting = (device) async =>
        order.add('disconnect:${device.id}');
    var failPlatform = true;
    final owner = DeviceConnectionPool(
      stopActivities: (_, connection) async =>
          order.add('activities:${connection.device.id}'),
      onDisconnected: (_, connection) =>
          order.add('released:${connection.device.id}'),
    );
    final original = _connection(
      client,
      'old',
      releasePlatformResources: () async {
        order.add('platform:old');
        if (failPlatform) {
          throw StateError('UsbDeviceConnection.close unconfirmed');
        }
      },
    );
    final successor = _connection(
      client,
      'new',
      releasePlatformResources: () async => order.add('platform:new'),
    );
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    await expectLater(owner.disconnect('record'), throwsStateError);
    var opened = false;
    await expectLater(
      owner.replace(
        'record',
        open: (_) async {
          opened = true;
          return successor;
        },
        verify: (_, _) async {},
      ),
      throwsStateError,
    );
    expect(opened, isFalse);
    expect(client.disconnected, ['old']);
    failPlatform = false;
    await owner.replace(
      'record',
      open: (_) async => successor,
      verify: (_, _) async {},
    );
    expect(owner.current('record'), same(successor));
    expect(client.disconnected, ['old']);
    await owner.release('record', original);
    expect(owner.current('record'), same(successor));
    expect(order.where((step) => step == 'platform:new'), isEmpty);
    await owner.close();
    expect(client.disconnected, ['old', 'new']);
    expect(order, [
      'activities:old',
      'disconnect:old',
      'platform:old',
      'platform:old',
      'platform:old',
      'released:old',
      'activities:new',
      'disconnect:new',
      'platform:new',
      'released:new',
    ]);
  });

  test('迟到 USB 候选核验取消也保持原始平台句柄直至其 SDK 断开', () async {
    final client = _Client();
    final started = Completer<void>(), stopped = Completer<void>();
    final opened = Completer<DeviceConnection>();
    var platformReleased = false;
    client.disconnecting = (_) async {
      expect(platformReleased, isFalse);
      await stopped.future;
    };
    final owner = DeviceConnectionPool(stopActivities: (_, _) async {});
    final pending = owner.replace(
      'record',
      open: (_) {
        started.complete();
        return opened.future;
      },
      verify: (_, _) async {},
    );
    final rejected = expectLater(pending, _failure('cancelled'));
    await started.future;
    final disconnect = owner.disconnect('record');
    opened.complete(
      _connection(
        client,
        'late',
        releasePlatformResources: () async => platformReleased = true,
      ),
    );
    expect(platformReleased, isFalse);
    stopped.complete();
    await rejected;
    await disconnect;
    expect(platformReleased, isTrue);
    expect(client.disconnected, ['late']);
    await owner.close();
  });

  test('断开通知只在实际断开后触发，覆盖替换退休与最终 close', () async {
    final client = _Client();
    final released = <DeviceConnection>[];
    final owner = DeviceConnectionPool(
      stopActivities: (_, _) async {},
      onDisconnected: (id, connection) {
        expect(id, 'record');
        expect(client.disconnected, contains(connection.device.id));
        released.add(connection);
      },
    );
    final original = _connection(client, 'original');
    final replacement = _connection(client, 'replacement');
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    expect(released, isEmpty);
    await owner.reconfigure(
      'record',
      open: (_) async => replacement,
      verify: (_, _) async {},
    );
    expect(released, [same(original)]);
    await owner.close();
    expect(released, [same(original), same(replacement)]);
    await owner.close();
    expect(released, hasLength(2));
  });

  test('内部候选核验失败的精确断开通知不包含仍然准入的原连接', () async {
    final client = _Client();
    final released = <DeviceConnection>[];
    final owner = DeviceConnectionPool(
      stopActivities: (_, _) async {},
      onDisconnected: (_, connection) => released.add(connection),
    );
    final original = _connection(client, 'original');
    final candidate = _connection(client, 'candidate');
    await owner.replace(
      'record',
      open: (_) async => original,
      verify: (_, _) async {},
    );
    final verification = StateError('identity mismatch');
    await expectLater(
      owner.reconfigure(
        'record',
        open: (_) async => candidate,
        verify: (_, _) async => throw verification,
      ),
      throwsA(same(verification)),
    );
    expect(released, [same(candidate)]);
    expect(owner.require('record'), same(original));
    await owner.close();
    expect(released, [same(candidate), same(original)]);
  });

  test('实际断开失败不通知，close 重试成功才通知同一对象一次', () async {
    final client = _Client();
    final released = <DeviceConnection>[];
    final owner = DeviceConnectionPool(
      stopActivities: (_, _) async {},
      onDisconnected: (_, connection) => released.add(connection),
    );
    final connection = _connection(client, 'connection');
    await owner.replace(
      'record',
      open: (_) async => connection,
      verify: (_, _) async {},
    );
    client.disconnecting = (_) async =>
        throw StateError('disconnect not confirmed');
    await expectLater(owner.close(), throwsA(isA<Object>()));
    expect(released, isEmpty);
    client.disconnecting = null;
    await owner.close();
    expect(released, [same(connection)]);
    expect(client.disconnected, ['connection']);
  });

  test('通知失败仍继续排空其余退休资源，重试不重复断开已结束对象', () async {
    final client = _Client();
    final released = <String>[];
    final notificationFailure = StateError('notification failed');
    final owner = DeviceConnectionPool(
      stopActivities: (_, _) async {},
      onDisconnected: (_, connection) {
        released.add(connection.device.id);
        if (connection.device.id == 'candidate') throw notificationFailure;
      },
    );
    await owner.replace(
      'record',
      open: (_) async => _connection(client, 'original'),
      verify: (_, _) async {},
    );
    client.disconnecting = (_) async =>
        throw StateError('disconnect not confirmed');
    await expectLater(
      owner.reconfigure(
        'record',
        open: (_) async => _connection(client, 'candidate'),
        verify: (_, _) async => throw StateError('invalid candidate'),
      ),
      _failure('connection_cleanup_unconfirmed'),
    );
    client.disconnecting = null;
    await expectLater(
      owner.disconnect('record'),
      throwsA(same(notificationFailure)),
    );
    expect(released, ['candidate', 'original']);
    expect(client.disconnected, ['candidate', 'original']);
    await owner.disconnect('record');
    await owner.close();
    expect(client.disconnected, ['candidate', 'original']);
  });

  test('取消监听同步重入的新请求保留独立代次，外层旧请求不能覆盖或遗失连接', () async {
    final client = _Client();
    final owner = DeviceConnectionPool(stopActivities: (_, _) async {});
    await owner.replace(
      'record',
      open: (_) async => _connection(client, 'original'),
      verify: (_, _) async {},
    );
    final verifying = Completer<void>();
    Future<DeviceConnection>? reentrant;
    final candidate = owner.reconfigure(
      'record',
      open: (_) async => _connection(client, 'candidate'),
      verify: (_, cancellation) async {
        cancellation.onCancel(() {
          reentrant = owner.replace(
            'record',
            open: (_) async => _connection(client, 'newest'),
            verify: (_, _) async {},
          );
        });
        verifying.complete();
        await cancellation.whenCancelled;
      },
    );
    final rejectedCandidate = expectLater(candidate, _failure('cancelled'));
    await verifying.future;
    var staleOpened = false;
    final stale = owner.replace(
      'record',
      open: (_) async {
        staleOpened = true;
        return _connection(client, 'stale');
      },
      verify: (_, _) async {},
    );
    await expectLater(stale, _failure('cancelled'));
    await rejectedCandidate;
    expect((await reentrant!).device.id, 'newest');
    expect(owner.require('record').device.id, 'newest');
    expect(staleOpened, isFalse);
    expect(client.disconnected.toSet(), {'original', 'candidate'});
    await owner.close();
    expect(client.disconnected.toSet(), {'original', 'candidate', 'newest'});
  });

  for (final action in ['disconnect', 'invalidate', 'close']) {
    test('$action 不让取消监听异常阻断撤准入或遗留资源', () async {
      final client = _Client();
      final owner = DeviceConnectionPool(stopActivities: (_, _) async {});
      await owner.replace(
        'first',
        open: (_) async => _connection(client, 'original'),
        verify: (_, _) async {},
      );
      await owner.replace(
        'second',
        open: (_) async => _connection(client, 'independent'),
        verify: (_, _) async {},
      );
      final verifying = Completer<void>();
      final noticeFailure = StateError('取消监听失败');
      final candidate = owner.reconfigure(
        'first',
        open: (_) async => _connection(client, 'candidate'),
        verify: (_, cancellation) async {
          cancellation.onCancel(() => throw noticeFailure);
          verifying.complete();
          await cancellation.whenCancelled;
        },
      );
      final rejected = expectLater(candidate, _failure('cancelled'));
      await verifying.future;
      final stopping = switch (action) {
        'disconnect' => owner.disconnect('first'),
        'invalidate' => owner.invalidate(['first', 'second']),
        _ => owner.close(),
      };
      expect(owner.current('first'), isNull);
      expect(owner.current('second') == null, action != 'disconnect');
      await expectLater(stopping, throwsA(same(noticeFailure)));
      await rejected;
      expect(client.disconnected, containsAll(['original', 'candidate']));
      if (action != 'disconnect') {
        expect(client.disconnected, contains('independent'));
      }
      await owner.close();
      expect(client.disconnected.toSet(), {
        'original',
        'candidate',
        'independent',
      });
    });
  }

  test('同设备替换等待旧活动释放，不阻塞另一设备且不关闭共享客户端', () async {
    final client = _Client();
    final releasing = Completer<void>();
    final cleanupStarted = Completer<void>();
    final owner = DeviceConnectionPool(
      stopActivities: (id, connection) async {
        if (connection.device.id == 'old') {
          cleanupStarted.complete();
          await releasing.future;
        }
      },
    );
    await owner.replace(
      'first',
      open: (_) async => _connection(client, 'old'),
      verify: (_, _) async {},
    );
    var newOpened = false;
    final replacement = owner.replace(
      'first',
      open: (_) async {
        newOpened = true;
        return _connection(client, 'new');
      },
      verify: (_, _) async {},
    );
    expect(owner.current('first'), isNull);
    await cleanupStarted.future;
    await owner.replace(
      'second',
      open: (_) async => _connection(client, 'independent'),
      verify: (_, _) async {},
    );
    expect(newOpened, isFalse);
    expect(owner.require('second').device.id, 'independent');
    releasing.complete();
    await replacement;
    expect(client.disconnected, ['old']);
    expect(owner.require('first').device.id, 'new');
    await owner.close();
    expect(client.disconnected.toSet(), {'old', 'new', 'independent'});
  });

  test('取消核验仍等待实际探测收尾，退出前不释放候选或启动后继', () async {
    final client = _Client();
    final verifying = Completer<void>();
    final cancellationObserved = Completer<void>();
    final probeReleased = Completer<void>();
    var verificationExited = false;
    var successorOpened = false;
    final owner = DeviceConnectionPool(
      stopActivities: (_, connection) async {
        if (connection.device.id == 'candidate') {
          expect(verificationExited, isTrue);
        }
      },
    );
    final opening = owner.replace(
      'record',
      open: (_) async => _connection(client, 'candidate'),
      verify: (_, cancellation) async {
        verifying.complete();
        await cancellation.whenCancelled;
        cancellationObserved.complete();
        // 模拟已发出取消的实际探测仍在关闭流；不能提前释放连接。
        await probeReleased.future;
        verificationExited = true;
      },
    );
    final rejected = expectLater(opening, _failure('cancelled'));
    await verifying.future;
    final replacement = owner.replace(
      'record',
      open: (_) async {
        successorOpened = true;
        return _connection(client, 'successor');
      },
      verify: (_, _) async {},
    );
    await cancellationObserved.future;
    expect(owner.current('record'), isNull);
    expect(client.disconnected, isEmpty);
    expect(successorOpened, isFalse);
    probeReleased.complete();
    await rejected;
    await replacement;
    expect(client.disconnected, ['candidate']);
    expect(owner.require('record').device.id, 'successor');
    await owner.close();
  });
}
